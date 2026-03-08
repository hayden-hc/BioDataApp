import SwiftUI
import Charts

// ─────────────────────────────────────────────
// MARK: - Root Tab View
// ─────────────────────────────────────────────

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            SyncView(selectedTab: $selectedTab)
                .tabItem { Label("Score", systemImage: "heart.fill") }
                .tag(0)
            CSVView(selectedTab: $selectedTab)
                .tabItem { Label("Data", systemImage: "tablecells") }
                .tag(1)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .fontWeight(.semibold)
                .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
            }
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Score Model
// ─────────────────────────────────────────────

struct DayScore: Identifiable {
    var id: Date { date }  // stable identity based on date
    let date: Date
    let score: Double
    let steps: Int
    let restingHR: Int
    let exerciseMinutes: Int
    let sleepHours: Double
}

/// When HR is available: 4 × 25 pts = 100.
/// When HR is missing: reweight steps + exercise + sleep to fill 100.
func computeScore(steps: Int, restingHR: Int, exerciseMinutes: Int, sleepHours: Double) -> Double {
    let stepsNorm    = min(Double(steps) / 10_000.0, 1.0)
    let exerciseNorm = min(Double(exerciseMinutes) / 60.0, 1.0)
    let sleepNorm    = min(max((sleepHours - 4.0) / 4.0, 0.0), 1.0)

    if restingHR > 0 {
        let clamped = max(50.0, min(Double(restingHR), 90.0))
        let hrNorm  = 1.0 - (clamped - 50.0) / 40.0
        return (stepsNorm + hrNorm + exerciseNorm + sleepNorm) / 4.0 * 100.0
    } else {
        return (stepsNorm + exerciseNorm + sleepNorm) / 3.0 * 100.0
    }
}

func scoreColor(_ score: Double) -> Color {
    switch score {
    case 75...: return Color(red: 0.20, green: 0.78, blue: 0.45)
    case 50...: return Color(red: 0.79, green: 0.66, blue: 0.30)
    default:    return Color(red: 0.85, green: 0.35, blue: 0.35)
    }
}

// ─────────────────────────────────────────────
// MARK: - Score Tab
// ─────────────────────────────────────────────

struct SyncView: View {
    @Binding var selectedTab: Int

    @State private var selectedDate    = Date()
    @State private var steps           = "0"
    @State private var exerciseMinutes = "0"
    @State private var sleepHours      = "0.0"
    @State private var restingHR       = ""
    @State private var mood: Double    = 5.0

    @State private var score: Double        = 0
    @State private var recommendations: [String] = []
    @State private var history: [DayScore]  = []

