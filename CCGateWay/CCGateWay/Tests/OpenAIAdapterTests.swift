import Foundation
import Testing

@testable import CCGateWay

@Suite("OpenAI Adapter Tests")
struct OpenAIAdapterTests {

    static let provider = ProviderConfig(
        name: "OpenAI",
        type: "openai",
        baseUrl: "https://api.openai.com/v1",
        slots: ["default": "gpt-4o"]
    )

    // MARK: - Request Transform

    @Test("Transform basic Anthropic request to OpenAI format")
    func transformBasicRequest() throws {
        let adapter = OpenAIAdapter()
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 100,
            "messages": [
                ["role": "user", "content": "Hello"]
            ],
        ]

        let (url, headers, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "gpt-4o",
            provider: Self.provider,
            apiKey: "sk-test-key",
            forceNonStreaming: true
        )

        // URL should be baseUrl + /v1/chat/completions
        #expect(url.string == "https://api.openai.com/v1/chat/completions")

        // Headers should include Bearer auth
        #expect(headers.first(name: "Authorization") == "Bearer sk-test-key")
        #expect(headers.first(name: "Content-Type") == "application/json")

        // Body should have OpenAI format
        #expect(body["model"] as? String == "gpt-4o")
        #expect(body["max_tokens"] as? Int == 100)
        #expect(body["stream"] as? Bool == false)

