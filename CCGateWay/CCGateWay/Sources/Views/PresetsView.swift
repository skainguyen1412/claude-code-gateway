import SwiftUI

private enum PresetListItem: Identifiable, Equatable {
    case configured(name: String)
    case draft

    var id: String {
        switch self {
        case .configured(let name):
            return name
        case .draft:
            return "__draft_preset__"
        }
    }
}

struct PresetsView: View {
    @EnvironmentObject var config: GatewayConfig
    @State private var selectedPresetID: String?
    @State private var isCreatingPreset: Bool = false

    private var providerNames: [String] {
        config.providers.keys.sorted()
    }

    private var allItems: [PresetListItem] {
        var items: [PresetListItem] = config.presets.keys.sorted().map { .configured(name: $0) }
        if isCreatingPreset {
            items.append(.draft)
        }
        return items
    }

    var body: some View {
        HStack(spacing: 0) {
            List(allItems, selection: $selectedPresetID) { item in
                switch item {
                case .configured(let name):
                    PresetRow(name: name, isActive: config.activePreset == name)
                        .tag(item.id)
                case .draft:
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.dashed")
                            .foregroundColor(.blue)
                        Text("New Preset")
                    }
                    .padding(.vertical, 6)
                    .tag(item.id)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 250)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        isCreatingPreset = true
                        selectedPresetID = PresetListItem.draft.id
                    }) {
                        Label("Add Preset", systemImage: "plus")
                    }
                    .help("Add Custom Preset")
                }
            }
            .onChange(of: selectedPresetID) { newValue in
                if newValue != PresetListItem.draft.id && isCreatingPreset {
                    isCreatingPreset = false
                }
            }

            detailView
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if selectedPresetID == PresetListItem.draft.id {
            PresetEditView(
                preset: nil,
                providers: config.providers,
                activePresetName: config.activePreset,
                onSave: { savePreset($0, replacing: $1) },
                onDelete: nil,
                onActivate: nil
            )
        } else if let selectedName = selectedPresetID,
            let preset = config.presets[selectedName]
        {
            PresetEditView(
                preset: preset,
                providers: config.providers,
                activePresetName: config.activePreset,
                onSave: { savePreset($0, replacing: $1) },
                onDelete: { deletePreset(named: selectedName) },
                onActivate: { name in
                    config.switchPreset(to: name)
                    selectedPresetID = name
                }
            )
            .id(selectedName)
        } else {
            VStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("Select a preset")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func savePreset(_ preset: PresetConfig, replacing oldName: String?) {
        let normalizedName = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return }

        var updated = preset
        updated.name = normalizedName

        if let oldName, oldName != normalizedName {
            config.presets.removeValue(forKey: oldName)
            if config.activePreset == oldName {
                config.activePreset = normalizedName
            }
        }

        config.presets[normalizedName] = updated
        config.save()
        if config.activePreset == normalizedName {
            config.syncWithClaudeCode()
        }

        isCreatingPreset = false
        selectedPresetID = normalizedName
    }

    private func deletePreset(named name: String) {
        let wasActive = config.activePreset == name
        config.presets.removeValue(forKey: name)

        if wasActive {
            config.activePreset = ""
            config.syncWithClaudeCode()
        }

        config.save()
        selectedPresetID = config.presets.keys.sorted().first
    }
}

private struct PresetRow: View {
    let name: String
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .fontWeight(.medium)
                Text("Preset")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

struct PresetEditView: View {
    let preset: PresetConfig?
    let providers: [String: ProviderConfig]
    let activePresetName: String
    let onSave: (PresetConfig, String?) -> Void
    let onDelete: (() -> Void)?
    let onActivate: ((String) -> Void)?

    @State private var name: String
    @State private var slots: [String: PresetSlotTarget]
    @State private var validationErrors: [String] = []

    private var providerNames: [String] {
        providers.keys.sorted()
    }

