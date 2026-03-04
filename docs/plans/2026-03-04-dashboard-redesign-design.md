# Dashboard Redesign

## Context
The current `OverviewView` dashboard looks bland with its pure black background and standard `.regularMaterial` cards. The user requested a more visually appealing design.

## Goal
Implement a "Vibrant Glassy macOS Native" aesthetic that adds depth, color, and a premium feel to the main dashboard.

## Architecture & Components

1. **Ambient Background View (`AmbientBackgroundView.swift`)**
   - A new SwiftUI view that renders 3-4 soft, slow-moving, heavily blurred overlapping circles (`.blur(radius: 120)`).
   - Colors will be premium dark-mode appropriate (deep purples, soft blues, pink highlights).
   - Uses simple `@State` offsets and `.onAppear` looping implicit animations.
   - Inserted at the base of the `OverviewView` ZStack with `.ignoresSafeArea()`.

2. **Glassy Card Re-styling (`MetricCard`, Hero Banner, Active Provider)**
   - Change background material from `.regularMaterial` to `.ultraThinMaterial` or `.thinMaterial` to allow the ambient colors to bleed through.
   - Add a subtle inner top highlight using `.overlay`.
   - Add a soft dark drop shadow (`.shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)`).
   - Increase internal padding slightly and grid spacing for a more breathable layout.

3. **Typography and Details**
   - Use `.system(.title, design: .rounded).weight(.bold)` for metric numbers.
   - Increase the glow on the server status dot matching its state (red/green).

## Trade-offs
- **Performance:** Rendering multiple large blurs can be computationally heavy. We will keep the animation slow and restrict the number of circles to 3-4 to maintain a smooth framerate.

## Testing Plan
- Visually verify the animation doesn't cause high CPU usage.
- Ensure text remains readable (high contrast) against all positions of the background gradient.
