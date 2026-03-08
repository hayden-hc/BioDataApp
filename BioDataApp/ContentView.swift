import SwiftUI
import Charts

// ─────────────────────────────────────────────
// MARK: - Root Tab View
// ─────────────────────────────────────────────

struct ContentView: View {
    var body: some View {
        TabView {
            SyncView()
                .tabItem {
                    Label("Sync", systemImage: "heart.fill")
                }
            CSVView()
                .tabItem {
                    Label("Data", systemImage: "tablecells")
                }
        }
        .preferredColorScheme(.dark)
    }
}

// ─────────────────────────────────────────────
// MARK: - Score Model
// ─────────────────────────────────────────────

struct DayScore: Identifiable {
    let id = UUID()
    let date: Date
    let score: Double
    let steps: Int
    let restingHR: Int
    let exerciseMinutes: Int
    let sleepHours: Double
}

/// Scores each metric 0–25, total 0–100
func computeScore(steps: Int, restingHR: Int, exerciseMinutes: Int, sleepHours: Double) -> Double {
    // Steps: 0 = 0pts, 10000+ = 25pts
    let stepsScore = min(Double(steps) / 10_000.0, 1.0) * 25.0

    // Resting HR: 50 or below = 25pts, 90+ = 0pts (lower is better)
    let hrScore: Double = {
        if restingHR <= 0 { return 0 }
        let clamped = max(50.0, min(Double(restingHR), 90.0))
        return (1.0 - (clamped - 50.0) / 40.0) * 25.0
    }()

    // Exercise: 0 = 0pts, 60+ mins = 25pts
    let exerciseScore = min(Double(exerciseMinutes) / 60.0, 1.0) * 25.0

    // Sleep: 4h = 0pts, 8h = 25pts, scales linearly
    let sleepScore = min(max((sleepHours - 4.0) / 4.0, 0.0), 1.0) * 25.0

    return stepsScore + hrScore + exerciseScore + sleepScore
}

func scoreColor(_ score: Double) -> Color {
    switch score {
    case 75...: return Color(red: 0.20, green: 0.78, blue: 0.45)
    case 50...: return Color(red: 0.79, green: 0.66, blue: 0.30)
    default:    return Color(red: 0.85, green: 0.35, blue: 0.35)
    }
}

// ─────────────────────────────────────────────
// MARK: - Sync Tab
// ─────────────────────────────────────────────

