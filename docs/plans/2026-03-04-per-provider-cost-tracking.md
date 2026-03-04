# Per-Provider Cost Tracking Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Show per-provider cost inline on each provider row in the menu bar Quick Switch list.

**Architecture:** Add a `providerCosts` dictionary to `GatewayServer` that aggregates cost per provider name. Pass the per-provider cost to `MenuProviderRow` in the menu bar dropdown. Two files, no new models.

**Tech Stack:** SwiftUI, Swift

---

### Task 1: Add per-provider cost tracking to GatewayServer

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Gateway/GatewayServer.swift`

**Step 1: Add the providerCosts property**

Add after line 10 (`@Published private(set) var todayRequests: Int = 0`):

```swift
@Published private(set) var providerCosts: [String: Double] = [:]
```

**Step 2: Update addLog to track per-provider cost**

In `addLog(_:)`, after `self.todayCost += log.cost` (line 85), add:

```swift
self.providerCosts[log.providerName, default: 0] += log.cost
```

**Step 3: Update resetDailyCost to clear per-provider costs**

In `resetDailyCost()`, after `todayRequests = 0` (line 105), add:

```swift
providerCosts = [:]
```

**Step 4: Build to verify**

Run: `tuist build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Gateway/GatewayServer.swift
git commit -m "feat: track per-provider cost in GatewayServer"
```

---

### Task 2: Display per-provider cost in MenuProviderRow

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/MenuBarDropdown.swift`

**Step 1: Add cost parameter to MenuProviderRow**

Update the `MenuProviderRow` struct to accept a `cost` parameter:

```swift
struct MenuProviderRow: View {
    let name: String
    let isActive: Bool
    let cost: Double
    let action: () -> Void
```

**Step 2: Display cost in the row**

In `MenuProviderRow`'s `body`, add the cost text between `Text(name)` and `Spacer()`:

```swift
Text(name)
    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
    .foregroundColor(isActive ? .primary : .primary.opacity(0.8))

Spacer()

Text(String(format: "$%.4f", cost))
    .font(.system(size: 11, weight: .medium, design: .monospaced))
    .foregroundColor(.secondary)
```

Remove the existing `Spacer()` that was between `Text(name)` and the checkmark.

**Step 3: Update MenuProviderRow call site**

In `MenuBarDropdown`, update the ForEach to pass cost:

```swift
MenuProviderRow(
    name: providerName,
    isActive: config.activeProvider == providerName,
    cost: server.providerCosts[providerName, default: 0]
) {
```

**Step 4: Build to verify**

Run: `tuist build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Views/MenuBarDropdown.swift
git commit -m "feat: show per-provider cost in menu bar provider rows"
```
