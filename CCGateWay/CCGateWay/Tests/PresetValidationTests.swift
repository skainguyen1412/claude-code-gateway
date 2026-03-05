import Testing
@testable import CCGateWay

@Suite("Preset validation")
struct PresetValidationTests {
    @Test("preset is invalid when a slot is missing")
    func missingSlot() {
        let preset = PresetConfig(
            name: "Broken",
            slots: ["default": .init(providerName: "OpenAI", modelId: "gpt-5")]
        )
        #expect(PresetValidator.validate(preset: preset).isValid == false)
    }
}
