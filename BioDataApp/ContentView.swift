import SwiftUI
import Charts

// ─────────────────────────────────────────────
// MARK: - Root Tab View
// ─────────────────────────────────────────────

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "heart.fill")
                }
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "tablecells")
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
    let mood: Int
}

// ── API config — change IP to your Mac's local WiFi address ──
let kAPIBase = "http://10.144.131.189:5001"
let kUserID  = "user_1"   // change per user if needed

// User profile sent with every /score call — update to match real user
let kUserProfile: [String: Any] = [
    "height_cm": 175,
    "weight_kg": 70,
    "gender":    "male",
    "age":       25
]

// ── Fetch score from Python model via POST /score ──────────────
func fetchAPIScore(
    steps: Int,
    restingHR: Int,
    exerciseMinutes: Int,
    sleepHours: Double,
    mood: Int,
    completion: @escaping (Double?) -> Void
) {
    print("1 fetch")
    guard let url = URL(string: "\(kAPIBase)/score") else { completion(nil); return }

    var body: [String: Any] = [
        "user_id":          kUserID,
        "profile":          kUserProfile,
        "steps":            steps,
        "exercise_minutes": exerciseMinutes,
        "sleep_hours":      sleepHours,
        "mood":             mood
    ]
    if restingHR > 0 { body["resting_hr"] = restingHR }
    print("2 fetch")
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.timeoutInterval = 6
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)

    print("3 fetch")
    URLSession.shared.dataTask(with: req) { data, _, error in
        if let error = error {
            print("❌ API network error: \(error.localizedDescription)")
            completion(nil); return
        }
        guard let data = data else {
            print("❌ API error: no data")
            completion(nil); return
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ API error: bad JSON — \(String(data: data, encoding: .utf8) ?? "?")")
            completion(nil); return
        }
        guard let score = json["score"] as? Double else {
            print("❌ API error: missing score key — \(json)")
            completion(nil); return
        }
        print("✅ API score received: \(score)")
        completion(score)
    }.resume()
    print("4 fetch")
}

func scoreColor(_ score: Double) -> Color {
    switch score {
    case 75...: return Color(red: 0.20, green: 0.78, blue: 0.45)
    case 50...: return Color(red: 0.79, green: 0.66, blue: 0.30)
    default:    return Color(red: 0.85, green: 0.35, blue: 0.35)
    }
}

// ─────────────────────────────────────────────
// MARK: - Mood persistence helper
// ─────────────────────────────────────────────

func todayKey() -> String {
    let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
    return fmt.string(from: Date())
}

func savedMoodForToday() -> Int {
    UserDefaults.standard.integer(forKey: "mood_\(todayKey())")
}

func saveMoodForToday(_ mood: Int) {
    UserDefaults.standard.set(mood, forKey: "mood_\(todayKey())")
    writeMoodToCSV(mood)
}

func writeMoodToCSV(_ mood: Int) {
    let url = csvURL()
    guard var content = try? String(contentsOf: url, encoding: .utf8) else { return }
    var lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
    guard lines.count > 0 else { return }

    var headers = lines[0].components(separatedBy: ",")
    let today   = todayKey()

    // Add mood column to header if missing
    if !headers.contains("mood") {
        headers.append("mood")
        lines[0] = headers.joined(separator: ",")
    }

    let moodIdx = headers.firstIndex(of: "mood")!
    let dateIdx = headers.firstIndex(of: "date") ?? 0

    // Find today's row and update or add mood
    var found = false
    for i in 1..<lines.count {
        var cols = lines[i].components(separatedBy: ",")
        if cols.indices.contains(dateIdx) && cols[dateIdx] == today {
            // Pad if needed
            while cols.count <= moodIdx { cols.append("") }
            cols[moodIdx] = "\(mood)"
            lines[i] = cols.joined(separator: ",")
            found = true
            break
        }
    }

    // If today's row doesn't exist yet, append a minimal one
    if !found {
        var newRow = Array(repeating: "", count: headers.count)
        newRow[dateIdx] = today
        newRow[moodIdx] = "\(mood)"
        lines.append(newRow.joined(separator: ","))
    }

    content = lines.joined(separator: "\n") + "\n"
    try? content.write(to: url, atomically: true, encoding: .utf8)
}

