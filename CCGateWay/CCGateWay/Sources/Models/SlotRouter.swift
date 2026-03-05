import Foundation

enum SlotRouter {
    /// Known Anthropic model prefixes mapped to slot names
    private static let anthropicModelToSlot: [(pattern: String, slot: String)] = [
        // Haiku models -> background slot
        ("claude-3-5-haiku", "background"),
        ("claude-3-haiku", "background"),
        // Sonnet models -> default slot
        ("claude-sonnet-4", "default"),
        ("claude-3-7-sonnet", "default"),
        ("claude-3-5-sonnet", "default"),
        ("claude-3-sonnet", "default"),
        // Opus models -> think slot
        ("claude-opus-4", "think"),
        ("claude-3-opus", "think"),
    ]

    /// Resolve an incoming Anthropic model name to a canonical slot.
    static func resolveSlot(requestedModel: String) -> String {
        // Check for partial/prefix match (model names have version suffixes like -20241022)
        for (pattern, slot) in anthropicModelToSlot {
            if requestedModel.contains(pattern) { return slot }
        }

        // Check if the model name contains "thinking" -> think slot
        if requestedModel.contains("thinking") || requestedModel.contains("think") {
            return "think"
        }

        // Fallback to default slot
        return "default"
    }

    /// Backward-compatible helper used by existing provider-slot routing.
    static func resolve(
        requestedModel: String,
        provider: ProviderConfig
    ) -> (slot: String, providerModel: String) {
        let slot = resolveSlot(requestedModel: requestedModel)
        if let model = provider.slots[slot] {
            return (slot, model)
        }
        let fallback = provider.slots["default"] ?? provider.slots.values.first ?? requestedModel
        return (slot, fallback)
    }
}
