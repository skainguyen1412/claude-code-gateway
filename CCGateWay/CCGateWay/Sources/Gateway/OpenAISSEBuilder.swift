import Foundation

/// Builds Anthropic-format SSE event strings from parsed OpenAI streaming chunks.
/// Converts OpenAI chat.completion.chunk format to Anthropic message events.
struct OpenAISSEBuilder {
    private let messageId: String
    private let requestedModel: String
    private var hasStarted = false
    private var hasTextBlockStarted = false
    private var contentBlockIndex = 0
    private var currentBlockIndex = -1

    // Tool call tracking — OpenAI sends tool call args incrementally
    private var activeToolCalls: [Int: (id: String, name: String, args: String, blockIndex: Int)] =
        [:]

    // Token tracking
    private var lastInputTokens = 0
    private var lastOutputTokens = 0

    // Provider-specific chunk processing hook
    private var chunkProcessor: ChunkProcessor

    init(requestedModel: String, chunkProcessor: ChunkProcessor = DefaultChunkProcessor()) {
        self.messageId = "msg_\(UUID().uuidString.prefix(16))"
        self.requestedModel = requestedModel
        self.chunkProcessor = chunkProcessor
    }

    /// Process a single OpenAI streaming JSON chunk and return Anthropic SSE events.
    mutating func processOpenAIChunk(_ jsonString: String) -> [String] {
        guard let data = jsonString.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        var events: [String] = []

        // Check for error
        if let error = json["error"] as? [String: Any] {
            let errorMsg = error["message"] as? String ?? "Unknown error"
            events.append(
                sseEvent(
                    "error",
                    data: [
                        "type": "error",
                        "error": [
                            "type": "api_error",
                            "message": "OpenAI API error: \(errorMsg)",
                        ],
                    ]))
            return events
        }

        // Track usage (OpenAI sends usage in a separate chunk when stream_options.include_usage is true)
        if let usage = json["usage"] as? [String: Any] {
            lastInputTokens = usage["prompt_tokens"] as? Int ?? lastInputTokens
            lastOutputTokens = usage["completion_tokens"] as? Int ?? lastOutputTokens
        }

        // Extract model from upstream chunk (like claude-code-router reference)
        let upstreamModel = json["model"] as? String ?? requestedModel

        // 1. Emit message_start on first chunk
        if !hasStarted {
            hasStarted = true
            let messageStart: [String: Any] = [
                "type": "message_start",
                "message": [
                    "id": messageId,
                    "type": "message",
                    "role": "assistant",
                    "content": [] as [Any],
                    "model": upstreamModel,
                    "stop_reason": NSNull(),
                    "stop_sequence": NSNull(),
                    "usage": [
                        "input_tokens": 0,
                        "output_tokens": 0,
                    ],
                ] as [String: Any],
            ]
            events.append(sseEvent("message_start", data: messageStart))
        }

        // 2. Process choices
        var mutableJson = json
        let choices = mutableJson["choices"] as? [[String: Any]] ?? []
        guard let choice = choices.first else { return events }

        var delta = choice["delta"] as? [String: Any] ?? [:]
        let finishReason = choice["finish_reason"] as? String

        // 2a. Let chunk processor handle provider-specific fields first
        let extraEvents = chunkProcessor.process(chunk: &mutableJson, delta: &delta)
        events.append(contentsOf: extraEvents)

        // 3. Text content
        if let content = delta["content"] as? String, !content.isEmpty {
            if !hasTextBlockStarted {
                hasTextBlockStarted = true
                let blockIndex = nextBlockIndex()
                events.append(
                    sseEvent(
                        "content_block_start",
                        data: [
                            "type": "content_block_start",
                            "index": blockIndex,
                            "content_block": ["type": "text", "text": ""],
                        ]))
            }
            events.append(
                sseEvent(
                    "content_block_delta",
                    data: [
                        "type": "content_block_delta",
                        "index": currentBlockIndex,
                        "delta": ["type": "text_delta", "text": content],
                    ]))
        }

        // 4. Tool calls
        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
            // Close text block if open
            if hasTextBlockStarted {
                events.append(contentBlockStop(index: currentBlockIndex))
                hasTextBlockStarted = false
            }

            for tc in toolCalls {
                let tcIndex = tc["index"] as? Int ?? 0
                let function = tc["function"] as? [String: Any] ?? [:]

                if activeToolCalls[tcIndex] == nil {
                    // New tool call — emit content_block_start
                    let toolId =
                        tc["id"] as? String ?? "call_\(UUID().uuidString.prefix(12))"
                    let toolName = function["name"] as? String ?? "unknown"
                    let blockIndex = nextBlockIndex()

                    activeToolCalls[tcIndex] = (
                        id: toolId, name: toolName, args: "", blockIndex: blockIndex
                    )

                    events.append(
                        sseEvent(
                            "content_block_start",
                            data: [
                                "type": "content_block_start",
                                "index": blockIndex,
                                "content_block": [
                                    "type": "tool_use",
                                    "id": toolId,
                                    "name": toolName,
                                    "input": [String: Any](),
                                ] as [String: Any],
                            ]))
                }

                // Accumulate arguments
                if let args = function["arguments"] as? String, !args.isEmpty {
                    activeToolCalls[tcIndex]?.args += args
                    let blockIndex = activeToolCalls[tcIndex]!.blockIndex

                    events.append(
                        sseEvent(
                            "content_block_delta",
                            data: [
                                "type": "content_block_delta",
                                "index": blockIndex,
                                "delta": [
                                    "type": "input_json_delta",
                                    "partial_json": args,
                                ],
                            ]))
                }
            }
        }

