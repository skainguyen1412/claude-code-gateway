# Usage & Cost Persistence Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Replace in-memory-only cost tracking with persistent JSON storage and redesign the Usage & Cost dashboard with real historical data.

**Architecture:** New `UsageStore` class handles JSON file persistence at `~/.ccgateway/usage_history.json` with daily summaries. `GatewayServer` delegates cost tracking to `UsageStore`. `UsageCostView` is rewritten with 3-zone layout: summary cards, 30-day trend chart, provider breakdown.

**Tech Stack:** SwiftUI, Swift Charts, Foundation (JSONEncoder/Decoder, FileManager)

---

### Task 1: Create UsageStore model structs

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Models/UsageStore.swift`

**Step 1: Create model structs and UsageStore class**

Create `CCGateWay/CCGateWay/Sources/Models/UsageStore.swift` with:

```swift
import Foundation

struct ProviderUsage: Codable {
    var cost: Double
    var requests: Int
}

struct DailyUsageRecord: Codable, Identifiable {
    var id: String { date }
    let date: String
    var totalCost: Double
    var requestCount: Int
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var providers: [String: ProviderUsage]
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var history: [DailyUsageRecord] = []
    @Published private(set) var todayRecord: DailyUsageRecord

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var todayDateString: String {
        Self.dateFormatter.string(from: Date())
    }

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ccgateway")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("usage_history.json")

        // Temporary today record — will be replaced in loadHistory()
        let today = Self.dateFormatter.string(from: Date())
        self.todayRecord = DailyUsageRecord(
            date: today, totalCost: 0, requestCount: 0,
            totalInputTokens: 0, totalOutputTokens: 0, providers: [:]
        )
        loadHistory()
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            history = [todayRecord]
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            var records = try JSONDecoder().decode([DailyUsageRecord].self, from: data)

            // Find or create today's entry
            let today = todayDateString
            if let idx = records.firstIndex(where: { $0.date == today }) {
                todayRecord = records[idx]
            } else {
                let newToday = DailyUsageRecord(
                    date: today, totalCost: 0, requestCount: 0,
                    totalInputTokens: 0, totalOutputTokens: 0, providers: [:]
                )
                records.append(newToday)
                todayRecord = newToday
            }
            history = records
        } catch {
            print("[UsageStore] ⚠️ Failed to load history: \(error)")
            history = [todayRecord]
        }
    }

    func save() {
        do {
            // Update today's record in history before saving
            if let idx = history.firstIndex(where: { $0.date == todayRecord.date }) {
                history[idx] = todayRecord
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(history)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[UsageStore] ⚠️ Failed to save history: \(error)")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    // MARK: - Recording

    func recordRequest(
        cost: Double, inputTokens: Int, outputTokens: Int, providerName: String
    ) {
        // Check for day rollover
        let today = todayDateString
        if todayRecord.date != today {
            // Finalize yesterday's record
            if let idx = history.firstIndex(where: { $0.date == todayRecord.date }) {
                history[idx] = todayRecord
            }
            // Create new today
            let newToday = DailyUsageRecord(
                date: today, totalCost: 0, requestCount: 0,
                totalInputTokens: 0, totalOutputTokens: 0, providers: [:]
            )
            history.append(newToday)
            todayRecord = newToday
        }

        // Update today's record
        todayRecord.totalCost += cost
        todayRecord.requestCount += 1
        todayRecord.totalInputTokens += inputTokens
        todayRecord.totalOutputTokens += outputTokens

        var providerUsage = todayRecord.providers[providerName] ?? ProviderUsage(cost: 0, requests: 0)
        providerUsage.cost += cost
        providerUsage.requests += 1
        todayRecord.providers[providerName] = providerUsage

        // Update in history array
        if let idx = history.firstIndex(where: { $0.date == todayRecord.date }) {
            history[idx] = todayRecord
        }

        scheduleSave()
    }

    // MARK: - Computed Properties

    var last7DaysCost: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let cutoffStr = Self.dateFormatter.string(from: cutoff)
        return history.filter { $0.date >= cutoffStr }.reduce(0) { $0 + $1.totalCost }
    }

    var last30DaysCost: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let cutoffStr = Self.dateFormatter.string(from: cutoff)
        return history.filter { $0.date >= cutoffStr }.reduce(0) { $0 + $1.totalCost }
    }

    /// Returns last 30 days of records for chart display, filling gaps with zero-cost entries.
    var chartData: [DailyUsageRecord] {
        let calendar = Calendar.current
        var result: [DailyUsageRecord] = []
        let historyByDate = Dictionary(uniqueKeysWithValues: history.map { ($0.date, $0) })

        for dayOffset in (0..<30).reversed() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date())!
            let dateStr = Self.dateFormatter.string(from: date)
            if let record = historyByDate[dateStr] {
                result.append(record)
            } else {
                result.append(DailyUsageRecord(
                    date: dateStr, totalCost: 0, requestCount: 0,
                    totalInputTokens: 0, totalOutputTokens: 0, providers: [:]
                ))
            }
        }
        return result
    }

    /// Parse a date string back to Date for chart display.
    static func parseDate(_ dateString: String) -> Date? {
        dateFormatter.date(from: dateString)
    }
}
```

**Step 2: Build to verify**

Run: `tuist build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Models/UsageStore.swift
git commit -m "feat: add UsageStore with JSON persistence and daily summaries"
```

---

### Task 2: Integrate UsageStore into GatewayServer

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Gateway/GatewayServer.swift`