    private let gold = Color(red: 0.79, green: 0.66, blue: 0.30)
    private let bg   = Color(red: 0.05, green: 0.11, blue: 0.16)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // ── App Title ──────────────────────────────
                    HStack {
                        Text("Vita")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        + Text("Metric")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(gold)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    // ── Date Picker (top, prominent) ──────────
                    VStack(spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Date")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Color(white: 0.45))
                                    .tracking(1)
                                    .textCase(.uppercase)
                                DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .colorScheme(.dark)
                                    .tint(gold)
                                    .labelsHidden()
                                    .scaleEffect(1.3, anchor: .leading)
                                    .padding(.bottom, 6)
                                    .onChange(of: selectedDate) { _ in
                                        steps = "0"; exerciseMinutes = "0"
                                        sleepHours = "0.0"; restingHR = ""
                                        recommendations = []
                                        loadFromCSV()
                                        autoScore()
                                    }
                            }
                            Spacer()
                            if isToday(selectedDate) {
                                Text("Today")
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(gold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(gold.opacity(0.15))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(white: 1).opacity(0.05))
                    .cornerRadius(14)
                    .padding(.horizontal)

                    // ── Score Ring ─────────────────────────────
                    ScoreRingView(score: score)

                    // ── Metric Summary ─────────────────────────
                    HStack(spacing: 10) {
                        MetricSummaryCard(label: "Steps",    value: formatSteps(steps),         icon: "figure.walk")
                        MetricSummaryCard(label: "Exercise", value: "\(exerciseMinutes)m",       icon: "flame.fill")
                        MetricSummaryCard(label: "Sleep",    value: "\(sleepHours)h",            icon: "moon.fill")
                    }
                    .padding(.horizontal)

                    // ── Recommendations ────────────────────────
                    if !recommendations.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recommendations")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(gold)
                                .tracking(1)
                                .textCase(.uppercase)
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(recommendations, id: \.self) { rec in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•")
                                            .foregroundColor(gold)
                                            .font(.system(size: 14, weight: .bold))
                                        Text(rec)
                                            .font(.system(size: 13))
                                            .foregroundColor(Color(white: 0.8))
                                    }
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(white: 1).opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 1).opacity(0.07), lineWidth: 1))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }

                    // ── Metric Inputs ──────────────────────────
                    VStack(spacing: 10) {
                        MetricInputRow(label: "Steps",      icon: "figure.walk", value: $steps,           unit: "",    step: 500, isDecimal: false, placeholder: "0")
                        MetricInputRow(label: "Exercise",   icon: "flame.fill",  value: $exerciseMinutes, unit: "min", step: 5,   isDecimal: false, placeholder: "0")
                        MetricInputRow(label: "Sleep",      icon: "moon.fill",   value: $sleepHours,      unit: "hrs", step: 0.5, isDecimal: true,  placeholder: "0.0")
                        MetricInputRow(label: "Resting HR", icon: "heart.fill",  value: $restingHR,       unit: "bpm", step: 1,   isDecimal: false, placeholder: "optional")
                    }
                    .padding(.horizontal)

                    // ── Mood Slider ────────────────────────────
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "face.smiling").foregroundColor(gold).frame(width: 20)
                            Text("Mood")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Color(white: 0.7))
                            Spacer()
                            Text(String(format: "%.1f / 10", mood))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(gold)
                        }
                        Slider(value: $mood, in: 0...10, step: 0.5).tint(gold)
                    }
                    .padding(14)
                    .background(Color(white: 1).opacity(0.04))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // ── Save & Sync ─────────────────────────────
                    HStack(spacing: 14) {
                        Button(action: saveCurrentDay) {
                            Label("Save", systemImage: "square.and.arrow.down")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(gold)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                        }
                        Button(action: syncFromHealth) {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(white: 1).opacity(0.12))
                                .foregroundColor(gold)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(gold.opacity(0.5), lineWidth: 1))
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)

                    // ── Score Trend Chart ──────────────────────
                    if history.count > 1 {
                        ScoreChartView(history: history).padding(.horizontal)
                    }

                    Spacer(minLength: 32)
                }
                .padding(.vertical)
            }
            .refreshable { refresh() }
        }
        .onAppear { refresh() }
        .onChange(of: selectedTab) { tab in
            if tab == 0 { refresh() }
        }
    }

    // ── Helpers ────────────────────────────────

    private func refresh() {
        loadCSVHistoryReturning()
        loadFromCSV()
        autoScore()
    }

    private func autoScore() {
        let s   = Int(steps) ?? 0
        let ex  = Int(exerciseMinutes) ?? 0
        let sl  = Double(sleepHours) ?? 0
        let rhr = restingHR.isEmpty ? nil : Double(restingHR)

        score = computeScore(steps: s, restingHR: Int(rhr ?? 0), exerciseMinutes: ex, sleepHours: sl)

        guard AppSettings.hasProfile, s > 0 || ex > 0 || sl > 0 else { return }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: selectedDate)
        let req     = ScoreRequest(
            userId:          TallyWellAPI.shared.userId,
            profile:         AppSettings.profile,
            steps:           Double(s),
            exerciseMinutes: Double(ex),
            sleepHours:      sl,
            mood:            mood,
            restingHr:       rhr,
            date:            dateStr
        )
        let targetDate = selectedDate
        Task.detached(priority: .background) {
            if let response = try? await TallyWellAPI.shared.postScore(req) {
                await MainActor.run {
                    score           = response.score
                    recommendations = response.recommendations.filter {
                        !$0.contains("0.0h") && !$0.contains("0.0 h")
                    }
                    // Keep graph in sync: update history entry for this date to the API score
                    if let idx = history.firstIndex(where: {
                        Calendar.current.isDate($0.date, inSameDayAs: targetDate)
                    }) {
                        let d = history[idx]
                        history[idx] = DayScore(date: d.date, score: response.score,
                                                steps: d.steps, restingHR: d.restingHR,
                                                exerciseMinutes: d.exerciseMinutes, sleepHours: d.sleepHours)
                    }
                }
            }
        }
    }

    private func loadFromCSV() {
        let url = csvURL()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: selectedDate)
        let lines   = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else { return }
        let headers  = lines[0].components(separatedBy: ",")
        let dateIdx  = headers.firstIndex(of: "date")                   ?? 0
        let stepsIdx = headers.firstIndex(of: "steps")                  ?? 1
        let hrIdx    = headers.firstIndex(of: "resting_heart_rate_bpm") ?? 2
        let exIdx    = headers.firstIndex(of: "exercise_minutes")       ?? 3
        let sleepIdx = headers.firstIndex(of: "sleep_hours")            ?? 4
        for line in lines.dropFirst() {
            let cols = line.components(separatedBy: ",")
            guard cols.count > max(dateIdx, stepsIdx, hrIdx, exIdx, sleepIdx) else { continue }
            guard cols[dateIdx] == dateStr else { continue }
            steps           = cols[stepsIdx]
            exerciseMinutes = cols[exIdx]
            sleepHours      = cols[sleepIdx]
            if !cols[hrIdx].isEmpty { restingHR = cols[hrIdx] }
            break
        }
    }

    /// Loads CSV into `history` and returns the same array (so callers can use it for day_index before state updates).
    private func loadCSVHistoryReturning() -> [DayScore] {
        let url = csvURL()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return history }
        let lines   = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else { return history }
        let headers  = lines[0].components(separatedBy: ",")
        let dateIdx  = headers.firstIndex(of: "date")                   ?? 0
        let stepsIdx = headers.firstIndex(of: "steps")                  ?? 1
        let hrIdx    = headers.firstIndex(of: "resting_heart_rate_bpm") ?? 2
        let exIdx    = headers.firstIndex(of: "exercise_minutes")       ?? 3
        let sleepIdx = headers.firstIndex(of: "sleep_hours")            ?? 4
        let dateFmt  = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"
        let loaded   = lines.dropFirst().compactMap { line -> DayScore? in
            let cols = line.components(separatedBy: ",")
            guard cols.count > max(dateIdx, stepsIdx, hrIdx, exIdx, sleepIdx) else { return nil }
            guard let date = dateFmt.date(from: cols[dateIdx]) else { return nil }
            let s  = Int(cols[stepsIdx])    ?? 0
            let hr = Int(cols[hrIdx])       ?? 0
            let ex = Int(cols[exIdx])       ?? 0
            let sl = Double(cols[sleepIdx]) ?? 0
            return DayScore(date: date, score: computeScore(steps: s, restingHR: hr, exerciseMinutes: ex, sleepHours: sl),
                            steps: s, restingHR: hr, exerciseMinutes: ex, sleepHours: sl)
        }.sorted { $0.date < $1.date }
        history = loaded
        return loaded
    }

    private func loadCSVHistory() {
        _ = loadCSVHistoryReturning()
    }

    private func isToday(_ date: Date) -> Bool { Calendar.current.isDateInToday(date) }

    private func formatSteps(_ s: String) -> String {
        guard let n = Int(s) else { return s }
        return n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }

    /// Save current form values to CSV for the selected date and refresh score.
    private func saveCurrentDay() {
        let s   = Int(steps) ?? 0
        let ex  = Int(exerciseMinutes) ?? 0
        let sl  = Double(sleepHours) ?? 0
        let rhr = restingHR.isEmpty ? nil : Double(restingHR)
        HealthBridge.shared.saveDay(date: selectedDate, steps: s, rhr: rhr, exercise: ex, sleep: sl)
        loadCSVHistoryReturning()
        autoScore()
    }

    /// Fetch the selected day from HealthKit and overwrite form + CSV (then refresh score).
    private func syncFromHealth() {
        HealthBridge.shared.ensureHealthAuthorization { granted in
            guard granted else { return }
            HealthBridge.shared.fetchDay(date: selectedDate) { s, rhr, ex, sl in
                steps           = "\(s)"
                exerciseMinutes = "\(ex)"
                sleepHours      = String(format: "%.2f", sl)
                restingHR       = rhr.map { String(format: "%.0f", $0) } ?? ""
                HealthBridge.shared.saveDay(date: selectedDate, steps: s, rhr: rhr, exercise: ex, sleep: sl)
                loadCSVHistoryReturning()
                autoScore()
            }
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Metric Input Row
// ─────────────────────────────────────────────

struct MetricInputRow: View {
    let label: String
    let icon: String
    @Binding var value: String
    let unit: String
    let step: Double
    let isDecimal: Bool
    let placeholder: String

    private let gold = Color(red: 0.79, green: 0.66, blue: 0.30)

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(gold).frame(width: 20)
                Text(label)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color(white: 0.7))
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: decrement) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(gold)
                        .font(.system(size: 26))
                }
                TextField(placeholder, text: $value)
                    .keyboardType(isDecimal ? .decimalPad : .numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 76)
                    .padding(.vertical, 7)
                    .background(Color(white: 1).opacity(0.08))
                    .cornerRadius(8)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                        .frame(width: 30, alignment: .leading)
                }
                Button(action: increment) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(gold)
                        .font(.system(size: 26))
                }
            }
        }
        .padding(14)
        .background(Color(white: 1).opacity(0.04))
        .cornerRadius(12)
    }

    private func increment() {
        if isDecimal {
            value = String(format: "%.1f", (Double(value) ?? 0) + step)
        } else {
            value = "\((Int(value) ?? 0) + Int(step))"
        }
    }

    private func decrement() {
        if isDecimal {
            value = String(format: "%.1f", max(0, (Double(value) ?? 0) - step))
        } else {
            value = "\(max(0, (Int(value) ?? 0) - Int(step)))"
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Metric Summary Card
// ─────────────────────────────────────────────

struct MetricSummaryCard: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(white: 0.45))
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(white: 1).opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 1).opacity(0.07), lineWidth: 1))
        .cornerRadius(12)
    }
}