struct SyncView: View {
    @State private var isSyncing   = false
    @State private var lastSynced  = "Never"
    @State private var rowCount    = 0
    @State private var todayScore: Double = 0
    @State private var history: [DayScore] = []

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.11, blue: 0.16)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {

                    // Title
                    VStack(spacing: 6) {
                        Text("BioData")
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .foregroundColor(.white)
                        Text("Health → CSV Bridge")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Color(white: 0.5))
                            .tracking(2)
                            .textCase(.uppercase)
                    }
                    .padding(.top, 20)

                    // ── Score Ring ──────────────────────────────
                    ScoreRingView(score: todayScore)

                    // ── Sync + Update buttons ───────────────────
                    HStack(spacing: 16) {
                        // Sync button (pulse ring)
                        ZStack {
                            if isSyncing {
                                Circle()
                                    .stroke(Color(red: 0.79, green: 0.66, blue: 0.30).opacity(0.3), lineWidth: 1)
                                    .frame(width: 100, height: 100)
                                    .scaleEffect(isSyncing ? 1.4 : 1)
                                    .opacity(isSyncing ? 0 : 1)
                                    .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: isSyncing)
                            }

                            Button(action: triggerSync) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.79, green: 0.66, blue: 0.30),
                                                    Color(red: 0.63, green: 0.48, blue: 0.16)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 80, height: 80)
                                        .shadow(color: Color(red: 0.79, green: 0.66, blue: 0.30).opacity(0.4), radius: 16)

                                    if isSyncing {
                                        ProgressView().tint(.black).scaleEffect(1.2)
                                    } else {
                                        VStack(spacing: 3) {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                                .font(.system(size: 22, weight: .medium))
                                                .foregroundColor(.black)
                                            Text("Sync")
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundColor(.black)
                                        }
                                    }
                                }
                            }
                            .disabled(isSyncing)
                        }

                        // Update Today button
                        Button(action: triggerSync) {
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(Color(white: 1).opacity(0.06))
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Circle().stroke(Color(white: 1).opacity(0.1), lineWidth: 1)
                                        )
                                    VStack(spacing: 3) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 22, weight: .medium))
                                            .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                                        Text("Update")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                                    }
                                }
                            }
                        }
                        .disabled(isSyncing)
                    }

                    // ── Status cards ────────────────────────────
                    HStack(spacing: 16) {
                        StatusCard(label: "Last Sync", value: lastSynced, icon: "clock")
                        StatusCard(label: "Rows saved", value: "\(rowCount)", icon: "list.bullet")
                    }
                    .padding(.horizontal)

                    Text(isSyncing ? "Fetching health data…" : "Tap Sync to fetch today's data")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))

                    // ── Score Chart ─────────────────────────────
                    if history.count > 1 {
                        ScoreChartView(history: history)
                            .padding(.horizontal)
                    }

                    // ── History Log ─────────────────────────────
                    if !history.isEmpty {
                        HistoryLogView(history: history)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 32)
                }
                .padding()
            }
        }
        .onAppear { refreshStats() }
    }

    private func triggerSync() {
        isSyncing = true
        HealthBridge.shared.syncToday {
            DispatchQueue.main.async {
                isSyncing = false
                refreshStats()
            }
        }
    }

    private func refreshStats() {
        let url = csvURL()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        rowCount = max(0, lines.count - 1)

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let modified = attrs?[.modificationDate] as? Date {
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d, h:mm a"
            lastSynced = fmt.string(from: modified)
        }

        // Parse CSV into DayScore history
        guard lines.count > 1 else { return }
        let headers = lines[0].components(separatedBy: ",")
        let dateIdx    = headers.firstIndex(of: "date")               ?? 0
        let stepsIdx   = headers.firstIndex(of: "steps")              ?? 1
        let hrIdx      = headers.firstIndex(of: "resting_heart_rate_bpm") ?? 2
        let exIdx      = headers.firstIndex(of: "exercise_minutes")   ?? 3
        let sleepIdx   = headers.firstIndex(of: "sleep_hours")        ?? 4

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        history = lines.dropFirst().compactMap { line -> DayScore? in
            let cols = line.components(separatedBy: ",")
            guard cols.count > max(dateIdx, stepsIdx, hrIdx, exIdx, sleepIdx) else { return nil }
            guard let date = dateFmt.date(from: cols[dateIdx]) else { return nil }
            let steps    = Int(cols[stepsIdx])    ?? 0
            let hr       = Int(cols[hrIdx])       ?? 0
            let exercise = Int(cols[exIdx])       ?? 0
            let sleep    = Double(cols[sleepIdx]) ?? 0
            let score    = computeScore(steps: steps, restingHR: hr, exerciseMinutes: exercise, sleepHours: sleep)
            return DayScore(date: date, score: score, steps: steps, restingHR: hr, exerciseMinutes: exercise, sleepHours: sleep)
        }
        .sorted { $0.date < $1.date }

        todayScore = history.last?.score ?? 0
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
                .stroke(
                    scoreColor(score),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .frame(width: 150, height: 150)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: score)

            VStack(spacing: 2) {
                Text("\(Int(score))")
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("TODAY'S SCORE")
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

struct ScoreChartView: View {
    let history: [DayScore]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Score Trend")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(white: 0.45))
                .tracking(1)
                .textCase(.uppercase)

            Chart(history) { day in
                LineMark(
                    x: .value("Date", day.date),
                    y: .value("Score", day.score)
                )
                .foregroundStyle(Color(red: 0.79, green: 0.66, blue: 0.30))
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Date", day.date),
                    y: .value("Score", day.score)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.79, green: 0.66, blue: 0.30).opacity(0.25),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", day.date),
                    y: .value("Score", day.score)
                )
                .foregroundStyle(scoreColor(day.score))
                .symbolSize(30)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, history.count / 5))) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(Color(white: 0.4))
                        .font(.system(size: 9, design: .monospaced))
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine().foregroundStyle(Color(white: 1).opacity(0.05))
                    AxisValueLabel()
                        .foregroundStyle(Color(white: 0.4))
                        .font(.system(size: 9, design: .monospaced))
                }
            }
            .frame(height: 160)
        }
        .padding(16)
        .background(Color(white: 1).opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(white: 1).opacity(0.07), lineWidth: 1))
        .cornerRadius(14)
    }
}

