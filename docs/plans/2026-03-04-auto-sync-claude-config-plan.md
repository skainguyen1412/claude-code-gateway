# Auto-Sync Claude Config Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Automatically synchronize `~/.claude/settings.json` when the user switches their active AI provider.

**Architecture:** Move `updateClaudeCodeConfig()` logic from `SettingsView.swift` to a new `syncWithClaudeCode()` method inside `GatewayConfig.swift`, and automatically call it whenever the active provider changes. Update the settings UI to reflect that synchronization is fully automated.

**Tech Stack:** Swift, SwiftUI

---

### Task 1: Migrate Sync Logic to GatewayConfig

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Models/GatewayConfig.swift`

**Step 1: Add `syncWithClaudeCode()` method**

Inside `GatewayConfig.swift`, right after the `switchProvider(to:)` method, add the following function:

```swift
    // MARK: - Auto-Sync
    
    public func syncWithClaudeCode() {
        Task {
            let fileManager = FileManager.default
            let homeURL = fileManager.homeDirectoryForCurrentUser
            let claudeJsonURL = homeURL.appendingPathComponent(".claude/settings.json")

            do {
                var jsonDict: [String: Any] = [:]

                // Ensure ~/.claude directory exists
                let claudeDir = homeURL.appendingPathComponent(".claude")
                if !fileManager.fileExists(atPath: claudeDir.path) {
                    try fileManager.createDirectory(
                        at: claudeDir, withIntermediateDirectories: true)
                }

                // Read existing config if it exists
                if fileManager.fileExists(atPath: claudeJsonURL.path) {
                    let data = try Data(contentsOf: claudeJsonURL)
                    if let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        jsonDict = existing
                    }
                }

                // Ensure "env" dictionary exists
                var envDict = jsonDict["env"] as? [String: Any] ?? [:]

                let defaultModel = activeProviderConfig?.slots["default"] ?? "unknown_model"
                let opusModel = activeProviderConfig?.slots["think"] ?? defaultModel
                let haikuModel = activeProviderConfig?.slots["background"] ?? defaultModel

                // Update configurations native Oh My OpenCode wrapper requires
                envDict["ANTHROPIC_AUTH_TOKEN"] = "dummy_key_gateway"
                envDict["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:\\(port)"
                envDict["ANTHROPIC_MODEL"] = defaultModel
                envDict["ANTHROPIC_DEFAULT_OPUS_MODEL"] = opusModel
                envDict["ANTHROPIC_DEFAULT_SONNET_MODEL"] = defaultModel
                envDict["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = haikuModel
                envDict["CLAUDE_CODE_SUBAGENT_MODEL"] = haikuModel

                jsonDict["env"] = envDict

                let encodedData = try JSONSerialization.data(
                    withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys])
                try encodedData.write(to: claudeJsonURL, options: .atomic)
                
                print("Successfully updated ~/.claude/settings.json to point to CCGateWay.")
            } catch {
                print("Failed to update ~/.claude/settings.json: \\(error)")
            }
        }
    }
```

**Step 2: Automate call in `switchProvider(to:)`**

Update the existing `switchProvider(to:)` method in `GatewayConfig.swift` so it calls `syncWithClaudeCode()` exactly like this:

```swift
    func switchProvider(to name: String) {
        guard providers[name] != nil else { return }
        activeProvider = name
        save()
        syncWithClaudeCode()
    }
```

**Step 3: Run project to see if it compiles**

Run: `xcodebuild build -project CCGateWay/CCGateWay.xcodeproj -scheme CCGateWay`
Expected: Succeeds

**Step 4: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Models/GatewayConfig.swift
git commit -m "feat: migrate and automate claude config sync in GatewayConfig"
```

### Task 2: Clean up Settings UI

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/SettingsView.swift`

**Step 1: Remove Old Manual Update Logic**

In `SettingsView.swift`, delete the entire `private func updateClaudeCodeConfig()` method, and remove the unused `@State private var showUpdateConfigSuccessAlert = false`.

Replace the content of the `Section("Claude Code Integration")` block to just have informational text, removing the manual button:

```swift
            Section("Claude Code Integration") {
                Text(
                    "CCGateWay routes requests at http://127.0.0.1:\\(config.port). Your local Claude Code configuration (~/.claude/settings.json) is automatically kept in sync when you switch providers."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 5)
            }
```

**Step 2: Run project to verify compilation**

Run: `xcodebuild build -project CCGateWay/CCGateWay.xcodeproj -scheme CCGateWay`
Expected: Succeeds

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Views/SettingsView.swift
git commit -m "refactor: remove manual claude config update from settings ui"
```
