# Menu Bar Provider Switcher Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Refactor the menu bar widget to use a native macOS menu dropdown, allowing users to quickly switch between configured providers.

**Architecture:** We will change the `MenuBarExtra` style in `CCGateWayApp.swift` from `.window` to `.menu`. Then, we will rewrite `MenuBarDropdown.swift` to construct a native menu consisting of read-only text items for status/cost, a list of providers (as buttons with checkmarks for the active one), and app actions.

**Tech Stack:** SwiftUI, macOS native menus

---

### Task 1: Update App Entry Point to Native Menu

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/CCGateWayApp.swift`

**Step 1: Modify MenuBarExtra style**

In `CCGateWayApp.swift`, change `.menuBarExtraStyle(.window)` to `.menuBarExtraStyle(.menu)`.

```swift
// CCGateWayApp.swift around line 40
        }
        .menuBarExtraStyle(.menu)
```

**Step 2: Commit App Entry Point Update**

Run: `git add CCGateWay/CCGateWay/Sources/CCGateWayApp.swift && git commit -m "feat: change menu bar style to native macOS menu"`

---

### Task 2: Refactor MenuBarDropdown for Native Menu

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/MenuBarDropdown.swift`

**Step 1: Rewrite MenuBarDropdown.swift**

Replace the entire contents of `MenuBarDropdown.swift` to use standard menu items instead of `VStack`.

```swift
import SwiftUI

struct MenuBarDropdown: View {
    @EnvironmentObject var config: GatewayConfig
    @EnvironmentObject var server: GatewayServer
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Status Information (Read-only)
        if server.isRunning {
            Text("🟢 CCGateWay - Running")
        } else {
            Text("🔴 CCGateWay - Stopped")
        }
        
        Text("Today: $\(String(format: "%.4f", server.todayCost))")
        
        Divider()
        
        // Provider Selection List
        Text("Providers")
        
        ForEach(config.providers.keys.sorted(), id: \.self) { providerName in
            Button(action: {
                config.switchProvider(to: providerName)
            }) {
                HStack {
                    Text(providerName)
                    if config.activeProvider == providerName {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        
        Divider()
        
        // App Actions
        Button("Open Dashboard") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "dashboard")
        }
        .keyboardShortcut("d", modifiers: [.command])

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}
```

**Step 2: Commit MenuBarDropdown Update**

Run: `git add CCGateWay/CCGateWay/Sources/Views/MenuBarDropdown.swift && git commit -m "feat: refactor menu bar dropdown for native macOS menu format"`

---

### Task 3: Build and Run Application to Verify

**Files:** N/A

**Step 1: Rebuild and Run App**

Since this is UI behavior, compiling and running the macOS app is necessary to verify the native menu renders correctly.

Run: `xcodebuild -scheme CCGateWay -project CCGateWay/CCGateWay.xcodeproj build`

Expected: The app compiles successfully.

**Step 2: Note for manual run**

The tester should manually run the app via Xcode or open the resulting app bundle. Verify clicking the menu bar icon natively drops down a list. Verify that selecting a provider correctly switches the active provider, updating the checkmark.

