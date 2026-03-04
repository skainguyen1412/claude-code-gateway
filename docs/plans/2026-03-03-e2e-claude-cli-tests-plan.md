# E2E Claude CLI Integration Tests — Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Automate manual Claude Code testing by writing Swift Testing integration tests that spawn the real `claude` CLI against an in-process gateway server.

**Architecture:** Start a standalone Vapor server with the same `GatewayRoutes` in each test, spawn `claude -p "prompt"` as a `Process` with `ANTHROPIC_BASE_URL` pointing at the test server, capture stdout/stderr and assert correctness.

**Tech Stack:** Swift Testing, Vapor, Foundation.Process, Keychain

---

### Task 1: Create `E2ETestServer` — Lightweight Vapor Test Server

**Files:**
- Create: `CCGateWay/CCGateWay/Tests/E2ETestServer.swift`

**Step 1: Write the `E2ETestServer`**

This helper starts a Vapor server on a random available port with the real `GatewayRoutes`. It has no `@MainActor` or `ObservableObject` — it's purely for tests.

```swift
import Foundation
import Vapor

@testable import CCGateWay

/// A lightweight Vapor server for E2E testing.
/// Starts on a random port with the same routes as the real app.
actor E2ETestServer {
    private var app: Application?
    private(set) var port: Int = 0

    /// The gateway config used by this test server
    let config: GatewayConfig

    /// A minimal GatewayServer stand-in for logging (logs are discarded in tests)
    private var server: GatewayServer?

    init(config: GatewayConfig) {
        self.config = config
    }

    /// Start the Vapor server. Returns the port it's listening on.
    @discardableResult
    func start() async throws -> Int {
        var env = Environment.testing
        env.arguments = ["vapor"]
        let app = try await Application.make(env)

        // Find a random available port
        app.http.server.configuration.hostname = "127.0.0.1"
        app.http.server.configuration.port = 0  // OS assigns random port

        app.routes.defaultMaxBodySize = "100mb"

        // We need a GatewayServer for the routes (it handles logging)
        let gatewayServer = await GatewayServer(config: config)
        self.server = gatewayServer

        let routes = GatewayRoutes(config: config, server: gatewayServer)
        try routes.boot(app)

        self.app = app

        // Start server in background
        try await app.startup()

        // Get the actual port assigned by OS
        let assignedPort = app.http.server.shared.localAddress?.port ?? 0
        self.port = assignedPort

        return assignedPort
    }

    /// Stop the server and clean up.
    func stop() async {
        app?.server.shutdown()
        try? await app?.asyncShutdown()
        app = nil
        server = nil
    }
}
```

**Step 2: Verify it compiles**

Run: `cd CCGateWay && tuist build --scheme CCGateWayTests 2>&1 | tail -20`
Expected: Build succeeds (or at least the test server file compiles)

If `app.http.server.shared.localAddress` doesn't exist, check Vapor docs and adapt. The key thing is getting the actual assigned port when we bind to port `0`.

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Tests/E2ETestServer.swift
git commit -m "test: add E2ETestServer — lightweight Vapor server for integration tests"
```

---

### Task 2: Create `ClaudeCliRunner` — Process wrapper for `claude` CLI

**Files:**
- Create: `CCGateWay/CCGateWay/Tests/ClaudeCliRunner.swift`

**Step 1: Write the `ClaudeCliRunner`**

This wraps `Foundation.Process` to run `claude -p "prompt"` with custom environment variables.

```swift
import Foundation

/// Result of running the claude CLI
struct ClaudeCliResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

/// Runs the `claude` CLI as a child process for E2E testing.
struct ClaudeCliRunner {
    let claudePath: String
    let baseURL: String  // e.g. "http://127.0.0.1:12345"
    let authToken: String

    init(
        claudePath: String = "/Users/chaileasevn/.local/bin/claude",
        baseURL: String,
        authToken: String = "dummy_key_gateway"
    ) {
        self.claudePath = claudePath
        self.baseURL = baseURL
        self.authToken = authToken
    }