        // 5. Finish reason
        if let finishReason = finishReason {
            // Close open text block
            if hasTextBlockStarted {
                events.append(contentBlockStop(index: currentBlockIndex))
                hasTextBlockStarted = false
            }

            // Close open tool call blocks
            for (_, tc) in activeToolCalls.sorted(by: { $0.key < $1.key }) {
                events.append(contentBlockStop(index: tc.blockIndex))
            }
            activeToolCalls.removeAll()

            let stopReason: String
            switch finishReason {
            case "stop": stopReason = "end_turn"
            case "length": stopReason = "max_tokens"
            case "tool_calls": stopReason = "tool_use"
            default: stopReason = "end_turn"
            }

            events.append(
                sseEvent(
                    "message_delta",
                    data: [
                        "type": "message_delta",
                        "delta": [
                            "stop_reason": stopReason,
                            "stop_sequence": NSNull(),
                        ] as [String: Any],
                        "usage": [
                            "input_tokens": lastInputTokens,
                            "output_tokens": lastOutputTokens,
                        ],
                    ]))
            events.append(sseEvent("message_stop", data: ["type": "message_stop"]))
        }

        return events
    }

    /// Generate final events if stream ends without a finish_reason.
    mutating func finalize() -> [String] {
        var events: [String] = []

        // Let chunk processor emit any buffered content (e.g., thinking blocks)
        let processorEvents = chunkProcessor.finalize()
        events.append(contentsOf: processorEvents)

        if hasTextBlockStarted {
            events.append(contentBlockStop(index: currentBlockIndex))
        }
        for (_, tc) in activeToolCalls.sorted(by: { $0.key < $1.key }) {
            events.append(contentBlockStop(index: tc.blockIndex))
        }

        events.append(
            sseEvent(
                "message_delta",
                data: [
                    "type": "message_delta",
                    "delta": [
                        "stop_reason": "end_turn",
                        "stop_sequence": NSNull(),
                    ] as [String: Any],
                    "usage": [
                        "input_tokens": lastInputTokens,
                        "output_tokens": lastOutputTokens,
                    ],
                ]))
        events.append(sseEvent("message_stop", data: ["type": "message_stop"]))

        return events
    }

    /// Returns last tracked (inputTokens, outputTokens).
    var tokenUsage: (inputTokens: Int, outputTokens: Int) {
        (lastInputTokens, lastOutputTokens)
    }

    // MARK: - Helpers

    private mutating func nextBlockIndex() -> Int {
        let idx = contentBlockIndex
        contentBlockIndex += 1
        currentBlockIndex = idx
        return idx
    }

    private func contentBlockStop(index: Int) -> String {
        sseEvent(
            "content_block_stop",
            data: [
                "type": "content_block_stop",
                "index": index,
            ])
    }

    private func sseEvent(_ event: String, data: [String: Any]) -> String {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
            let jsonStr = String(data: jsonData, encoding: .utf8)
        else { return "" }
        return "event: \(event)\ndata: \(jsonStr)\n\n"
    }
}
