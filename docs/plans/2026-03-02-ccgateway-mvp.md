# CCGateWay Full Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Build a native macOS app with a Dashboard window (control panel) + Menu Bar widget (quick switch) + embedded Vapor gateway server that proxies Claude Code to alternative LLM providers.

**Architecture:** Single Swift binary with SwiftUI (Dashboard + MenuBarExtra) and an embedded Vapor server on a background thread. SQLite for usage logging. Keychain for API keys. Config JSON for provider/slot settings. Reference implementation: `claude-code-router` at `/Users/chaileasevn/Desktop/Code/claude-code-router`.

**Tech Stack:** Swift, SwiftUI, Vapor, Tuist, SQLite (via GRDB or raw), macOS Keychain

---

### Task 1: Add Vapor dependency to Tuist project

**Files:**
- Modify: `CCGateWay/Tuist.swift`
- Modify: `CCGateWay/Project.swift`

**Step 1: Update `Tuist.swift` to declare Vapor as external SPM dependency**

```swift
// CCGateWay/Tuist.swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(),
    dependencies: .init(
        swiftPackageManager: .init([
            .remote(
                url: "https://github.com/vapor/vapor.git",
                requirement: .upToNextMajor(from: "4.99.0")
            ),
        ])
    )
)
```

**Step 2: Update `Project.swift` to link Vapor and set macOS deployment target**

```swift
// CCGateWay/Project.swift
import ProjectDescription

let project = Project(
    name: "CCGateWay",
    targets: [
        .target(
            name: "CCGateWay",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.CCGateWay",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "LSUIElement": .boolean(true),
            ]),
            buildableFolders: [
                "CCGateWay/Sources",
                "CCGateWay/Resources",
            ],
            dependencies: [
                .external(name: "Vapor"),
            ]
        ),
        .target(
            name: "CCGateWayTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.tuist.CCGateWayTests",
            infoPlist: .default,
            buildableFolders: [
                "CCGateWay/Tests"
            ],
            dependencies: [.target(name: "CCGateWay")]
        ),
    ]
)
```

Note: `LSUIElement: true` makes the app run without a Dock icon (menu bar style). We will add an `NSApplication` activation toggle to show the Dashboard window on demand.

**Step 3: Fetch and generate**

Run:
```bash
cd CCGateWay && tuist install && tuist generate
```
Expected: Xcode project generated with Vapor linked.

**Step 4: Verify build**

Run: `cd CCGateWay && tuist build`
Expected: Build succeeds.

**Step 5: Commit**

```bash
cd .. && git add -A && git commit -m "feat: add Vapor dependency to Tuist project"
```

---

### Task 2: Create data models — GatewayConfig, ProviderConfig, SlotRouter

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Models/GatewayConfig.swift`
- Create: `CCGateWay/CCGateWay/Sources/Models/ProviderConfig.swift`
- Create: `CCGateWay/CCGateWay/Sources/Models/SlotRouter.swift`
- Create: `CCGateWay/CCGateWay/Sources/Models/RequestLog.swift`

**Step 1: Create ProviderConfig**

```swift
// CCGateWay/CCGateWay/Sources/Models/ProviderConfig.swift
import Foundation

struct ProviderConfig: Codable, Identifiable, Hashable {
    var id: String { name.lowercased() }
    var name: String
    var type: String              // "gemini", "openrouter", "openai", "anthropic"
    var baseUrl: String
    var slots: [String: String]   // "default" -> "gemini-2.5-pro"
    var enabled: Bool = true
}
```

**Step 2: Create GatewayConfig**

```swift
// CCGateWay/CCGateWay/Sources/Models/GatewayConfig.swift
import Foundation

class GatewayConfig: ObservableObject, Codable {
    @Published var activeProvider: String
    @Published var port: Int
    @Published var providers: [String: ProviderConfig]
    @Published var autoStartOnLogin: Bool

    enum CodingKeys: String, CodingKey {
        case activeProvider, port, providers, autoStartOnLogin
    }

