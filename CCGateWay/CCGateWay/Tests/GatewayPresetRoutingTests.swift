import Testing
@testable import CCGateWay

@Suite("Gateway preset routing")
struct GatewayPresetRoutingTests {
    @Test("routing picks provider/model from active preset slot")
    func picksPresetTarget() throws {
        let config = GatewayConfig(
            activeProvider: "OpenAI",
            port: 3456,
            providers: [
                "OpenAI": .openAIDefault,
                "Groq": ProviderConfig.templates.first { $0.name == "Groq" }!,
            ],
            autoStartOnLogin: false
        )
        config.presets = [
            "Mixed": PresetConfig(
                name: "Mixed",
                slots: [
                    "default": .init(providerName: "Groq", modelId: "llama-3.3-70b-versatile")
                ]
            )
        ]
        config.activePreset = "Mixed"

        let resolved = try GatewayRoutes.resolveTargetForTests(
            requestedModel: "claude-3-5-sonnet-20241022",
            config: config,
            keyLookup: { _ in "key" }
        )

        #expect(resolved.provider.name == "Groq")
        #expect(resolved.modelId == "llama-3.3-70b-versatile")
    }
}
