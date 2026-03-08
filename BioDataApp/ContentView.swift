import SwiftUI

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
// MARK: - Sync Tab
// ─────────────────────────────────────────────

struct SyncView: View {
    @State private var isSyncing  = false
    @State private var lastSynced = "Never"
    @State private var rowCount   = 0

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.11, blue: 0.16)
                .ignoresSafeArea()

            VStack(spacing: 40) {

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

                // Pulse ring + button
                ZStack {
                    if isSyncing {
                        Circle()
                            .stroke(Color(red: 0.79, green: 0.66, blue: 0.30).opacity(0.3), lineWidth: 1)
                            .frame(width: 160, height: 160)
                            .scaleEffect(isSyncing ? 1.4 : 1)
                            .opacity(isSyncing ? 0 : 1)
                            .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: isSyncing)

                        Circle()
                            .stroke(Color(red: 0.79, green: 0.66, blue: 0.30).opacity(0.15), lineWidth: 1)
                            .frame(width: 130, height: 130)
                            .scaleEffect(isSyncing ? 1.3 : 1)
                            .opacity(isSyncing ? 0 : 1)
                            .animation(.easeOut(duration: 1).repeatForever(autoreverses: false).delay(0.2), value: isSyncing)
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
                                .frame(width: 110, height: 110)
                                .shadow(color: Color(red: 0.79, green: 0.66, blue: 0.30).opacity(0.4), radius: 20)

                            if isSyncing {
                                ProgressView()
                                    .tint(.black)
                                    .scaleEffect(1.3)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 32, weight: .medium))
                                    .foregroundColor(.black)
                            }
                        }
                    }
                    .disabled(isSyncing)
                }

                // Status cards
                HStack(spacing: 16) {
                    StatusCard(label: "Last Sync", value: lastSynced, icon: "clock")
                    StatusCard(label: "Rows saved", value: "\(rowCount)", icon: "list.bullet")
                }
                .padding(.horizontal)

                Text(isSyncing ? "Fetching health data…" : "Tap to sync today's data")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
            }
            .padding()
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
        rowCount = max(0, lines.count - 1) // subtract header

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let modified = attrs?[.modificationDate] as? Date {
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d, h:mm a"
            lastSynced = fmt.string(from: modified)
        }
    }
}

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
    @State private var rows:    [[String]] = []
    @State private var headers: [String]  = []
    @State private var showShare = false
    @State private var isEmpty   = false

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.11, blue: 0.16)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // Top bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("health_log.csv")
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
                    // Scrollable table
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {

                            // Header row
                            HStack(spacing: 0) {
                                ForEach(headers, id: \.self) { h in
                                    Text(h)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(Color(red: 0.79, green: 0.66, blue: 0.30))
                                        .tracking(1)
                                        .textCase(.uppercase)
                                        .frame(width: colWidth(h), alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                }
                            }
                            .background(Color(white: 1).opacity(0.04))

                            Divider().opacity(0.1)

                            // Data rows
                            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                                HStack(spacing: 0) {
                                    ForEach(Array(zip(headers, row)), id: \.0) { header, cell in
                                        Text(cell.isEmpty ? "—" : cell)
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundColor(cell.isEmpty ? Color(white: 0.3) : .white)
                                            .frame(width: colWidth(header), alignment: .leading)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 12)
                                    }
                                }
                                .background(idx % 2 == 0 ? Color.clear : Color(white: 1).opacity(0.02))

                                Divider().opacity(0.06)
                            }
                        }
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
        case "date":                    return 110
        case "steps":                   return 80
        case "resting_heart_rate_bpm":  return 160
        case "exercise_minutes":        return 140
        case "sleep_hours":             return 110
        default:                        return 120
        }
    }

    private func loadCSV() {
        let url = csvURL()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            isEmpty = true; return
        }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else { isEmpty = true; return }

        isEmpty  = false
        headers  = lines[0].components(separatedBy: ",")
        rows     = lines.dropFirst().map { $0.components(separatedBy: ",") }
            .reversed() // newest first
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
