import Foundation
import SwiftUI

final class GatewayConfig: ObservableObject {
    @Published var activeProvider: String
    @Published var port: Int
    @Published var providers: [String: ProviderConfig]
    @Published var autoStartOnLogin: Bool

    init(
        activeProvider: String = "",
        port: Int = 3456,
        providers: [String: ProviderConfig] = [:],
        autoStartOnLogin: Bool = false
    ) {
        self.activeProvider = activeProvider
        self.port = port
        self.providers = providers
        self.autoStartOnLogin = autoStartOnLogin
    }

    // MARK: - Persistence

    private struct StorageModel: Codable {
        var activeProvider: String
        var port: Int
        var providers: [String: ProviderConfig]
        var autoStartOnLogin: Bool
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
        return GatewayConfig(
            activeProvider: storage.activeProvider,
            port: storage.port,
            providers: storage.providers,
            autoStartOnLogin: storage.autoStartOnLogin
        )
    }

    func save() {
        let storage = StorageModel(
            activeProvider: activeProvider,
            port: port,
            providers: providers,
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

    func switchProvider(to name: String) {
        guard providers[name] != nil else { return }
        activeProvider = name
        save()
        syncWithClaudeCode()
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
                var envDict = jsonDict["env"] as? [String: Any] ?? [:]

                let defaultModel = activeProviderConfig?.slots["default"] ?? "unknown_model"
                let opusModel = activeProviderConfig?.slots["think"] ?? defaultModel
                let haikuModel = activeProviderConfig?.slots["background"] ?? defaultModel

                // Update configurations native Oh My OpenCode wrapper requires
                envDict["ANTHROPIC_AUTH_TOKEN"] = "dummy_key_gateway"
                envDict["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:\(port)"
                envDict["ANTHROPIC_MODEL"] = defaultModel
                envDict["ANTHROPIC_DEFAULT_OPUS_MODEL"] = opusModel
                envDict["ANTHROPIC_DEFAULT_SONNET_MODEL"] = defaultModel
                envDict["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = haikuModel
                envDict["CLAUDE_CODE_SUBAGENT_MODEL"] = haikuModel

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