**Step 1: Add usageStore property and update addLog**

Replace cost-tracking properties and update `addLog` to delegate to `UsageStore`. The new GatewayServer should:

1. Remove these properties: `todayCost`, `monthCost`, `todayRequests`, `providerCosts`
2. Remove `resetDailyCost()` method
3. Add `var usageStore: UsageStore?` property
4. In `addLog(_:)`, after appending the log, call `self.usageStore?.recordRequest(...)`

Updated file should look like:

```swift
import Foundation
import Vapor

@MainActor
final class GatewayServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = "Stopped"
    @Published var requestLogs: [RequestLog] = []

    private var app: Application?
    private var serverTask: Task<Void, Never>?

    let config: GatewayConfig
    var usageStore: UsageStore?

    init(config: GatewayConfig) {
        self.config = config
    }

    func start() {
        guard !isRunning else { return }

        let port = config.port
        let config = self.config

        statusMessage = "Starting..."

        serverTask = Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                var env = Environment.production
                env.arguments = ["vapor"]
                let app = try await Application.make(env)
                app.http.server.configuration.hostname = "127.0.0.1"
                app.http.server.configuration.port = port

                // Allow large payloads from Claude Code (e.g. 100MB)
                app.routes.defaultMaxBodySize = "100mb"

                // Register routes
                let routes = GatewayRoutes(config: config, server: self)
                try routes.boot(app)

                await MainActor.run {
                    self.app = app
                    self.isRunning = true
                    self.statusMessage = "Running on 127.0.0.1:\(port)"
                }

                try await app.execute()
            } catch {
                await MainActor.run {
                    self.isRunning = false
                    self.statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    func stop() {
        app?.server.shutdown()
        serverTask?.cancel()
        serverTask = nil
        app = nil
        isRunning = false
        statusMessage = "Stopped"
    }

    func restart() {
        stop()
        // Brief delay to allow port release
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            start()
        }
    }

    // MARK: - Logging

    nonisolated func addLog(_ log: RequestLog) {
        Task { @MainActor in
            self.requestLogs.append(log)

            // Delegate cost tracking to UsageStore
            self.usageStore?.recordRequest(
                cost: log.cost,
                inputTokens: log.inputTokens,
                outputTokens: log.outputTokens,
                providerName: log.providerName
            )

            // Keep last 1000 logs in memory
            if self.requestLogs.count > 1000 {
                self.requestLogs.removeFirst(self.requestLogs.count - 1000)
            }
        }
    }

    nonisolated func clearLogs() {
        Task { @MainActor in
            self.requestLogs.removeAll()
        }
    }
}
```

**Step 2: Build to verify**

Run: `tuist build`
Expected: Build may fail due to views still referencing removed properties — that's expected, we fix in Tasks 4-6.

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Gateway/GatewayServer.swift
git commit -m "refactor: remove cost tracking from GatewayServer, delegate to UsageStore"
```

---

### Task 3: Wire UsageStore in CCGateWayApp

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/CCGateWayApp.swift`

