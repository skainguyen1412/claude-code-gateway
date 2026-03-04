import Foundation
import Testing

@testable import CCGateWay

@Suite("Groq Adapter")
struct GroqAdapterTests {

    static let provider = ProviderConfig(
        name: "Groq",
        type: "openai",
        baseUrl: "https://api.groq.com/openai/v1",
        slots: ["default": "llama-3.3-70b-versatile"]
    )

    @Test("Strips cache_control from messages")
    func stripsCacheControl() throws {
        let adapter = GroqAdapter()
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "Hello", "cache_control": ["type": "ephemeral"]]
                    ] as [[String: Any]],
                ] as [String: Any]
            ],
        ]

        // Should not throw — cache_control stripped before hitting Groq
        let (_, _, _) = try adapter.transformRequest(
            anthropicBody: body, targetModel: "llama-3.3-70b-versatile",
            provider: Self.provider, apiKey: "sk-test", forceNonStreaming: true
        )
    }

    @Test("Strips $schema from tool parameters")
    func stripsSchema() throws {
        let adapter = GroqAdapter()
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "messages": [["role": "user", "content": "Hi"]],
            "tools": [
                [
                    "name": "test_tool",
                    "description": "A test",
                    "input_schema": [
                        "$schema": "http://json-schema.org/draft-07/schema#",
                        "type": "object",
                        "properties": ["name": ["type": "string"]],
                    ] as [String: Any],
                ] as [String: Any]
            ],
        ]

        let (_, _, result) = try adapter.transformRequest(
            anthropicBody: body, targetModel: "llama-3.3-70b-versatile",
            provider: Self.provider, apiKey: "sk-test", forceNonStreaming: true
        )

        // Verify tools are present and $schema is stripped
        if let tools = result["tools"] as? [[String: Any]],
            let function = tools.first?["function"] as? [String: Any],
            let params = function["parameters"] as? [String: Any]
        {
            #expect(params["$schema"] == nil)
            #expect(params["type"] as? String == "object")
        }
    }

    @Test("Returns GroqChunkProcessor")
    func returnsCorrectChunkProcessor() {
        let adapter = GroqAdapter()
        let processor = adapter.makeChunkProcessor()
        #expect(processor is GroqChunkProcessor)
    }
}
