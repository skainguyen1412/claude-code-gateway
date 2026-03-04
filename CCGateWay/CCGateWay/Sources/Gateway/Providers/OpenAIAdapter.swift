import Foundation
import Vapor

struct OpenAIAdapter: ProviderAdapter {
  let providerType = "openai"

  func transformRequest(
    anthropicBody: [String: Any],
    targetModel: String,
    provider: ProviderConfig,
    apiKey: String,
    forceNonStreaming: Bool = false
  ) throws -> (url: URI, headers: HTTPHeaders, body: [String: Any]) {

    let isStreaming = !forceNonStreaming && ((anthropicBody["stream"] as? Bool) ?? false)

    // URL: ensure we end up at .../v1/chat/completions
    let baseUrl =
      provider.baseUrl.hasSuffix("/")
      ? String(provider.baseUrl.dropLast()) : provider.baseUrl
    let url: URI
    if baseUrl.hasSuffix("/v1") {
      url = URI(string: "\(baseUrl)/chat/completions")
    } else {
      url = URI(string: "\(baseUrl)/v1/chat/completions")
    }

    // Headers: Bearer token auth
    var headers = HTTPHeaders()
    headers.add(name: "Authorization", value: "Bearer \(apiKey)")
    headers.add(name: "Content-Type", value: "application/json")

    // Build OpenAI body
    var body: [String: Any] = [
      "model": targetModel,
      "stream": isStreaming,
    ]

    if let maxTokens = anthropicBody["max_tokens"] as? Int {
      // 1. Clamp to model's maxOutputTokens if known
      var clampedTokens = maxTokens
      if let modelInfo = ModelCatalog.find(modelId: targetModel),
        maxTokens > modelInfo.maxOutputTokens
      {
        clampedTokens = modelInfo.maxOutputTokens
        print(
          "[OpenAIAdapter] ⚠️ Clamped max_tokens \(maxTokens) → \(clampedTokens) for \(targetModel)"
        )
      }

      // 2. Newer models (o1, o3, o4-mini, gpt-5 series, etc.) use max_completion_tokens instead
      let useCompletionTokens = ["o1", "o3", "o4", "gpt"].contains {
        targetModel.hasPrefix($0) || targetModel.contains("/\($0)")
          || targetModel.contains("-\($0)")
      }

      if useCompletionTokens {
        body["max_completion_tokens"] = clampedTokens
      } else {
        body["max_tokens"] = clampedTokens
      }
    }
    if let temperature = anthropicBody["temperature"] as? Double {
      body["temperature"] = temperature
    }

    // Include stream_options for usage tracking during streaming
    if isStreaming {
      body["stream_options"] = ["include_usage": true]
    }

    // Build messages array
    var openAIMessages: [[String: Any]] = []

    // 1. System prompt
    if let system = anthropicBody["system"] {
      let systemText = extractSystemText(from: system)
      if !systemText.isEmpty {
        openAIMessages.append(["role": "system", "content": systemText])
      }
    }

    // 2. Convert messages
    if let messages = anthropicBody["messages"] as? [[String: Any]] {
      for msg in messages {
        let role = msg["role"] as? String ?? "user"
        openAIMessages.append(contentsOf: convertMessage(role: role, msg: msg))
      }
    }

    body["messages"] = openAIMessages

    // 3. Convert tools
    if let tools = anthropicBody["tools"] as? [[String: Any]], !tools.isEmpty {
      body["tools"] = tools.map { tool -> [String: Any] in
        [
          "type": "function",
          "function": [
            "name": tool["name"] as? String ?? "",
            "description": tool["description"] as? String ?? "",
            "parameters": tool["input_schema"] as? [String: Any] ?? [:],
          ] as [String: Any],
        ]
      }
    }

    return (url, headers, body)
  }

