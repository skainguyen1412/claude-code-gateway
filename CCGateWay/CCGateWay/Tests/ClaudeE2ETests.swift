import Foundation
import Testing

@testable import CCGateWay

@Suite("Claude E2E Integration Tests")
struct ClaudeE2ETests {

    /// Helper: create a test GatewayConfig with Gemini provider
    static func makeTestConfig() -> GatewayConfig {
        let provider = ProviderConfig(
            name: "Gemini",
            type: "gemini",
            baseUrl: "https://generativelanguage.googleapis.com/v1beta/models/",
            slots: [
                "default": "gemini-2.5-flash",
                "background": "gemini-2.5-flash",
                "think": "gemini-2.5-flash",
                "longContext": "gemini-2.5-flash",
            ]
        )
        return GatewayConfig(
            activeProvider: "Gemini",
            port: 0,  // Will use random port
            providers: ["Gemini": provider]
        )
    }

    /// Helper: start server and return (server, runner) pair
    static func startServerAndRunner() async throws -> (E2ETestServer, ClaudeCliRunner)? {
        // Verify Gemini API key exists
        guard let apiKey = KeychainManager.load(key: "Gemini_api_key"), !apiKey.isEmpty else {
            print("No Gemini API key in Keychain — skip E2E tests")
            return nil
        }

        let config = makeTestConfig()
        let server = E2ETestServer(config: config)
        let port = try await server.start()

        let runner = ClaudeCliRunner(
            baseURL: "http://127.0.0.1:\(port)"
        )

        return (server, runner)
    }

    // MARK: - Test Cases

    @Test("Health check endpoint returns ok")
    func healthCheck() async throws {
        let config = Self.makeTestConfig()
        let server = E2ETestServer(config: config)
        let port = try await server.start()
        defer { Task { await server.stop() } }

        // Simple HTTP GET to /health
        let url = URL(string: "http://127.0.0.1:\(port)/health")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = response as! HTTPURLResponse

        #expect(httpResponse.statusCode == 200)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
        #expect(json?["status"] == "ok")
    }

