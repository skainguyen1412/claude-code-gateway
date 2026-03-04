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

        // Execute the process
        try process.run()

        // Wait with timeout
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
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