**Step 1: Create and inject UsageStore**

Add `@StateObject private var usageStore = UsageStore()` and connect it to `GatewayServer`. Inject as `.environmentObject(usageStore)` to both the Window and MenuBarExtra.

Updated file:

```swift
import SwiftUI

@main
struct CCGateWayApp: App {
    @StateObject private var config = GatewayConfig.load()
    @StateObject private var server: GatewayServer
    @StateObject private var usageStore = UsageStore()

    // Track initialization to trigger logic on first start
    @State private var hasInitialized = false

    init() {
        let loadedConfig = GatewayConfig.load()
        _config = StateObject(wrappedValue: loadedConfig)
        _server = StateObject(wrappedValue: GatewayServer(config: loadedConfig))
    }

    var body: some Scene {
        // Main Dashboard Window (single instance only)
        Window("CCGateWay", id: "dashboard") {
            DashboardView()
                .environmentObject(config)
                .environmentObject(server)
                .environmentObject(usageStore)
                .onAppear {
                    handleFirstLaunch()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)

        // Menu Bar Widget
        MenuBarExtra(
            "CCGateWay",
            systemImage: server.isRunning
                ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
        ) {
            MenuBarDropdown()
                .environmentObject(config)
                .environmentObject(server)
                .environmentObject(usageStore)
        }
        .menuBarExtraStyle(.window)
    }

    private func handleFirstLaunch() {
        guard !hasInitialized else { return }
        hasInitialized = true

        // Connect UsageStore to GatewayServer
        server.usageStore = usageStore

        // Start server if needed
        if config.autoStartOnLogin {
            server.start()
        }
    }
}
```

**Step 2: Build to verify**

Run: `tuist build`
Expected: Build may still fail from view references — that's OK.

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/CCGateWayApp.swift
git commit -m "feat: wire UsageStore into app and connect to GatewayServer"
```

---

### Task 4: Update OverviewView to use UsageStore

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/OverviewView.swift`

**Step 1: Replace GatewayServer cost references with UsageStore**

Add `@EnvironmentObject var usageStore: UsageStore` and update the metric cards:

Change line 68 from:
```swift
value: "$\(String(format: "%.4f", server.todayCost))",
```
to:
```swift
value: "$\(String(format: "%.4f", usageStore.todayRecord.totalCost))",
```

Change line 73 from:
```swift
value: "\(server.todayRequests)",
```
to:
```swift
value: "\(usageStore.todayRecord.requestCount)",
```

Add after `@EnvironmentObject var server: GatewayServer`:
```swift
@EnvironmentObject var usageStore: UsageStore
```

**Step 2: Build to verify**

Run: `tuist build`
Expected: Build may still fail from MenuBarDropdown/UsageCostView — that's OK.

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Views/OverviewView.swift
git commit -m "refactor: OverviewView reads from UsageStore"
```

---

### Task 5: Update MenuBarDropdown to use UsageStore

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/MenuBarDropdown.swift`

**Step 1: Replace GatewayServer cost references with UsageStore**

Add `@EnvironmentObject var usageStore: UsageStore` to `MenuBarDropdown`.

Change line 16 from:
```swift
Text("Today: \(formatCost(server.todayCost))")
```
to:
```swift
Text("Today: \(formatCost(usageStore.todayRecord.totalCost))")
```

Change line 78 from:
```swift
cost: server.providerCosts[providerName, default: 0]
```
to:
```swift
cost: usageStore.todayRecord.providers[providerName]?.cost ?? 0
```

**Step 2: Build to verify**

Run: `tuist build`
Expected: Build may still fail from UsageCostView — that's OK.

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Views/MenuBarDropdown.swift
git commit -m "refactor: MenuBarDropdown reads from UsageStore"
```

---

### Task 6: Rewrite UsageCostView with 3-zone layout

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/UsageCostView.swift`

**Step 1: Complete rewrite of UsageCostView**

Replace the entire file content with:

