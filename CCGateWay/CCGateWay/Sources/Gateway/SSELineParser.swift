import Foundation
import NIOCore

/// Parses raw byte stream into complete SSE data lines.
/// Accumulates partial data across ByteBuffer boundaries.
struct SSELineParser: Sendable {
    private var buffer: String = ""

    /// Feed raw bytes, returns any complete SSE data payloads (JSON strings).
    mutating func feed(_ byteBuffer: ByteBuffer) -> [String] {
        guard
            let chunk = byteBuffer.getString(
                at: byteBuffer.readerIndex, length: byteBuffer.readableBytes)
        else {
            return []
        }
        buffer += chunk

        var results: [String] = []

        // Split on double newline (SSE event boundary)
        while let range = buffer.range(of: "\n\n") {
            let eventBlock = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])

            // Extract the data line(s) from the event block
            let lines = eventBlock.components(separatedBy: "\n")
            for line in lines {
                if line.hasPrefix("data: ") {
                    let jsonStr = String(line.dropFirst(6))
                    if !jsonStr.isEmpty {
                        results.append(jsonStr)
                    }
                }
            }
        }

        return results
    }
}