    init(
        preset: PresetConfig?,
        providers: [String: ProviderConfig],
        activePresetName: String,
        onSave: @escaping (PresetConfig, String?) -> Void,
        onDelete: (() -> Void)?,
        onActivate: ((String) -> Void)?
    ) {
        self.preset = preset
        self.providers = providers
        self.activePresetName = activePresetName
        self.onSave = onSave
        self.onDelete = onDelete
        self.onActivate = onActivate

        let firstProvider = providers.keys.sorted().first ?? ""
        var initialSlots: [String: PresetSlotTarget] = [:]
        for slot in PresetValidator.requiredSlots {
            if let existing = preset?.slots[slot] {
                initialSlots[slot] = existing
            } else {
                initialSlots[slot] = PresetSlotTarget(providerName: firstProvider, modelId: "")
            }
        }

        _name = State(initialValue: preset?.name ?? "New Preset")
        _slots = State(initialValue: initialSlots)
    }

    private var draftPreset: PresetConfig {
        PresetConfig(name: name, slots: slots)
    }

    private var validation: (isValid: Bool, errors: [String]) {
        PresetValidator.validate(preset: draftPreset)
    }

    var body: some View {
        Form {
            Section("Preset") {
                TextField("Preset name", text: $name)
            }

            Section("Slot Mapping") {
                ForEach(PresetValidator.requiredSlots, id: \.self) { slot in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(slotTitle(slot))
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if providerNames.isEmpty {
                            Text("Add at least one provider before configuring presets.")
                                .foregroundColor(.secondary)
                        } else {
                            Picker("Provider", selection: providerBinding(for: slot)) {
                                ForEach(providerNames, id: \.self) { providerName in
                                    Text(providerName).tag(providerName)
                                }
                            }
                            ModelSlotPicker(
                                label: "Model",
                                slotName: slot,
                                selection: modelBinding(for: slot),
                                catalogKey: catalogKey(for: slot)
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if !validationErrors.isEmpty {
                Section("Validation") {
                    ForEach(validationErrors, id: \.self) { error in
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }

            HStack {
                Button("Save Preset") {
                    let result = validation
                    guard result.isValid else {
                        validationErrors = result.errors
                        return
                    }
                    validationErrors = []
                    onSave(draftPreset, preset?.name)
                }
                .buttonStyle(.borderedProminent)

                if let onActivate {
                    Button("Make Active") {
                        let result = validation
                        guard result.isValid else {
                            validationErrors = result.errors
                            return
                        }
                        validationErrors = []
                        onSave(draftPreset, preset?.name)
                        onActivate(name.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(activePresetName == name.trimmingCharacters(in: .whitespacesAndNewlines))
                }

                if let onDelete {
                    Button("Delete Preset", role: .destructive, action: onDelete)
                }
            }
            .padding(.top, 8)
        }
        .formStyle(.grouped)
        .padding()
    }

    private func providerBinding(for slot: String) -> Binding<String> {
        Binding(
            get: { slots[slot]?.providerName ?? providerNames.first ?? "" },
            set: { newValue in
                var target = slots[slot] ?? PresetSlotTarget(providerName: "", modelId: "")
                target.providerName = newValue
                slots[slot] = target
            }
        )
    }

    private func modelBinding(for slot: String) -> Binding<String> {
        Binding(
            get: { slots[slot]?.modelId ?? "" },
            set: { newValue in
                var target = slots[slot] ?? PresetSlotTarget(providerName: "", modelId: "")
                target.modelId = newValue
                slots[slot] = target
            }
        )
    }

    private func catalogKey(for slot: String) -> String {
        let providerName = slots[slot]?.providerName ?? ""
        return providers[providerName]?.catalogKey ?? ""
    }

    private func slotTitle(_ slot: String) -> String {
        switch slot {
        case "default": return "Default"
        case "background": return "Background"
        case "think": return "Think"
        case "longContext": return "Long Context"
        default: return slot
        }
    }
}