    init(activeProvider: String = "gemini", port: Int = 3456,
         providers: [String: ProviderConfig] = [:], autoStartOnLogin: Bool = false) {
        self.activeProvider = activeProvider
        self.port = port
        self.providers = providers
        self.autoStartOnLogin = autoStartOnLogin
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeProvider = try c.decode(String.self, forKey: .activeProvider)
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 3456
        providers = try c.decode([String: ProviderConfig].self, forKey: .providers)
        autoStartOnLogin = try c.decodeIfPresent(Bool.self, forKey: .autoStartOnLogin) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(activeProvider, forKey: .activeProvider)
        try c.encode(port, forKey: .port)
        try c.encode(providers, forKey: .providers)
        try c.encode(autoStartOnLogin, forKey: .autoStartOnLogin)
    }

    // MARK: - Persistence

    static var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("CCGateWay")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> GatewayConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(GatewayConfig.self, from: data) else {
            return GatewayConfig()
        }
        return config
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) {
            try? data.write(to: GatewayConfig.configURL, options: .atomic)
        }
    }

    // MARK: - Auto-import from claude-code-router

    static func importFromClaudeCodeRouter() -> GatewayConfig? {
        let routerConfigURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-code-router/config.json")
        guard let data = try? Data(contentsOf: routerConfigURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providersArr = json["Providers"] as? [[String: Any]] else {
            return nil
        }

        var providers: [String: ProviderConfig] = [:]
        for p in providersArr {
            guard let name = p["name"] as? String,
                  let baseUrl = p["api_base_url"] as? String else { continue }
            let models = p["models"] as? [String] ?? []
            let type = detectProviderType(name: name, baseUrl: baseUrl)
            let slots = buildSlotsFromModels(models: models)
            providers[name] = ProviderConfig(
                name: name, type: type, baseUrl: baseUrl, slots: slots
            )
        }

        // Parse router section for active provider
        let router = json["Router"] as? [String: Any]
        let defaultRoute = router?["default"] as? String ?? ""
        let activeProvider = defaultRoute.components(separatedBy: ",").first ?? providers.keys.first ?? ""

        let config = GatewayConfig(activeProvider: activeProvider, providers: providers)
        return config
    }

    private static func detectProviderType(name: String, baseUrl: String) -> String {
        if baseUrl.contains("generativelanguage.googleapis.com") || name.lowercased().contains("gemini") {
            return "gemini"
        } else if baseUrl.contains("openrouter.ai") {
            return "openrouter"
        } else if baseUrl.contains("api.openai.com") {
            return "openai"
        } else if baseUrl.contains("api.deepseek.com") {
            return "deepseek"
        }
        return "openai" // default to OpenAI-compatible
    }

    private static func buildSlotsFromModels(models: [String]) -> [String: String] {
        guard let first = models.first else { return ["default": ""] }
        return [
            "default": first,
            "background": models.count > 1 ? models[1] : first,
            "think": first,
            "longContext": first
        ]
    }
}
```

**Step 3: Create SlotRouter**

```swift
// CCGateWay/CCGateWay/Sources/Models/SlotRouter.swift
import Foundation

struct SlotRouter {
    static let anthropicModelToSlot: [String: String] = [
        "claude-3-5-haiku": "background",
        "claude-3-haiku": "background",
        "claude-3-5-sonnet": "default",
        "claude-3-sonnet": "default",
        "claude-sonnet-4": "default",
        "claude-3-opus": "think",
        "claude-opus-4": "think",
    ]

    static func resolve(requestedModel: String, provider: ProviderConfig) -> (slot: String, providerModel: String) {
        // Exact match
        if let slot = anthropicModelToSlot[requestedModel],
           let model = provider.slots[slot] {
            return (slot, model)
        }
        // Partial match
        for (pattern, slot) in anthropicModelToSlot {
            if requestedModel.contains(pattern), let model = provider.slots[slot] {
                return (slot, model)
            }
        }
        // Thinking keyword
        if requestedModel.contains("thinking") || requestedModel.contains("think"),
           let model = provider.slots["think"] {
            return ("think", model)
        }
        // Fallback
        let model = provider.slots["default"] ?? provider.slots.values.first ?? requestedModel
        return ("default", model)
    }
}
```

**Step 4: Create RequestLog model**

```swift
// CCGateWay/CCGateWay/Sources/Models/RequestLog.swift
import Foundation