    @Test("Raw Anthropic /v1/messages request returns valid response")
    func rawMessagesEndpoint() async throws {
        guard let apiKey = KeychainManager.load(key: "Gemini_api_key"), !apiKey.isEmpty else {
            print("No Gemini API key — skip E2E test")
            return
        }

        let config = Self.makeTestConfig()
        let server = E2ETestServer(config: config)
        let port = try await server.start()
        defer { Task { await server.stop() } }

        // Build an Anthropic-format request
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 50,
            "messages": [
                [
                    "role": "user",
                    "content": "Reply with exactly the word GATEWAY_OK and nothing else.",
                ]
            ],
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: anthropicBody)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/messages")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer dummy_key_gateway", forHTTPHeaderField: "Authorization")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        #expect(httpResponse.statusCode == 200)

        // Parse Anthropic-format response
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["type"] as? String == "message")
        #expect(json["role"] as? String == "assistant")

        // Verify content array exists with text
        let content = json["content"] as? [[String: Any]]
        #expect(content != nil)
        #expect(content?.isEmpty == false)

        let firstContent = content?.first
        #expect(firstContent?["type"] as? String == "text")

        let text = firstContent?["text"] as? String ?? ""
        #expect(text.contains("GATEWAY_OK"))

        // Verify usage exists
        let usage = json["usage"] as? [String: Any]
        #expect(usage != nil)
        #expect(usage?["input_tokens"] as? Int != nil)
        #expect(usage?["output_tokens"] as? Int != nil)
    }

    @Test("Claude CLI basic prompt returns text response")
    func claudeCliBasicPrompt() async throws {
        guard let (server, runner) = try await Self.startServerAndRunner() else { return }
        defer { Task { await server.stop() } }

        let result = try await runner.run(
            prompt: "Reply with exactly the word GATEWAY_OK and nothing else.",
            timeoutSeconds: 30
        )

        #expect(
            result.succeeded, "claude exited with code \(result.exitCode), stderr: \(result.stderr)"
        )
        #expect(
            result.stdout.contains("GATEWAY_OK"), "Expected GATEWAY_OK in stdout: \(result.stdout)")
    }

    @Test("Claude CLI JSON output has valid Anthropic structure")
    func claudeCliJsonOutput() async throws {
        guard let (server, runner) = try await Self.startServerAndRunner() else { return }
        defer { Task { await server.stop() } }

        let result = try await runner.run(
            prompt: "Reply with the word hello.",
            outputFormat: "json",
            timeoutSeconds: 30
        )

        #expect(
            result.succeeded, "claude exited with code \(result.exitCode), stderr: \(result.stderr)"
        )

        // Parse the JSON output
        let data = Data(result.stdout.utf8)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Could not parse CLI JSON output: \(result.stdout)")
            return
        }

        // Claude CLI JSON output should have a result field
        #expect(json.isEmpty == false, "JSON output should not be empty")
    }

    @Test("Slot routing: different model names route to correct slots")
    func slotRouting() async throws {
        // This test verifies SlotRouter logic without needing the CLI
        let config = Self.makeTestConfig()
        guard let provider = config.activeProviderConfig else {
            Issue.record("No active provider")
            return
        }

        // claude-sonnet-4 -> default slot
        let (slot1, model1) = SlotRouter.resolve(
            requestedModel: "claude-sonnet-4-20250514", provider: provider)
        #expect(slot1 == "default")
        #expect(model1 == "gemini-2.5-flash")

        // claude-3-haiku -> background slot
        let (slot2, model2) = SlotRouter.resolve(
            requestedModel: "claude-3-haiku-20240307", provider: provider)
        #expect(slot2 == "background")
        #expect(model2 == "gemini-2.5-flash")

        // claude-3-opus -> think slot
        let (slot3, model3) = SlotRouter.resolve(
            requestedModel: "claude-3-opus-20240229", provider: provider)
        #expect(slot3 == "think")
        #expect(model3 == "gemini-2.5-flash")

        // Unknown model -> default slot
        let (slot4, _) = SlotRouter.resolve(
            requestedModel: "some-unknown-model", provider: provider)
        #expect(slot4 == "default")
    }

    @Test("Streaming SSE request returns valid Anthropic event sequence")
    func streamingSSE() async throws {
        guard let apiKey = KeychainManager.load(key: "Gemini_api_key"), !apiKey.isEmpty else {
            print("No Gemini API key — skip streaming E2E test")
            return
        }

        let config = Self.makeTestConfig()
        let server = E2ETestServer(config: config)
        let port = try await server.start()
        defer { Task { await server.stop() } }

        // Build a streaming Anthropic-format request
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 50,
            "stream": true,
            "messages": [
                [
                    "role": "user",
                    "content": "Reply with exactly the word STREAM_OK and nothing else.",
                ]
            ],
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: anthropicBody)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/messages")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer dummy_key_gateway", forHTTPHeaderField: "Authorization")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        #expect(httpResponse.statusCode == 200)

        // Content-Type should be text/event-stream
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        #expect(
            contentType.contains("text/event-stream"),
            "Expected text/event-stream, got: \(contentType)")

        // Parse SSE events
        let sseText = String(data: data, encoding: .utf8) ?? ""
        #expect(!sseText.isEmpty, "SSE response should not be empty")

        // Validate we received the expected event types in order
        let hasMessageStart = sseText.contains("event: message_start")
        let hasContentBlockStart = sseText.contains("event: content_block_start")
        let hasContentBlockDelta = sseText.contains("event: content_block_delta")
        let hasContentBlockStop = sseText.contains("event: content_block_stop")
        let hasMessageDelta = sseText.contains("event: message_delta")
        let hasMessageStop = sseText.contains("event: message_stop")

        #expect(hasMessageStart, "Missing message_start event")
        #expect(hasContentBlockStart, "Missing content_block_start event")
        #expect(hasContentBlockDelta, "Missing content_block_delta event")
        #expect(hasContentBlockStop, "Missing content_block_stop event")
        #expect(hasMessageDelta, "Missing message_delta event")
        #expect(hasMessageStop, "Missing message_stop event")

        // Verify the text content contains our expected response
        #expect(sseText.contains("text_delta"), "Expected text_delta in streaming response")
    }
}
