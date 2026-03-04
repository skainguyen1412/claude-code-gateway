import Foundation
import Vapor

/// Adapter for Groq API. Wraps OpenAIAdapter with Groq-specific preprocessing.
struct GroqAdapter: ProviderAdapter {
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
        RequestCleaner.stripCacheControl(from: &cleanedBody)
        RequestCleaner.stripSchemaFromTools(from: &cleanedBody)

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
        return GroqChunkProcessor()
    }
}
