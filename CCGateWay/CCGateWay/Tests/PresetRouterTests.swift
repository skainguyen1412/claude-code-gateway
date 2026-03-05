import Testing
@testable import CCGateWay

@Suite("Preset Router")
struct PresetRouterTests {
    @Test("resolveSlotTarget returns provider and model for slot")
    func resolveTarget() throws {
        let preset = PresetConfig(
            name: "Mixed",
            slots: [
                "default": .init(providerName: "OpenAI", modelId: "gpt-5")
            ]
        )

        let target = try PresetRouter.resolveSlotTarget(slot: "default", preset: preset)
        #expect(target.providerName == "OpenAI")
        #expect(target.modelId == "gpt-5")
    }

    @Test("resolveSlot returns background for haiku model")
    func slotDetection() {
        let slot = SlotRouter.resolveSlot(requestedModel: "claude-3-5-haiku-20241022")
        #expect(slot == "background")
    }
}
