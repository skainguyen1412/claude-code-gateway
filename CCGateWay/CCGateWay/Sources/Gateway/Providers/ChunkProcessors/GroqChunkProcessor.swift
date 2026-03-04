import Foundation

/// Handles Groq's streaming quirks: regenerates tool call IDs as call_UUID format.
/// Groq sometimes returns numeric IDs that Claude Code doesn't understand.
struct GroqChunkProcessor: ChunkProcessor {
    mutating func process(chunk: inout [String: Any], delta: inout [String: Any]) -> [String] {
        // Regenerate tool call IDs — Groq sometimes returns numeric IDs
        if var toolCalls = delta["tool_calls"] as? [[String: Any]] {
            for i in toolCalls.indices {
                toolCalls[i]["id"] = "call_\(UUID().uuidString.prefix(12))"
            }
            delta["tool_calls"] = toolCalls
        }
        return []
    }

    mutating func finalize() -> [String] {
        return []
    }
}
