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
            CorrelationGraphView()
                .tabItem { Label("Analytics", systemImage: "chart.xyaxis.line") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
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

/// Gradient: 0 → red, 50 → yellow/amber, 100 → green. Each score maps to a single shade.
func scoreColor(_ score: Double) -> Color {
    let s = max(0, min(100, score))
    // Anchors (RGB 0–1): red @ 0, amber @ 50, green @ 100
    let red   = (r: 0.92, g: 0.32, b: 0.28)
    let amber = (r: 0.98, g: 0.72, b: 0.22)
    let green = (r: 0.22, g: 0.78, b: 0.45)
    let r, g, b: Double
    if s <= 50 {
        let t = s / 50
        r = (1 - t) * red.r   + t * amber.r
        g = (1 - t) * red.g   + t * amber.g
        b = (1 - t) * red.b   + t * amber.b
    } else {
        let t = (s - 50) / 50
        r = (1 - t) * amber.r + t * green.r
        g = (1 - t) * amber.g + t * green.g
        b = (1 - t) * amber.b + t * green.b
    }
    return Color(red: r, green: g, blue: b)
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
                    HStack(spacing: 10) {
                        Image("VitaMetrics Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 28)
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

                    // ── Metric Summary (all 4) ─────────────────────────
                    HStack(spacing: 10) {
                        MetricSummaryCard(label: "Steps",    value: formatSteps(steps),         icon: "figure.walk")
                        MetricSummaryCard(label: "Exercise", value: "\(exerciseMinutes)m",       icon: "flame.fill")
                        MetricSummaryCard(label: "Sleep",    value: "\(sleepHours)h",            icon: "moon.fill")
                        MetricSummaryCard(label: "Resting HR", value: restingHR.isEmpty ? "—" : "\(restingHR)", icon: "heart.fill")
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
                        Slider(value: $mood, in: 0...10, step: 0.5)
                        .tint(LinearGradient(
                            colors: [scoreColor(0), scoreColor(50), scoreColor(100)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                    }
                    .padding(14)
                    .background(Color(white: 1).opacity(0.04))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // ── Score Trend Chart / Calendar Heat Map (swipe) ───────
                    if history.count > 1 {
                        ScoreChartOrHeatMapView(history: history).padding(.horizontal)
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
// MARK: - Spider (Radar) Chart — 5 metrics vs goals
// ─────────────────────────────────────────────

/// Single day or weekly average values for the 5 spider axes (same order as goals).
struct SpiderValues {
    var sleepHours: Double
    var activityMinutes: Double
    var steps: Double
    var restingHR: Double  // use goal if missing
    var mood: Double
}

struct SpiderChartView: View {
    let values: SpiderValues
    let goals: SpiderGoals
    let isWeekly: Bool

    private let gold = Color(red: 0.79, green: 0.66, blue: 0.30)
    private let axisLabels = ["Sleep", "Activity", "Steps", "Resting HR", "Mood"]
    private let n = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = (size / 2) * 0.78

            ZStack(alignment: .center) {
                // Goal pentagon (outer)
                SpiderPentagon(radius: radius, center: center, values: [1, 1, 1, 1, 1])
                    .stroke(Color(white: 1).opacity(0.2), lineWidth: 1.5)

                // Grid rings at 25%, 50%, 75%
                ForEach([0.25, 0.5, 0.75], id: \.self) { level in
                    SpiderPentagon(radius: radius * level, center: center, values: [level, level, level, level, level])
                        .stroke(Color(white: 1).opacity(0.06), lineWidth: 0.5)
                }

                // Actual data polygon (filled)
                SpiderPentagon(radius: radius, center: center, values: normalizedValues)
                    .fill(gold.opacity(0.35))
                    .overlay(
                        SpiderPentagon(radius: radius, center: center, values: normalizedValues)
                            .stroke(gold, lineWidth: 2)
                    )

                // Axis labels + goal values at outer edge
                ForEach(0..<n, id: \.self) { i in
                    let angle = angleForIndex(i)
                    let pt = point(radius: radius, angle: angle, center: center)
                    let label = axisLabels[i]
                    let goalText = goalLabel(for: i)
                    VStack(spacing: 2) {
                        Text(goalText)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(white: 0.45))
                        Text(label)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(white: 0.7))
                    }
                    .position(x: pt.x + (pt.x - center.x) * 0.15, y: pt.y + (pt.y - center.y) * 0.15)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 220)
        }
        .padding(14)
        .background(Color(white: 1).opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 1).opacity(0.07), lineWidth: 1))
        .cornerRadius(12)
    }

    /// Normalized 0...1 (1 = at/above goal). RHR: lower is better so use goal/actual.
    private var normalizedValues: [Double] {
        let s = min(1, values.sleepHours / (goals.sleep_hours > 0 ? goals.sleep_hours : 1))
        let a = min(1, values.activityMinutes / (goals.exercise_min > 0 ? goals.exercise_min : 1))
        let st = min(1, values.steps / (goals.steps > 0 ? goals.steps : 1))
        let rhr = values.restingHR > 0 ? min(1, goals.resting_hr / values.restingHR) : 0
        let m = min(1, values.mood / (goals.mood > 0 ? goals.mood : 1))
        return [s, a, st, rhr, m]
    }

    private func angleForIndex(_ i: Int) -> Double {
        // Top = -90° (SwiftUI y down), then clockwise 72° per axis
        return (-90 + Double(i) * 72) * .pi / 180
    }

    private func point(radius: CGFloat, angle: Double, center: CGPoint) -> CGPoint {
        CGPoint(
            x: center.x + radius * Darwin.cos(angle),
            y: center.y + radius * Darwin.sin(angle)
        )
    }

    private func goalLabel(for i: Int) -> String {
        switch i {
        case 0: return String(format: "%.1fh", goals.sleep_hours)
        case 1: return "\(Int(goals.exercise_min))m"
        case 2: return formatSpiderSteps(goals.steps)
        case 3: return "\(Int(goals.resting_hr))"
        case 4: return String(format: "%.1f", goals.mood)
        default: return ""
        }
    }

    private func formatSpiderSteps(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.1fk", v / 1000) }
        return "\(Int(v))"
    }
}

struct SpiderPentagon: Shape {
    let radius: CGFloat
    let center: CGPoint
    let values: [Double]  // 5 values 0–1

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count >= 5 else { return path }
        for i in 0..<5 {
            let angle = (-90 + Double(i) * 72) * .pi / 180
            let r = radius * CGFloat(values[i])
            let pt = CGPoint(x: center.x + r * Darwin.cos(angle), y: center.y + r * Darwin.sin(angle))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}

// ─────────────────────────────────────────────
// MARK: - Score Ring
// ─────────────────────────────────────────────

struct ScoreRingView: View {
    let score: Double

    private var ringGradient: AngularGradient {
        AngularGradient(
            colors: [scoreColor(0), scoreColor(50), scoreColor(100), scoreColor(0)],
            center: .center
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(white: 1).opacity(0.06), lineWidth: 12)
                .frame(width: 150, height: 150)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, score / 100.0))))
                .stroke(ringGradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
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
        VStack(alignment: .leading, spacing: 10) {
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
                            .foregroundStyle(Color(white: 0.5))
                            .font(.system(size: 9, design: .monospaced))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { _ in
                        AxisGridLine().foregroundStyle(Color(white: 1).opacity(0.05))
                        AxisValueLabel()
                            .foregroundStyle(Color(white: 0.5))
                            .font(.system(size: 9, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity)
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
        .frame(maxWidth: .infinity)
        .background(Color(white: 1).opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(white: 1).opacity(0.07), lineWidth: 1))
        .cornerRadius(14)
    }
}

// ─────────────────────────────────────────────
// MARK: - Swipeable Chart / Calendar Heat Map
// ─────────────────────────────────────────────

struct ScoreChartOrHeatMapView: View {
    let history: [DayScore]
    @State private var page: Int = 0

    private let gold = Color(red: 0.79, green: 0.66, blue: 0.30)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Text(page == 0 ? "Swipe → calendar" : "← Swipe back to graph")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(gold.opacity(0.9))
            }
            TabView(selection: $page) {
                ScoreChartView(history: history)
                    .tag(0)
                ScoreCalendarHeatMapView(history: history)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 260)
            .clipped()
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Calendar Heat Map (score color per day)
// ─────────────────────────────────────────────

struct ScoreCalendarHeatMapView: View {
    let history: [DayScore]

    private let calendar = Calendar.current
    private let weekLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private let gold = Color(red: 0.79, green: 0.66, blue: 0.30)
    private let spacing: CGFloat = 5
    /// Height / width: < 1 gives wider-than-tall (horizontal) cells.
    private let cellAspectRatio: CGFloat = 0.58

    private var scoreByDate: [Date: Double] {
        history.reduce(into: [:]) { acc, d in
            acc[calendar.startOfDay(for: d.date)] = d.score
        }
    }

    /// Months to show: most recent first (current, then -1, -2, ...).
    private var monthsToShow: [(start: Date, name: String)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var out: [(Date, String)] = []
        let today = Date()
        for offset in 0..<12 {
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: today),
                  let start = calendar.date(from: calendar.dateComponents([.year, .month], from: monthStart)) else { break }
            out.append((start, formatter.string(from: start)))
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width - 32
            VStack(alignment: .leading, spacing: 0) {
                Text("Score by day")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(white: 0.6))
                    .tracking(1)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(monthsToShow, id: \.start) { monthStart, monthName in
                            MonthHeatMapSection(
                                monthStart: monthStart,
                                monthName: monthName,
                                scoreByDate: scoreByDate,
                                weekLabels: weekLabels,
                                gold: gold,
                                spacing: spacing,
                                cellAspectRatio: cellAspectRatio,
                                availableWidth: availableWidth
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 8) {
                    Text("Low")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(white: 0.5))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [scoreColor(0), scoreColor(50), scoreColor(100)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 8)
                        .frame(maxWidth: .infinity)
                    Text("High")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(white: 0.5))
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
        }
        .frame(height: 260)
        .background(Color(white: 1).opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(white: 1).opacity(0.07), lineWidth: 1))
        .cornerRadius(14)
    }
}

private struct MonthHeatMapSection: View {
    let monthStart: Date
    let monthName: String
    let scoreByDate: [Date: Double]
    let weekLabels: [String]
    let gold: Color
    let spacing: CGFloat
    let cellAspectRatio: CGFloat
    let availableWidth: CGFloat

    private let calendar = Calendar.current

    private var numberOfDaysInMonth: Int {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return 31 }
        return range.count
    }

    private var firstWeekday: Int {
        let w = calendar.component(.weekday, from: monthStart)
        return (w - 1) % 7
    }

    private var totalCells: Int { firstWeekday + numberOfDaysInMonth }

    private var numberOfRows: Int { (totalCells + 6) / 7 }

    private var cellWidth: CGFloat { (availableWidth - (spacing * 6)) / 7 }

    private var cellHeight: CGFloat { cellWidth * cellAspectRatio }

    var body: some View {
        let gridColumns = Array(repeating: GridItem(.fixed(cellWidth), spacing: spacing), count: 7)
        let gridHeight = CGFloat(numberOfRows) * cellHeight + CGFloat(max(0, numberOfRows - 1)) * spacing

        VStack(alignment: .leading, spacing: 6) {
            Text(monthName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(gold)

            HStack(spacing: spacing) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekLabels[i])
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(white: 0.55))
                        .frame(width: cellWidth, alignment: .center)
                }
            }

            LazyVGrid(columns: gridColumns, spacing: spacing) {
                ForEach(0..<totalCells, id: \.self) { i in
                    let cellColor: Color = {
                        if i < firstWeekday { return Color.clear }
                        let day = i - firstWeekday + 1
                        guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else {
                            return Color(white: 0.15)
                        }
                        let key = calendar.startOfDay(for: date)
                        if let score = scoreByDate[key] { return scoreColor(score) }
                        return Color(white: 0.15)
                    }()
                    RoundedRectangle(cornerRadius: 5)
                        .fill(cellColor)
                        .frame(width: cellWidth, height: cellHeight)
                }
            }
            .frame(width: availableWidth, height: gridHeight, alignment: .topLeading)
        }
        .frame(width: availableWidth, alignment: .leading)
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

