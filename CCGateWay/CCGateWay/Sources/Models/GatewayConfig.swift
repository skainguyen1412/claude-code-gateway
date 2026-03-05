import Foundation
import SwiftUI

final class GatewayConfig: ObservableObject {
    @Published var activeProvider: String
    @Published var port: Int
    @Published var providers: [String: ProviderConfig]
    @Published var presets: [String: PresetConfig]
    @Published var activePreset: String
    @Published var autoStartOnLogin: Bool

    init(
        activeProvider: String = "",
        port: Int = 3456,
        providers: [String: ProviderConfig] = [:],
        presets: [String: PresetConfig] = [:],
        activePreset: String = "",
        autoStartOnLogin: Bool = false
    ) {
        self.activeProvider = activeProvider
        self.port = port
        self.providers = providers
        self.presets = presets
        self.activePreset = activePreset
        self.autoStartOnLogin = autoStartOnLogin
    }

    // MARK: - Persistence

    private struct StorageModel: Codable {
        var activeProvider: String
        var port: Int
        var providers: [String: ProviderConfig]
        var presets: [String: PresetConfig]
        var activePreset: String
        var autoStartOnLogin: Bool

        enum CodingKeys: String, CodingKey {
            case activeProvider
            case port
            case providers
            case presets
            case activePreset
            case autoStartOnLogin
        }

        init(
            activeProvider: String,
            port: Int,
            providers: [String: ProviderConfig],
            presets: [String: PresetConfig],
            activePreset: String,
            autoStartOnLogin: Bool
        ) {
            self.activeProvider = activeProvider
            self.port = port
            self.providers = providers
            self.presets = presets
            self.activePreset = activePreset
            self.autoStartOnLogin = autoStartOnLogin
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            activeProvider = try container.decodeIfPresent(String.self, forKey: .activeProvider) ?? ""
            port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 3456
            providers = try container.decodeIfPresent([String: ProviderConfig].self, forKey: .providers) ?? [:]
            presets = try container.decodeIfPresent([String: PresetConfig].self, forKey: .presets) ?? [:]
            activePreset = try container.decodeIfPresent(String.self, forKey: .activePreset) ?? ""
            autoStartOnLogin = try container.decodeIfPresent(Bool.self, forKey: .autoStartOnLogin) ?? false
        }
    }

