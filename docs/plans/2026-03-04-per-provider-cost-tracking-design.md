# Per-Provider Cost Tracking in Menu Bar

**Date:** 2026-03-04
**Status:** Approved

## Goal

Show cost per provider inline on each provider row in the menu bar Quick Switch list, so users see at a glance how much each provider is costing them today.

## Current State

- `GatewayServer` tracks a single `todayCost: Double` — flat sum across all providers.
- `RequestLog` already has `providerName` and `cost` fields.
- Menu bar shows `"Today: $X.XXXX"` as one number in the header.
- `MenuProviderRow` shows provider name, icon, and active checkmark — no cost.

## Design

### Data Layer (`GatewayServer.swift`)

- Add `@Published private(set) var providerCosts: [String: Double] = [:]`
- In `addLog(_:)`: increment `providerCosts[log.providerName, default: 0] += log.cost`
- In `resetDailyCost()`: reset `providerCosts = [:]`

### View Layer (`MenuBarDropdown.swift`)

- Header remains: `"Today: $X.XXXX"` (total across all providers).
- `MenuProviderRow` gains a `cost: Double` parameter.
- Cost displayed right-aligned in monospaced font before the checkmark:
  ```
  [icon]  Gemini       $0.0032  [✓]
  [icon]  DeepSeek     $0.0014
  [icon]  OpenRouter   $0.0000
  ```

### Files Changed

| File | Change |
|------|--------|
| `GatewayServer.swift` | Add `providerCosts` dict, update `addLog()` and `resetDailyCost()` |
| `MenuBarDropdown.swift` | Pass cost to `MenuProviderRow`, display inline |

### Out of Scope

- Persistence of per-provider costs (in-memory only, resets daily)
- Per-provider charts or historical data
- Per-model cost breakdown