// ─────────────────────────────────────────────
// MARK: - Score Ring
// ─────────────────────────────────────────────

struct ScoreRingView: View {
    let score: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(white: 1).opacity(0.06), lineWidth: 12)
                .frame(width: 150, height: 150)
            Circle()
                .trim(from: 0, to: CGFloat(score / 100.0))
                .stroke(scoreColor(score), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 150, height: 150)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: score)
            VStack(spacing: 2) {
                Text("\(Int(score))")
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("SCORE")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .tracking(1)
            }
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Score Chart
// ─────────────────────────────────────────────

enum ChartRange: String, CaseIterable {
    case week  = "1W"
    case two   = "2W"
    case month = "1M"
    case three = "3M"

    var days: Int {
        switch self { case .week: return 7; case .two: return 14; case .month: return 30; case .three: return 90 }
    }
}

struct ScoreChartView: View {
    let history: [DayScore]
    @State private var range: ChartRange = .month

    private let gold = Color(red: 0.79, green: 0.66, blue: 0.30)

    private var filtered: [DayScore] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -range.days, to: Date())!
        return history.filter { $0.date >= cutoff }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Score Trend")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(white: 0.45))
                    .tracking(1)
                    .textCase(.uppercase)
                Spacer()
                Picker("", selection: $range) {
                    ForEach(ChartRange.allCases, id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .colorScheme(.dark)
            }

            if filtered.count > 1 {
                Chart(filtered) { day in
                    LineMark(x: .value("Date", day.date), y: .value("Score", day.score))
                        .foregroundStyle(gold)
                        .interpolationMethod(.catmullRom)
                    AreaMark(x: .value("Date", day.date), y: .value("Score", day.score))
                        .foregroundStyle(LinearGradient(
                            colors: [gold.opacity(0.25), Color.clear],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", day.date), y: .value("Score", day.score))
                        .foregroundStyle(scoreColor(day.score))
                        .symbolSize(30)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, filtered.count / 5))) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(Color(white: 0.4))
                            .font(.system(size: 9, design: .monospaced))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { _ in
                        AxisGridLine().foregroundStyle(Color(white: 1).opacity(0.05))
                        AxisValueLabel()
                            .foregroundStyle(Color(white: 0.4))
                            .font(.system(size: 9, design: .monospaced))
                    }
                }
                .frame(height: 160)
            } else {
                Text("Not enough data for this range")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(white: 0.35))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 80)
            }
        }
        .padding(16)
        .background(Color(white: 1).opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(white: 1).opacity(0.07), lineWidth: 1))
        .cornerRadius(14)
    }
}