// ─────────────────────────────────────────────
// MARK: - Home Tab
// ─────────────────────────────────────────────

struct HomeView: View {
    @State private var todayScore: Double = 0
    @State private var selectedMood: Int  = 0
    @State private var history: [DayScore] = []
    @State private var isLoadingScore = false

    private let moodOptions: [(Int, String, String)] = [
        (1, "Terrible", "1"),
        (2, "Bad",      "2"),
        (3, "Okay",     "3"),
        (4, "Good",     "4"),
        (5, "Great",    "5")
    ]

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.11, blue: 0.16)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 36) {

                    // ── Title ───────────────────────────────────
                    VStack(spacing: 6) {
                        Text("BioData")
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .foregroundColor(.white)
                        Text("Health · CSV Bridge")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Color(white: 0.5))
                            .tracking(2)
                            .textCase(.uppercase)
                    }
                    .padding(.top, 24)

                    // ── Score Ring ──────────────────────────────
                    ZStack {
                        ScoreRingView(score: todayScore)
                        if isLoadingScore {
                            ProgressView()
                                .tint(Color(white: 0.5))
                                .offset(y: 52)
                        }
                    }

                    // ── Score Chart ─────────────────────────────
                    if history.count > 1 {
                        ScoreChartView(history: history)
                            .padding(.horizontal)
                    }

                    // ── Mood Survey ─────────────────────────────
                    VStack(alignment: .leading, spacing: 14) {
                        Text("How are you feeling today?")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(white: 0.45))
                            .tracking(1)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)

                        HStack(spacing: 8) {
                            ForEach(moodOptions, id: \.0) { value, label, num in
                                let isSelected = selectedMood == value
                                Button(action: {
                                    selectedMood = value
                                    saveMoodForToday(value)
                                }) {
                                    VStack(spacing: 5) {
                                        Text(num)
                                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                                            .foregroundColor(isSelected ? .black : Color(white: 0.6))
                                        Text(label)
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundColor(isSelected ? .black : Color(white: 0.4))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        isSelected
                                            ? LinearGradient(
                                                colors: [
                                                    Color(red: 0.79, green: 0.66, blue: 0.30),
                                                    Color(red: 0.63, green: 0.48, blue: 0.16)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                              )
                                            : LinearGradient(
                                                colors: [Color(white: 1).opacity(0.05), Color(white: 1).opacity(0.05)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                              )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(
                                                isSelected
                                                    ? Color(red: 0.79, green: 0.66, blue: 0.30).opacity(0.6)
                                                    : Color(white: 1).opacity(0.07),
                                                lineWidth: 1
                                            )
                                    )
                                    .cornerRadius(10)
                                }
                            }
                        }

                        if selectedMood > 0 {
                            Text("Mood saved for today ✓")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(white: 0.35))
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 32)
                }
                .padding(.horizontal)
            }
        }
        .onAppear {
            selectedMood = savedMoodForToday()
            loadStats()
        }
    }

    private func loadStats() {
        let url = csvURL()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else { return }

        let headers  = lines[0].components(separatedBy: ",")
        let dateIdx  = headers.firstIndex(of: "date")                   ?? 0
        let stepsIdx = headers.firstIndex(of: "steps")                  ?? 1
        let hrIdx    = headers.firstIndex(of: "resting_heart_rate_bpm") ?? 2
        let exIdx    = headers.firstIndex(of: "exercise_minutes")       ?? 3
        let sleepIdx = headers.firstIndex(of: "sleep_hours")            ?? 4
        let moodIdx  = headers.firstIndex(of: "mood")

        let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"

        // Parse CSV rows — score starts at 0, API will fill it in
        let parsed = lines.dropFirst().compactMap { line -> DayScore? in
            let cols = line.components(separatedBy: ",")
            guard cols.indices.contains(dateIdx),
                  let date = dateFmt.date(from: cols[dateIdx]) else { return nil }
            let steps    = Int(cols[safe: stepsIdx] ?? "")    ?? 0
            let hr       = Int(cols[safe: hrIdx] ?? "")       ?? 0
            let exercise = Int(cols[safe: exIdx] ?? "")       ?? 0
            let sleep    = Double(cols[safe: sleepIdx] ?? "") ?? 0
            let mood     = moodIdx.flatMap { Int(cols[safe: $0] ?? "") } ?? 0
            // score = 0 as placeholder; API call below will replace it
            return DayScore(date: date, score: 0, steps: steps, restingHR: hr,
                            exerciseMinutes: exercise, sleepHours: sleep, mood: mood)
        }
        .sorted { $0.date < $1.date }

        history = parsed
        todayScore = 0

        // Fetch API scores for every row, update history and todayScore as results arrive
        isLoadingScore = true
        let group = DispatchGroup()

        var updatedHistory = parsed

        for (i, day) in parsed.enumerated() {
            group.enter()
            fetchAPIScore(
                steps:           day.steps,
                restingHR:       day.restingHR,
                exerciseMinutes: day.exerciseMinutes,
                sleepHours:      day.sleepHours,
                mood:            day.mood > 0 ? day.mood : 3
            ) { apiScore in
                guard let apiScore else {
                    print("⚠️ API returned nil for row \(i) — score stays 0")
                    group.leave(); return
                }
                let updated = DayScore(
                    date: day.date, score: apiScore,
                    steps: day.steps, restingHR: day.restingHR,
                    exerciseMinutes: day.exerciseMinutes,
                    sleepHours: day.sleepHours, mood: day.mood
                )
                DispatchQueue.main.async {
                    updatedHistory[i] = updated
                    self.history = updatedHistory
                    // Keep todayScore in sync with the last (most recent) entry
                    if i == parsed.count - 1 {
                        self.todayScore = apiScore
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.history = updatedHistory
            self.todayScore = updatedHistory.last?.score ?? 0
            self.isLoadingScore = false
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - History Tab (table + sync)
// ─────────────────────────────────────────────

struct HistoryView: View {
    @State private var rows:      [[String]] = []
    @State private var headers:   [String]   = []
    @State private var showShare  = false
    @State private var isEmpty    = false
    @State private var isSyncing  = false
    @State private var lastSynced = ""
    @State private var history: [DayScore] = []
    @State private var isLoadingScores = false

    private let abbrev: [String: String] = [
        "date":                   "Date",
        "steps":                  "Steps",
        "resting_heart_rate_bpm": "RHR",
        "exercise_minutes":       "Ex",
        "sleep_hours":            "Sleep",
        "mood":                   "Mood"
    ]

    private var dataHeaders: [String] { headers.filter { $0 != "date" } }
    private var dateColIndex: Int     { headers.firstIndex(of: "date") ?? 0 }

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

                    // Sync button
                    Button(action: triggerSync) {
                        HStack(spacing: 6) {
                            if isSyncing {
                                ProgressView().tint(.black).scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(isSyncing ? "Syncing…" : "Sync")
                        }
                        .font(.system(size: 13, weight: .medium))
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
                    .disabled(isSyncing)

                    // Export button
                    Button(action: { showShare = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.79, green: 0.66, blue: 0.30).opacity(0.1))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(red: 0.79, green: 0.66, blue: 0.30).opacity(0.3), lineWidth: 1)
                        )
                    }
                    .disabled(isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                if !lastSynced.isEmpty {
                    Text("Last synced \(lastSynced)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(white: 0.3))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)
                }

                Divider().opacity(0.12)

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

                    // ── Table ────────────────────────────────────
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {

                            // Header row
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

                    // ── Score Chart ──────────────────────────
                    if isLoadingScores {
                        HStack(spacing: 8) {
                            ProgressView().tint(Color(white: 0.5))
                            Text("Loading scores…")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(white: 0.35))
                        }
                        .padding(.vertical, 12)
                    } else if history.count > 1 {
                        ScoreChartView(history: history)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
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
        case "steps":                   return 56
        case "resting_heart_rate_bpm":  return 42
        case "exercise_minutes":        return 50
        case "sleep_hours":             return 46
        case "mood":                    return 36
        default:                        return 56
        }
    }

    private func formatCell(header: String, value: String) -> String {
        switch header {
        case "sleep_hours":
            if let d = Double(value) { return String(format: "%.1f", d) }
        case "exercise_minutes":
            if let i = Int(value) { return "\(i)m" }
        case "mood":
            return value
        default: break
        }
        return value
    }

    private func triggerSync() {
        isSyncing = true
        HealthBridge.shared.syncToday {
            DispatchQueue.main.async {
                isSyncing = false
                loadCSV()
            }
        }
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
        rows    = lines.dropFirst()
            .map { $0.components(separatedBy: ",") }
            .sorted { ($0.first ?? "") > ($1.first ?? "") }

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let modified = attrs?[.modificationDate] as? Date {
            let fmt = DateFormatter(); fmt.dateFormat = "MMM d, h:mm a"
            lastSynced = fmt.string(from: modified)
        }

        // Parse into DayScore for chart — score = 0 until API responds
        let hdrs     = lines[0].components(separatedBy: ",")
        let dateIdx  = hdrs.firstIndex(of: "date")                   ?? 0
        let stepsIdx = hdrs.firstIndex(of: "steps")                  ?? 1
        let hrIdx    = hdrs.firstIndex(of: "resting_heart_rate_bpm") ?? 2
        let exIdx    = hdrs.firstIndex(of: "exercise_minutes")       ?? 3
        let sleepIdx = hdrs.firstIndex(of: "sleep_hours")            ?? 4
        let moodIdx  = hdrs.firstIndex(of: "mood")
        let dateFmt  = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"

        let parsed = lines.dropFirst().compactMap { line -> DayScore? in
            let cols = line.components(separatedBy: ",")
            guard cols.indices.contains(dateIdx),
                  let date = dateFmt.date(from: cols[dateIdx]) else { return nil }
            let steps    = Int(cols[safe: stepsIdx] ?? "")    ?? 0
            let hr       = Int(cols[safe: hrIdx] ?? "")       ?? 0
            let exercise = Int(cols[safe: exIdx] ?? "")       ?? 0
            let sleep    = Double(cols[safe: sleepIdx] ?? "") ?? 0
            let mood     = moodIdx.flatMap { Int(cols[safe: $0] ?? "") } ?? 0
            // score = 0 as placeholder; API will replace it
            return DayScore(date: date, score: 0, steps: steps, restingHR: hr,
                            exerciseMinutes: exercise, sleepHours: sleep, mood: mood)
        }.sorted { $0.date < $1.date }

        history = parsed
        isLoadingScores = true

        var updatedHistory = parsed
        let group = DispatchGroup()

        for (i, day) in parsed.enumerated() {
            group.enter()
            fetchAPIScore(
                steps:           day.steps,
                restingHR:       day.restingHR,
                exerciseMinutes: day.exerciseMinutes,
                sleepHours:      day.sleepHours,
                mood:            day.mood > 0 ? day.mood : 3
            ) { apiScore in
                guard let apiScore else {
                    print("⚠️ API returned nil for history row \(i) — score stays 0")
                    group.leave(); return
                }
                let updated = DayScore(
                    date: day.date, score: apiScore,
                    steps: day.steps, restingHR: day.restingHR,
                    exerciseMinutes: day.exerciseMinutes,
                    sleepHours: day.sleepHours, mood: day.mood
                )
                DispatchQueue.main.async {
                    updatedHistory[i] = updated
                    self.history = updatedHistory
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.history = updatedHistory
            self.isLoadingScores = false
        }
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
                LineMark(x: .value("Date", day.date), y: .value("Score", day.score))
                    .foregroundStyle(Color(red: 0.79, green: 0.66, blue: 0.30))
                    .interpolationMethod(.catmullRom)
                AreaMark(x: .value("Date", day.date), y: .value("Score", day.score))
                    .foregroundStyle(LinearGradient(
                        colors: [Color(red: 0.79, green: 0.66, blue: 0.30).opacity(0.25), Color.clear],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Date", day.date), y: .value("Score", day.score))
                    .foregroundStyle(scoreColor(day.score))
                    .symbolSize(30)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, history.count / 5))) { _ in
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
        }
        .padding(16)
        .background(Color(white: 1).opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(white: 1).opacity(0.07), lineWidth: 1))
        .cornerRadius(14)
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
// MARK: - Helpers
// ─────────────────────────────────────────────

func csvURL() -> URL {
    FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("health_log.csv")
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    ContentView()
}