```swift
import Charts
import SwiftUI

struct UsageCostView: View {
    @EnvironmentObject var server: GatewayServer
    @EnvironmentObject var config: GatewayConfig
    @EnvironmentObject var usageStore: UsageStore

    let columns = [
        GridItem(.flexible()), GridItem(.flexible()),
        GridItem(.flexible()), GridItem(.flexible()),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Usage & Cost")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // ZONE 1: Summary Cards
                LazyVGrid(columns: columns, spacing: 16) {
                    MetricCard(
                        title: "Today's Cost",
                        value: formatCost(usageStore.todayRecord.totalCost),
                        icon: "dollarsign.circle.fill"
                    )
                    MetricCard(
                        title: "Today's Requests",
                        value: "\(usageStore.todayRecord.requestCount)",
                        icon: "arrow.left.arrow.right"
                    )
                    MetricCard(
                        title: "7-Day Total",
                        value: formatCost(usageStore.last7DaysCost),
                        icon: "calendar.badge.clock"
                    )
                    MetricCard(
                        title: "30-Day Total",
                        value: formatCost(usageStore.last30DaysCost),
                        icon: "calendar"
                    )
                }

                // ZONE 2: 30-Day Cost Trend
                VStack(alignment: .leading, spacing: 10) {
                    Text("30-Day Cost Trend")
                        .font(.headline)

                    Chart(usageStore.chartData) { record in
                        if let date = UsageStore.parseDate(record.date) {
                            BarMark(
                                x: .value("Date", date, unit: .day),
                                y: .value("Cost", record.totalCost)
                            )
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .cornerRadius(4)
                        }
                    }
                    .frame(height: 250)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            AxisGridLine()
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let cost = value.as(Double.self) {
                                    Text(formatCost(cost))
                                }
                            }
                            AxisGridLine()
                        }
                    }
                }
                .padding(20)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )

                // ZONE 3: Provider Breakdown (Today)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Today's Provider Breakdown")
                        .font(.headline)

                    if usageStore.todayRecord.providers.isEmpty {
                        HStack {
                            Image(systemName: "tray")
                                .foregroundColor(.secondary)
                            Text("No usage today")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        let sorted = usageStore.todayRecord.providers
                            .sorted { $0.value.cost > $1.value.cost }
                        let maxCost = sorted.first?.value.cost ?? 1.0
                        let totalCost = usageStore.todayRecord.totalCost

                        ForEach(sorted, id: \.key) { providerName, usage in
                            ProviderBreakdownRow(
                                name: providerName,
                                cost: usage.cost,
                                requests: usage.requests,
                                percentage: totalCost > 0 ? usage.cost / totalCost : 0,
                                barFraction: maxCost > 0 ? usage.cost / maxCost : 0
                            )
                        }
                    }
                }
                .padding(20)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )

                Spacer()
            }
            .padding()
        }
    }

    private func formatCost(_ cost: Double) -> String {
        if cost == 0 { return "$0" }
        if cost < 0.0001 { return "<$0.0001" }
        if cost >= 1.0 {
            return String(format: "$%.2f", cost)
        }
        return String(format: "$%.4f", cost)
    }
}

struct ProviderBreakdownRow: View {
    let name: String
    let cost: Double
    let requests: Int
    let percentage: Double
    let barFraction: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(name)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                Text("\(requests) req")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Text(String(format: "$%.4f", cost))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))

                Text(String(format: "%.0f%%", percentage * 100))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * barFraction, 4), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}
```

**Step 2: Build to verify**

Run: `tuist build`
Expected: Build succeeds — all references now point to UsageStore

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Views/UsageCostView.swift
git commit -m "feat: rewrite UsageCostView with real data and 3-zone layout"
```

---

### Task 7: Final build verification and save-on-quit

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/CCGateWayApp.swift`

**Step 1: Add save on app termination**

In `CCGateWayApp`, add to the Window scene:

```swift
.onDisappear {
    usageStore.save()
}
```

And add notification observer for app termination. In `handleFirstLaunch()`, add:

```swift
NotificationCenter.default.addObserver(
    forName: NSApplication.willTerminateNotification,
    object: nil,
    queue: .main
) { _ in
    usageStore.save()
}
```

**Step 2: Full build verification**

Run: `tuist build`
Expected: Build succeeds with zero errors

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/CCGateWayApp.swift
git commit -m "feat: save usage data on app termination"
```
