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

        // Bind to localhost on a random port (port 0 means OS assigned)
        app.http.server.configuration.hostname = "127.0.0.1"
        app.http.server.configuration.port = 0

        app.routes.defaultMaxBodySize = "100mb"

        // We need a GatewayServer for the routes (it handles logging)
        let gatewayServer = await GatewayServer(config: config)
        self.server = gatewayServer

        let routes = GatewayRoutes(config: config, server: gatewayServer)
        try routes.boot(app)

        self.app = app

        // Start server asynchronously (app.startup vs app.execute)
        // Vapor 4 handles this with App.execute() acting semi-blocking on MainActor
        // A better approach for tests: startup() starts the server in the background
        try await app.startup()

        // Get the actual port assigned by OS
        let assignedPort = app.http.server.shared.localAddress?.port ?? 0
        self.port = assignedPort

        return assignedPort
    }

    /// Stop the server and clean up.
    func stop() async {
        await app?.server.shutdown()
        try? await app?.asyncShutdown()
        app = nil
        server = nil
    }
}
