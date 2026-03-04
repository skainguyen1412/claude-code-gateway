import Foundation
import Testing

@testable import CCGateWay

@Suite("OpenAI Adapter Token Clamping & Reasoning Models")
struct OpenAIAdapterClampTests {

    static let provider = ProviderConfig(
        name: "OpenAI",
        type: "openai",
        baseUrl: "https://api.openai.com/v1",
        slots: ["default": "gpt-5", "think": "o3"]
    )

    @Test("Clamps max_tokens for standard models")
    func clampsForStandardModel() throws {
        let adapter = OpenAIAdapter()
        // deepseek-chat maxOutputTokens = 8192
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 200_000,
            "messages": [["role": "user", "content": "Hello"]],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "deepseek-chat",
            provider: Self.provider,
            apiKey: "sk-test",
            forceNonStreaming: true
        )

        #expect(body["max_tokens"] as? Int == 8192)
        #expect(body["max_completion_tokens"] == nil)  // standard model keeps max_tokens
    }

    @Test("Renames max_tokens to max_completion_tokens for o3")
    func renamesForO3() throws {
        let adapter = OpenAIAdapter()
        let anthropicBody: [String: Any] = [
            "model": "claude-opus-4-20250514",
            "max_tokens": 8192,
            "messages": [["role": "user", "content": "Think hard"]],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "o3",
            provider: Self.provider,
            apiKey: "sk-test",
            forceNonStreaming: true
        )

        // For reasoning models: max_tokens should be renamed to max_completion_tokens
        #expect(body["max_completion_tokens"] as? Int == 8192)
        #expect(body["max_tokens"] == nil)
    }

    @Test("Renames max_tokens to max_completion_tokens for o4-mini")
    func renamesForO4Mini() throws {
        let adapter = OpenAIAdapter()
        let anthropicBody: [String: Any] = [
            "model": "claude-opus-4-20250514",
            "max_tokens": 50_000,
            "messages": [["role": "user", "content": "Think hard"]],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "o4-mini",
            provider: Self.provider,
            apiKey: "sk-test",
            forceNonStreaming: true
        )

        #expect(body["max_completion_tokens"] as? Int == 50_000)
        #expect(body["max_tokens"] == nil)
    }

    @Test("Clamps AND renames for reasoning model when over limit")
    func clampsAndRenamesForO3() throws {
        let adapter = OpenAIAdapter()
        // o3 maxOutputTokens = 100_000
        let anthropicBody: [String: Any] = [
            "model": "claude-opus-4-20250514",
            "max_tokens": 200_000,
            "messages": [["role": "user", "content": "Think very hard"]],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "o3",
            provider: Self.provider,
            apiKey: "sk-test",
            forceNonStreaming: true
        )

        #expect(body["max_completion_tokens"] as? Int == 100_000)  // clamped + renamed
        #expect(body["max_tokens"] == nil)
    }

    @Test("Passes through max_tokens when within model limit for standard model")
    func passesValidMaxTokens() throws {
        let adapter = OpenAIAdapter()
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "messages": [["role": "user", "content": "Hello"]],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "deepseek-chat",
            provider: Self.provider,
            apiKey: "sk-test",
            forceNonStreaming: true
        )

        #expect(body["max_tokens"] as? Int == 4096)  // within limit, no clamping
    }

    @Test("Falls back to original value when model not in catalog")
    func fallsBackForUnknownModel() throws {
        let adapter = OpenAIAdapter()
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 200_000,
            "messages": [["role": "user", "content": "Hello"]],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "unknown-model",
            provider: Self.provider,
            apiKey: "sk-test",
            forceNonStreaming: true
        )

        #expect(body["max_tokens"] as? Int == 200_000)  // no clamping for unknown
    }
}
