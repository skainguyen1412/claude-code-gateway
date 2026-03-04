import Foundation
import Testing

@testable import CCGateWay

@Suite("Gemini Adapter Token Clamping")
struct GeminiAdapterClampTests {

    static let provider = ProviderConfig(
        name: "Gemini",
        type: "gemini",
        baseUrl: "https://generativelanguage.googleapis.com/v1beta/models/",
        slots: ["default": "gemini-2.5-flash"]
    )

    @Test("Clamps max_tokens to model maxOutputTokens when exceeded")
    func clampsExcessiveMaxTokens() throws {
        let adapter = GeminiAdapter()
        // gemini-2.5-flash maxOutputTokens = 65535
        // Request 100,000 — should be clamped to 65535
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 100_000,
            "messages": [["role": "user", "content": "Hello"]],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "gemini-2.5-flash",
            provider: Self.provider,
            apiKey: "test-key",
            forceNonStreaming: true
        )

        let genConfig = body["generationConfig"] as? [String: Any]
        let maxOutput = genConfig?["maxOutputTokens"] as? Int
        #expect(maxOutput == 65535)
    }

    @Test("Passes through max_tokens when within model limit")
    func passesValidMaxTokens() throws {
        let adapter = GeminiAdapter()
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "messages": [["role": "user", "content": "Hello"]],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "gemini-2.5-flash",
            provider: Self.provider,
            apiKey: "test-key",
            forceNonStreaming: true
        )

        let genConfig = body["generationConfig"] as? [String: Any]
        let maxOutput = genConfig?["maxOutputTokens"] as? Int
        #expect(maxOutput == 4096)
    }

    @Test("Falls back to original value when model not in catalog")
    func fallsBackForUnknownModel() throws {
        let adapter = GeminiAdapter()
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 100_000,
            "messages": [["role": "user", "content": "Hello"]],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "gemini-unknown-model",
            provider: Self.provider,
            apiKey: "test-key",
            forceNonStreaming: true
        )

        let genConfig = body["generationConfig"] as? [String: Any]
        let maxOutput = genConfig?["maxOutputTokens"] as? Int
        #expect(maxOutput == 100_000)  // no clamping for unknown models
    }
}
