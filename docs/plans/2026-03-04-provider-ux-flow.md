# Providers UX Flow Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Simplify the process of adding new providers by introducing an "Available" providers section that auto-fills all complex fields, allowing the user to simply provide an API key and click "Enable".

**Architecture:** 
1. `ProviderConfig` will expose a static list of `templates`.
2. `ProvidersView` will split the list into two sections: "Configured" and "Available". Available providers are templates not yet present in the configured list, and are greyed out.
3. `ProviderEditView` will accept a template, prepopulate its `@State` variables, but treat it as a new creation (not editing an existing provider). The save button becomes "Enable Provider". Once enabled, the UI instantly switches to the configured provider.

**Tech Stack:** SwiftUI, MVVM pattern via `EnvironmentObject`

---

### Task 1: Add Standard Templates to ProviderConfig

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Models/ProviderConfig.swift:10-34`

**Step 1: Write the templates in ProviderConfig**

Modify the file to include a `static let templates` array that contains standard templates for Gemini, OpenAI, DeepSeek, OpenRouter, and Groq.

```swift
    // After enabled: Bool = true

    static let templates: [ProviderConfig] = [
        geminiDefault,
        openAIDefault,
        ProviderConfig(
            name: "DeepSeek",
            type: "deepseek",
            baseUrl: "https://api.deepseek.com",
            slots: [
                "default": "deepseek-chat",
                "background": "deepseek-chat",
                "think": "deepseek-reasoner",
                "longContext": "deepseek-chat"
            ]
        ),
        ProviderConfig(
            name: "OpenRouter",
            type: "openrouter",
            baseUrl: "https://openrouter.ai/api/v1",
            slots: [
                "default": "anthropic/claude-3.5-sonnet",
                "background": "anthropic/claude-3-haiku",
                "think": "anthropic/claude-3.5-sonnet",
                "longContext": "anthropic/claude-3.5-sonnet"
            ]
        ),
        ProviderConfig(
            name: "Groq",
            type: "openai",
            baseUrl: "https://api.groq.com/openai/v1",
            slots: [
                "default": "llama-3.3-70b-versatile",
                "background": "llama-3.1-8b-instant",
                "think": "llama-3.3-70b-versatile",
                "longContext": "llama-3.3-70b-versatile"
            ]
        )
    ]

    static let geminiDefault = ProviderConfig(
        name: "Gemini",
// ... rest remains the same
```

**Step 2: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Models/ProviderConfig.swift
git commit -m "feat: add preset templates for popular providers"
```

---

### Task 2: Refactor ProviderEditView for Template State

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/ProviderEditView.swift:25-45`
- Modify: `CCGateWay/CCGateWay/Sources/Views/ProviderEditView.swift:115-125`

**Step 1: Add `isTemplate` flag and `onSave` callback**

```swift
    // Update ProviderEditView properties
    let isEditing: Bool
    let isTemplate: Bool
    let originalName: String?
    var onSave: ((String) -> Void)? = nil

    init(provider: ProviderConfig?, isTemplate: Bool = false, onSave: ((String) -> Void)? = nil) {
        self.isTemplate = isTemplate
        self.isEditing = provider != nil && !isTemplate
        self.originalName = isTemplate ? nil : provider?.name
        self.onSave = onSave

        if let p = provider {
// ...
```

**Step 2: Update the Save Button wording**

Change the wording in the `HStack` inside `body`:
```swift
                Button(isTemplate ? "Enable Provider" : "Save") {
                    saveProvider()
                    onSave?(name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || baseUrl.isEmpty)
```

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Views/ProviderEditView.swift
git commit -m "feat: add template mode to ProviderEditView"
```

---

### Task 3: Refactor ProvidersView List & Detail Area

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/ProvidersView.swift:10-54`
- Modify: `CCGateWay/CCGateWay/Sources/Views/ProvidersView.swift:56-78`

**Step 1: Update `ProviderRow` for greyed-out state**

```swift
struct ProviderRow: View {
    let provider: ProviderConfig
    let isActive: Bool
    let isConfigured: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(provider.name)
                    .fontWeight(.medium)
                    .foregroundColor(isConfigured ? .primary : .secondary)
                Text(provider.type.capitalized)
                    .font(.caption)
                    .foregroundColor(isConfigured ? .secondary : .secondary.opacity(0.5))
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if !isConfigured {
                Image(systemName: "plus.circle")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
```

**Step 2: Update the `List` to show Configured and Available sections**

```swift
            // Inside HStack(spacing: 0)
            List(selection: $selectedProviderID) {
                Section("Configured") {
                    ForEach(config.providers.keys.sorted(), id: \.self) { key in
                        if let provider = config.providers[key] {
                            ProviderRow(provider: provider, isActive: config.activeProvider == key, isConfigured: true)
                                .tag(key)
                        }
                    }
                }
                
                let unconfiguredTemplates = ProviderConfig.templates.filter { config.providers[$0.name] == nil }
                if !unconfiguredTemplates.isEmpty {
                    Section("Available") {
                        ForEach(unconfiguredTemplates, id: \.name) { template in
                            ProviderRow(provider: template, isActive: false, isConfigured: false)
                                .tag("template_\(template.name)")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(width: 250)
```

**Step 3: Update the Detail area to handle templates properly**

```swift
            Divider()

            // Detail / Edit Area
            if let selectedID = selectedProviderID {
                if selectedID.hasPrefix("template_"), 
                   let templateName = selectedID.components(separatedBy: "_").last, 
                   let template = ProviderConfig.templates.first(where: { $0.name == templateName }) {
                    
                    ProviderEditView(provider: template, isTemplate: true) { newName in
                        selectedProviderID = newName // Auto-select the newly configured provider
                    }
                    .id(selectedID)
                    
                } else if let provider = config.providers[selectedID] {
                    ProviderEditView(provider: provider, isTemplate: false)
                        .id(selectedID)
                }
            } else {
// ...
```

**Step 4: Fix the modal Add sheet**
Update the sheet presentation at the bottom of the View:
```swift
        .sheet(isPresented: $isShowingAddSheet) {
            ProviderEditView(provider: nil, isTemplate: false) { newName in
                selectedProviderID = newName
            }
            .environmentObject(config)
        }
```

**Step 5: Test the Build**

Run: `cd CCGateWay && swift run CCGateWay` (Wait until the gateway builds, or use Xcode to ensure it compiles with no errors).

**Step 6: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Views/ProvidersView.swift
git commit -m "feat: display available provider templates in sidebar"
```

---
