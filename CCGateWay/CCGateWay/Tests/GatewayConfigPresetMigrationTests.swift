import Foundation
import Testing
@testable import CCGateWay

@Suite("Gateway Config Preset Migration")
struct GatewayConfigPresetMigrationTests {
    @Test("legacy payload decodes with default preset fields")
    func legacyDecodeDefaults() throws {
        let legacyJSON = """
            {
              "activeProvider": "OpenAI",
              "autoStartOnLogin": false,
              "port": 3456,
              "providers": {
                "OpenAI": {
                  "name": "OpenAI",
                  "type": "openai",
                  "baseUrl": "https://api.openai.com/v1",
                  "slots": { "default": "gpt-5" },
                  "enabled": true
                }
              }
            }
            """.data(using: .utf8)!

        let config = try GatewayConfig.decodeFromDataForTests(legacyJSON)
        #expect(config.presets.isEmpty)
        #expect(config.activePreset.isEmpty)
    }

    @Test("migration creates preset from active provider slots")
    func migrationBuildsPreset() {
        let config = GatewayConfig(
            activeProvider: "OpenAI",
            port: 3456,
            providers: [
                "OpenAI": ProviderConfig(
                    name: "OpenAI",
                    type: "openai",
                    baseUrl: "https://api.openai.com/v1",
                    slots: [
                        "default": "gpt-5",
                        "background": "gpt-5-mini",
                        "think": "o3",
                        "longContext": "gpt-5.2-pro",
                    ],
                    enabled: true
                )
            ],
            autoStartOnLogin: false
        )

        config.migrateProvidersToPresetsIfNeeded()

        #expect(config.presets["Migrated Preset"] != nil)
        #expect(config.activePreset.isEmpty)
    }
}
