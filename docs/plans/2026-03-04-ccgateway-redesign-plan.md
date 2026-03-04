# CCGateWay UI Redesign Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Redesign CCGateWay using modern macOS translucent design and Apple Health-style widgets.

**Architecture:** We will update `CCGateWayApp` and various existing SwiftUI views (`DashboardView`, `OverviewView`, `ProvidersView`, `RequestLogView`, `UsageCostView`) to use translucent backgrounds, Grid-based layouts, `.regularMaterial` fills, larger corner radii, system colors, and SF Pro Typography. Since it's UI code, we test by building, running the app, and verifying visually, and ensuring no compile errors.

**Tech Stack:** SwiftUI, Foundation, Charts

---

### Task 1: App Window & Dashboard Layout Restyling

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/CCGateWayApp.swift`
- Modify: `CCGateWay/CCGateWay/Sources/Views/DashboardView.swift`

**Step 1: Update Window Style**

In `CCGateWayApp.swift`, we apply transparent title bar to `WindowGroup` to enable the full height vibrancy:
```swift
        WindowGroup(id: "dashboard") {
            DashboardView()
                .environmentObject(config)
                .environmentObject(server)
                .onAppear {
                    handleFirstLaunch()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact) // Add this
```

**Step 2: Apply Vibrancy to DashboardView**

In `DashboardView.swift`, update the background of the `detail` view:
```swift
        } detail: {
            detailView(for: selectedTab)
                .environmentObject(config)
                .environmentObject(server)
                // Add translucent background logic
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
        }
```

**Step 3: Build & Verify**

Run: `xcodebuild -workspace CCGateWay/CCGateWay.xcodeproj/project.xcworkspace -scheme CCGateWay build`
Expected: Build SUCCEEDS

**Step 4: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/CCGateWayApp.swift CCGateWay/CCGateWay/Sources/Views/DashboardView.swift
git commit -m "style: apply window toolbar style and ultrathin material to dashboard"
```

---

### Task 2: Overview View Hero Component & Grid

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/OverviewView.swift`

**Step 1: Implement the Grid & Hero Layout**

Replace the current vertical layout with a more modern configuration. Remove `Color(NSColor.controlBackgroundColor)` backgrounds in favor of `.regularMaterial` with larger corner radii.

```swift
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var config: GatewayConfig
    @EnvironmentObject var server: GatewayServer

    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Dashboard")
                    .font(.largeTitle)
                    .fontWeight(.heavy)

                // Hero Component: Server Status
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle()
                                .fill(server.isRunning ? Color.green : Color.red)
                                .frame(width: 14, height: 14)
                                .shadow(color: server.isRunning ? .green.opacity(0.8) : .red.opacity(0.8), radius: 6)
                            Text("Server Status")
                                .font(.headline)
                        }
                        Text(server.statusMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    if server.isRunning {
                        Button("Restart") {
                            server.restart()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Button(action: {
                        if server.isRunning {
                            server.stop()
                        } else {
                            server.start()
                        }
                    }) {
                        Text(server.isRunning ? "Stop" : "Start Server")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(server.isRunning ? .red : .green)
                    .controlSize(.large)
                }
                .padding(20)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )

                LazyVGrid(columns: columns, spacing: 16) {
                    MetricCard(
                        title: "Today's Cost",
                        value: "$\(String(format: "%.4f", server.todayCost))",
                        icon: "dollarsign.circle.fill"
                    )
                    MetricCard(
                        title: "Requests Today", 
                        value: "\(server.todayRequests)",
                        icon: "arrow.left.arrow.right"
                    )
                }
                
                // Active Provider Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "network.badge.shield.half.filled")
                            .foregroundColor(.blue)
                        Text("Active Provider")
                            .font(.headline)
                    }
                    Divider()

                    if let active = config.activeProviderConfig {
                        HStack {
                            Text(active.name)
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(active.type.capitalized)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                        }
                        Text(active.baseUrl)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        Text("No provider selected.")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(20)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
            }
            .padding(32)
        }
    }
}

// Helper view for metrics
struct MetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .font(.title3)
                Spacer()
            }
            
            Text(value)
                .font(.system(.title, design: .rounded))
                .fontWeight(.bold)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
             RoundedRectangle(cornerRadius: 16, style: .continuous)
                 .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}
```

**Step 2: Build & Verify**

Run: `xcodebuild -workspace CCGateWay/CCGateWay.xcodeproj/project.xcworkspace -scheme CCGateWay build`
Expected: Build SUCCEEDS

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Views/OverviewView.swift 
git commit -m "style: restyle overview layout to grid and hero widget"
```

---