// ─────────────────────────────────────────────
// MARK: - History Log
// ─────────────────────────────────────────────

struct HistoryLogView: View {
    let history: [DayScore]

    private var sorted: [DayScore] { history.reversed() }

    private let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Past Metrics")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(white: 0.45))
                .tracking(1)
                .textCase(.uppercase)

            VStack(spacing: 1) {
                // Column headers
                HStack {
                    Text("DATE")
                        .frame(width: 60, alignment: .leading)
                    Spacer()
                    Text("SCORE")
                        .frame(width: 46, alignment: .trailing)
                    Text("STEPS")
                        .frame(width: 52, alignment: .trailing)
                    Text("HR")
                        .frame(width: 34, alignment: .trailing)
                    Text("EX")
                        .frame(width: 34, alignment: .trailing)
                    Text("ZZZ")
                        .frame(width: 38, alignment: .trailing)
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                .tracking(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(white: 1).opacity(0.04))

                ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, day in
                    HStack {
                        Text(dateFmt.string(from: day.date))
                            .frame(width: 60, alignment: .leading)
                            .foregroundColor(Color(white: 0.6))
                        Spacer()
                        Text("\(Int(day.score))")
                            .frame(width: 46, alignment: .trailing)
                            .foregroundColor(scoreColor(day.score))
                            .fontWeight(.semibold)
                        Text("\(day.steps)")
                            .frame(width: 52, alignment: .trailing)
                            .foregroundColor(.white)
                        Text(day.restingHR > 0 ? "\(day.restingHR)" : "—")
                            .frame(width: 34, alignment: .trailing)
                            .foregroundColor(.white)
                        Text("\(day.exerciseMinutes)m")
                            .frame(width: 34, alignment: .trailing)
                            .foregroundColor(.white)
                        Text(String(format: "%.1fh", day.sleepHours))
                            .frame(width: 38, alignment: .trailing)
                            .foregroundColor(.white)
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(idx % 2 == 0 ? Color.clear : Color(white: 1).opacity(0.02))

                    if idx < sorted.count - 1 {
                        Divider().opacity(0.06)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .background(Color(white: 1).opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(white: 1).opacity(0.07), lineWidth: 1))
        .cornerRadius(14)
    }
}

// ─────────────────────────────────────────────
// MARK: - Status Card
// ─────────────────────────────────────────────

struct StatusCard: View {
    let label: String
    let value: String
    let icon:  String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                Text(label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(white: 0.45))
                    .tracking(1)
                    .textCase(.uppercase)
            }
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(white: 1).opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(white: 1).opacity(0.07), lineWidth: 1)
        )
        .cornerRadius(14)
    }
}

// ─────────────────────────────────────────────
// MARK: - CSV Tab
// ─────────────────────────────────────────────

struct CSVView: View {
    @State private var rows:     [[String]] = []
    @State private var headers:  [String]  = []
    @State private var showShare = false
    @State private var isEmpty   = false

    private let abbrev: [String: String] = [
        "date":                   "Date",
        "steps":                  "Steps",
        "resting_heart_rate_bpm": "RHR",
        "exercise_minutes":       "Ex.Min",
        "sleep_hours":            "Sleep"
    ]

    private var dataHeaders: [String] {
        headers.filter { $0 != "date" }
    }

