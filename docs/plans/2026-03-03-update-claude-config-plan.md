# Update Claude Code Config Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Modify the `updateClaudeCodeConfig` function in CCGateWay to natively read and write `~/.claude/settings.json` to configure Claude Code's backend automatically.

**Architecture:** Use Swift's `FileManager` to locate the home directory and config file, and `JSONSerialization` to safely parse, inject, and reserialize the `"env"` dictionary without running external scripts.

**Tech Stack:** Swift, SwiftUI, Vapor

---

### Task 1: Update SettingsView to Edit ~/.claude/settings.json

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/SettingsView.swift`

**Step 1: Write the implementation**

Replace the existing `updateClaudeCodeConfig` method entirely with the new native JSON saving method.

```swift
    private func updateClaudeCodeConfig() {
        Task {
            let fileManager = FileManager.default
            let homeURL = fileManager.homeDirectoryForCurrentUser
            let claudeJsonURL = homeURL.appendingPathComponent(".claude/settings.json")
            
            do {
                var jsonDict: [String: Any] = [:]
                
                // Ensure ~/.claude directory exists
                let claudeDir = homeURL.appendingPathComponent(".claude")
                if !fileManager.fileExists(atPath: claudeDir.path) {
                    try fileManager.createDirectory(at: claudeDir, withIntermediateDirectories: true)
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
                
                // Update configurations native Oh My OpenCode wrapper requires
                envDict["ANTHROPIC_AUTH_TOKEN"] = "dummy_key_gateway"
                envDict["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:\(config.port)/v1/messages"
                
                // We keep original values or they will be empty if new
                
                jsonDict["env"] = envDict
                
                let encodedData = try JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys])
                try encodedData.write(to: claudeJsonURL, options: .atomic)
                
                await MainActor.run {
                    showUpdateConfigSuccessAlert = true
                }
            } catch {
                print("Failed to update ~/.claude/settings.json: \(error)")
            }
        }
    }
```

**Step 2: Compile the app**

Run: `tuist test`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Views/SettingsView.swift
git commit -m "feat: natively write claude settings JSON"
```
