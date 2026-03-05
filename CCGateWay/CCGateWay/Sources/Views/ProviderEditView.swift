import SwiftUI

enum ConnectionTestState: Equatable {
    case idle
    case testing
    case success
    case failure(String)
}

struct ProviderEditView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var config: GatewayConfig

    // State
    @State private var name: String = ""
    @State private var type: String = "gemini"
    @State private var baseUrl: String = ""
    @State private var defaultSlot: String = ""
    @State private var backgroundSlot: String = ""
    @State private var thinkSlot: String = ""
    @State private var longContextSlot: String = ""
    @State private var apiKey: String = ""
    @State private var isEnabled: Bool = true
    @State private var testState: ConnectionTestState = .idle
    @State private var deleteErrorMessage: String?

    let isEditing: Bool
    let isTemplate: Bool
    let originalName: String?
    var onSave: ((String) -> Void)? = nil

    let providerTypes = ["gemini", "openai"]

    /// The catalog key used to look up models — derived from the provider name.
    private var catalogKey: String {
        // Try matching by name first (matches template names like "Gemini", "OpenAI", etc.)
        let key = name.lowercased()
        if !ModelCatalog.models(forProvider: key).isEmpty {
            return key
        }
        // Fallback to endpoint type
        return type
    }

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

    var body: some View {
        Form {
            Section("Basic Information") {
                TextField("Name", text: $name)

                Picker("Endpoint Type", selection: $type) {
                    ForEach(providerTypes, id: \.self) { t in
                        Text(t.capitalized).tag(t)
                    }
                }

                TextField("Base URL", text: $baseUrl)

                SecureField("API Key", text: $apiKey)
                    .onAppear {
                        if isEditing, let n = originalName {
                            apiKey = KeychainManager.load(key: "\(n)_api_key") ?? ""
                        }
                    }

                Toggle("Enabled", isOn: $isEnabled)
            }

            Section("Model Selection") {
                ModelSlotPicker(
                    label: "Default",
                    slotName: "default",
                    selection: $defaultSlot,
                    catalogKey: catalogKey
                )
                ModelSlotPicker(
                    label: "Background",
                    slotName: "background",
                    selection: $backgroundSlot,
                    catalogKey: catalogKey
                )
                ModelSlotPicker(
                    label: "Think",
                    slotName: "think",
                    selection: $thinkSlot,
                    catalogKey: catalogKey
                )
                ModelSlotPicker(
                    label: "Long Context",
                    slotName: "longContext",
                    selection: $longContextSlot,
                    catalogKey: catalogKey
                )
            }

            HStack {
                HStack(spacing: 12) {
                    Button("Test Connection") {
                        runTestConnection()
                    }
                    .disabled(testState == .testing || baseUrl.isEmpty || apiKey.isEmpty)

                    switch testState {
                    case .idle:
                        EmptyView()
                    case .testing:
                        ProgressView()
                            .controlSize(.small)
                        Text("Testing...")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Success")
                            .foregroundColor(.green)
                            .font(.caption)
                    case .failure(let errorMsg):
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(errorMsg)
                            .foregroundColor(.red)
                            .font(.caption)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(errorMsg)  // Tooltip for full error
                    }
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isTemplate ? "Enable Provider" : (!isEditing ? "Add Provider" : "Save")) {
                    saveProvider()
                    onSave?(name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || baseUrl.isEmpty)
            }
            .padding(.top, 20)

            if isEditing {
                if let deleteErrorMessage {
                    Text(deleteErrorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.top, 6)
                }

                Button("Make Active Provider") {
                    config.switchProvider(to: name)
                }
                .padding(.top, 10)

                Button(role: .destructive) {
                    deleteProvider()
                    dismiss()
                } label: {
                    Text("Delete Provider")
                        .foregroundColor(.red)
                }
                .padding(.top, 10)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
        .frame(minWidth: 450, idealWidth: 550)
        .onChange(of: baseUrl) { testState = .idle }
        .onChange(of: apiKey) { testState = .idle }
        .onChange(of: type) { testState = .idle }
        .onChange(of: defaultSlot) { testState = .idle }
    }

    private func saveProvider() {
        var slots: [String: String] = [:]
        if !defaultSlot.isEmpty { slots["default"] = defaultSlot }
        if !backgroundSlot.isEmpty { slots["background"] = backgroundSlot }
        if !thinkSlot.isEmpty { slots["think"] = thinkSlot }
        if !longContextSlot.isEmpty { slots["longContext"] = longContextSlot }

        let newProvider = ProviderConfig(
            name: name,
            type: type,
            baseUrl: baseUrl,
            slots: slots,
            enabled: isEnabled
        )

        if isEditing, let oldName = originalName, oldName != name {
            config.providers.removeValue(forKey: oldName)
            KeychainManager.delete(key: "\(oldName)_api_key")
        }

        config.providers[name] = newProvider

        if !apiKey.isEmpty && apiKey != "••••••••" {
            KeychainManager.save(key: "\(name)_api_key", value: apiKey)
        }

        if config.activeProvider.isEmpty || (isEditing && config.activeProvider == originalName) {
            config.activeProvider = name
        }

        config.save()
    }

    private func deleteProvider() {
        guard let name = originalName else { return }
        let blockers = config.presetsUsingProvider(name)
        guard blockers.isEmpty else {
            deleteErrorMessage =
                "Cannot delete '\(name)'. It is used by preset(s): \(blockers.joined(separator: ", "))."
            return
        }

        deleteErrorMessage = nil
        config.providers.removeValue(forKey: name)
        KeychainManager.delete(key: "\(name)_api_key")
        if config.activeProvider == name {
            config.activeProvider = config.providers.keys.first ?? ""
        }
        config.save()
    }

    private func runTestConnection() {
        // Reset state
        testState = .testing

        // Build parameters
        let testBaseUrl = self.baseUrl
        let testApiKey = self.apiKey
        let testType = self.type
        // Try to pick a model to test with
        let testModel =
            !self.defaultSlot.isEmpty
            ? self.defaultSlot
            : (!self.backgroundSlot.isEmpty
                ? self.backgroundSlot
                : (testType == "gemini" ? "gemini-3-flash-preview" : "gpt-5-mini"))

        Task {
            do {
                _ = try await GatewayTestService.shared.testConnection(
                    baseUrl: testBaseUrl,
                    apiKey: testApiKey,
                    type: testType,
                    model: testModel
                )
                // If we get here, no error was thrown
                if !Task.isCancelled {
                    testState = .success
                }
            } catch {
                if !Task.isCancelled {
                    testState = .failure(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Model Slot Picker

/// A picker that shows curated models from the catalog with a fallback
/// text field for custom model IDs.
struct ModelSlotPicker: View {
    let label: String
    let slotName: String
    @Binding var selection: String
    let catalogKey: String

    private static let customTag = "__custom__"

    /// The value for the Picker binding — either the model ID if it's in the catalog, or the custom tag.
    private var pickerValue: String {
        let models = ModelCatalog.models(forProvider: catalogKey)
        if models.contains(where: { $0.modelId == selection }) {
            return selection
        }
        return Self.customTag
    }

    /// Whether the user has selected "Custom…" or typed a non-catalog model.
    private var isCustom: Bool {
        pickerValue == Self.customTag
    }

    var body: some View {
        let models = ModelCatalog.models(forProvider: catalogKey)

        if models.isEmpty {
            // No catalog for this provider — plain text field
            TextField(label, text: $selection)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Picker(
                    label,
                    selection: Binding(
                        get: { pickerValue },
                        set: { newValue in
                            if newValue == Self.customTag {
                                // Switch to custom — clear if it was a catalog model
                                if !isCustom { selection = "" }
                            } else {
                                selection = newValue
                            }
                        }
                    )
                ) {
                    ForEach(models) { model in
                        ModelPickerRow(model: model)
                            .tag(model.modelId)
                    }
                    Divider()
                    Text("Custom…").tag(Self.customTag)
                }

                // Show selected model info
                if let info = models.first(where: { $0.modelId == selection }) {
                    HStack(spacing: 8) {
                        ModelTierBadge(tier: info.tier)

                        Text("\(formatTokenCount(info.maxInputTokens)) ctx")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(
                            "$\(info.cost.inputPerMillion, specifier: "%.2f")/$\(info.cost.outputPerMillion, specifier: "%.2f") /M"
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)

                        if info.supportsFunctionCalling {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .help("Supports function/tool calling")
                        }
                    }
                }

                // Custom text field
                if isCustom {
                    TextField("Custom model ID", text: $selection)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
            }
        }
    }

    private func formatTokenCount(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let m = Double(tokens) / 1_000_000.0
            return m.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(m))M" : String(format: "%.1fM", m)
        } else {
            return "\(tokens / 1_000)K"
        }
    }
}

// MARK: - Model Picker Row

/// A single row inside the model picker dropdown.
struct ModelPickerRow: View {
    let model: ModelInfo

    var body: some View {
        HStack {
            Text(model.displayName)
            Spacer()
            Text("$\(model.cost.inputPerMillion, specifier: "%.2f") in")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Model Tier Badge

/// Small colored badge showing the model's capability tier.
struct ModelTierBadge: View {
    let tier: ModelTier

    var body: some View {
        Text(tier.rawValue.capitalized)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tierColor.opacity(0.15))
            .foregroundColor(tierColor)
            .clipShape(Capsule())
    }

    private var tierColor: Color {
        switch tier {
        case .flagship: return .purple
        case .standard: return .blue
        case .fast: return .green
        case .reasoning: return .orange
        }
    }
}
