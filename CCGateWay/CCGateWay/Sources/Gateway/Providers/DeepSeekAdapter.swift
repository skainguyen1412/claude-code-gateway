import Foundation
import Vapor

/// Adapter for DeepSeek API. Wraps OpenAIAdapter with DeepSeek-specific preprocessing.
struct DeepSeekAdapter: ProviderAdapter {
    let providerType = "openai"
    private let base = OpenAIAdapter()

    func transformRequest(
        anthropicBody: [String: Any],
        targetModel: String,
        provider: ProviderConfig,
        apiKey: String,
        forceNonStreaming: Bool = false
    ) throws -> (url: URI, headers: HTTPHeaders, body: [String: Any]) {
        // 1. Clean unsupported fields
        var cleanedBody = anthropicBody
        RequestCleaner.stripCacheControl(from: &cleanedBody)

        // 2. Hard-cap max_tokens at 8192 (DeepSeek's limit)
        if let maxTokens = cleanedBody["max_tokens"] as? Int, maxTokens > 8192 {
            cleanedBody["max_tokens"] = 8192
            print("[DeepSeekAdapter] ⚠️ Clamped max_tokens \(maxTokens) → 8192")
        }

        // 3. Delegate to base OpenAI adapter
        return try base.transformRequest(
            anthropicBody: cleanedBody,
            targetModel: targetModel,
            provider: provider,
            apiKey: apiKey,
            forceNonStreaming: forceNonStreaming
        )
    }

    func transformResponse(
        responseData: Data, isStreaming: Bool, requestedModel: String
    ) throws -> Data {
        return try base.transformResponse(
            responseData: responseData, isStreaming: isStreaming, requestedModel: requestedModel
        )
    }

    func makeChunkProcessor() -> ChunkProcessor {
        return DeepSeekChunkProcessor()
    }
}
