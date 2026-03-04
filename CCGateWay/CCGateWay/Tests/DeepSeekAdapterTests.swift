import Foundation
import Testing

@testable import CCGateWay

@Suite("DeepSeek Adapter")
struct DeepSeekAdapterTests {

    static let provider = ProviderConfig(
        name: "DeepSeek",
        type: "openai",
        baseUrl: "https://api.deepseek.com",
        slots: ["default": "deepseek-chat", "think": "deepseek-reasoner"]
    )

    @Test("Caps max_tokens at 8192")
    func capsMaxTokens() throws {
        let adapter = DeepSeekAdapter()
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 16384,
            "messages": [["role": "user", "content": "Hi"]],
        ]

        let (_, _, result) = try adapter.transformRequest(
            anthropicBody: body, targetModel: "deepseek-chat",
            provider: Self.provider, apiKey: "sk-test", forceNonStreaming: true
        )

        #expect(result["max_tokens"] as? Int == 8192)
    }

    @Test("Passes through max_tokens when within limit")
    func passesValidMaxTokens() throws {
        let adapter = DeepSeekAdapter()
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "messages": [["role": "user", "content": "Hi"]],
        ]

        let (_, _, result) = try adapter.transformRequest(
            anthropicBody: body, targetModel: "deepseek-chat",
            provider: Self.provider, apiKey: "sk-test", forceNonStreaming: true
        )

        #expect(result["max_tokens"] as? Int == 4096)
    }

    @Test("Returns DeepSeekChunkProcessor")
    func returnsCorrectChunkProcessor() {
        let adapter = DeepSeekAdapter()
        let processor = adapter.makeChunkProcessor()
        #expect(processor is DeepSeekChunkProcessor)
    }
}
