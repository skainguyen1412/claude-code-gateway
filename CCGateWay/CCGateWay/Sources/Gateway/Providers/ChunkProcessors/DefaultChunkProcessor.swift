import Foundation

/// No-op chunk processor for vanilla OpenAI models.
struct DefaultChunkProcessor: ChunkProcessor {
    mutating func process(chunk: inout [String: Any], delta: inout [String: Any]) -> [String] {
        return []
    }

    mutating func finalize() -> [String] {
        return []
    }
}
