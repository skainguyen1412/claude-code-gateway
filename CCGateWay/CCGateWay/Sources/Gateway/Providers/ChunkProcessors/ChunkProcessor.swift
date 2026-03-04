import Foundation

/// Injected into OpenAISSEBuilder to handle provider-specific streaming fields.
/// Each provider can implement its own chunk processor to extract/transform
/// fields like reasoning_content or fix tool call IDs before generic conversion.
protocol ChunkProcessor {
    /// Pre-process a parsed JSON chunk before generic Anthropic conversion.
    /// Modify chunk/delta in-place and return any extra SSE events to emit.
    mutating func process(chunk: inout [String: Any], delta: inout [String: Any]) -> [String]

    /// Called when stream ends — emit any buffered content (e.g., thinking blocks).
    mutating func finalize() -> [String]
}
