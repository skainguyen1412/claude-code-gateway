# Add Custom Provider Support Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Allow users to add and manage custom LLM provider endpoints using either the OpenAI or Gemini protocol adapters.

**Architecture:** We will introduce a new `ProviderListItem.draft` enum case to represent a configuration being set up. This draft will be displayed in `ProvidersView`. When the user is setting up the draft in `ProviderEditView`, they will supply a base URL, API key, and select an endpoint type. When they click save, the draft will be stored inside the persistent `GatewayConfig.providers` dictionary using its requested name.

**Tech Stack:** Swift, SwiftUI

---

### Task 1: Update `ProviderListItem` and `ProvidersView` to handle a Draft state

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/ProvidersView.swift`

**Step 1: Add a Draft State to the Models**
Update the `ProviderListItem` enum in `ProvidersView.swift` to support a `draft` form.

```swift
private enum ProviderListItem: Identifiable {
    case configured(key: String, provider: ProviderConfig)
    case template(provider: ProviderConfig)
    case draft

    var id: String {
        switch self {
        case .configured(let key, _): return key
        case .template(let provider): return "template_\(provider.name)"
        case .draft: return "draft_custom_provider"
        }
    }

    var isConfigured: Bool {
        if case .configured = self { return true }
        return false
    }
}
```

**Step 2: Embed the Draft Row in the UI**
In `ProvidersView`, introduce a `@State private var isCreatingCustomProvider: Bool = false` boolean. When this is true, inject `.draft` at the bottom of the list array.

```swift
    private var allItems: [ProviderListItem] {
        let configuredKeys = Set(config.providers.keys.map { $0.lowercased() })
        
        let configured: [ProviderListItem] = config.providers.keys.sorted().compactMap { key in
            guard let provider = config.providers[key] else { return nil }
            return .configured(key: key, provider: provider)
        }
        
        let templates: [ProviderListItem] = ProviderConfig.templates
            .filter { !configuredKeys.contains($0.name.lowercased()) }
            .map { .template(provider: $0) }
        
        var items = configured + templates
        if isCreatingCustomProvider {
            items.append(.draft)
        }
        return items
    }
```

**Step 3: Render the Draft Row**
In `ProvidersView.body`'s List rendering, modify how rows are rendered. Since `draft` does not contain a provider object inherently, manually construct its row.

```swift
            List(allItems, selection: $selectedProviderID) { item in
                switch item {
                case .configured(let key, let provider):
                    ProviderRow(provider: provider, isActive: config.activeProvider == key, isConfigured: true)
                        .tag(item.id)
                case .template(let provider):
                    ProviderRow(provider: provider, isActive: false, isConfigured: false)
                        .tag(item.id)
                case .draft:
                    HStack(spacing: 12) {
                        ProviderIconView(icon: ProviderIconInfo(assetName: nil, sfSymbol: "plus.circle.dashed", color: .blue), size: 24)
                            .frame(width: 32, height: 32)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("New Custom Provider")
                                .fontWeight(.medium)
                            Text("Setup")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(item.id)
                }
            }
```

**Step 4: Update the Detail View Rendering logic**
In the detail view section (`if let selectedID = selectedProviderID`), update it to intercept the "draft_custom_provider" ID and display the Editor with an empty template.

```swift
            // Detail / Edit Area
            if let selectedID = selectedProviderID {
                if selectedID == "draft_custom_provider" {
                    ProviderEditView(provider: nil, isTemplate: false) { newName in
                         isCreatingCustomProvider = false
                         selectedProviderID = newName 
                    }
                    .id("draft")
                } else if selectedID.hasPrefix("template_"),
// ... rest of method untouched
```

**Step 5: Add a Toolbar button to trigger creation**
Attach a Toolbar to the List in `ProvidersView` to add the `+` button. Also append an onChange to reset `isCreatingCustomProvider` if a user navigates away so they don't have dangling drafts.

```swift
            .listStyle(.sidebar)
            .frame(width: 250)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        isCreatingCustomProvider = true
                        selectedProviderID = "draft_custom_provider"
                    }) {
                        Label("Add Provider", systemImage: "plus")
                    }
                    .help("Add Custom Provider")
                }
            }
            .onChange(of: selectedProviderID) { newID in
                if newID != "draft_custom_provider" && isCreatingCustomProvider {
                    isCreatingCustomProvider = false
                }
            }
```

**Step 6: Ensure Build Passes**
Run: `xcodebuild -project CCGateWay/CCGateWay.xcodeproj -scheme CCGateWay -destination "platform=macOS,arch=arm64" clean build`
Expected Result: `** BUILD SUCCEEDED **`

**Step 7: Commit Changes**
Commit changes indicating UI adjustments for Custom Providers list UI logic.

### Task 2: Fix `ProviderEditView` to support Creating New Providers

**Files:**
- Modify:`CCGateWay/CCGateWay/Sources/Views/ProviderEditView.swift`

**Step 1: Init Fixes for Draft Custom Configurations**
In `ProviderEditView`, update the `init()` method and properties mildly so they provide better defaults when starting completely fresh.

```swift
    init(provider: ProviderConfig?, isTemplate: Bool = false, onSave: ((String) -> Void)? = nil) {
        self.isTemplate = isTemplate
        self.isEditing = provider != nil && !isTemplate
        self.originalName = isTemplate ? nil : provider?.name
        self.onSave = onSave

        if let p = provider {
            _name = State(initialValue: p.name)
            _type = State(initialValue: p.type)
            _baseUrl = State(initialValue: p.baseUrl)
            _isEnabled = State(initialValue: p.enabled)

            _defaultSlot = State(initialValue: p.slots["default"] ?? "")
            _backgroundSlot = State(initialValue: p.slots["background"] ?? "")
            _thinkSlot = State(initialValue: p.slots["think"] ?? "")
            _longContextSlot = State(initialValue: p.slots["longContext"] ?? "")
        } else {
            _name = State(initialValue: "New Custom Provider")
            _type = State(initialValue: "openai")
            _baseUrl = State(initialValue: "http://localhost:11434/v1")
        }
    }
```

**Step 2: Update Header and Action Texts**
Change the Save button text label logic to support "Add Provider" when we are explicitly creating a Custom Provider.

```swift
// Replace `Button(isTemplate ? "Enable Provider" : "Save") {`  with:
Button(isTemplate ? "Enable Provider" : (!isEditing ? "Add Provider" : "Save")) {
```

**Step 3: Fix Navigation & Cancel dismissal**
Because `ProvidersView` watches `isCreatingCustomProvider`, clicking Cancel or picking a different provider automatically hides the draft.
Verify that `dismiss()` is hooked correctly. Do not need to actually change this code, just check it logic wise.

**Step 4: Ensure Build Passes**
Run: `xcodebuild -project CCGateWay/CCGateWay.xcodeproj -scheme CCGateWay -destination "platform=macOS,arch=arm64" clean build`
Expected Result: `** BUILD SUCCEEDED **`

**Step 5: Commit Changes**
Commit changes indicating Edit View is now fully robust for creating fully new providers.