// MARK: - Parameter subscore (from Correlation tab) — stored for Score page
private let parameterSubscoreKey = "ParameterSubscore"
private let parameterSubscoreParam1Key = "ParameterSubscoreParam1"
private let parameterSubscoreParam2Key = "ParameterSubscoreParam2"

func saveParameterSubscore(_ value: Double, param1: String, param2: String) {
    UserDefaults.standard.set(value, forKey: parameterSubscoreKey)
    UserDefaults.standard.set(param1, forKey: parameterSubscoreParam1Key)
    UserDefaults.standard.set(param2, forKey: parameterSubscoreParam2Key)
}

func loadParameterSubscore() -> (value: Double, param1: String, param2: String)? {
    let p1 = UserDefaults.standard.string(forKey: parameterSubscoreParam1Key) ?? ""
    let p2 = UserDefaults.standard.string(forKey: parameterSubscoreParam2Key) ?? ""
    guard !p1.isEmpty, !p2.isEmpty else { return nil }
    let v = UserDefaults.standard.double(forKey: parameterSubscoreKey)
    return (v, p1, p2)
}

/// Load all rows from health CSV as [DayScore] for use in correlation graph etc.
func loadDayScoresFromCSV() -> [DayScore] {
    let url = csvURL()
    guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
    guard lines.count > 1 else { return [] }
    let headers = lines[0].components(separatedBy: ",")
    let dateIdx = headers.firstIndex(of: "date") ?? 0
    let stepsIdx = headers.firstIndex(of: "steps") ?? 1
    let hrIdx = headers.firstIndex(of: "resting_heart_rate_bpm") ?? 2
    let exIdx = headers.firstIndex(of: "exercise_minutes") ?? 3
    let sleepIdx = headers.firstIndex(of: "sleep_hours") ?? 4
    let dateFmt = DateFormatter()
    dateFmt.dateFormat = "yyyy-MM-dd"
    return lines.dropFirst().compactMap { line -> DayScore? in
        let cols = line.components(separatedBy: ",")
        guard cols.count > max(dateIdx, stepsIdx, hrIdx, exIdx, sleepIdx) else { return nil }
        guard let date = dateFmt.date(from: cols[dateIdx]) else { return nil }
        let s = Int(cols[stepsIdx]) ?? 0
        let hr = Int(cols[hrIdx]) ?? 0
        let ex = Int(cols[exIdx]) ?? 0
        let sl = Double(cols[sleepIdx]) ?? 0
        return DayScore(
            date: date,
            score: computeScore(steps: s, restingHR: hr, exerciseMinutes: ex, sleepHours: sl),
            steps: s,
            restingHR: hr,
            exerciseMinutes: ex,
            sleepHours: sl
        )
    }.sorted { $0.date < $1.date }
}

