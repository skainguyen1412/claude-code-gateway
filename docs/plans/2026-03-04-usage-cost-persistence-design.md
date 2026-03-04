# Usage & Cost Persistence + Redesigned Dashboard

**Date:** 2026-03-04
**Status:** Approved

## Goal

Replace the non-functional Usage & Cost system with real data persistence and a redesigned dashboard. Currently: cost data is in-memory only (lost on restart), the 7-day chart uses hardcoded dummy data, and Monthly Est. is a meaningless `todayCost × 30`.

## Data Layer: UsageStore

### Storage

JSON file at `~/.ccgateway/usage_history.json`. One entry per day:

```json
[
  {
    "date": "2026-03-04",
    "totalCost": 0.4821,
    "requestCount": 47,
    "totalInputTokens": 125000,
    "totalOutputTokens": 38000,
    "providers": {
      "Gemini": { "cost": 0.32, "requests": 30 },
      "DeepSeek": { "cost": 0.1621, "requests": 17 }
    }
  }
]
```

### Model Structs

```swift
struct DailyUsageRecord: Codable, Identifiable {
    var id: String { date }
    let date: String                           // "2026-03-04"
    var totalCost: Double
    var requestCount: Int
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var providers: [String: ProviderUsage]
}

struct ProviderUsage: Codable {
    var cost: Double
    var requests: Int
}
```

### UsageStore Class

`@MainActor class UsageStore: ObservableObject`

- `@Published var history: [DailyUsageRecord]` — full array from JSON
- `@Published var todayRecord: DailyUsageRecord` — current day's running tally
- On init: load JSON, find or create today's entry
- `recordRequest(cost:, inputTokens:, outputTokens:, providerName:)` — updates todayRecord, debounced save
- `save()` — serialize history to disk (debounced, every 5 seconds)
- Automatic daily rollover: if date changed since last request, finalize yesterday and create new today

### Computed Properties

- `last7DaysCost: Double` — sum of last 7 days
- `last30DaysCost: Double` — sum of last 30 days
- `chartData: [DailyUsageRecord]` — last 30 days for the chart

## UI: Redesigned Usage & Cost Page

### Zone 1: Summary Cards (4-column grid)

| Card | Source |
|------|--------|
| Today's Cost | `usageStore.todayRecord.totalCost` |
| Today's Requests | `usageStore.todayRecord.requestCount` |
| 7-Day Total | `usageStore.last7DaysCost` |
| 30-Day Total | `usageStore.last30DaysCost` |

### Zone 2: 30-Day Cost Trend (Bar Chart)

- Swift Charts `BarMark` with real data from `usageStore.chartData`
- X-axis: dates, Y-axis: cost
- Today's bar updates live
- Blue→purple gradient bars

### Zone 3: Provider Breakdown (Today)

- Horizontal progress bars per provider
- Provider icon + name + filled bar + cost + percentage
- Sorted by cost descending
- "No usage today" for providers with 0 cost

## Integration

### Data Flow

```
GatewayRoutes → GatewayServer.addLog(log) → usageStore.recordRequest(...)
                                           → Views react via @Published
```

### GatewayServer Cleanup

Remove: `todayCost`, `monthCost`, `todayRequests`, `providerCosts`, `resetDailyCost()`
Keep: `requestLogs[]`, `addLog()`, `isRunning`, `statusMessage`, server lifecycle

### Wiring (CCGateWayApp)

- Create `UsageStore` at app init
- Inject as `.environmentObject(usageStore)`
- Pass to `GatewayServer`

## Files

| File | Change |
|------|--------|
| **New** `Models/UsageStore.swift` | Persistence manager + model structs |
| `Gateway/GatewayServer.swift` | Remove cost fields, delegate to UsageStore |
| `CCGateWayApp.swift` | Create & inject UsageStore |
| `Views/UsageCostView.swift` | Complete rewrite — 3-zone layout |
| `Views/OverviewView.swift` | Read from UsageStore |
| `Views/MenuBarDropdown.swift` | Read from UsageStore |

## Out of Scope

- Per-request persistence (only daily summaries)
- Export/import of usage data
- Budget alerts or spending limits
- Per-model cost breakdown (only per-provider)