// ─────────────────────────────────────────────
// ─────────────────────────────────────────────
// MARK: - Data Tab
// ─────────────────────────────────────────────

struct CSVView: View {
    @Binding var selectedTab: Int

    @State private var rows:        [[String]] = []
    @State private var headers:     [String]   = []
    @State private var showShare    = false
    @State private var isEmpty      = false
    @State private var isFetching   = false
    @State private var fetchStatus: String?    = nil

    private let abbrev: [String: String] = [
        "date": "Date", "steps": "Steps",
        "resting_heart_rate_bpm": "RHR",
        "exercise_minutes": "Ex.Min", "sleep_hours": "Sleep"
    ]
    private var dataHeaders: [String]  { headers.filter { $0 != "date" } }
    private var dateColIndex: Int      { headers.firstIndex(of: "date") ?? 0 }

    private func prettyDate(_ raw: String) -> String {
        let i = DateFormatter(); i.dateFormat = "yyyy-MM-dd"
        let o = DateFormatter(); o.dateFormat = "MMM d"
        return i.date(from: raw.trimmingCharacters(in: .whitespaces)).map { o.string(from: $0) } ?? raw
    }

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.11, blue: 0.16).ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Top bar ──────────────────────────────────
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("History")
                            .font(.system(size: 17, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("\(rows.count) rows")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(white: 0.4))
                    }
                    Spacer()

                    // Sync button
                    Button(action: syncHealth) {
                        HStack(spacing: 6) {
                            if isFetching {
                                ProgressView().tint(.black).scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.down.heart")
                            }
                            Text(isFetching ? "Syncing…" : "Sync")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(white: 0.82))
                        .cornerRadius(10)
                    }
                    .disabled(isFetching)

                    // Export button
                    Button(action: { showShare = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(LinearGradient(
                            colors: [Color(red: 0.79, green: 0.66, blue: 0.30), Color(red: 0.63, green: 0.48, blue: 0.16)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(red: 0.05, green: 0.11, blue: 0.16))

                // Status message
                if let status = fetchStatus {
                    Text(status)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider().opacity(0.15)

                if isEmpty && !isFetching {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "tablecells").font(.system(size: 44)).foregroundColor(Color(white: 0.25))
                        Text("No data yet").font(.system(size: 15, design: .monospaced)).foregroundColor(Color(white: 0.35))
                        Text("Tap Sync to pull from Apple Health")
                            .font(.system(size: 12)).foregroundColor(Color(white: 0.25))
                    }
                    Spacer()
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            // Header row
                            HStack(spacing: 0) {
                                Text("DATE")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                                    .tracking(1)
                                    .frame(width: 52, alignment: .leading)
                                    .padding(.horizontal, 8).padding(.vertical, 10)
                                Rectangle().frame(width: 1)
                                    .foregroundColor(Color(white: 1).opacity(0.1)).padding(.vertical, 4)
                                ForEach(dataHeaders, id: \.self) { h in
                                    Text(abbrev[h] ?? h)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                                        .tracking(1).textCase(.uppercase)
                                        .frame(width: colWidth(h), alignment: .leading)
                                        .padding(.horizontal, 8).padding(.vertical, 10)
                                }
                            }
                            .background(Color(white: 1).opacity(0.04))
                            Divider().opacity(0.1)

                            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                                HStack(spacing: 0) {
                                    let raw = row.indices.contains(dateColIndex) ? row[dateColIndex] : ""
                                    Text(prettyDate(raw))
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                                        .frame(width: 52, alignment: .leading)
                                        .padding(.horizontal, 8).padding(.vertical, 12)
                                    Rectangle().frame(width: 1)
                                        .foregroundColor(Color(white: 1).opacity(0.1)).padding(.vertical, 6)
                                    ForEach(dataHeaders, id: \.self) { h in
                                        let colIdx = headers.firstIndex(of: h) ?? 0
                                        let cell = row.indices.contains(colIdx) ? row[colIdx] : ""
                                        Text(cell.isEmpty ? "—" : formatCell(header: h, value: cell))
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundColor(cell.isEmpty ? Color(white: 0.3) : .white)
                                            .frame(width: colWidth(h), alignment: .leading)
                                            .padding(.horizontal, 8).padding(.vertical, 12)
                                    }
                                }
                                .background(idx % 2 == 0 ? Color.clear : Color(white: 1).opacity(0.02))
                                Divider().opacity(0.06)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            }
        }
        .onAppear(perform: loadCSV)
        .sheet(isPresented: $showShare) { ShareSheet(url: csvURL()) }
    }

    // ── Sync ───────────────────────────────────

    private func syncHealth() {
        isFetching   = true
        fetchStatus  = nil
        HealthBridge.shared.ensureHealthAuthorization { granted in
            guard granted else { isFetching = false; return }

            if rows.isEmpty {
                fetchStatus = "Syncing 90 days of history…"
                HealthBridge.shared.fetchHistory(daysBack: 90) {
                    loadCSV()
                    fetchStatus = "Synced \(rows.count) days"
                    isFetching  = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { fetchStatus = nil }
                }
            } else {
                let today = Calendar.current.startOfDay(for: Date())
                HealthBridge.shared.fetchDay(date: today) { s, rhr, ex, sl in
                    HealthBridge.shared.saveDay(date: today, steps: s, rhr: rhr, exercise: ex, sleep: sl)
                    loadCSV()
                    isFetching  = false
                }
            }
        }
    }

    // ── CSV helpers ────────────────────────────

    private func colWidth(_ header: String) -> CGFloat {
        switch header {
        case "steps": return 68; case "resting_heart_rate_bpm": return 52
        case "exercise_minutes": return 64; case "sleep_hours": return 56
        default: return 70
        }
    }

    private func formatCell(header: String, value: String) -> String {
        switch header {
        case "sleep_hours":      if let d = Double(value) { return String(format: "%.1fh", d) }
        case "exercise_minutes": if let i = Int(value)    { return "\(i)m" }
        default: break
        }
        return value
    }

    private func loadCSV() {
        let url = csvURL()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { isEmpty = true; return }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else { isEmpty = true; return }
        isEmpty = false
        headers = lines[0].components(separatedBy: ",")
        let dateColIdx = (lines.first?.components(separatedBy: ",").firstIndex(of: "date")) ?? 0
        rows = lines.dropFirst()
            .map { $0.components(separatedBy: ",") }
            .sorted { a, b in
                let d1 = a.indices.contains(dateColIdx) ? a[dateColIdx] : ""
                let d2 = b.indices.contains(dateColIdx) ? b[dateColIdx] : ""
                return d1 > d2  // yyyy-MM-dd sorts lexicographically → descending = most recent first
            }
    }
}

