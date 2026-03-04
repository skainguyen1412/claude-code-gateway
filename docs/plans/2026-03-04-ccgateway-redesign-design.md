# CCGateWay Redesign Architecture & Design Plan

## 1. Overall Layout & Architecture
We will embrace standard modern macOS design (similar to apps like Apple Settings or Messages):
*   **Sidebar Navigation**: A fully translucent sidebar (`.regularMaterial`) that blends into the user's desktop wallpaper, featuring rounded, prominent selection highlights for navigation items (Overview, Providers, Request Log, etc.).
*   **Content Area**: A clean, structured main content area. We will remove the stark white/dark solid backgrounds from the cards (`NSColor.controlBackgroundColor`) and replace them with layered translucent materials or subtle gradients to provide depth and "vibrancy."
*   **Window Styling**: We'll ensure the window uses `.titlebarAppearsTransparent` and blends the toolbar seamlessly into the content/sidebar.

## 2. Core Views & Components

### Overview (Dashboard)
*   **Widgets:** We will move away from the basic `HStack/VStack` flow and use a staggered or pure grid (`LazyVGrid`) of Apple Health-style widgets.
*   **Aesthetics:** Cards will have larger corner radii (`16pt` or `20pt`), generous padding, and subtle inner shadows or borders. The backgrounds will use thick material (`.thickMaterial` or `Color(NSColor.windowBackgroundColor).opacity(0.8)`) so they pop against the window background.
*   **Server Controls:** Instead of standard bordered buttons, we'll design a prominent "Hero Component" for the Server Status (large pulsing green dot when running, prominent stop/start toggle) allowing it to stand out as the primary action of the app.

### Providers View
*   **Refinement:** The current `List` feels a bit raw. We'll add better group styling and icons for the different provider types.
*   **Configuration Form:** The `ProviderEditView` form will be spaced out more generously. We will organize sections into distinct, styled "Cards" rather than standard form groups to feel more like a modern settings page.

### Request Log & Usage Views
*   **Request Log:** We will keep the data dense but visually separate the rows using soft alternating backgrounds or clear dividing lines. We'll introduce a "Status Pill" (green `200`, red `Error`) rather than just raw text or simple icons for instant readability.
*   **Usage Chart:** The Swift Charts view will get a more vibrant, smooth gradient fill matching the system branding color (e.g., `.blue.gradient` or a custom custom mix like deep purple-to-blue) with softer, rounded bars.

## 3. Typography, Spacing, & Micro-Interactions

### Typography Structure
*   **Headers:** We will use Large/Heavy SF Pro (`.largeTitle`, `.fontWeight(.heavy)`) for main section headers, rather than the current plain styling.
*   **Data Labels:** For metrics, tokens, and numeric values, we will use SF Monospaced (`.font(.system(.body, design: .monospaced))`) or heavily weighted text (`.font(.title).weight(.bold)`) so the raw numbers instantly grab your attention.
*   **System Colors:** We'll leverage Apple’s native semantic colors (`.secondary`, `.tertiary`) extensively to establish a clear visual hierarchy of text so less important info (like IDs or timestamps) recedes visually.

### Spacing & Polish
*   **Whitespace:** The layout will have a more airy feel. We’ll lean heavily on SwiftUI’s native spacing and generous paddings to separate groups of information naturally without relying entirely on hard divider lines.
*   **Micro-Animations:** We'll add subtle hover effects (if supported) and smooth transitions (`.animation(.smooth(duration: 0.3), value: ...)` on toggles, charts, and metrics popping in, adding that “liquid glass” / “iOS on Mac” premium feel you asked for.
