import Foundation
import Vapor

enum PresetRouter {
    static func resolveSlotTarget(slot: String, preset: PresetConfig) throws -> PresetSlotTarget {
        guard let target = preset.slots[slot] else {
            throw Abort(.badRequest, reason: "Active preset has no mapping for slot '\(slot)'.")
        }
        return target
    }
}
