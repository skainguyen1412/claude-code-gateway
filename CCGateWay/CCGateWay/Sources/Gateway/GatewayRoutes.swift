import AsyncHTTPClient
import Foundation
import Vapor

struct ResolvedGatewayTarget {
    let provider: ProviderConfig
    let modelId: String
    let slot: String
    let apiKey: String
}

struct GatewayRoutes {
    let config: GatewayConfig
    let server: GatewayServer

    static func resolveTarget(
        requestedModel: String,
        config: GatewayConfig,
        keyLookup: (String) -> String?
    ) throws -> ResolvedGatewayTarget {
        let slot = SlotRouter.resolveSlot(requestedModel: requestedModel)

        if let activePreset = config.activePresetConfig {
            let target = try PresetRouter.resolveSlotTarget(slot: slot, preset: activePreset)
            guard let provider = config.providers[target.providerName] else {
                throw Abort(
                    .badRequest,
                    reason: "Active preset maps slot '\(slot)' to unknown provider '\(target.providerName)'."
                )
            }
            guard let apiKey = keyLookup("\(provider.name)_api_key") else {
                throw Abort(.unauthorized, reason: "Missing API key for provider '\(provider.name)'.")
            }
            return ResolvedGatewayTarget(
                provider: provider,
                modelId: target.modelId,
                slot: slot,
                apiKey: apiKey
            )
        }

        guard let provider = config.activeProviderConfig else {
            throw Abort(.badRequest, reason: "No active provider configured.")
        }

        let (_, providerModel) = SlotRouter.resolve(
            requestedModel: requestedModel,
            provider: provider
        )
        guard let apiKey = keyLookup("\(provider.name)_api_key") else {
            throw Abort(.unauthorized, reason: "Missing API key for active provider.")
        }

        return ResolvedGatewayTarget(
            provider: provider,
            modelId: providerModel,
            slot: slot,
            apiKey: apiKey
        )
    }

    static func resolveTargetForTests(
        requestedModel: String,
        config: GatewayConfig,
        keyLookup: (String) -> String?
    ) throws -> ResolvedGatewayTarget {
        try resolveTarget(requestedModel: requestedModel, config: config, keyLookup: keyLookup)
    }

    func boot(_ app: Application) throws {
        // Health check
        app.get("health") { req in
            ["status": "ok"]
        }

        // Messages endpoint
        app.post("v1", "messages") { req async throws -> Response in
            let startTime = Date()

            do {
                // 1. Parse Anthropic request body
                let bodyData = req.body.data.flatMap { Data(buffer: $0) } ?? Data()
                guard
                    let anthropicBody = try JSONSerialization.jsonObject(with: bodyData)
                        as? [String: Any],
                    let requestedModel = anthropicBody["model"] as? String
                else {
                    throw Abort(.badRequest, reason: "Invalid Anthropic request body")
                }

                let resolved = try Self.resolveTarget(
                    requestedModel: requestedModel,
                    config: config,
                    keyLookup: { KeychainManager.load(key: $0) }
                )
                let configProvider = resolved.provider
                let providerModel = resolved.modelId
                let slot = resolved.slot

                let isStreaming = (anthropicBody["stream"] as? Bool) ?? false

                let adapter = self.adapter(
                    for: configProvider.type, providerName: configProvider.name)
                let (url, headers, transformedBody) = try adapter.transformRequest(
                    anthropicBody: anthropicBody,
                    targetModel: providerModel,
                    provider: configProvider,
                    apiKey: resolved.apiKey,
                    forceNonStreaming: !isStreaming
                )

                if isStreaming {
                    return try await self.handleStreaming(
                        req: req,
                        adapter: adapter,
                        url: url,
                        headers: headers,
                        transformedBody: transformedBody,
                        requestedModel: providerModel,
                        slot: slot,
                        providerModel: providerModel,
                        providerName: configProvider.name,
                        startTime: startTime
                    )
                } else {
                    let clientRequestData = try JSONSerialization.data(
                        withJSONObject: transformedBody)

                    // Set up client request
                    let clientRequest = ClientRequest(
                        method: .POST,
                        url: url,
                        headers: headers,
                        body: ByteBuffer(data: clientRequestData)
                    )

                    print(
                        "[Gateway] ➡️ Sending to \(configProvider.name): \(url) (model: \(providerModel), slot: \(slot))"
                    )

                    do {
                        let clientResponse = try await req.client.send(clientRequest)
                        let responseData =
                            clientResponse.body.flatMap { Data(buffer: $0) } ?? Data()

                        // Log upstream response for debugging
                        let statusCode = clientResponse.status.code
                        let preview =
                            String(data: responseData.prefix(500), encoding: .utf8) ?? "(binary)"
                        print(
                            "[Gateway] ⬅️ \(configProvider.name) responded \(statusCode): \(preview)"
                        )

                        let transformedResponseData = try adapter.transformResponse(
                            responseData: responseData,
                            isStreaming: false,
                            requestedModel: providerModel
                        )

                        self.logSuccess(
                            slot: slot,
                            model: providerModel,
                            provider: configProvider.name,
                            authropicResp: transformedResponseData,
                            startTime: startTime
                        )

                        var responseHeaders = HTTPHeaders()
                        responseHeaders.add(name: "Content-Type", value: "application/json")

                        return Response(
                            status: .ok,
                            headers: responseHeaders,
                            body: .init(data: transformedResponseData)
                        )
                    } catch {
                        self.logFailure(
                            slot: slot,
                            model: providerModel,
                            provider: configProvider.name,
                            error: error,
                            startTime: startTime
                        )
                        throw error
                    }
                }
            } catch {
                self.logFailure(
                    slot: "unknown",
                    model: "unknown",
                    provider: config.activeProviderConfig?.name ?? "none",
                    error: error,
                    startTime: startTime
                )
                throw error
            }
        }
    }