### Task 3: Providers & Provider Edit Restyling

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/ProvidersView.swift`
- Modify: `CCGateWay/CCGateWay/Sources/Views/ProviderEditView.swift`

**Step 1: Simplify ProvidersView Selection**

In `ProvidersView`, remove the heavy line `Divider()` and use an `.ultraThinMaterial` background. No structural changes, just ensure it plays well with the new Dashboard root backgrounds.

**Step 2: Revamp ProviderEditView into a Modern Form**

In `ProviderEditView.swift`, use SwiftUI `.formStyle(.grouped)` to make the sections look like prominent macOS settings blocks instead of a plain list. 

Update the `body` modifiers at the end of `ProviderEditView` (around line 178) from:
```swift
        }
        .padding()
        .frame(minWidth: 400, idealWidth: 500)
```
to:
```swift
        }
        .formStyle(.grouped) // Adds native macOS group styling
        .scrollContentBackground(.hidden) // Ensure material shines through
        .padding()
        .frame(minWidth: 450, idealWidth: 550)
```

**Step 3: Build & Verify**

Run: `xcodebuild -workspace CCGateWay/CCGateWay.xcodeproj/project.xcworkspace -scheme CCGateWay build`
Expected: Build SUCCEEDS

**Step 4: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Views/ProvidersView.swift CCGateWay/CCGateWay/Sources/Views/ProviderEditView.swift
git commit -m "style: apply grouped form style to provider editor"
```

---

### Task 4: Request Log Visualization

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/RequestLogView.swift`

**Step 1: Style the Log Rows**

Replace the current `HStack` inside the `ForEach` in `RequestLogView` with a more visually clean "Status Pill" design and Monospaced data. Update the inner `HStack` in `RequestLogView`:

```swift
                            HStack(spacing: 12) {
                                // Status Pill
                                Group {
                                    if log.success {
                                        Text("200 OK")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.green.opacity(0.2))
                                            .foregroundColor(.green)
                                            .clipShape(Capsule())
                                    } else {
                                        Text("ERROR")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.red.opacity(0.2))
                                            .foregroundColor(.red)
                                            .clipShape(Capsule())
                                    }
                                }
                                .frame(width: 55, alignment: .leading)

                                Text("[\(formattedTime(log.timestamp))]")
                                    .foregroundColor(.secondary)
                                    .font(.system(.caption, design: .monospaced))

                                Text("\(log.slot) → \(log.providerModel)")
                                    .fontWeight(.medium)
                                    .font(.system(.body, design: .rounded))

                                Spacer()

                                Text("\(log.inputTokens + log.outputTokens) tok")
                                    .foregroundColor(.secondary)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 80, alignment: .trailing)

                                Text(String(format: "$%.4f", log.cost))
                                    .foregroundColor(.secondary)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 80, alignment: .trailing)

                                Text("\(log.latencyMs)ms")
                                    .foregroundColor(latencyColor(log.latencyMs))
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 60, alignment: .trailing)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                log.id == server.requestLogs.last?.id 
                                ? Color.blue.opacity(0.1) 
                                : Color.secondary.opacity(0.05)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
```

Update headers:
```swift
                Text("Request Log")
                    .font(.largeTitle)
                    .fontWeight(.heavy)
```

**Step 2: Build & Verify**

Run: `xcodebuild -workspace CCGateWay/CCGateWay.xcodeproj/project.xcworkspace -scheme CCGateWay build`
Expected: Build SUCCEEDS

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Views/RequestLogView.swift
git commit -m "style: modern request log view styling"
```

---

### Task 5: Usage & Cost Chart Vibes

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/UsageCostView.swift`

**Step 1: Overhaul Usage Chart**

In `UsageCostView.swift`, apply `.regularMaterial` and rounded corners to the cards, matching `OverviewView`.

```swift
    // Update metric cards usage
                HStack(spacing: 20) {
                    MetricCard(
                        title: "Today's Cost", value: String(format: "$%.4f", server.todayCost),
                        icon: "dollarsign.circle.fill")
                    MetricCard(
                        title: "Monthly Est.",
                        value: String(format: "$%.2f", server.todayCost * 30), icon: "calendar")
                }
```
And replace the background styling on the Chart VStack:
```swift
                }
                .padding(20)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                     RoundedRectangle(cornerRadius: 16, style: .continuous)
                         .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
```

Also, update the `.foregroundStyle(Color.blue.gradient)` on the `BarMark` inside the Chart to use a rounded corner: 
```swift
                        BarMark(
                            x: .value("Date", item.date, unit: .day),
                            y: .value("Cost", item.cost)
                        )
                        .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .bottom, endPoint: .top))
                        .cornerRadius(6)
```

**Step 2: Build & Verify**

Run: `xcodebuild -workspace CCGateWay/CCGateWay.xcodeproj/project.xcworkspace -scheme CCGateWay build`
Expected: Build SUCCEEDS

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Views/UsageCostView.swift
git commit -m "style: apply new grid metrics style and vibrant gradients to usage view"
```
