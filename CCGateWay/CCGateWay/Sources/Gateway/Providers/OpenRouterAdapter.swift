import Foundation
import Vapor

/// Adapter for OpenRouter API. Wraps OpenAIAdapter with OpenRouter-specific preprocessing.
struct OpenRouterAdapter: ProviderAdapter {
    let providerType = "openai"
    private let base = OpenAIAdapter()

    func transformRequest(
        anthropicBody: [String: Any],
        targetModel: String,
        provider: ProviderConfig,
        apiKey: String,
        forceNonStreaming: Bool = false
    ) throws -> (url: URI, headers: HTTPHeaders, body: [String: Any]) {
        var cleanedBody = anthropicBody

        // Only strip cache_control for non-Claude models
        // OpenRouter can route to Claude, which supports cache_control natively
        let isClaudeModel = targetModel.lowercased().contains("claude")
        if !isClaudeModel {
            RequestCleaner.stripCacheControl(from: &cleanedBody)
        }

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
        return OpenRouterChunkProcessor()
    }
}