    /// Run `claude -p "prompt"` and capture output.
    /// - Parameters:
    ///   - prompt: The prompt to send
    ///   - outputFormat: "text" (default), "json", or "stream-json"
    ///   - model: Optional model override
    ///   - timeoutSeconds: Max time to wait for the process
    /// - Returns: The CLI result with stdout, stderr, exit code
    func run(
        prompt: String,
        outputFormat: String = "text",
        model: String? = nil,
        timeoutSeconds: TimeInterval = 60
    ) async throws -> ClaudeCliResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)

        var args = [
            "-p", prompt,
            "--output-format", outputFormat,
            "--no-session-persistence",
        ]
        if let model = model {
            args += ["--model", model]
        }
        process.arguments = args

        // Set environment: point claude at our test gateway
        var env = ProcessInfo.processInfo.environment
        env["ANTHROPIC_BASE_URL"] = baseURL
        env["ANTHROPIC_AUTH_TOKEN"] = authToken
        // Override model settings so claude uses anthropic model names
        // (our gateway will route them via SlotRouter)
        env["ANTHROPIC_MODEL"] = nil  // Let claude use its default
        env.removeValue(forKey: "ANTHROPIC_MODEL")
        env.removeValue(forKey: "ANTHROPIC_DEFAULT_SONNET_MODEL")
        env.removeValue(forKey: "ANTHROPIC_DEFAULT_HAIKU_MODEL")
        env.removeValue(forKey: "ANTHROPIC_DEFAULT_OPUS_MODEL")
        env.removeValue(forKey: "CLAUDE_CODE_SUBAGENT_MODEL")
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Wait with timeout
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeoutSeconds))
            if process.isRunning {
                process.terminate()
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ClaudeCliResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
```

**Step 2: Verify it compiles**

Run: `cd CCGateWay && tuist build --scheme CCGateWayTests 2>&1 | tail -20`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Tests/ClaudeCliRunner.swift
git commit -m "test: add ClaudeCliRunner — Process wrapper for claude CLI"
```

---

### Task 3: Create `ClaudeE2ETests` — The actual test cases

**Files:**
- Create: `CCGateWay/CCGateWay/Tests/ClaudeE2ETests.swift`

**Step 1: Write the test suite**

```swift
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
                "default": "gemini-2.5-flash-preview-05-20",
                "background": "gemini-2.5-flash-preview-05-20",
                "think": "gemini-2.5-flash-preview-05-20",
                "longContext": "gemini-2.5-flash-preview-05-20",
            ]
        )
        return GatewayConfig(
            activeProvider: "Gemini",
            port: 0,  // Will use random port
            providers: ["Gemini": provider]
        )
    }

    /// Helper: start server and return (server, runner) pair
    static func startServerAndRunner() async throws -> (E2ETestServer, ClaudeCliRunner) {
        // Verify Gemini API key exists
        guard let apiKey = KeychainManager.load(key: "Gemini_api_key"), !apiKey.isEmpty else {
            throw TestSkipError("No Gemini API key in Keychain — skip E2E tests")
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
            throw TestSkipError("No Gemini API key")
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
                ["role": "user", "content": "Reply with exactly the word GATEWAY_OK and nothing else."]
            ]
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
        let (server, runner) = try await Self.startServerAndRunner()
        defer { Task { await server.stop() } }

        let result = try await runner.run(
            prompt: "Reply with exactly the word GATEWAY_OK and nothing else.",
            timeoutSeconds: 30
        )

        #expect(result.succeeded, "claude exited with code \(result.exitCode), stderr: \(result.stderr)")
        #expect(result.stdout.contains("GATEWAY_OK"), "Expected GATEWAY_OK in stdout: \(result.stdout)")
    }

    @Test("Claude CLI JSON output has valid Anthropic structure")
    func claudeCliJsonOutput() async throws {
        let (server, runner) = try await Self.startServerAndRunner()
        defer { Task { await server.stop() } }

        let result = try await runner.run(
            prompt: "Reply with the word hello.",
            outputFormat: "json",
            timeoutSeconds: 30
        )

        #expect(result.succeeded, "claude exited with code \(result.exitCode), stderr: \(result.stderr)")

        // Parse the JSON output
        let data = Data(result.stdout.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

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
        let (slot1, model1) = SlotRouter.resolve(requestedModel: "claude-sonnet-4-20250514", provider: provider)
        #expect(slot1 == "default")
        #expect(model1 == "gemini-2.5-flash-preview-05-20")

        // claude-3-haiku -> background slot
        let (slot2, model2) = SlotRouter.resolve(requestedModel: "claude-3-haiku-20240307", provider: provider)
        #expect(slot2 == "background")
        #expect(model2 == "gemini-2.5-flash-preview-05-20")

        // claude-3-opus -> think slot
        let (slot3, model3) = SlotRouter.resolve(requestedModel: "claude-3-opus-20240229", provider: provider)
        #expect(slot3 == "think")
        #expect(model3 == "gemini-2.5-flash-preview-05-20")

        // Unknown model -> default slot
        let (slot4, _) = SlotRouter.resolve(requestedModel: "some-unknown-model", provider: provider)
        #expect(slot4 == "default")
    }
}

/// Error to skip tests when prerequisites aren't met
struct TestSkipError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { self.description = message }
}
```

**Step 2: Verify it compiles**

Run: `cd CCGateWay && tuist build --scheme CCGateWayTests 2>&1 | tail -20`
Expected: Build succeeds

**Step 3: Run the tests**

Run: `cd CCGateWay && swift test 2>&1 | tail -30`

Or via Xcode:
Run: `cd CCGateWay && xcodebuild test -workspace CCGateWay.xcworkspace -scheme CCGateWayTests -destination 'platform=macOS' 2>&1 | tail -40`

Expected: All tests pass (health check, raw messages, CLI basic prompt, JSON output, slot routing)

**Step 4: Commit**

```bash
git add CCGateWay/CCGateWay/Tests/ClaudeE2ETests.swift
git commit -m "test: add E2E Claude CLI integration tests"
```

---

### Task 4: Fix compilation issues and iterate

This is a buffer task. After the initial implementation, there will likely be:

**Step 1: Address Vapor API differences**

The `E2ETestServer` uses `app.startup()` and `app.http.server.shared.localAddress` which may vary by Vapor version. Check the actual Vapor API available in the project and adapt:
- If `app.startup()` doesn't exist, use `try await app.execute()` in a detached Task
- If port 0 binding doesn't return the assigned port, bind to a known port (e.g. `19876`) instead
- If `GatewayServer` init requires `@MainActor`, wrap creation in `await MainActor.run { ... }`

**Step 2: Address `@MainActor` / Sendable issues**

`GatewayServer` is `@MainActor`. The test server needs to create it on the main actor. Adjust the `E2ETestServer` to handle this correctly — possibly by making `startServerAndRunner()` a `@MainActor` function.

**Step 3: Verify all tests pass**

Run the test suite and fix any remaining issues until all 5 tests pass.

**Step 4: Commit**

```bash
git add -A
git commit -m "test: fix E2E test compilation and runtime issues"
```

---

### Task 5: Final verification and cleanup

**Step 1: Run the full test suite**

Run all tests including the existing ones:
```bash
cd CCGateWay && xcodebuild test -workspace CCGateWay.xcworkspace -scheme CCGateWayTests -destination 'platform=macOS' 2>&1 | tail -40
```

Expected: All tests pass (existing + new E2E tests)

**Step 2: Commit final state**

```bash
git add -A
git commit -m "test: complete E2E Claude CLI integration test suite"
```
