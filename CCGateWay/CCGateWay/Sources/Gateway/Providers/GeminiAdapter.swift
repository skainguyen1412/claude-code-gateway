import Foundation
import Vapor

struct GeminiAdapter: ProviderAdapter {
    let providerType = "gemini"

    func transformRequest(
        anthropicBody: [String: Any],
        targetModel: String,
        provider: ProviderConfig,
        apiKey: String,
        forceNonStreaming: Bool = false
    ) throws -> (url: URI, headers: HTTPHeaders, body: [String: Any]) {

        let isStreaming = !forceNonStreaming && ((anthropicBody["stream"] as? Bool) ?? false)
        let action = isStreaming ? "streamGenerateContent?alt=sse" : "generateContent"

        let pathStr = provider.baseUrl.hasSuffix("/") ? provider.baseUrl : provider.baseUrl + "/"
        let urlString = "\(pathStr)\(targetModel):\(action)"
        let url = URI(string: urlString)

        var headers = HTTPHeaders()
        headers.add(name: "x-goog-api-key", value: apiKey)
        headers.add(name: "Content-Type", value: "application/json")

        var body: [String: Any] = [:]

        // 1. Map messages
        let contents = buildContents(from: anthropicBody)
        if !contents.isEmpty {
            body["contents"] = contents
        }

        // 2. Map tools
        let tools = buildTools(from: anthropicBody)
        if !tools.isEmpty {
            body["tools"] = [["functionDeclarations": tools]]
        }

        // 3. Map system prompt
        if let system = anthropicBody["system"] {
            let systemText = extractSystemText(from: system)
            if !systemText.isEmpty {
                body["systemInstruction"] = [
                    "parts": [["text": systemText]]
                ]
            }
        }

        // 4. Map configuration (temperature, maxTokens, etc.)
        var generationConfig: [String: Any] = [:]
        if let temperature = anthropicBody["temperature"] as? Double {
            generationConfig["temperature"] = temperature
        }
        if let maxTokens = anthropicBody["max_tokens"] as? Int {
            if let modelInfo = ModelCatalog.find(modelId: targetModel),
                maxTokens > modelInfo.maxOutputTokens
            {
                generationConfig["maxOutputTokens"] = modelInfo.maxOutputTokens
                print(
                    "[GeminiAdapter] ⚠️ Clamped max_tokens \(maxTokens) → \(modelInfo.maxOutputTokens) for \(targetModel)"
                )
            } else {
                generationConfig["maxOutputTokens"] = maxTokens
            }
        }
        if !generationConfig.isEmpty {
            body["generationConfig"] = generationConfig
        }

        return (url, headers, body)
    }

    func transformResponse(responseData: Data, isStreaming: Bool, requestedModel: String) throws
        -> Data
    {
        guard let gemini = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        else {
            // Log the raw response for debugging
            let rawStr = String(data: responseData, encoding: .utf8) ?? "(binary data)"
            print("[GeminiAdapter] ❌ Failed to parse response JSON. Raw: \(rawStr.prefix(500))")
            throw Abort(.badGateway, reason: "Invalid Gemini response JSON")
        }

        // Check for Gemini API errors first (e.g., invalid model, bad schema, quota)
        if let error = gemini["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? 0
            let message = error["message"] as? String ?? "Unknown Gemini error"
            let status = error["status"] as? String ?? ""
            print("[GeminiAdapter] ❌ Gemini API error \(code) (\(status)): \(message)")
            throw Abort(
                HTTPResponseStatus(statusCode: code != 0 ? code : 502),
                reason: "Gemini API error: \(message)"
            )
        }

        guard let candidates = gemini["candidates"] as? [[String: Any]],
            let firstCandidate = candidates.first
        else {
            // Log full response so we can debug what Gemini actually returned
            let debugStr = String(data: responseData, encoding: .utf8) ?? "(binary)"
            print("[GeminiAdapter] ❌ Missing candidates. Full response: \(debugStr.prefix(1000))")
            throw Abort(.badGateway, reason: "Missing candidates in Gemini response")
        }

        var anthropicContent: [[String: Any]] = []

        if let content = firstCandidate["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        {
            for part in parts {
                // Skip thinking parts (internal model reasoning)
                if part["thought"] as? Bool == true {
                    continue
                }

                if let text = part["text"] as? String {
                    anthropicContent.append([
                        "type": "text",
                        "text": text,
                    ])
                }
                if let funcCall = part["functionCall"] as? [String: Any] {
                    let name = funcCall["name"] as? String ?? "unknown_function"
                    let args = funcCall["args"] as? [String: Any] ?? [:]
                    let id = funcCall["id"] as? String ?? "call_\(UUID().uuidString.prefix(12))"
                    var toolUse: [String: Any] = [
                        "type": "tool_use",
                        "id": id,
                        "name": name,
                        "input": args,
                    ]
                    // Preserve thoughtSignature so it round-trips through Anthropic format.
                    // Gemini 3 models require this on functionCall parts in subsequent turns.
                    if let sig = part["thoughtSignature"] as? String {
                        toolUse["_thought_signature"] = sig
                    }
                    anthropicContent.append(toolUse)
                }
            }
        }

        let usageMetadata = gemini["usageMetadata"] as? [String: Any]
        let inputTokens = usageMetadata?["promptTokenCount"] as? Int ?? 0
        let outputTokens = usageMetadata?["candidatesTokenCount"] as? Int ?? 0

        let finishReason = firstCandidate["finishReason"] as? String ?? ""
        let stopReason: String
        switch finishReason {
        case "STOP": stopReason = "end_turn"
        case "MAX_TOKENS": stopReason = "max_tokens"
        default: stopReason = "end_turn"  // Fallback
        }

        let mappedResponse: [String: Any] = [
            "id": "msg_\(UUID().uuidString.prefix(16))",
            "type": "message",
            "role": "assistant",
            "model": requestedModel,
            "stop_sequence": NSNull(),
            "stop_reason": stopReason,
            "content": anthropicContent,
            "usage": [
                "input_tokens": inputTokens,
                "output_tokens": outputTokens,
            ],
        ]

        return try JSONSerialization.data(withJSONObject: mappedResponse)
    }

