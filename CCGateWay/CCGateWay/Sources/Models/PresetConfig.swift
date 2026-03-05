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
