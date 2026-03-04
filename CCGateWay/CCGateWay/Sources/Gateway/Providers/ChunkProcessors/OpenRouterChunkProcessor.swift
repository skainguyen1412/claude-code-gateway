import Foundation

/// Handles OpenRouter streaming quirks:
/// - Extracts `reasoning` field (OpenRouter's name for thinking content)
/// - Fixes numeric tool call IDs → call_UUID format
struct OpenRouterChunkProcessor: ChunkProcessor {
    private var reasoningContent = ""
    private var isReasoningComplete = false
    private var hasToolCall = false

    mutating func process(chunk: inout [String: Any], delta: inout [String: Any]) -> [String] {
        // Extract reasoning from delta (OpenRouter uses "reasoning", not "reasoning_content")
        if let reasoning = delta["reasoning"] as? String, !reasoning.isEmpty {
            reasoningContent += reasoning
            delta.removeValue(forKey: "reasoning")
            return []
        }

        // Mark reasoning complete when content appears
        if (delta["content"] as? String) != nil,
            !reasoningContent.isEmpty,
            !isReasoningComplete
        {
            isReasoningComplete = true
        }

        // Fix numeric tool call IDs
        if var toolCalls = delta["tool_calls"] as? [[String: Any]] {
            for i in toolCalls.indices {
                if let id = toolCalls[i]["id"] as? String,
                    Int(id) != nil
                {
                    toolCalls[i]["id"] = "call_\(UUID().uuidString.prefix(12))"
                }
            }
            delta["tool_calls"] = toolCalls
            if !hasToolCall { hasToolCall = true }
        }

        return []
    }

    mutating func finalize() -> [String] {
        return []
    }
}