    private func adapter(for type: String, providerName: String = "") -> ProviderAdapter {
        switch type {
        case "gemini":
            return GeminiAdapter()
        case "openai":
            switch providerName.lowercased() {
            case "deepseek":
                return DeepSeekAdapter()
            case "groq":
                return GroqAdapter()
            case "openrouter":
                return OpenRouterAdapter()
            default:
                return OpenAIAdapter()
            }
        default:
            return GeminiAdapter()  // Fallback to gemini
        }
    }

    private func handleStreaming(
        req: Request,
        adapter: ProviderAdapter,
        url: URI,
        headers: HTTPHeaders,
        transformedBody: [String: Any],
        requestedModel: String,
        slot: String,
        providerModel: String,
        providerName: String,
        startTime: Date
    ) async throws -> Response {
        let clientRequestData = try JSONSerialization.data(withJSONObject: transformedBody)

        var httpRequest = HTTPClientRequest(url: url.string)
        httpRequest.method = .POST
        for (name, value) in headers {
            httpRequest.headers.add(name: name, value: value)
        }
        httpRequest.body = .bytes(ByteBuffer(data: clientRequestData))

        print(
            "[Gateway] ➡️ Streaming to \(providerName): \(url) (model: \(providerModel), slot: \(slot))"
        )

        let httpClient = req.application.http.client.shared
        let httpResponse = try await httpClient.execute(httpRequest, timeout: .seconds(300))

        print("[Gateway] ⬅️ \(providerName) streaming response status: \(httpResponse.status.code)")

        guard httpResponse.status == .ok else {
            let body = try await httpResponse.body.collect(upTo: 1024 * 1024)
            let responseData = Data(buffer: body)
            let transformedResponseData = try adapter.transformResponse(
                responseData: responseData,
                isStreaming: false,
                requestedModel: requestedModel
            )
            var responseHeaders = HTTPHeaders()
            responseHeaders.add(name: "Content-Type", value: "application/json")
            return Response(
                status: .ok,
                headers: responseHeaders,
                body: .init(data: transformedResponseData)
            )
        }

        var responseHeaders = HTTPHeaders()
        responseHeaders.add(name: "Content-Type", value: "text/event-stream")
        responseHeaders.add(name: "Cache-Control", value: "no-cache")
        responseHeaders.add(name: "Connection", value: "keep-alive")

        let upstreamBody = httpResponse.body
        let adapterType = adapter.providerType

        let response = Response(
            status: .ok,
            headers: responseHeaders,
            body: .init(managedAsyncStream: { writer in
                var parser = SSELineParser()
                var receivedFinishReason = false
                var finalInputTokens = 0
                var finalOutputTokens = 0

                do {
                    if adapterType == "openai" {
                        // OpenAI streaming path
                        var openAIBuilder = OpenAISSEBuilder(
                            requestedModel: requestedModel,
                            chunkProcessor: adapter.makeChunkProcessor()
                        )

                        for try await chunk in upstreamBody {
                            let jsonPayloads = parser.feed(chunk)

                            for payload in jsonPayloads {
                                // Skip OpenAI's [DONE] sentinel
                                if payload == "[DONE]" { continue }

                                let sseEvents = openAIBuilder.processOpenAIChunk(payload)
                                for event in sseEvents {
                                    if event.contains("message_stop") {
                                        receivedFinishReason = true
                                    }
                                    try await writer.write(.buffer(ByteBuffer(string: event)))
                                }
                            }
                        }

                        if !receivedFinishReason {
                            let finalEvents = openAIBuilder.finalize()
                            for event in finalEvents {
                                try await writer.write(.buffer(ByteBuffer(string: event)))
                            }
                        }

                        let usage = openAIBuilder.tokenUsage
                        finalInputTokens = usage.inputTokens
                        finalOutputTokens = usage.outputTokens
                    } else {
                        // Gemini streaming path
                        var geminiBuilder = AnthropicSSEBuilder(requestedModel: requestedModel)

                        for try await chunk in upstreamBody {
                            let jsonPayloads = parser.feed(chunk)

                            for payload in jsonPayloads {
                                let sseEvents = geminiBuilder.processGeminiChunk(payload)
                                for event in sseEvents {
                                    if event.contains("message_stop") {
                                        receivedFinishReason = true
                                    }
                                    try await writer.write(.buffer(ByteBuffer(string: event)))
                                }
                            }
                        }

                        if !receivedFinishReason {
                            let finalEvents = geminiBuilder.finalize()
                            for event in finalEvents {
                                try await writer.write(.buffer(ByteBuffer(string: event)))
                            }
                        }

                        let usage = geminiBuilder.tokenUsage
                        finalInputTokens = usage.inputTokens
                        finalOutputTokens = usage.outputTokens
                    }
                } catch {
                    print("[Gateway] ❌ Streaming error: \(error)")
                    // Emit error event + message_stop so Claude Code doesn't hang
                    let errorEvent =
                        "event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"api_error\",\"message\":\"Stream interrupted: \(error.localizedDescription)\"}}\n\n"
                    try? await writer.write(.buffer(ByteBuffer(string: errorEvent)))
                    if !receivedFinishReason {
                        let stopEvent = "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
                        try? await writer.write(.buffer(ByteBuffer(string: stopEvent)))
                    }
                }

                self.logStreamingSuccess(
                    slot: slot,
                    model: providerModel,
                    provider: providerName,
                    inputTokens: finalInputTokens,
                    outputTokens: finalOutputTokens,
                    startTime: startTime
                )
            })
        )

        return response
    }

