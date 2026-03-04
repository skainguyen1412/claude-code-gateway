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

    /// Resolve an incoming Anthropic model name to (slot, providerModel)
    static func resolve(
        requestedModel: String,
        provider: ProviderConfig
    ) -> (slot: String, providerModel: String) {
        // Check for partial/prefix match (model names have version suffixes like -20241022)
        for (pattern, slot) in anthropicModelToSlot {
            if requestedModel.contains(pattern),
                let model = provider.slots[slot]
            {
                return (slot, model)
            }
        }

        // Check if the model name contains "thinking" -> think slot
        if requestedModel.contains("thinking") || requestedModel.contains("think"),
            let model = provider.slots["think"]
        {
            return ("think", model)
        }

        // Fallback to default slot
        let model = provider.slots["default"] ?? provider.slots.values.first ?? requestedModel
        return ("default", model)
    }
}