// ─────────────────────────────────────────────
// MARK: - Share Sheet
// ─────────────────────────────────────────────

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// ─────────────────────────────────────────────
// MARK: - CSV URL helper
// ─────────────────────────────────────────────

func csvURL() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("health_log.csv")
}

// ─────────────────────────────────────────────
// MARK: - Settings
// ─────────────────────────────────────────────

struct SettingsView: View {
    @State private var apiBaseURL: String = TallyWellAPI.shared.baseURL
    @State private var height: String = "\(Int(AppSettings.heightCm))"
    @State private var weight: String = "\(Int(AppSettings.weightKg))"
    @State private var age: String = "\(AppSettings.age)"
    @State private var gender: String = AppSettings.gender
    @State private var saved = false
    @State private var testMessage: String? = nil
    @State private var testing = false

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.11, blue: 0.16).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Settings")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                        .padding(.top, 20)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("TallyWell API (run on your Mac)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                        Text("Device: use your Mac's IP (e.g. http://172.26.82.41:5001). Simulator: http://localhost:5001. Use http, not https.")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.5))
                        TextField("API base URL", text: $apiBaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(.system(size: 14, design: .monospaced))
                            .padding(12)
                            .background(Color(white: 1).opacity(0.08))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                        Button(action: testConnection) {
                            HStack {
                                if testing { ProgressView().tint(.white).scaleEffect(0.9) }
                                Text(testing ? "Testing…" : "Test connection")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .disabled(testing)
                        if let msg = testMessage {
                            Text(msg)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(msg.hasPrefix("OK") ? Color(red: 0.2, green: 0.78, blue: 0.45) : Color(red: 0.95, green: 0.6, blue: 0.4))
                                .multilineTextAlignment(.leading).padding(.top, 4)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Profile (for API score)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Height (cm)").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(white: 0.5))
                                TextField("170", text: $height).keyboardType(.numberPad)
                                    .font(.system(size: 14, design: .monospaced)).padding(10)
                                    .background(Color(white: 1).opacity(0.08)).cornerRadius(8).foregroundColor(.white)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Weight (kg)").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(white: 0.5))
                                TextField("70", text: $weight).keyboardType(.decimalPad)
                                    .font(.system(size: 14, design: .monospaced)).padding(10)
                                    .background(Color(white: 1).opacity(0.08)).cornerRadius(8).foregroundColor(.white)
                            }
                        }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Age").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(white: 0.5))
                                TextField("30", text: $age).keyboardType(.numberPad)
                                    .font(.system(size: 14, design: .monospaced)).padding(10)
                                    .background(Color(white: 1).opacity(0.08)).cornerRadius(8).foregroundColor(.white)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Gender").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(white: 0.5))
                                Picker("", selection: $gender) {
                                    Text("Male").tag("male"); Text("Female").tag("female")
                                }
                                .pickerStyle(.menu).tint(Color(red: 0.79, green: 0.66, blue: 0.30))
                            }
                        }
                    }

                    if saved {
                        Text("Saved.").font(.system(size: 12)).foregroundColor(Color(red: 0.20, green: 0.78, blue: 0.45))
                    }

                    Button(action: save) {
                        Text("Save")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(LinearGradient(
                                colors: [Color(red: 0.79, green: 0.66, blue: 0.30), Color(red: 0.63, green: 0.48, blue: 0.16)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .cornerRadius(12)
                    }
                    .padding(.top, 8)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .onAppear {
            apiBaseURL = TallyWellAPI.shared.baseURL
            height = "\(Int(AppSettings.heightCm))"; weight = "\(Int(AppSettings.weightKg))"
            age = "\(AppSettings.age)"; gender = AppSettings.gender
        }
    }

    private func save() {
        let url = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty { TallyWellAPI.shared.baseURL = url }
        if let h = Double(height), h > 0 { AppSettings.heightCm = h }
        if let w = Double(weight), w > 0 { AppSettings.weightKg = w }
        if let a = Int(age), a > 0 { AppSettings.age = a }
        AppSettings.gender = gender
        saved = true; testMessage = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
    }

    private func testConnection() {
        save(); testMessage = nil; testing = true
        Task.detached(priority: .userInitiated) {
            let msg = await TallyWellAPI.shared.checkHealth()
            await MainActor.run { testMessage = msg; testing = false }
        }
    }
}

#Preview { ContentView() }