    private func logSuccess(
        slot: String, model: String, provider: String, authropicResp: Data, startTime: Date
    ) {
        let latency = Int(Date().timeIntervalSince(startTime) * 1000)

        var inToks = 0
        var outToks = 0

        if let json = try? JSONSerialization.jsonObject(with: authropicResp) as? [String: Any],
            let usage = json["usage"] as? [String: Int]
        {
            inToks = usage["input_tokens"] ?? 0
            outToks = usage["output_tokens"] ?? 0
        }

        let totalCost = estimateCost(model: model, inputTokens: inToks, outputTokens: outToks)

        let log = RequestLog(
            timestamp: Date(),
            slot: slot,
            providerModel: model,
            providerName: provider,
            inputTokens: inToks,
            outputTokens: outToks,
            cost: totalCost,
            latencyMs: latency,
            success: true
        )
        server.addLog(log)
    }

    private func logStreamingSuccess(
        slot: String, model: String, provider: String,
        inputTokens: Int, outputTokens: Int, startTime: Date
    ) {
        let latency = Int(Date().timeIntervalSince(startTime) * 1000)
        let totalCost = estimateCost(
            model: model, inputTokens: inputTokens, outputTokens: outputTokens)

        let log = RequestLog(
            timestamp: Date(),
            slot: slot,
            providerModel: model,
            providerName: provider,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cost: totalCost,
            latencyMs: latency,
            success: true
        )
        server.addLog(log)
    }

    /// Calculate cost using ModelCatalog pricing, with fallback to default rates.
    private func estimateCost(model: String, inputTokens: Int, outputTokens: Int) -> Double {
        if let modelInfo = ModelCatalog.find(modelId: model) {
            return modelInfo.cost.estimate(inputTokens: inputTokens, outputTokens: outputTokens)
        }
        // Fallback: $1.25/M input, $10/M output (GPT-5 tier)
        let costIn = Double(inputTokens) / 1_000_000.0 * 1.25
        let costOut = Double(outputTokens) / 1_000_000.0 * 10.0
        return costIn + costOut
    }

    private func logFailure(
        slot: String, model: String, provider: String, error: Error, startTime: Date
    ) {
        let latency = Int(Date().timeIntervalSince(startTime) * 1000)
        let log = RequestLog(
            timestamp: Date(),
            slot: slot,
            providerModel: model,
            providerName: provider,
            inputTokens: 0,
            outputTokens: 0,
            cost: 0,
            latencyMs: latency,
            success: false
        )
        server.addLog(log)
    }
}