    static var configDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("CCGateWay")
    }

    static var configURL: URL {
        let dir = configDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> GatewayConfig {
        guard let data = try? Data(contentsOf: configURL),
            let storage = try? JSONDecoder().decode(StorageModel.self, from: data)
        else {
            return GatewayConfig()
        }
        let config = GatewayConfig(
            activeProvider: storage.activeProvider,
            port: storage.port,
            providers: storage.providers,
            presets: storage.presets,
            activePreset: storage.activePreset,
            autoStartOnLogin: storage.autoStartOnLogin
        )
        config.migrateProvidersToPresetsIfNeeded()
        return config
    }

    func save() {
        let storage = StorageModel(
            activeProvider: activeProvider,
            port: port,
            providers: providers,
            presets: presets,
            activePreset: activePreset,
            autoStartOnLogin: autoStartOnLogin
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(storage) {
            try? data.write(to: GatewayConfig.configURL, options: .atomic)
        }
    }

    // MARK: - Active provider helper

    var activeProviderConfig: ProviderConfig? {
        providers[activeProvider]
    }

    var activePresetConfig: PresetConfig? {
        presets[activePreset]
    }

    func switchProvider(to name: String) {
        guard providers[name] != nil else { return }
        activeProvider = name
        save()
        syncWithClaudeCode()
    }

    func switchPreset(to name: String) {
        guard presets[name] != nil else { return }
        activePreset = name
        save()
        syncWithClaudeCode()
    }

    func migrateProvidersToPresetsIfNeeded() {
        guard presets.isEmpty, let active = providers[activeProvider] else { return }

        let migratedName = "Migrated Preset"
        let migrated = PresetConfig(
            name: migratedName,
            slots: [
                "default": .init(providerName: active.name, modelId: active.slots["default"] ?? ""),
                "background": .init(providerName: active.name, modelId: active.slots["background"] ?? ""),
                "think": .init(providerName: active.name, modelId: active.slots["think"] ?? ""),
                "longContext": .init(providerName: active.name, modelId: active.slots["longContext"] ?? ""),
            ]
        )

        presets[migratedName] = migrated
        activePreset = migratedName
    }

    func activeSlotModels() -> (defaultModel: String, thinkModel: String, backgroundModel: String) {
        if let preset = activePresetConfig {
            let defaultModel =
                preset.slots["default"]?.modelId
                ?? activeProviderConfig?.slots["default"]
                ?? "unknown_model"
            let thinkModel = preset.slots["think"]?.modelId ?? defaultModel
            let backgroundModel = preset.slots["background"]?.modelId ?? defaultModel
            return (defaultModel, thinkModel, backgroundModel)
        }

        let defaultModel = activeProviderConfig?.slots["default"] ?? "unknown_model"
        return (
            defaultModel,
            activeProviderConfig?.slots["think"] ?? defaultModel,
            activeProviderConfig?.slots["background"] ?? defaultModel
        )
    }

    func buildClaudeEnv(existingEnv: [String: Any]) -> [String: Any] {
        var envDict = existingEnv
        let models = activeSlotModels()

        // Update configurations native Oh My OpenCode wrapper requires.
        envDict["ANTHROPIC_AUTH_TOKEN"] = "dummy_key_gateway"
        envDict["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:\(port)"
        envDict["ANTHROPIC_MODEL"] = models.defaultModel
        envDict["ANTHROPIC_DEFAULT_OPUS_MODEL"] = models.thinkModel
        envDict["ANTHROPIC_DEFAULT_SONNET_MODEL"] = models.defaultModel
        envDict["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = models.backgroundModel
        envDict["CLAUDE_CODE_SUBAGENT_MODEL"] = models.backgroundModel

        return envDict
    }

    // MARK: - Auto-Sync

    public func syncWithClaudeCode() {
        Task {
            let fileManager = FileManager.default
            let homeURL = fileManager.homeDirectoryForCurrentUser
            let claudeJsonURL = homeURL.appendingPathComponent(".claude/settings.json")

            do {
                var jsonDict: [String: Any] = [:]

                // Ensure ~/.claude directory exists
                let claudeDir = homeURL.appendingPathComponent(".claude")
                if !fileManager.fileExists(atPath: claudeDir.path) {
                    try fileManager.createDirectory(
                        at: claudeDir, withIntermediateDirectories: true)
                }

                // Read existing config if it exists
                if fileManager.fileExists(atPath: claudeJsonURL.path) {
                    let data = try Data(contentsOf: claudeJsonURL)
                    if let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    {
                        jsonDict = existing
                    }
                }

                // Ensure "env" dictionary exists
                let existingEnv = jsonDict["env"] as? [String: Any] ?? [:]
                let envDict = buildClaudeEnv(existingEnv: existingEnv)

                jsonDict["env"] = envDict

                let encodedData = try JSONSerialization.data(
                    withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys])
                try encodedData.write(to: claudeJsonURL, options: .atomic)

                print("Successfully updated ~/.claude/settings.json to point to CCGateWay.")
            } catch {
                print("Failed to update ~/.claude/settings.json: \(error)")
            }
        }
    }

    /// Removes all CCGateWay-injected env vars from ~/.claude/settings.json
    public func resetClaudeCodeSettings() {
        let fileManager = FileManager.default
        let homeURL = fileManager.homeDirectoryForCurrentUser
        let claudeJsonURL = homeURL.appendingPathComponent(".claude/settings.json")

        do {
            guard fileManager.fileExists(atPath: claudeJsonURL.path) else { return }

            let data = try Data(contentsOf: claudeJsonURL)
            guard var jsonDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

            if var envDict = jsonDict["env"] as? [String: Any] {
                let keysToRemove = [
                    "ANTHROPIC_AUTH_TOKEN",
                    "ANTHROPIC_BASE_URL",
                    "ANTHROPIC_MODEL",
                    "ANTHROPIC_DEFAULT_OPUS_MODEL",
                    "ANTHROPIC_DEFAULT_SONNET_MODEL",
                    "ANTHROPIC_DEFAULT_HAIKU_MODEL",
                    "CLAUDE_CODE_SUBAGENT_MODEL",
                ]
                for key in keysToRemove {
                    envDict.removeValue(forKey: key)
                }
                if envDict.isEmpty {
                    jsonDict.removeValue(forKey: "env")
                } else {
                    jsonDict["env"] = envDict
                }
            }

            let encodedData = try JSONSerialization.data(
                withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys])
            try encodedData.write(to: claudeJsonURL, options: .atomic)

            print("Successfully reset ~/.claude/settings.json — removed CCGateWay env vars.")
        } catch {
            print("Failed to reset ~/.claude/settings.json: \(error)")
        }
    }
}

#if DEBUG
extension GatewayConfig {
    static func decodeFromDataForTests(_ data: Data) throws -> GatewayConfig {
        let storage = try JSONDecoder().decode(StorageModel.self, from: data)
        return GatewayConfig(
            activeProvider: storage.activeProvider,
            port: storage.port,
            providers: storage.providers,
            presets: storage.presets,
            activePreset: storage.activePreset,
            autoStartOnLogin: storage.autoStartOnLogin
        )
    }

    func buildClaudeEnvForTests(existingEnv: [String: Any]) -> [String: Any] {
        buildClaudeEnv(existingEnv: existingEnv)
    }
}
#endif
