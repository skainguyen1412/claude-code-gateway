import Foundation
import Vapor

protocol ProviderAdapter {
    var providerType: String { get }

    func transformRequest(
        anthropicBody: [String: Any],
        targetModel: String,
        provider: ProviderConfig,
        apiKey: String,
        forceNonStreaming: Bool
    ) throws -> (url: URI, headers: HTTPHeaders, body: [String: Any])

    func transformResponse(
        responseData: Data,
        isStreaming: Bool,
        requestedModel: String
    ) throws -> Data

    /// Returns a chunk processor for provider-specific streaming behavior.
    func makeChunkProcessor() -> ChunkProcessor
}

extension ProviderAdapter {
    func makeChunkProcessor() -> ChunkProcessor {
        return DefaultChunkProcessor()
    }
}
