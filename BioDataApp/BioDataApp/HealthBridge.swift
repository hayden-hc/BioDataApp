import HealthKit
import Foundation

final class HealthBridge {

    static let shared = HealthBridge()
    private init() {}

    private let store = HKHealthStore()

    private var csvURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("health_log.csv")
    }

    private let readTypes: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    ]

    // ─────────────────────────────────────────
    // MARK: Permissions
    // ─────────────────────────────────────────

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        store.requestAuthorization(toShare: [], read: readTypes) { ok, error in
            if let error { print("[HealthBridge] Auth error: \(error)") }
            DispatchQueue.main.async { completion(ok) }
        }
    }

    // ─────────────────────────────────────────
    // MARK: Entry point (daily ongoing use)
    // ─────────────────────────────────────────

    func setup() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        createCSVIfNeeded()
        requestPermissions { [weak self] granted in
            guard granted else { return }
            self?.registerBackgroundDelivery()
            self?.syncToday()
        }
    }

    // ─────────────────────────────────────────
    // MARK: ONE-OFF historical bulk fetch
    // Call this ONCE to backfill past data.
    // Change daysBack to however far you want.
    // ─────────────────────────────────────────

    func fetchHistory(daysBack: Int = 90) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        createCSVIfNeeded()
        requestPermissions { [weak self] granted in
            guard granted, let self else { return }

            let calendar = Calendar.current
            let today    = calendar.startOfDay(for: Date())

            // Build array of past dates: oldest first
            let dates: [Date] = (0..<daysBack).reversed().compactMap {
                calendar.date(byAdding: .day, value: -$0, to: today)
            }

            print("[HealthBridge] Starting historical fetch for \(daysBack) days…")
            self.fetchDaysSequentially(dates: dates, index: 0)
        }
    }

    // Fetch one day at a time to avoid hammering HealthKit
    private func fetchDaysSequentially(dates: [Date], index: Int) {
        guard index < dates.count else {
            print("[HealthBridge] ✅ Historical fetch complete!")
            return
        }

        let dayStart = dates[index]
        let dayEnd   = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let group    = DispatchGroup()

        var steps:    Int     = 0
        var rhr:      Double? = nil
        var exercise: Int     = 0
        var sleep:    Double  = 0

        group.enter()
        querySum(.stepCount, unit: .count(), start: dayStart, end: dayEnd) {
            steps = Int($0 ?? 0); group.leave()
        }

        group.enter()
        queryLatest(.restingHeartRate, unit: HKUnit(from: "count/min"), start: dayStart, end: dayEnd) {
            rhr = $0; group.leave()
        }

        group.enter()
        querySum(.appleExerciseTime, unit: .minute(), start: dayStart, end: dayEnd) {
            exercise = Int($0 ?? 0); group.leave()
        }

        group.enter()
        querySleepHours(start: dayStart, end: dayEnd) {
            sleep = $0; group.leave()
        }

        group.notify(queue: .global(qos: .utility)) { [weak self] in
            guard let self else { return }
            self.appendRow(date: dayStart, steps: steps, rhr: rhr,
                           exercise: exercise, sleep: sleep)
            // Move to next day
            self.fetchDaysSequentially(dates: dates, index: index + 1)
        }
    }

    // ─────────────────────────────────────────
    // MARK: Daily sync (ongoing)
    // ─────────────────────────────────────────

    func syncToday(completion: (() -> Void)? = nil) {
        let end   = Date()
        let start = Calendar.current.startOfDay(for: end)
        let group = DispatchGroup()

        var steps:    Int     = 0
        var rhr:      Double? = nil
        var exercise: Int     = 0
        var sleep:    Double  = 0

        group.enter()
        querySum(.stepCount, unit: .count(), start: start, end: end) {
            steps = Int($0 ?? 0); group.leave()
        }
        group.enter()
        queryLatest(.restingHeartRate, unit: HKUnit(from: "count/min"), start: start, end: end) {
            rhr = $0; group.leave()
        }
        group.enter()
        querySum(.appleExerciseTime, unit: .minute(), start: start, end: end) {
            exercise = Int($0 ?? 0); group.leave()
        }
        group.enter()
        querySleepHours(start: start, end: end) {
            sleep = $0; group.leave()
        }

        group.notify(queue: .global(qos: .utility)) { [weak self] in
            guard let self else { completion?(); return }
            let today = Calendar.current.startOfDay(for: Date())
            self.appendRow(date: today, steps: steps, rhr: rhr,
                           exercise: exercise, sleep: sleep)
            completion?()
        }
    }

    // ─────────────────────────────────────────
    // MARK: Background delivery
    // ─────────────────────────────────────────

    private func registerBackgroundDelivery() {
        let watched: [(HKObjectType, HKUpdateFrequency)] = [
            (HKObjectType.quantityType(forIdentifier: .stepCount)!,         .hourly),
            (HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,  .daily),
            (HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!, .hourly),
            (HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,     .daily)
        ]
        for (type, frequency) in watched {
            store.enableBackgroundDelivery(for: type, frequency: frequency) { _, _ in }
            let query = HKObserverQuery(sampleType: type as! HKSampleType, predicate: nil) {
                [weak self] _, completionHandler, error in
                guard error == nil else { completionHandler(); return }
                self?.syncToday { completionHandler() }
            }
            store.execute(query)
        }
    }

    // ─────────────────────────────────────────
    // MARK: CSV helpers
    // ─────────────────────────────────────────

    private func createCSVIfNeeded() {
        guard !FileManager.default.fileExists(atPath: csvURL.path) else { return }
        let header = "date,steps,resting_heart_rate_bpm,exercise_minutes,sleep_hours\n"
        try? header.write(to: csvURL, atomically: true, encoding: .utf8)
        print("[HealthBridge] Created CSV at \(csvURL.path)")
    }

    private func appendRow(date: Date, steps: Int, rhr: Double?,
                           exercise: Int, sleep: Double) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr  = df.string(from: date)
        let rhrStr   = rhr.map { String(format: "%.1f", $0) } ?? ""
        let sleepStr = String(format: "%.2f", sleep)
        let newRow   = "\(dateStr),\(steps),\(rhrStr),\(exercise),\(sleepStr)"

        let existing = (try? String(contentsOf: csvURL, encoding: .utf8)) ?? ""
        var lines    = existing.components(separatedBy: "\n").filter { !$0.isEmpty }

        if let idx = lines.firstIndex(where: { $0.hasPrefix(dateStr) }) {
            lines[idx] = newRow
        } else {
            lines.append(newRow)
        }

        let output = lines.joined(separator: "\n") + "\n"
        try? output.write(to: csvURL, atomically: true, encoding: .utf8)
        print("[HealthBridge] Wrote: \(newRow)")
    }

    // ─────────────────────────────────────────
    // MARK: HealthKit query helpers
    // ─────────────────────────────────────────

    private func querySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                          start: Date, end: Date, completion: @escaping (Double?) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { completion(nil); return }
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred,
                                      options: .cumulativeSum) { _, stats, _ in
            completion(stats?.sumQuantity()?.doubleValue(for: unit))
        }
        store.execute(query)
    }

    private func queryLatest(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                             start: Date, end: Date, completion: @escaping (Double?) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { completion(nil); return }
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort  = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: pred,
                                  limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            completion((samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
        }
        store.execute(query)
    }

    private func querySleepHours(start: Date, end: Date, completion: @escaping (Double) -> Void) {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { completion(0); return }
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKSampleQuery(sampleType: type, predicate: pred,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            let asleep: Set<HKCategoryValueSleepAnalysis> = [
                .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified
            ]
            let seconds = (samples as? [HKCategorySample])?
                .filter { asleep.contains(HKCategoryValueSleepAnalysis(rawValue: $0.value)!) }
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } ?? 0
            completion(seconds / 3600)
        }
        store.execute(query)
    }
}
