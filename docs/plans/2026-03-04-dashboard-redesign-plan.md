# Dashboard Redesign Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Implement a "Vibrant Glassy macOS Native" ambient background and glassy cards for the main dashboard.

**Architecture:** A new `AmbientBackgroundView` generates a slow-moving, heavily blurred background of overlapping colorful circles. `OverviewView` places this in a ZStack underneath the dashboard content, and updates the material of the metric cards from `.regularMaterial` to `.ultraThinMaterial` with a semi-transparent stroke and drop shadow to give a premium glass look.

**Tech Stack:** SwiftUI (macOS 14+)

---

### Task 1: Create AmbientBackgroundView

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Views/AmbientBackgroundView.swift`

**Step 1: Write the implementation**

Create the `AmbientBackgroundView.swift` file.

```swift
import SwiftUI

struct AmbientBackgroundView: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Base dark background
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            
            // Orb 1: Deep Blue
            Circle()
                .fill(Color.blue.opacity(0.4))
                .frame(width: 500, height: 500)
                .offset(x: animate ? -200 : 200, y: animate ? -100 : 100)
                .blur(radius: 120)
            
            // Orb 2: Purple
            Circle()
                .fill(Color.purple.opacity(0.4))
                .frame(width: 400, height: 400)
                .offset(x: animate ? 200 : -200, y: animate ? 150 : -100)
                .blur(radius: 100)
            
            // Orb 3: Pink/Red highlight
            Circle()
                .fill(Color.pink.opacity(0.3))
                .frame(width: 300, height: 300)
                .offset(x: animate ? -100 : 150, y: animate ? 200 : -200)
                .blur(radius: 120)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 10.0).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

#Preview {
    AmbientBackgroundView()
}
```

**Step 2: Verify compilation**

`tuist generate` and then build it to verify. Or load up Xcode to check the preview.

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Views/AmbientBackgroundView.swift
git commit -m "feat: add AmbientBackgroundView for dashboard"
```

---

### Task 2: Refactor MetricCard to Glass Style

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/OverviewView.swift`

**Step 1: Update MetricCard view code**

Update the `MetricCard` struct in `OverviewView.swift` (around line 131) to use the new glassy style:

```swift
// ... existing view properties
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
```

**Step 2: Commit**
```bash
git add CCGateWay/CCGateWay/Sources/Views/OverviewView.swift
git commit -m "style: update MetricCard to glassy minimalist style"
```

---

### Task 3: Integrate Background and Refactor Overview Cards

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/OverviewView.swift`

**Step 1: Wrap OverviewView in ZStack and update styles**

In `OverviewView.swift`:
1. Wrap the `ScrollView` in a `ZStack` and put `AmbientBackgroundView()` at the back.
2. Update the "Server Status" hero banner and "Active Provider" card with the same background modifiers as `MetricCard` (replace `.regularMaterial` and custom stroke to `.ultraThinMaterial`, add the soft shadow, and update the stroke to `Color.white.opacity(0.15)`).
3. Increase the `LazyVGrid` spacing from `16` to `20`.

```swift
    var body: some View {
        ZStack {
            AmbientBackgroundView()
            
            ScrollView {
                // ... rest of view
```

Server Status & Active Provider Card styling setup:
```swift
                // ... inner content
                .padding(20)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
```

**Step 2: Build app to verify**

Run `tuist build` to test that everything compiles perfectly.

**Step 3: Commit**
```bash
git add CCGateWay/CCGateWay/Sources/Views/OverviewView.swift
git commit -m "feat: integrate AmbientBackgroundView and apply glassy card styles to dashboard"
```
