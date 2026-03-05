import Testing
@testable import CCGateWay

@Suite("Gateway preset sync")
struct GatewayConfigPresetSyncTests {
    @Test("env model vars are generated from active preset")
    func presetEnvValues() {
        let config = GatewayConfig(activeProvider: "", port: 3456, providers: [:], autoStartOnLogin: false)
        config.presets = [
            "Mixed": PresetConfig(
                name: "Mixed",
                slots: [
                    "default": .init(providerName: "OpenAI", modelId: "gpt-5"),
                    "background": .init(providerName: "Groq", modelId: "llama-3.1-8b-instant"),
                    "think": .init(providerName: "OpenAI", modelId: "o3"),
                    "longContext": .init(providerName: "OpenAI", modelId: "gpt-5.2-pro"),
                ]
            )
        ]
        config.activePreset = "Mixed"

        let env = config.buildClaudeEnvForTests(existingEnv: [:])
        #expect(env["ANTHROPIC_MODEL"] as? String == "gpt-5")
        #expect(env["ANTHROPIC_DEFAULT_OPUS_MODEL"] as? String == "o3")
        #expect(env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] as? String == "llama-3.1-8b-instant")
    }
}