struct RequestLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let slot: String
    let providerModel: String
    let inputTokens: Int
    let outputTokens: Int
    let cost: Double
    let latencyMs: Int
    let success: Bool

    var formattedLine: String {
        let time = Self.timeFormatter.string(from: timestamp)
        let tokens = inputTokens + outputTokens
        let costStr = String(format: "$%.4f", cost)
        let latency = String(format: "%.1fs", Double(latencyMs) / 1000.0)
        return "[\(time)] \(slot) → \(providerModel) | \(tokens) tok | \(costStr) | \(latency)"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
```

**Step 5: Verify build**

Run: `cd CCGateWay && tuist build`
Expected: Build succeeds.

**Step 6: Commit**

```bash
cd .. && git add -A && git commit -m "feat: add data models — GatewayConfig, ProviderConfig, SlotRouter, RequestLog"
```

---

### Task 3: Create the embedded Vapor GatewayServer

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Gateway/GatewayServer.swift`

**Step 1: Create GatewayServer class**

```swift
// CCGateWay/CCGateWay/Sources/Gateway/GatewayServer.swift
import Vapor
import Foundation

@MainActor
final class GatewayServer: ObservableObject {
    @Published var isRunning = false
    @Published var statusMessage = "Stopped"
    @Published var requestLogs: [RequestLog] = []
    @Published var todayCost: Double = 0.0
    @Published var monthCost: Double = 0.0
    @Published var todayRequests: Int = 0

    private var app: Application?
    private var serverTask: Task<Void, Never>?

    let config: GatewayConfig

    init(config: GatewayConfig) {
        self.config = config
    }

    func start() {
        guard !isRunning else { return }

        let port = config.port
        let config = self.config

        serverTask = Task.detached { [weak self] in
            do {
                let app = try await Application.make(.production)
                app.http.server.configuration.hostname = "127.0.0.1"
                app.http.server.configuration.port = port

                // Register routes
                GatewayRoutes.register(on: app, config: config, server: self)

                await MainActor.run {
                    self?.app = app
                    self?.isRunning = true
                    self?.statusMessage = "Running on port \(port)"
                }

                try await app.execute()
            } catch {
                await MainActor.run {
                    self?.isRunning = false
                    self?.statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    func stop() {
        app?.shutdown()
        serverTask?.cancel()
        serverTask = nil
        app = nil
        isRunning = false
        statusMessage = "Stopped"
    }

    nonisolated func addLog(_ log: RequestLog) {
        Task { @MainActor in
            self.requestLogs.append(log)
            self.todayCost += log.cost
            self.todayRequests += 1
            // Keep last 500 logs in memory
            if self.requestLogs.count > 500 {
                self.requestLogs.removeFirst(self.requestLogs.count - 500)
            }
        }
    }
}
```

**Step 2: Verify build**

Run: `cd CCGateWay && tuist build`
Expected: Build succeeds.

**Step 3: Commit**

```bash
cd .. && git add -A && git commit -m "feat: add GatewayServer with embedded Vapor"
```

---

### Task 4: Implement Gemini Provider Adapter

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Gateway/Providers/ProviderAdapter.swift`
- Create: `CCGateWay/CCGateWay/Sources/Gateway/Providers/GeminiAdapter.swift`

**Step 1: Define ProviderAdapter protocol**

```swift
// CCGateWay/CCGateWay/Sources/Gateway/Providers/ProviderAdapter.swift
import Vapor

protocol ProviderAdapter {
    var providerType: String { get }

    func transformRequest(
        anthropicBody: [String: Any],
        targetModel: String,
        provider: ProviderConfig,
        apiKey: String
    ) throws -> (url: URI, headers: HTTPHeaders, body: [String: Any])

    func transformResponse(responseData: Data, isStreaming: Bool) throws -> Data
}
```

**Step 2: Implement GeminiAdapter**

Reference: `/Users/chaileasevn/Desktop/Code/claude-code-router/packages/core/src/utils/gemini.util.ts`

The adapter must handle:
- Anthropic `system` field → Gemini `contents` (as first user turn)
- Anthropic `messages` → Gemini `contents` (role mapping: assistant→model)
- Anthropic `tools` → Gemini `functionDeclarations`
- Tool call/result round-trips
- Gemini response → Anthropic message format (text + tool_use content blocks)

Full implementation in `GeminiAdapter.swift` — translate the `buildRequestBody()` and `transformResponseOut()` functions from the TS reference into Swift. Key mappings:
- `user` → `user`, `assistant` → `model`
- `tool_use` content blocks → `functionCall` parts
- `tool_result` content blocks → `functionResponse` parts
- Gemini `usageMetadata` → Anthropic `usage` (promptTokenCount → input_tokens, candidatesTokenCount → output_tokens)

**Step 3: Verify build**

Run: `cd CCGateWay && tuist build`

**Step 4: Commit**

```bash
cd .. && git add -A && git commit -m "feat: add GeminiAdapter — Anthropic<->Gemini format translation"
```

---

### Task 5: Wire gateway routes — `/v1/messages` and `/health`

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Gateway/GatewayRoutes.swift`
- Create: `CCGateWay/CCGateWay/Sources/Gateway/KeychainManager.swift`

**Step 1: Create KeychainManager**

Simple wrapper around Security framework for save/load/delete of API keys.

**Step 2: Create GatewayRoutes**

The `/v1/messages` handler:
1. Parse raw JSON body
2. Get active provider from config
3. Resolve model name → slot → provider model via SlotRouter
4. Get API key from Keychain (fallback to env var)
5. Transform request via adapter
6. Send HTTP request to provider
7. Transform response back to Anthropic format
8. Log the request (timestamp, slot, model, tokens, cost, latency)
9. Return Anthropic-compatible JSON

**Step 3: Verify build**

Run: `cd CCGateWay && tuist build`

**Step 4: Commit**

```bash
cd .. && git add -A && git commit -m "feat: wire /v1/messages route through slot router and adapter"
```

---

### Task 6: Build the App Shell — Dashboard + MenuBar dual-window

**Files:**
- Rewrite: `CCGateWay/CCGateWay/Sources/CCGateWayApp.swift`
- Create: `CCGateWay/CCGateWay/Sources/Views/DashboardView.swift`
- Create: `CCGateWay/CCGateWay/Sources/Views/SidebarView.swift`
- Create: `CCGateWay/CCGateWay/Sources/Views/MenuBarDropdown.swift`

**Step 1: Rewrite CCGateWayApp.swift**

```swift
// CCGateWay/CCGateWay/Sources/CCGateWayApp.swift
import SwiftUI

@main
struct CCGateWayApp: App {
    @StateObject private var config = GatewayConfig.load()
    @StateObject private var gateway: GatewayServer

    init() {
        let cfg = GatewayConfig.load()

        // Auto-import from claude-code-router on first launch
        if cfg.providers.isEmpty, let imported = GatewayConfig.importFromClaudeCodeRouter() {
            _config = StateObject(wrappedValue: imported)
            _gateway = StateObject(wrappedValue: GatewayServer(config: imported))
            imported.save()
        } else {
            _config = StateObject(wrappedValue: cfg)
            _gateway = StateObject(wrappedValue: GatewayServer(config: cfg))
        }
    }

    var body: some Scene {
        // Main Dashboard Window
        Window("CCGateWay", id: "dashboard") {
            DashboardView(config: config, gateway: gateway)
        }
        .defaultSize(width: 900, height: 600)

        // Menu Bar Widget
        MenuBarExtra {
            MenuBarDropdown(config: config, gateway: gateway)
        } label: {
            let costStr = String(format: "$%.2f", gateway.todayCost)
            let provider = config.activeProvider.capitalized
            Label("\(costStr) • \(provider)", systemImage: "bolt.fill")
        }
    }
}
```

**Step 2: Create DashboardView with sidebar navigation**

NavigationSplitView with sidebar (5 sections) and detail content area.

**Step 3: Create MenuBarDropdown**

Compact view with: today/month cost, provider radio list, "Open Dashboard" button, Quit button.

**Step 4: Verify build**

Run: `cd CCGateWay && tuist build`

**Step 5: Commit**

```bash
cd .. && git add -A && git commit -m "feat: add dual-window app shell — Dashboard + MenuBarExtra"
```

---

### Task 7: Build Dashboard — Overview Section

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Views/OverviewView.swift`

**Step 1: Create OverviewView**

Shows:
- Gateway status pill (green Running / red Stopped)
- Start/Stop toggle button
- Active provider name with icon
- Today's cost (large number)
- Today's request count
- Port number display

**Step 2: Verify build**

Run: `cd CCGateWay && tuist build`

**Step 3: Commit**

```bash
cd .. && git add -A && git commit -m "feat: add Overview section to dashboard"
```

---

### Task 8: Build Dashboard — Providers Section

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Views/ProvidersView.swift`
- Create: `CCGateWay/CCGateWay/Sources/Views/ProviderEditView.swift`

**Step 1: Create ProvidersView**

List of configured providers. Each row shows: name, type badge, enabled toggle, slot summary. Add/delete buttons.

**Step 2: Create ProviderEditView**

Form for editing a single provider:
- Name (text field)
- Type (picker: Gemini, OpenRouter, OpenAI, DeepSeek, Custom)
- Base URL (text field, auto-filled based on type)
- API Key (secure field, saved to Keychain)
- Slot mappings: 4 text fields (default, background, think, longContext)
- "Test Connection" button — sends a minimal request and shows success/error

**Step 3: Verify build**

Run: `cd CCGateWay && tuist build`

**Step 4: Commit**

```bash
cd .. && git add -A && git commit -m "feat: add Providers section with add/edit/delete"
```

---

### Task 9: Build Dashboard — Request Log Section

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Views/RequestLogView.swift`

**Step 1: Create RequestLogView**

A `List` bound to `gateway.requestLogs` that auto-scrolls to the bottom. Each row displays the `formattedLine` from `RequestLog`. Clear button at the top. Empty state message when no logs yet.

Uses monospaced font for the log lines.

**Step 2: Verify build**

Run: `cd CCGateWay && tuist build`

**Step 3: Commit**

```bash
cd .. && git add -A && git commit -m "feat: add Request Log section with live scrolling"
```

---

### Task 10: Build Dashboard — Usage & Cost Section

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Views/UsageCostView.swift`

**Step 1: Create UsageCostView**

- Today's total cost (big number)
- This month's total cost
- Cost breakdown by provider (simple table)
- Daily spend bar chart for last 7 days (using SwiftUI Charts framework)

Note: For MVP, cost data comes from in-memory `requestLogs`. SQLite persistence is a follow-up task.

**Step 2: Verify build**

Run: `cd CCGateWay && tuist build`

**Step 3: Commit**

```bash
cd .. && git add -A && git commit -m "feat: add Usage & Cost section with charts"
```

---

### Task 11: Build Dashboard — Settings Section

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Views/SettingsView.swift`

**Step 1: Create SettingsView**

Form with:
- Port number (stepper, default 3456)
- Auto-start on login (toggle)
- Claude Code config path display
- "Configure Claude Code" button — writes `ANTHROPIC_BASE_URL` to Claude's settings
- "Import from claude-code-router" button — re-runs the auto-import logic
- App version display

**Step 2: Verify build**

Run: `cd CCGateWay && tuist build`

**Step 3: Commit**

```bash
cd .. && git add -A && git commit -m "feat: add Settings section"
```

---

### Task 12: End-to-end integration test

**Step 1: Build and run the full app**

Run: `cd CCGateWay && tuist build`
Launch the app.

**Step 2: Add a Gemini provider via the Dashboard**

Open Dashboard → Providers → Add → Fill in Gemini details → Save API key → Test Connection.

**Step 3: Test with curl**

```bash
curl -X POST http://127.0.0.1:3456/v1/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "Say hello"}]
  }'
```

Expected: Anthropic-format JSON response with Gemini-generated content. Request appears in the live log.

**Step 4: Test menu bar switching**

Click menu bar → switch to a different provider → verify the next curl request goes to the new provider.

**Step 5: Test with Claude Code**

```bash
export ANTHROPIC_BASE_URL=http://127.0.0.1:3456
export ANTHROPIC_API_KEY=dummy
claude
```

Expected: Claude Code starts and routes through gateway.

**Step 6: Commit**

```bash
cd .. && git add -A && git commit -m "feat: MVP complete — full app with dashboard, menu bar, and gateway"
```
