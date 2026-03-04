import Foundation

/// Handles DeepSeek's `reasoning_content` field in streaming responses.
/// Converts it to Anthropic-compatible thinking block SSE events.
struct DeepSeekChunkProcessor: ChunkProcessor {
    private var reasoningContent = ""
    private var isReasoningComplete = false

    mutating func process(chunk: inout [String: Any], delta: inout [String: Any]) -> [String] {
        // Extract reasoning_content from delta (DeepSeek's thinking field)
        if let rc = delta["reasoning_content"] as? String, !rc.isEmpty {
            reasoningContent += rc
            // Remove from delta so generic builder doesn't see it as text
            delta.removeValue(forKey: "reasoning_content")
            return []
        }

        // When regular content appears after reasoning, mark reasoning as complete
        if (delta["content"] as? String) != nil,
            !reasoningContent.isEmpty,
            !isReasoningComplete
        {
            isReasoningComplete = true
        }

        return []
    }

    mutating func finalize() -> [String] {
        return []
    }
}