    // MARK: - Private Helpers

    private func extractSystemText(from system: Any) -> String {
        if let str = system as? String {
            return str
        }
        if let arr = system as? [[String: Any]] {
            return arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }

    private func buildContents(from anthropicBody: [String: Any]) -> [[String: Any]] {
        guard let messages = anthropicBody["messages"] as? [[String: Any]] else { return [] }
        var contents: [[String: Any]] = []

        // Tools buffer for when user answers tool calls
        var pendingFunctionResponses: [[String: Any]] = []

        for msg in messages {
            let role = msg["role"] as? String ?? "user"

            if role == "user" {
                // User role extraction
                var userParts: [[String: Any]] = []

                if let txt = msg["content"] as? String {
                    userParts.append(["text": txt])
                } else if let arr = msg["content"] as? [[String: Any]] {
                    for part in arr {
                        let type = part["type"] as? String
                        if type == "text", let t = part["text"] as? String {
                            userParts.append(["text": t])
                        } else if type == "tool_result" {
                            // Extract tool result
                            let toolId = part["tool_use_id"] as? String ?? ""
                            // Can be string or array
                            let contentVal = part["content"]
                            let resultStr: String
                            if let s = contentVal as? String {
                                resultStr = s
                            } else if let a = contentVal as? [[String: Any]] {
                                resultStr = a.compactMap { $0["text"] as? String }.joined(
                                    separator: "\n")
                            } else {
                                resultStr = "Success"
                            }

                            pendingFunctionResponses.append([
                                "functionResponse": [
                                    "name": toolId,
                                    "response": ["result": resultStr],
                                ]
                            ])
                        }
                    }
                }

                if !userParts.isEmpty {
                    contents.append(["role": "user", "parts": userParts])
                }

                if !pendingFunctionResponses.isEmpty {
                    contents.append(["role": "user", "parts": pendingFunctionResponses])
                    pendingFunctionResponses = []
                }

            } else if role == "assistant" {
                var modelParts: [[String: Any]] = []

                if let txt = msg["content"] as? String {
                    modelParts.append(["text": txt])
                } else if let arr = msg["content"] as? [[String: Any]] {
                    for part in arr {
                        let type = part["type"] as? String
                        if type == "text", let t = part["text"] as? String {
                            modelParts.append(["text": t])
                        } else if type == "tool_use" {
                            let name = part["name"] as? String ?? ""
                            let input = part["input"] as? [String: Any] ?? [:]
                            let id = part["id"] as? String
                            var functionCall: [String: Any] = [
                                "name": name,
                                "args": input,
                            ]
                            if let id = id {
                                functionCall["id"] = id
                            }
                            // Build the Gemini part with optional thoughtSignature
                            var geminiPart: [String: Any] = [
                                "functionCall": functionCall
                            ]
                            // Restore thoughtSignature that was preserved during response translation.
                            // This is required by Gemini 3 models for function calls in the current turn.
                            if let sig = part["_thought_signature"] as? String {
                                geminiPart["thoughtSignature"] = sig
                            }
                            modelParts.append(geminiPart)
                        }
                    }
                }

                if !modelParts.isEmpty {
                    contents.append(["role": "model", "parts": modelParts])
                }
            }
        }

        return contents
    }

    private func buildTools(from anthropicBody: [String: Any]) -> [[String: Any]] {
        guard let list = anthropicBody["tools"] as? [[String: Any]] else { return [] }
        return list.map { tool in
            var obj: [String: Any] = [
                "name": tool["name"] as? String ?? "",
                "description": tool["description"] as? String ?? "",
            ]
            if let schema = tool["input_schema"] as? [String: Any] {
                // Check if schema contains "$schema" key — if so, use parametersJsonSchema
                // (raw JSON Schema) instead of parameters (simplified Gemini schema).
                // This matches the reference claude-code-router implementation.
                if schema.keys.contains("$schema") {
                    obj["parametersJsonSchema"] = schema
                } else {
                    // Process schema: remove unsupported fields like "additionalProperties"
                    var processedSchema = schema
                    processedSchema.removeValue(forKey: "additionalProperties")
                    obj["parameters"] = processedSchema
                }
            }
            return obj
        }
    }
}
