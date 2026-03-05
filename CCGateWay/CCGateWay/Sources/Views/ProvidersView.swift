import SwiftUI

private enum ProviderMenuItem: Identifiable, Equatable {
    case configuredProvider(key: String, provider: ProviderConfig)
    case templateProvider(provider: ProviderConfig)
    case preset(name: String)
    case draftProvider
    case draftPreset

    var id: String {
        switch self {
        case .configuredProvider(let key, _): return "provider_\(key)"
        case .templateProvider(let provider): return "template_\(provider.name)"
        case .preset(let name): return "preset_\(name)"
        case .draftProvider: return "draft_custom_provider"
        case .draftPreset: return "draft_custom_preset"
        }
    }
}

struct ProvidersView: View {
    @EnvironmentObject var config: GatewayConfig
    @State private var selectedItemID: String?
    @State private var isCreatingCustomProvider: Bool = false
    @State private var isCreatingPreset: Bool = false

    private var providerItems: [ProviderMenuItem] {
        let configuredKeys = Set(config.providers.keys.map { $0.lowercased() })

        let configured: [ProviderMenuItem] = config.providers.keys.sorted().compactMap { key in
            guard let provider = config.providers[key] else { return nil }
            return .configuredProvider(key: key, provider: provider)
        }

        let templates: [ProviderMenuItem] = ProviderConfig.templates
            .filter { !configuredKeys.contains($0.name.lowercased()) }
            .map { .templateProvider(provider: $0) }

        var items = configured + templates
        if isCreatingCustomProvider {
            items.append(.draftProvider)
        }
        return items
    }

    private var presetItems: [ProviderMenuItem] {
        var items = config.presets.keys.sorted().map { ProviderMenuItem.preset(name: $0) }
        if isCreatingPreset {
            items.append(.draftPreset)
        }
        return items
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedItemID) {
                Section("Providers") {
                    ForEach(providerItems, id: \.id) { item in
                        switch item {
                        case .configuredProvider(let key, let provider):
                            ProviderRow(
                                provider: provider,
                                isActive: config.activePreset.isEmpty && config.activeProvider == key,
                                isConfigured: true
                            )
                            .tag(item.id)
                        case .templateProvider(let provider):
                            ProviderRow(provider: provider, isActive: false, isConfigured: false)
                                .tag(item.id)
                        case .draftProvider:
                            HStack(spacing: 12) {
                                ProviderIconView(
                                    icon: ProviderIconInfo(
                                        assetName: nil, sfSymbol: "plus.circle.dashed", color: .blue),
                                    size: 24
                                )
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
                        default:
                            EmptyView()
                        }
                    }
                }

                Section("Presets") {
                    ForEach(presetItems, id: \.id) { item in
                        switch item {
                        case .preset(let name):
                            PresetListRow(name: name, isActive: config.activePreset == name)
                                .tag(item.id)
                        case .draftPreset:
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.dashed")
                                    .foregroundColor(.blue)
                                Text("New Preset")
                            }
                            .padding(.vertical, 6)
                            .tag(item.id)
                        default:
                            EmptyView()
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(width: 250)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("Add Provider") {
                            isCreatingCustomProvider = true
                            isCreatingPreset = false
                            selectedItemID = ProviderMenuItem.draftProvider.id
                        }
                        Button("Add Preset") {
                            isCreatingPreset = true
                            isCreatingCustomProvider = false
                            selectedItemID = ProviderMenuItem.draftPreset.id
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .help("Add Provider or Preset")
                }
            }
            .onChange(of: selectedItemID) { newID in
                if newID != ProviderMenuItem.draftProvider.id && isCreatingCustomProvider {
                    isCreatingCustomProvider = false
                }
                if newID != ProviderMenuItem.draftPreset.id && isCreatingPreset {
                    isCreatingPreset = false
                }
            }

            detailView
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if selectedItemID == ProviderMenuItem.draftProvider.id {
            ProviderEditView(
                provider: nil,
                isTemplate: false,
                onSave: { newName in
                    isCreatingCustomProvider = false
                    selectedItemID = "provider_\(newName)"
                },
                onCancel: {
                    isCreatingCustomProvider = false
                    selectedItemID = nil
                }
            )
            .id("draft_provider")
        } else if selectedItemID == ProviderMenuItem.draftPreset.id {
            PresetEditView(
                preset: nil,
                providers: config.providers,
                activePresetName: config.activePreset,
                onSave: { savePreset($0, replacing: $1) },
                onDelete: nil,
                onActivate: nil
            )
            .id("draft_preset")
        } else if let selectedID = selectedItemID,
            selectedID.hasPrefix("template_"),
            let templateName = selectedID.dropFirst("template_".count)
                .description
                .trimmingCharacters(in: .whitespaces) as String?,
            let template = ProviderConfig.templates.first(where: { $0.name == templateName })
        {
            ProviderEditView(
                provider: template,
                isTemplate: true,
                onSave: { newName in
                    selectedItemID = "provider_\(newName)"
                },
                onCancel: {
                    selectedItemID = nil
                }
            )
            .id(selectedID)
        } else if let selectedID = selectedItemID,
            selectedID.hasPrefix("provider_"),
            let provider = config.providers[String(selectedID.dropFirst("provider_".count))]
        {
            ProviderEditView(
                provider: provider,
                isTemplate: false,
                onCancel: {
                    selectedItemID = nil
                },
                onDeleted: {
                    selectedItemID = nil
                }
            )
            .id(selectedID)
        } else if let selectedID = selectedItemID,
            selectedID.hasPrefix("preset_")
        {
            let presetName = String(selectedID.dropFirst("preset_".count))
            if let preset = config.presets[presetName] {
                PresetEditView(
                    preset: preset,
                    providers: config.providers,
                    activePresetName: config.activePreset,
                    onSave: { savePreset($0, replacing: $1) },
                    onDelete: { deletePreset(named: presetName) },
                    onActivate: { name in
                        config.switchPreset(to: name)
                        selectedItemID = "preset_\(name)"
                    }
                )
                .id(selectedID)
            } else {
                placeholderView
            }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        VStack {
            Image(systemName: "network")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Select a provider or preset")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        selectedItemID = "preset_\(normalizedName)"
    }

    private func deletePreset(named name: String) {
        let wasActive = config.activePreset == name
        config.presets.removeValue(forKey: name)

        if wasActive {
            config.activePreset = ""
            config.syncWithClaudeCode()
        }

        config.save()
        selectedItemID = config.presets.keys.sorted().first.map { "preset_\($0)" }
    }
}

struct ProviderRow: View {
    let provider: ProviderConfig
    let isActive: Bool
    let isConfigured: Bool

    /// Use the template's properly-cased name if this provider matches one.
    private var displayName: String {
        ProviderConfig.templates
            .first(where: { $0.name.lowercased() == provider.name.lowercased() })?
            .name ?? provider.name
    }

    var body: some View {
        HStack(spacing: 12) {
            ProviderIconView(icon: provider.providerIcon, size: 24)
                .frame(width: 32, height: 32)
                .background(provider.providerIcon.color.opacity(isConfigured ? 0.12 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(isConfigured ? 1.0 : 0.6)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .fontWeight(isConfigured ? .medium : .regular)
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
                Text("Set up")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PresetListRow: View {
    let name: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .frame(width: 32, height: 32)
                .foregroundColor(.blue)
                .background(Color.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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