// ─────────────────────────────────────────────
// MARK: - Correlation Tab (time on X, two standardized params on Y, subscore 0–100)
// ─────────────────────────────────────────────

enum CorrelationParam: String, CaseIterable {
    case steps = "Steps"
    case exercise = "Exercise (min)"
    case sleep = "Sleep (hrs)"
    case restingHR = "Resting HR"
    case score = "Score"

    func rawValue(from d: DayScore) -> Double? {
        switch self {
        case .steps:      return Double(d.steps)
        case .exercise:   return Double(d.exerciseMinutes)
        case .sleep:      return d.sleepHours
        case .restingHR:  return d.restingHR > 0 ? Double(d.restingHR) : nil
        case .score:      return d.score
        }
    }
}

struct CorrelationDayRow: Identifiable {
    let id: Date
    let date: Date
    let score1: Double   // 0–100 from param1 (for subscore)
    let score2: Double   // 0–100 from param2 (for subscore)
    let subscore: Double // 0–100 combined
    let z1: Double       // z-score for param1
    let z2: Double       // z-score for param2
}

struct CorrelationGraphView: View {
    @State private var dataPoints: [DayScore] = []
    @State private var param1: CorrelationParam = .steps
    @State private var param2: CorrelationParam = .sleep
    @State private var timeRange: ChartRange = .month
    @State private var spiderGoals: SpiderGoals?
    @State private var spiderModeSingleDay = true
    private let gold = Color(red: 0.79, green: 0.66, blue: 0.30)
    private let cyan = Color(red: 0.35, green: 0.75, blue: 0.85)