  func transformResponse(responseData: Data, isStreaming: Bool, requestedModel: String) throws
    -> Data
  {
    guard let openAI = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
    else {
      let rawStr = String(data: responseData, encoding: .utf8) ?? "(binary data)"
      print("[OpenAIAdapter] ❌ Failed to parse response JSON. Raw: \(rawStr.prefix(500))")
      throw Abort(.badGateway, reason: "Invalid OpenAI response JSON")
    }

    // Check for OpenAI API errors
    if let error = openAI["error"] as? [String: Any] {
      let message = error["message"] as? String ?? "Unknown OpenAI error"
      let type = error["type"] as? String ?? ""
      print("[OpenAIAdapter] ❌ OpenAI API error (\(type)): \(message)")
      throw Abort(.badGateway, reason: "OpenAI API error: \(message)")
    }

    let choices = openAI["choices"] as? [[String: Any]] ?? []
    guard let firstChoice = choices.first else {
      let debugStr = String(data: responseData, encoding: .utf8) ?? "(binary)"
      print(
        "[OpenAIAdapter] ❌ Missing choices. Full response: \(debugStr.prefix(1000))")
      throw Abort(.badGateway, reason: "Missing choices in OpenAI response")
    }

    let message = firstChoice["message"] as? [String: Any] ?? [:]
    var anthropicContent: [[String: Any]] = []

    // Text content
    if let text = message["content"] as? String, !text.isEmpty {
      anthropicContent.append([
        "type": "text",
        "text": text,
      ])
    }

    // Tool calls
    if let toolCalls = message["tool_calls"] as? [[String: Any]] {
      for tc in toolCalls {
        let function = tc["function"] as? [String: Any] ?? [:]
        let name = function["name"] as? String ?? "unknown"
        let argsStr = function["arguments"] as? String ?? "{}"
        let args =
          (try? JSONSerialization.jsonObject(with: Data(argsStr.utf8)))
          as? [String: Any] ?? [:]
        let id = tc["id"] as? String ?? "call_\(UUID().uuidString.prefix(12))"
        anthropicContent.append([
          "type": "tool_use",
          "id": id,
          "name": name,
          "input": args,
        ])
      }
    }

    // Usage
    let usage = openAI["usage"] as? [String: Any]
    let inputTokens = usage?["prompt_tokens"] as? Int ?? 0
    let outputTokens = usage?["completion_tokens"] as? Int ?? 0

    // Stop reason
    let finishReason = firstChoice["finish_reason"] as? String ?? ""
    let stopReason: String
    switch finishReason {
    case "stop": stopReason = "end_turn"
    case "length": stopReason = "max_tokens"
    case "tool_calls": stopReason = "tool_use"
    default: stopReason = "end_turn"
    }

    // Use model from upstream response (like claude-code-router reference), fallback to requestedModel
    let upstreamModel = openAI["model"] as? String ?? requestedModel

    let mappedResponse: [String: Any] = [
      "id": "msg_\(UUID().uuidString.prefix(16))",
      "type": "message",
      "role": "assistant",
      "model": upstreamModel,
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

  private func convertMessage(role: String, msg: [String: Any]) -> [[String: Any]] {
    var results: [[String: Any]] = []

    if role == "user" {
      if let text = msg["content"] as? String {
        results.append(["role": "user", "content": text])
      } else if let contentArr = msg["content"] as? [[String: Any]] {
        // Separate tool_results from text parts
        var textParts: [String] = []
        var toolResults: [[String: Any]] = []

        for part in contentArr {
          let type = part["type"] as? String
          if type == "text", let t = part["text"] as? String {
            textParts.append(t)
          } else if type == "tool_result" {
            let toolCallId = part["tool_use_id"] as? String ?? ""
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
            toolResults.append([
              "role": "tool",
              "tool_call_id": toolCallId,
              "content": resultStr,
            ])
          }
        }

        // Add tool results first (they must come right after the assistant's tool_calls)
        results.append(contentsOf: toolResults)

        // Then add user text if any
        if !textParts.isEmpty {
          results.append([
            "role": "user", "content": textParts.joined(separator: "\n"),
          ])
        }
      }
    } else if role == "assistant" {
      var assistantMsg: [String: Any] = ["role": "assistant"]

      if let text = msg["content"] as? String {
        assistantMsg["content"] = text
      } else if let contentArr = msg["content"] as? [[String: Any]] {
        // Extract text and tool_use parts
        let textParts = contentArr.compactMap { part -> String? in
          guard (part["type"] as? String) == "text" else { return nil }
          return part["text"] as? String
        }
        if !textParts.isEmpty {
          assistantMsg["content"] = textParts.joined(separator: "\n")
        }

        let toolUseParts = contentArr.filter {
          (($0["type"] as? String) == "tool_use")
        }
        if !toolUseParts.isEmpty {
          assistantMsg["tool_calls"] = toolUseParts.map {
            part -> [String: Any] in
            let input = part["input"] as? [String: Any] ?? [:]
            let argsData =
              (try? JSONSerialization.data(withJSONObject: input)) ?? Data()
            let argsStr = String(data: argsData, encoding: .utf8) ?? "{}"
            return [
              "id": part["id"] as? String
                ?? "call_\(UUID().uuidString.prefix(12))",
              "type": "function",
              "function": [
                "name": part["name"] as? String ?? "",
                "arguments": argsStr,
              ] as [String: Any],
            ]
          }
          // OpenAI requires content to be null or string when tool_calls present
          if assistantMsg["content"] == nil {
            assistantMsg["content"] = NSNull()
          }
        }
      }

      results.append(assistantMsg)
    }

    return results
  }
}
