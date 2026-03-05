import Testing
@testable import CCGateWay

@Suite("Provider preset dependencies")
struct ProviderPresetDependencyTests {
    @Test("provider used by preset is reported as blocked")
    func detectsPresetDependency() {
        let config = GatewayConfig(activeProvider: "", port: 3456, providers: [:], autoStartOnLogin: false)
        config.presets = [
            "Mixed": PresetConfig(
                name: "Mixed",
                slots: ["default": .init(providerName: "Groq", modelId: "llama-3.3-70b-versatile")]
            )
        ]

        let blockers = config.presetsUsingProvider("Groq")
        #expect(blockers == ["Mixed"])
    }

    @Test("renaming provider updates preset slot references")
    func renameProviderUpdatesPresetReferences() {
        let config = GatewayConfig(activeProvider: "", port: 3456, providers: [:], autoStartOnLogin: false)
        config.presets = [
            "Mixed": PresetConfig(
                name: "Mixed",
                slots: [
                    "default": .init(providerName: "Groq", modelId: "llama-3.3-70b-versatile"),
                    "background": .init(providerName: "OpenAI", modelId: "gpt-5-mini"),
                ]
            )
        ]

        config.updatePresetProviderReferences(from: "Groq", to: "MyGroq")

        let preset = config.presets["Mixed"]
        #expect(preset?.slots["default"]?.providerName == "MyGroq")
        #expect(preset?.slots["background"]?.providerName == "OpenAI")
    }
}
