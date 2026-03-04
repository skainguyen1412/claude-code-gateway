import Foundation
import Testing

@testable import CCGateWay

@Suite("OpenRouter Adapter")
struct OpenRouterAdapterTests {

    static let provider = ProviderConfig(
        name: "OpenRouter",
        type: "openai",
        baseUrl: "https://openrouter.ai/api/v1",
        slots: ["default": "google/gemini-3.1-pro-preview"]
    )

    @Test("Strips cache_control for non-Claude models")
    func stripsCacheControlForNonClaude() throws {
        let adapter = OpenRouterAdapter()
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

        // Non-Claude target: should succeed (cache_control stripped)
        let (_, _, _) = try adapter.transformRequest(
            anthropicBody: body, targetModel: "google/gemini-3.1-pro-preview",
            provider: Self.provider, apiKey: "sk-test", forceNonStreaming: true
        )
    }

    @Test("Keeps cache_control for Claude models via OpenRouter")
    func keepsCacheControlForClaude() throws {
        let adapter = OpenRouterAdapter()
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "messages": [["role": "user", "content": "Hello"]],
        ]

        // Claude target: should not strip cache_control
        let (_, _, _) = try adapter.transformRequest(
            anthropicBody: body, targetModel: "anthropic/claude-sonnet-4",
            provider: Self.provider, apiKey: "sk-test", forceNonStreaming: true
        )
    }

    @Test("Returns OpenRouterChunkProcessor")
    func returnsCorrectChunkProcessor() {
        let adapter = OpenRouterAdapter()
        let processor = adapter.makeChunkProcessor()
        #expect(processor is OpenRouterChunkProcessor)
    }
}