    private var filtered: [DayScore] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -timeRange.days, to: Date())!
        return dataPoints.filter { $0.date >= cutoff }
    }

    private var rows: [CorrelationDayRow] {
        guard !filtered.isEmpty else { return [] }
        let vals1 = filtered.compactMap { param1.rawValue(from: $0) }
        let vals2 = filtered.compactMap { param2.rawValue(from: $0) }
        let mean1 = vals1.isEmpty ? 0 : vals1.reduce(0, +) / Double(vals1.count)
        let mean2 = vals2.isEmpty ? 0 : vals2.reduce(0, +) / Double(vals2.count)
        let var1 = vals1.isEmpty ? 1.0 : vals1.map { ($0 - mean1) * ($0 - mean1) }.reduce(0, +) / Double(vals1.count)
        let var2 = vals2.isEmpty ? 1.0 : vals2.map { ($0 - mean2) * ($0 - mean2) }.reduce(0, +) / Double(vals2.count)
        let s1 = var1 > 1e-10 ? var1.squareRoot() : 1e-6
        let s2 = var2 > 1e-10 ? var2.squareRoot() : 1e-6
        return filtered.map { d in
            let v1 = param1.rawValue(from: d) ?? mean1
            let v2 = param2.rawValue(from: d) ?? mean2
            let z1 = (v1 - mean1) / s1
            let z2 = (v2 - mean2) / s2
            // When "Score" is selected, show actual score (0–100); otherwise show normalized 0–100 from z
            let score1: Double = param1 == .score ? min(100, max(0, d.score)) : min(100, max(0, 50 + 25 * z1))
            let score2: Double = param2 == .score ? min(100, max(0, d.score)) : min(100, max(0, 50 + 25 * z2))
            let subscore = min(100, max(0, 50 + 25 * (z1 + z2)))
            return CorrelationDayRow(id: d.date, date: d.date, score1: score1, score2: score2, subscore: subscore, z1: z1, z2: z2)
        }
    }

    /// Y-axis range for z-scores so all data fits; adds padding and ensures a minimum span.
    private var zScoreYRange: (min: Double, max: Double) {
        guard !rows.isEmpty else { return (-2.5, 2.5) }
        let allZ = rows.flatMap { [ $0.z1, $0.z2 ] }
        guard let lo = allZ.min(), let hi = allZ.max() else { return (-2.5, 2.5) }
        let span = max(hi - lo, 0.5)
        let pad = span * 0.15
        return (lo - pad, hi + pad)
    }

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.11, blue: 0.16).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Analytics")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    // ── Spider: Metrics vs goals ─────────────────────────────
                    if let goals = spiderGoals {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Radar Graph")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(Color(white: 0.55))
                                .padding(.horizontal, 20)
                            Picker("", selection: $spiderModeSingleDay) {
                                Text("Single day").tag(true)
                                Text("Weekly avg").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                            .padding(.horizontal, 20)
                            SpiderChartView(values: spiderValues(goals: goals), goals: goals, isWeekly: !spiderModeSingleDay)
                                .padding(.horizontal, 20)
                        }
                    }

                    // ── Comparison: z-scores over time ────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Compare Metrics (z-scores)")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Color(white: 0.55))
                            .padding(.horizontal, 20)

                        HStack(spacing: 12) {
                            Picker("", selection: $param1) {
                                ForEach(CorrelationParam.allCases, id: \.self) { p in
                                    Text(p.rawValue).tag(p)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(gold)
                            Picker("", selection: $param2) {
                                ForEach(CorrelationParam.allCases, id: \.self) { p in
                                    Text(p.rawValue).tag(p)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(gold)
                            Spacer()
                            Picker("", selection: $timeRange) {
                                ForEach(ChartRange.allCases, id: \.self) { r in
                                    Text(r.rawValue).tag(r)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                        }
                        .padding(.horizontal, 20)

                        if rows.isEmpty {
                            Text("No data for this range. Add days in Score or Data.")
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(Color(white: 0.45))
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                                .padding()
                        } else {
                            VStack(spacing: 0) {
                                Chart(rows) { r in
                                    LineMark(
                                        x: .value("Date", r.date),
                                        y: .value("z score", r.z1),
                                        series: .value("Series", "Param1")
                                    )
                                    .foregroundStyle(gold)
                                    .interpolationMethod(.linear)
                                    LineMark(
                                        x: .value("Date", r.date),
                                        y: .value("z score", r.z2),
                                        series: .value("Series", "Param2")
                                    )
                                    .foregroundStyle(cyan)
                                    .interpolationMethod(.linear)
                                }
                                .chartYScale(domain: zScoreYRange.min...zScoreYRange.max)
                                .chartXAxis {
                                    AxisMarks(values: .stride(by: .day, count: max(1, rows.count / 5))) { _ in
                                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                            .foregroundStyle(Color(white: 0.5))
                                            .font(.system(size: 9, design: .monospaced))
                                    }
                                }
                                .chartYAxis {
                                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                                        AxisGridLine().foregroundStyle(Color(white: 1).opacity(0.08))
                                        AxisValueLabel {
                                            if let v = value.as(Double.self) {
                                                Text(String(format: "%.1f", v))
                                                    .foregroundStyle(Color(white: 0.5))
                                                    .font(.system(size: 10, design: .monospaced))
                                            }
                                        }
                                    }
                                }
                                .chartYAxisLabel(position: .leading) {
                                    Text("z scores").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(white: 0.5))
                                }
                                .chartPlotStyle { plotArea in
                                    plotArea.padding(.horizontal, 8).padding(.vertical, 4)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 260)
                            .padding(.horizontal, 12)
                            .clipped()

                            HStack(spacing: 14) {
                                HStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 2).fill(gold).frame(width: 12, height: 8)
                                    Text(param1.rawValue).font(.system(size: 10, design: .monospaced)).foregroundColor(Color(white: 0.6))
                                }
                                HStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 2).fill(cyan).frame(width: 12, height: 8)
                                    Text(param2.rawValue).font(.system(size: 10, design: .monospaced)).foregroundColor(Color(white: 0.6))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                        }
                    }
                }
            }
        }
        .onAppear {
            dataPoints = loadDayScoresFromCSV()
            loadSpiderGoalsIfNeeded()
        }
        .onChange(of: param1) { _ in persistTodaySubscore() }
        .onChange(of: param2) { _ in persistTodaySubscore() }
        .onChange(of: timeRange) { _ in persistTodaySubscore() }
        .onChange(of: dataPoints.count) { _ in persistTodaySubscore() }
    }

    private func loadSpiderGoalsIfNeeded() {
        guard AppSettings.hasProfile else { return }
        Task {
            do {
                let g = try await TallyWellAPI.shared.fetchGoals(profile: AppSettings.profile)
                await MainActor.run { spiderGoals = g }
            } catch {
                await MainActor.run { spiderGoals = nil }
            }
        }
    }

    private func spiderValues(goals: SpiderGoals) -> SpiderValues {
        guard !dataPoints.isEmpty else {
            return SpiderValues(sleepHours: 0, activityMinutes: 0, steps: 0, restingHR: goals.resting_hr, mood: 5)
        }
        if spiderModeSingleDay {
            let d = dataPoints.last!
            let rhr = d.restingHR > 0 ? Double(d.restingHR) : goals.resting_hr
            return SpiderValues(
                sleepHours: d.sleepHours,
                activityMinutes: Double(d.exerciseMinutes),
                steps: Double(d.steps),
                restingHR: rhr,
                mood: 5.0
            )
        }
        let last7 = Array(dataPoints.suffix(7))
        let n = Double(last7.count)
        let sumSleep = last7.map(\.sleepHours).reduce(0, +)
        let sumEx = last7.map { Double($0.exerciseMinutes) }.reduce(0, +)
        let sumSteps = last7.map { Double($0.steps) }.reduce(0, +)
        let rhrs = last7.map { Double($0.restingHR) }.filter { $0 > 0 }
        return SpiderValues(
            sleepHours: sumSleep / n,
            activityMinutes: sumEx / n,
            steps: sumSteps / n,
            restingHR: rhrs.isEmpty ? goals.resting_hr : rhrs.reduce(0, +) / Double(rhrs.count),
            mood: 5.0
        )
    }

    private func persistTodaySubscore() {
        guard !rows.isEmpty else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let row = rows.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) })
            ?? rows.last!
        saveParameterSubscore(row.subscore, param1: param1.rawValue, param2: param2.rawValue)
    }
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