        // Messages should be converted
        let messages = body["messages"] as? [[String: Any]]
        #expect(messages?.count == 1)
        #expect(messages?[0]["role"] as? String == "user")
        #expect(messages?[0]["content"] as? String == "Hello")
    }

    @Test("Transform request with system prompt")
    func transformWithSystemPrompt() throws {
        let adapter = OpenAIAdapter()
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 100,
            "system": "You are a helpful assistant.",
            "messages": [
                ["role": "user", "content": "Hi"]
            ],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "gpt-4o",
            provider: Self.provider,
            apiKey: "sk-test-key",
            forceNonStreaming: true
        )

        let messages = body["messages"] as? [[String: Any]]
        #expect(messages?.count == 2)
        #expect(messages?[0]["role"] as? String == "system")
        #expect(messages?[0]["content"] as? String == "You are a helpful assistant.")
        #expect(messages?[1]["role"] as? String == "user")
    }

    @Test("Transform request with system prompt as array")
    func transformWithSystemPromptArray() throws {
        let adapter = OpenAIAdapter()
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 100,
            "system": [
                ["type": "text", "text": "First instruction."],
                ["type": "text", "text": "Second instruction."],
            ] as [[String: Any]],
            "messages": [
                ["role": "user", "content": "Hi"]
            ],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "gpt-4o",
            provider: Self.provider,
            apiKey: "sk-test-key",
            forceNonStreaming: true
        )

        let messages = body["messages"] as? [[String: Any]]
        #expect(messages?[0]["role"] as? String == "system")
        #expect(messages?[0]["content"] as? String == "First instruction.\nSecond instruction.")
    }

    @Test("Transform request with tools")
    func transformWithTools() throws {
        let adapter = OpenAIAdapter()
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 100,
            "messages": [
                ["role": "user", "content": "Get weather"]
            ],
            "tools": [
                [
                    "name": "get_weather",
                    "description": "Get the weather",
                    "input_schema": [
                        "type": "object",
                        "properties": [
                            "location": ["type": "string"]
                        ],
                    ] as [String: Any],
                ] as [String: Any]
            ],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "gpt-4o",
            provider: Self.provider,
            apiKey: "sk-test-key",
            forceNonStreaming: true
        )

        let tools = body["tools"] as? [[String: Any]]
        #expect(tools?.count == 1)
        let firstTool = tools?[0]
        #expect(firstTool?["type"] as? String == "function")
        let function = firstTool?["function"] as? [String: Any]
        #expect(function?["name"] as? String == "get_weather")
        #expect(function?["description"] as? String == "Get the weather")
    }

    @Test("Transform request with tool_result in user message")
    func transformWithToolResult() throws {
        let adapter = OpenAIAdapter()
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 100,
            "messages": [
                ["role": "user", "content": "Get weather"],
                [
                    "role": "assistant",
                    "content": [
                        [
                            "type": "tool_use",
                            "id": "call_123",
                            "name": "get_weather",
                            "input": ["location": "SF"],
                        ] as [String: Any]
                    ],
                ] as [String: Any],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "tool_result",
                            "tool_use_id": "call_123",
                            "content": "72°F and sunny",
                        ] as [String: Any]
                    ],
                ] as [String: Any],
            ],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "gpt-4o",
            provider: Self.provider,
            apiKey: "sk-test-key",
            forceNonStreaming: true
        )

        let messages = body["messages"] as? [[String: Any]]
        #expect(messages != nil)

        // Find the assistant message with tool_calls
        let assistantMsg = messages?.first(where: { ($0["role"] as? String) == "assistant" })
        let toolCalls = assistantMsg?["tool_calls"] as? [[String: Any]]
        #expect(toolCalls?.count == 1)
        #expect(toolCalls?[0]["id"] as? String == "call_123")
        let function = toolCalls?[0]["function"] as? [String: Any]
        #expect(function?["name"] as? String == "get_weather")

        // Find the tool response message
        let toolMsg = messages?.first(where: { ($0["role"] as? String) == "tool" })
        #expect(toolMsg?["tool_call_id"] as? String == "call_123")
        #expect(toolMsg?["content"] as? String == "72°F and sunny")
    }

    @Test("Transform streaming request sets stream: true")
    func transformStreamingRequest() throws {
        let adapter = OpenAIAdapter()
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 100,
            "stream": true,
            "messages": [
                ["role": "user", "content": "Hello"]
            ],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "gpt-4o",
            provider: Self.provider,
            apiKey: "sk-test-key",
            forceNonStreaming: false
        )

        #expect(body["stream"] as? Bool == true)
        // Should include stream_options for usage in stream
        let streamOptions = body["stream_options"] as? [String: Any]
        #expect(streamOptions?["include_usage"] as? Bool == true)
    }

    // MARK: - Response Transform

    @Test("Transform basic OpenAI response to Anthropic format")
    func transformBasicResponse() throws {
        let adapter = OpenAIAdapter()
        let openAIResponse: [String: Any] = [
            "id": "chatcmpl-123",
            "object": "chat.completion",
            "model": "gpt-4o",
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": "Hello!",
                    ],
                    "finish_reason": "stop",
                ] as [String: Any]
            ],
            "usage": [
                "prompt_tokens": 10,
                "completion_tokens": 5,
            ],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: openAIResponse)

        let result = try adapter.transformResponse(
            responseData: responseData,
            isStreaming: false,
            requestedModel: "claude-sonnet-4-20250514"
        )

        let json = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        #expect(json["type"] as? String == "message")
        #expect(json["role"] as? String == "assistant")
        #expect(json["model"] as? String == "gpt-4o")
        #expect(json["stop_reason"] as? String == "end_turn")

        let content = json["content"] as? [[String: Any]]
        #expect(content?.count == 1)
        #expect(content?[0]["type"] as? String == "text")
        #expect(content?[0]["text"] as? String == "Hello!")

        let usage = json["usage"] as? [String: Int]
        #expect(usage?["input_tokens"] == 10)
        #expect(usage?["output_tokens"] == 5)
    }

    @Test("Transform OpenAI response with tool_calls to Anthropic format")
    func transformToolCallResponse() throws {
        let adapter = OpenAIAdapter()
        let openAIResponse: [String: Any] = [
            "id": "chatcmpl-123",
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": NSNull(),
                        "tool_calls": [
                            [
                                "id": "call_abc",
                                "type": "function",
                                "function": [
                                    "name": "get_weather",
                                    "arguments": "{\"location\":\"SF\"}",
                                ] as [String: Any],
                            ] as [String: Any]
                        ],
                    ] as [String: Any],
                    "finish_reason": "tool_calls",
                ] as [String: Any]
            ],
            "usage": ["prompt_tokens": 10, "completion_tokens": 5],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: openAIResponse)

        let result = try adapter.transformResponse(
            responseData: responseData,
            isStreaming: false,
            requestedModel: "claude-sonnet-4-20250514"
        )

        let json = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        #expect(json["stop_reason"] as? String == "tool_use")

        let content = json["content"] as? [[String: Any]]
        #expect(content?.count == 1)
        #expect(content?[0]["type"] as? String == "tool_use")
        #expect(content?[0]["name"] as? String == "get_weather")
        #expect(content?[0]["id"] as? String == "call_abc")
        let input = content?[0]["input"] as? [String: Any]
        #expect(input?["location"] as? String == "SF")
    }

    @Test("Transform OpenAI error response throws appropriate error")
    func transformErrorResponse() throws {
        let adapter = OpenAIAdapter()
        let openAIResponse: [String: Any] = [
            "error": [
                "message": "Rate limit exceeded",
                "type": "rate_limit_error",
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: openAIResponse)

        #expect(throws: Error.self) {
            _ = try adapter.transformResponse(
                responseData: responseData,
                isStreaming: false,
                requestedModel: "claude-sonnet-4-20250514"
            )
        }
    }

    // MARK: - OpenAI SSE Builder Tests

    @Test("OpenAISSEBuilder emits message_start on first chunk")
    func sseBuilderMessageStart() {
        var builder = OpenAISSEBuilder(requestedModel: "claude-sonnet-4-20250514")
        let chunk = """
            {"id":"chatcmpl-123","object":"chat.completion.chunk","model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}
            """
        let events = builder.processOpenAIChunk(chunk)
        let joined = events.joined()
        #expect(joined.contains("event: message_start"))
        #expect(joined.contains("\"role\":\"assistant\""))
    }

    @Test("OpenAISSEBuilder emits text_delta for content chunks")
    func sseBuilderTextDelta() {
        var builder = OpenAISSEBuilder(requestedModel: "claude-sonnet-4-20250514")
        // First chunk to trigger message_start
        _ = builder.processOpenAIChunk(
            """
            {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}
            """)
        // Content chunk
        let events = builder.processOpenAIChunk(
            """
            {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}
            """)
        let joined = events.joined()
        #expect(joined.contains("text_delta"))
        #expect(joined.contains("Hello"))
    }

    @Test("OpenAISSEBuilder emits tool_use for tool_calls")
    func sseBuilderToolUse() {
        var builder = OpenAISSEBuilder(requestedModel: "claude-sonnet-4-20250514")
        // First chunk
        _ = builder.processOpenAIChunk(
            """
            {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"role":"assistant","content":null},"finish_reason":null}]}
            """)
        // Tool call chunk
        let events = builder.processOpenAIChunk(
            """
            {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"get_weather","arguments":"{\\"location\\":\\"SF\\"}"}}]},"finish_reason":null}]}
            """)
        let joined = events.joined()
        #expect(joined.contains("tool_use"))
        #expect(joined.contains("get_weather"))
    }

    @Test("OpenAISSEBuilder emits message_stop on finish_reason stop")
    func sseBuilderFinish() {
        var builder = OpenAISSEBuilder(requestedModel: "claude-sonnet-4-20250514")
        _ = builder.processOpenAIChunk(
            """
            {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"role":"assistant","content":"Hi"},"finish_reason":null}]}
            """)
        let events = builder.processOpenAIChunk(
            """
            {"id":"chatcmpl-123","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
            """)
        let joined = events.joined()
        #expect(joined.contains("message_stop"))
        #expect(joined.contains("end_turn"))
    }

    @Test("OpenAISSEBuilder tracks token usage from stream usage chunk")
    func sseBuilderUsage() {
        var builder = OpenAISSEBuilder(requestedModel: "claude-sonnet-4-20250514")
        _ = builder.processOpenAIChunk(
            """
            {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}
            """)
        _ = builder.processOpenAIChunk(
            """
            {"id":"chatcmpl-123","choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5}}
            """)
        let (input, output) = builder.tokenUsage
        #expect(input == 10)
        #expect(output == 5)
    }

    @Test("OpenAISSEBuilder finalize emits closing events when no finish_reason received")
    func sseBuilderFinalize() {
        var builder = OpenAISSEBuilder(requestedModel: "claude-sonnet-4-20250514")
        _ = builder.processOpenAIChunk(
            """
            {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}
            """)
        let events = builder.finalize()
        let joined = events.joined()
        #expect(joined.contains("message_stop"))
    }
}
