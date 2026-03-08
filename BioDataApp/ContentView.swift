import SwiftUI

// ─────────────────────────────────────────────
// MARK: - Root Tab View
// ─────────────────────────────────────────────

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            CSVView()
                .tabItem {
                    Label("Data", systemImage: "tablecells")
                }
            SuggestionsView()
                .tabItem {
                    Label("Suggestions", systemImage: "sparkles")
                }
        }
        .preferredColorScheme(.dark)
    }
}

// ─────────────────────────────────────────────
// MARK: - Home Tab (title only)
// ─────────────────────────────────────────────

struct HomeView: View {
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.11, blue: 0.16)
                .ignoresSafeArea()

            VStack(spacing: 6) {
                Text("BioData")
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .foregroundColor(.white)
                Text("Health · CSV Bridge")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .tracking(3)
                    .textCase(.uppercase)
            }
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Data Tab (CSV viewer + sync button)
// ─────────────────────────────────────────────

struct CSVView: View {
    @State private var rows:      [[String]] = []
    @State private var headers:   [String]   = []
    @State private var showShare  = false
    @State private var isEmpty    = false
    @State private var isSyncing  = false
    @State private var lastSynced = ""
    @State private var rowCount   = 0

    // Maps raw CSV header → display label
    private let headerLabels: [String: String] = [
        "date":                   "Date",
        "steps":                  "Steps",
        "resting_heart_rate_bpm": "RHR",
        "exercise_minutes":       "Exercise Minutes",
        "sleep_hours":            "Sleep Duration"
    ]

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.11, blue: 0.16)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Top bar ──
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("health_log.csv")
                            .font(.system(size: 17, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("\(rowCount) rows")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(white: 0.4))
                    }
                    Spacer()

                    // Sync button
                    Button(action: triggerSync) {
                        HStack(spacing: 6) {
                            if isSyncing {
                                ProgressView()
                                    .tint(.black)
                                    .scaleEffect(0.8)
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
                        .background(Color(red: 0.79, green: 0.66, blue: 0.30).opacity(0.12))
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

                Divider().opacity(0.12)

                // ── Last synced label ──
                if !lastSynced.isEmpty {
                    Text("Last synced \(lastSynced)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(white: 0.3))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                // ── Table or empty state ──
                if isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "tablecells")
                            .font(.system(size: 44))
                            .foregroundColor(Color(white: 0.2))
                        Text("No data yet")
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundColor(Color(white: 0.3))
                        Text("Tap Sync to fetch your health data")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.22))
                    }
                    Spacer()
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {

                            // Header row
                            HStack(spacing: 0) {
                                ForEach(headers, id: \.self) { h in
                                    Text(headerLabels[h] ?? h)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                                        .tracking(0.8)
                                        .textCase(.uppercase)
                                        .frame(width: colWidth(h), alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                }
                            }
                            .background(Color(white: 1).opacity(0.04))

                            Divider().opacity(0.1)

                            // Data rows — already sorted newest-first in loadCSV
                            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                                HStack(spacing: 0) {
                                    ForEach(Array(zip(headers, row)), id: \.0) { header, cell in
                                        Text(cell.isEmpty ? "—" : cell)
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundColor(cell.isEmpty ? Color(white: 0.28) : .white)
                                            .frame(width: colWidth(header), alignment: .leading)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 12)
                                    }
                                }
                                .background(idx % 2 == 0 ? Color.clear : Color(white: 1).opacity(0.02))

                                Divider().opacity(0.05)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .onAppear(perform: loadCSV)
        .sheet(isPresented: $showShare) {
            ShareSheet(url: csvURL())
        }
    }

    // ── Column widths ──
    private func colWidth(_ header: String) -> CGFloat {
        switch header {
        case "date":                    return 110
        case "steps":                   return 80
        case "resting_heart_rate_bpm":  return 70   // "RHR"
        case "exercise_minutes":        return 150
        case "sleep_hours":             return 130
        default:                        return 120
        }
    }

    // ── Sync ──
    private func triggerSync() {
        isSyncing = true
        HealthBridge.shared.syncToday {
            DispatchQueue.main.async {
                isSyncing = false
                loadCSV()
            }
        }
    }

    // ── Load & sort CSV (newest date first) ──
    private func loadCSV() {
        let url = csvURL()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            isEmpty = true; return
        }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else { isEmpty = true; return }

        isEmpty = false
        headers = lines[0].components(separatedBy: ",")

        // Sort rows by date string descending (YYYY-MM-DD sorts lexicographically)
        rows = lines.dropFirst()
            .map { $0.components(separatedBy: ",") }
            .sorted { ($0.first ?? "") > ($1.first ?? "") }

        rowCount = rows.count

        // Last modified timestamp
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let modified = attrs?[.modificationDate] as? Date {
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d, h:mm a"
            lastSynced = fmt.string(from: modified)
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Suggestions Tab (blank)
// ─────────────────────────────────────────────

struct SuggestionsView: View {
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.11, blue: 0.16)
                .ignoresSafeArea()
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Share sheet
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
