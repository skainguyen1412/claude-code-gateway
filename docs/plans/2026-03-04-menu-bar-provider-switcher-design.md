# Menu Bar Provider Switcher Design

## Overview
The goal is to improve the user experience of the menu bar widget for CCGateWay so that it allows users to quickly switch between AI providers. The current approach uses a custom popover window, which we will replace with a much faster Native macOS Menu Bar approach.

## Structure
The Menu Bar will now be structured as a standard macroscopic menu (`.menuBarExtraStyle(.menu)`). 

When the user clicks the menu bar icon, they see:

1. **Status Banner**: A read-only text view displaying "🟢 Running" or "🔴 Stopped"
2. **Cost Banner**: A read-only text view displaying the today's cost
3. **Separator**
4. **Provider List**: A flat list of all configured providers loaded from the `GatewayConfig`. When the user selects an option, the current active provider changes and saves back to the configuration.
5. **Separator**
6. **Actions**: 
    - "Open Dashboard" to bring the dashboard window to the front
    - "Quit" to terminate the app.

## Implementation Details

- **App Entry Point**: In `CCGateWayApp.swift`, change `.menuBarExtraStyle(.window)` to `.menuBarExtraStyle(.menu)`.
- **Menu Bar Content**: Refactor the contents of `MenuBarDropdown.swift`. Instead of using an interactive `VStack` layout suited for `.window`, it should use a standard menu bar format where standard SwiftUI `Button`, `Divider`, and `Text` views operate as native menu items.
- **Provider Switching**: Loop over `config.providers.keys.sorted()`. Use a `Button` with a custom label (incorporating an SF Symbol like a checkmark to indicate active state natively), or a standard `Picker` styled `label:EmptyView()` if we want macOS to natively handle the checkmark selection UI. `Button` is often simpler for custom items.

## Rollout
1. Change the style in `CCGateWayApp.swift`.
2. Rewrite `MenuBarDropdown.swift` to use native menu elements.
3. Verify that the current active provider switches seamlessly and persists appropriately to config.
