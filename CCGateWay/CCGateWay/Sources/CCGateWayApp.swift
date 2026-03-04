import SwiftUI

@main
struct CCGateWayApp: App {
    @StateObject private var config = GatewayConfig.load()
    @StateObject private var server: GatewayServer
    @StateObject private var usageStore = UsageStore()

    // Track initialization to trigger logic on first start
    @State private var hasInitialized = false

    init() {
        let loadedConfig = GatewayConfig.load()
        _config = StateObject(wrappedValue: loadedConfig)
        _server = StateObject(wrappedValue: GatewayServer(config: loadedConfig))
    }

    var body: some Scene {
        // Main Dashboard Window (single instance only)
        Window("CCGateWay", id: "dashboard") {
            DashboardView()
                .environmentObject(config)
                .environmentObject(server)
                .environmentObject(usageStore)
                .onAppear {
                    handleFirstLaunch()
                }
                .onDisappear {
                    usageStore.save()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 600)

        // Menu Bar Widget
        MenuBarExtra(
            "CCGateWay",
            systemImage: server.isRunning
                ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
        ) {
            MenuBarDropdown()
                .environmentObject(config)
                .environmentObject(server)
                .environmentObject(usageStore)
        }
        .menuBarExtraStyle(.window)
    }

    private func handleFirstLaunch() {
        guard !hasInitialized else { return }
        hasInitialized = true

        server.usageStore = usageStore

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                usageStore.save()
            }
        }

        // Start server if needed
        if config.autoStartOnLogin {
            server.start()
        }
    }
}
