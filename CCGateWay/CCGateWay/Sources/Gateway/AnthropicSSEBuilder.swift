import Foundation

/// Builds Anthropic-format SSE event strings from parsed Gemini response chunks.
/// Tracks state across chunks to properly sequence content blocks.
struct AnthropicSSEBuilder: Sendable {
    private let messageId: String
    private let requestedModel: String
    private var hasStarted = false
    private var hasTextBlockStarted = false
    private var contentBlockIndex = 0
    private var currentBlockIndex = -1

    // Token tracking for final usage
    private var lastInputTokens = 0
    private var lastOutputTokens = 0

    init(requestedModel: String) {
        self.messageId = "msg_\(UUID().uuidString.prefix(16))"
        self.requestedModel = requestedModel
    }

    /// Process a single Gemini JSON chunk and return Anthropic SSE event strings.
    /// Each returned string is a complete SSE event (e.g. "event: content_block_delta\ndata: {...}\n\n").
    mutating func processGeminiChunk(_ jsonString: String) -> [String] {
        guard let data = jsonString.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        var events: [String] = []

        // Check for error responses from Gemini
        if let error = json["error"] as? [String: Any] {
            let errorMsg = error["message"] as? String ?? "Unknown error"
            let errorEvent: [String: Any] = [
                "type": "error",
                "error": [
                    "type": "api_error",
                    "message": "Gemini API error: \(errorMsg)",
                ],
            ]
            events.append(sseEvent("error", data: errorEvent))
            return events
        }

        // Track usage metadata
        if let usage = json["usageMetadata"] as? [String: Any] {
            lastInputTokens = usage["promptTokenCount"] as? Int ?? lastInputTokens
            lastOutputTokens = usage["candidatesTokenCount"] as? Int ?? lastOutputTokens
        }

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
                    "model": requestedModel,
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

        // 2. Extract candidate parts
        guard let candidates = json["candidates"] as? [[String: Any]],
            let candidate = candidates.first,
            let content = candidate["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            // Chunk without candidates (e.g. usage-only chunk) — skip
            return events
        }

        let finishReason = candidate["finishReason"] as? String

        // 3. Process each part
        for part in parts {
            // Skip thinking parts (internal model reasoning)
            if part["thought"] as? Bool == true {
                continue
            }

            if let text = part["text"] as? String {
                // Text content
                if !hasTextBlockStarted {
                    hasTextBlockStarted = true
                    let blockIndex = nextBlockIndex()
                    let blockStart: [String: Any] = [
                        "type": "content_block_start",
                        "index": blockIndex,
                        "content_block": [
                            "type": "text",
                            "text": "",
                        ],
                    ]
                    events.append(sseEvent("content_block_start", data: blockStart))
                }

                let delta: [String: Any] = [
                    "type": "content_block_delta",
                    "index": currentBlockIndex,
                    "delta": [
                        "type": "text_delta",
                        "text": text,
                    ],
                ]
                events.append(sseEvent("content_block_delta", data: delta))
            }

            if let funcCall = part["functionCall"] as? [String: Any] {
                // Close text block if open
                if hasTextBlockStarted {
                    events.append(contentBlockStop(index: currentBlockIndex))
                    hasTextBlockStarted = false
                }

                let toolName = funcCall["name"] as? String ?? "unknown"
                let toolArgs = funcCall["args"] as? [String: Any] ?? [:]
                let toolId = funcCall["id"] as? String ?? "call_\(UUID().uuidString.prefix(12))"

                let blockIndex = nextBlockIndex()

                // Build tool_use content block, preserving thoughtSignature for round-tripping
                var toolBlock: [String: Any] = [
                    "type": "tool_use",
                    "id": toolId,
                    "name": toolName,
                    "input": [String: Any](),
                ]
                // Preserve thoughtSignature so it round-trips through Anthropic format.
                // Gemini 3 models require this on functionCall parts in subsequent turns.
                if let sig = part["thoughtSignature"] as? String {
                    toolBlock["_thought_signature"] = sig
                }

                // tool_use content_block_start
                let toolStart: [String: Any] = [
                    "type": "content_block_start",
                    "index": blockIndex,
                    "content_block": toolBlock,
                ]
                events.append(sseEvent("content_block_start", data: toolStart))

                // Send args as input_json_delta
                if let argsData = try? JSONSerialization.data(withJSONObject: toolArgs),
                    let argsStr = String(data: argsData, encoding: .utf8)
                {
                    let inputDelta: [String: Any] = [
                        "type": "content_block_delta",
                        "index": blockIndex,
                        "delta": [
                            "type": "input_json_delta",
                            "partial_json": argsStr,
                        ],
                    ]
                    events.append(sseEvent("content_block_delta", data: inputDelta))
                }

                // Close tool block
                events.append(contentBlockStop(index: blockIndex))
            }
        }

        // 4. If finish reason present, close everything
        if let finishReason = finishReason, finishReason == "STOP" || finishReason == "MAX_TOKENS" {
            // Close open text block
            if hasTextBlockStarted {
                events.append(contentBlockStop(index: currentBlockIndex))
                hasTextBlockStarted = false
            }

            let stopReason = finishReason == "MAX_TOKENS" ? "max_tokens" : "end_turn"

            let messageDelta: [String: Any] = [
                "type": "message_delta",
                "delta": [
                    "stop_reason": stopReason,
                    "stop_sequence": NSNull(),
                ] as [String: Any],
                "usage": [
                    "input_tokens": lastInputTokens,
                    "output_tokens": lastOutputTokens,
                ],
            ]
            events.append(sseEvent("message_delta", data: messageDelta))
            events.append(sseEvent("message_stop", data: ["type": "message_stop"]))
        }

        return events
    }

    /// Generate final events if the stream ends without a finishReason.
    /// Call this after all chunks have been processed.
    mutating func finalize() -> [String] {
        var events: [String] = []

        if hasTextBlockStarted {
            events.append(contentBlockStop(index: currentBlockIndex))
        }

        let messageDelta: [String: Any] = [
            "type": "message_delta",
            "delta": [
                "stop_reason": "end_turn",
                "stop_sequence": NSNull(),
            ] as [String: Any],
            "usage": [
                "input_tokens": lastInputTokens,
                "output_tokens": lastOutputTokens,
            ],
        ]
        events.append(sseEvent("message_delta", data: messageDelta))
        events.append(sseEvent("message_stop", data: ["type": "message_stop"]))

        return events
    }

    // MARK: - Public accessors

    /// Returns the last tracked (inputTokens, outputTokens) from Gemini usage metadata.
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
