import SwiftUI

/// A unified item representing either a configured provider or an available template.
private enum ProviderListItem: Identifiable {
    case configured(key: String, provider: ProviderConfig)
    case template(provider: ProviderConfig)

    var id: String {
        switch self {
        case .configured(let key, _): return key
        case .template(let provider): return "template_\(provider.name)"
        }
    }

    var provider: ProviderConfig {
        switch self {
        case .configured(_, let p): return p
        case .template(let p): return p
        }
    }

    var isConfigured: Bool {
        if case .configured = self { return true }
        return false
    }
}

struct ProvidersView: View {
    @EnvironmentObject var config: GatewayConfig
    @State private var selectedProviderID: String?

    /// Merges configured providers and unconfigured templates into one flat list.
    /// Configured first (sorted), then unconfigured templates (in catalog order).
    private var allItems: [ProviderListItem] {
        let configuredKeys = Set(config.providers.keys.map { $0.lowercased() })

        let configured: [ProviderListItem] = config.providers.keys.sorted().compactMap { key in
            guard let provider = config.providers[key] else { return nil }
            return .configured(key: key, provider: provider)
        }

        let templates: [ProviderListItem] = ProviderConfig.templates
            .filter { !configuredKeys.contains($0.name.lowercased()) }
            .map { .template(provider: $0) }

        return configured + templates
    }

    var body: some View {
        HStack(spacing: 0) {
            // Unified Providers List
            List(allItems, selection: $selectedProviderID) { item in
                ProviderRow(
                    provider: item.provider,
                    isActive: {
                        if case .configured(let key, _) = item {
                            return config.activeProvider == key
                        }
                        return false
                    }(),
                    isConfigured: item.isConfigured
                )
                .tag(item.id)
            }
            .listStyle(.sidebar)
            .frame(width: 250)

            // Detail / Edit Area
            if let selectedID = selectedProviderID {
                if selectedID.hasPrefix("template_"),
                    let templateName = selectedID.dropFirst("template_".count)
                        .description
                        .trimmingCharacters(in: .whitespaces) as String?,
                    let template = ProviderConfig.templates.first(where: {
                        $0.name == templateName
                    })
                {
                    ProviderEditView(provider: template, isTemplate: true) { newName in
                        selectedProviderID = newName  // Auto-select the newly configured provider
                    }
                    .id(selectedID)

                } else if let provider = config.providers[selectedID] {
                    ProviderEditView(provider: provider, isTemplate: false)
                        .id(selectedID)
                }
            } else {
                VStack {
                    Image(systemName: "network")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Select a provider")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
