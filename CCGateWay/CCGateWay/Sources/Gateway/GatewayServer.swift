import Foundation
import Vapor

@MainActor
final class GatewayServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = "Stopped"
    @Published var requestLogs: [RequestLog] = []

    private var app: Application?
    private var serverTask: Task<Void, Never>?

    let config: GatewayConfig
    var usageStore: UsageStore?

    init(config: GatewayConfig) {
        self.config = config
    }

    func start() {
        guard !isRunning else { return }

        let port = config.port
        let config = self.config

        statusMessage = "Starting..."

        serverTask = Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                var env = Environment.production
                env.arguments = ["vapor"]
                let app = try await Application.make(env)
                app.http.server.configuration.hostname = "127.0.0.1"
                app.http.server.configuration.port = port

                // Allow large payloads from Claude Code (e.g. 100MB)
                app.routes.defaultMaxBodySize = "100mb"

                // Register routes
                let routes = GatewayRoutes(config: config, server: self)
                try routes.boot(app)

                await MainActor.run {
                    self.app = app
                    self.isRunning = true
                    self.statusMessage = "Running on 127.0.0.1:\(port)"
                }

                try await app.execute()
            } catch {
                await MainActor.run {
                    self.isRunning = false
                    self.statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    func stop() {
        app?.server.shutdown()
        serverTask?.cancel()
        serverTask = nil
        app = nil
        isRunning = false
        statusMessage = "Stopped"
    }

    func restart() {
        stop()
        // Brief delay to allow port release
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            start()
        }
    }

    // MARK: - Logging

    nonisolated func addLog(_ log: RequestLog) {
        Task { @MainActor in
            self.requestLogs.append(log)

            // Delegate cost tracking to UsageStore
            self.usageStore?.recordRequest(
                cost: log.cost,
                inputTokens: log.inputTokens,
                outputTokens: log.outputTokens,
                providerName: log.providerName
            )

            // Keep last 1000 logs in memory
            if self.requestLogs.count > 1000 {
                self.requestLogs.removeFirst(self.requestLogs.count - 1000)
            }
        }
    }

    nonisolated func clearLogs() {
        Task { @MainActor in
            self.requestLogs.removeAll()
        }
    }
}
