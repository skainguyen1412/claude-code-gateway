import Foundation

struct PresetSlotTarget: Codable, Hashable {
    var providerName: String
    var modelId: String
}

struct PresetConfig: Codable, Identifiable, Hashable {
    var id: String { name.lowercased() }
    var name: String
    var enabled: Bool = true
    var slots: [String: PresetSlotTarget]
}

enum PresetValidator {
    static let requiredSlots = ["default", "background", "think", "longContext"]

    static func validate(preset: PresetConfig) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []

        if preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Preset name is required.")
        }

        for slot in requiredSlots {
            guard let target = preset.slots[slot],
                !target.providerName.isEmpty,
                !target.modelId.isEmpty
            else {
                errors.append("Slot '\(slot)' must map to provider and model.")
                continue
            }
        }

        return (errors.isEmpty, errors)
    }
}