    private var dateColIndex: Int {
        headers.firstIndex(of: "date") ?? 0
    }

    private func prettyDate(_ raw: String) -> String {
        let inFmt  = DateFormatter(); inFmt.dateFormat  = "yyyy-MM-dd"
        let outFmt = DateFormatter(); outFmt.dateFormat = "MMM d"
        if let d = inFmt.date(from: raw.trimmingCharacters(in: .whitespaces)) {
            return outFmt.string(from: d)
        }
        return raw
    }

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.11, blue: 0.16)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Top bar ──────────────────────────────────
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("History")
                            .font(.system(size: 17, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("\(rows.count) rows")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(white: 0.4))
                    }
                    Spacer()
                    Button(action: { showShare = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.79, green: 0.66, blue: 0.30),
                                    Color(red: 0.63, green: 0.48, blue: 0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(red: 0.05, green: 0.11, blue: 0.16))

                Divider().opacity(0.15)

                if isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "tablecells")
                            .font(.system(size: 44))
                            .foregroundColor(Color(white: 0.25))
                        Text("No data yet")
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundColor(Color(white: 0.35))
                        Text("Tap Sync to fetch your health data")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.25))
                    }
                    Spacer()
                } else {

                    // ── Single vertical ScrollView: date + data scroll together ──
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {

                            // Header row inside scroll so it hugs the first data row
                            HStack(spacing: 0) {
                                Text("DATE")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                                    .tracking(1)
                                    .frame(width: 52, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 10)

                                Rectangle()
                                    .frame(width: 1)
                                    .foregroundColor(Color(white: 1).opacity(0.1))
                                    .padding(.vertical, 4)

                                ForEach(dataHeaders, id: \.self) { h in
                                    Text(abbrev[h] ?? h)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                                        .tracking(1)
                                        .textCase(.uppercase)
                                        .frame(width: colWidth(h), alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 10)
                                }
                            }
                            .background(Color(white: 1).opacity(0.04))

                            Divider().opacity(0.1)

                            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                                HStack(spacing: 0) {

                                    // Frozen date cell
                                    let raw = row.indices.contains(dateColIndex) ? row[dateColIndex] : ""
                                    Text(prettyDate(raw))
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                                        .frame(width: 52, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 12)

                                    Rectangle()
                                        .frame(width: 1)
                                        .foregroundColor(Color(white: 1).opacity(0.1))
                                        .padding(.vertical, 6)

                                    // Data cells — same widths as headers
                                    ForEach(dataHeaders, id: \.self) { h in
                                        let colIdx = headers.firstIndex(of: h) ?? 0
                                        let cell = row.indices.contains(colIdx) ? row[colIdx] : ""
                                        Text(cell.isEmpty ? "—" : formatCell(header: h, value: cell))
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundColor(cell.isEmpty ? Color(white: 0.3) : .white)
                                            .frame(width: colWidth(h), alignment: .leading)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 12)
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
        .sheet(isPresented: $showShare) {
            ShareSheet(url: csvURL())
        }
    }

    private func colWidth(_ header: String) -> CGFloat {
        switch header {
        case "steps":                   return 68
        case "resting_heart_rate_bpm":  return 52
        case "exercise_minutes":        return 64
        case "sleep_hours":             return 56
        default:                        return 70
        }
    }

    private func formatCell(header: String, value: String) -> String {
        switch header {
        case "sleep_hours":
            if let d = Double(value) { return String(format: "%.1fh", d) }
        case "exercise_minutes":
            if let i = Int(value) { return "\(i)m" }
        default: break
        }
        return value
    }

    private func loadCSV() {
        let url = csvURL()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            isEmpty = true; return
        }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else { isEmpty = true; return }

        isEmpty = false
        headers = lines[0].components(separatedBy: ",")
        rows    = lines.dropFirst().map { $0.components(separatedBy: ",") }.reversed()
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
// MARK: - Shared CSV URL helper
// ─────────────────────────────────────────────

func csvURL() -> URL {
    FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("health_log.csv")
}

#Preview {
    ContentView()
}
