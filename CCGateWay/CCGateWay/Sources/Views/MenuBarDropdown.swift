import SwiftUI

struct MenuBarDropdown: View {
    @EnvironmentObject var config: GatewayConfig
    @EnvironmentObject var server: GatewayServer
    @EnvironmentObject var usageStore: UsageStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Header: Status and Cost
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CCGateWay")
                        .font(.system(size: 14, weight: .bold, design: .rounded))

                    Text("Today: \(formatCost(usageStore.todayRecord.totalCost))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Status Indicator
                Button(action: {
                    if server.isRunning {
                        server.stop()
                    } else {
                        server.start()
                    }
                }) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(server.isRunning ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                            .shadow(
                                color: server.isRunning ? .green.opacity(0.8) : .red.opacity(0.8),
                                radius: 3)

                        Text(server.isRunning ? "Active" : "Stopped")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(server.isRunning ? .green : .red)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .strokeBorder(
                                server.isRunning
                                    ? Color.green.opacity(0.3) : Color.red.opacity(0.3),
                                lineWidth: 1
                            )
                            .background(
                                Capsule().fill(
                                    (server.isRunning ? Color.green : Color.red).opacity(0.1)))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()
                .opacity(0.5)

            // Providers Section
            VStack(alignment: .leading, spacing: 8) {
                Text("QUICK SWITCH")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(config.providers.keys.sorted(), id: \.self) { providerName in
                            MenuProviderRow(
                                name: providerName,
                                isActive: config.activeProvider == providerName,
                                cost: usageStore.todayRecord.providers[providerName]?.cost ?? 0
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    config.switchProvider(to: providerName)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: 220)
            }

            Divider()
                .opacity(0.5)

            // Footer Actions
            HStack(spacing: 12) {
                Button(action: {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "dashboard")
                }) {
                    Label("Dashboard", systemImage: "macwindow")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HoverButtonStyle())

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(HoverButtonStyle())
                .frame(width: 32)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        }
        .frame(width: 280)
    }
}

struct MenuProviderRow: View {
    let name: String
    let isActive: Bool
    let cost: Double
    let action: () -> Void
    @State private var isHovered = false

    /// Use the template's properly-cased name if this provider matches one.
    private var displayName: String {
        ProviderConfig.templates
            .first(where: { $0.name.lowercased() == name.lowercased() })?
            .name ?? name
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ProviderIconView(providerName: name, size: 16)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                isActive
                                    ? ProviderConfig.providerIcon(for: name).color.opacity(0.15)
                                    : Color(NSColor.controlBackgroundColor).opacity(0.5))
                    )

                Text(displayName)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? .primary : .primary.opacity(0.8))

                Spacer()

                Text(formatCost(cost))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isActive
                            ? Color.blue.opacity(0.08)
                            : (isHovered ? Color(NSColor.quaternaryLabelColor) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isActive
                            ? Color.blue.opacity(0.3)
                            : (isHovered ? Color(NSColor.gridColor) : Color.clear), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct HoverButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        configuration.isPressed
                            ? Color.primary.opacity(0.1)
                            : (isHovered ? Color(NSColor.quaternaryLabelColor) : Color.clear))
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

private func formatCost(_ cost: Double) -> String {
    if cost == 0 { return "$0" }
    if cost < 0.0001 { return "<$0.0001" }
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencySymbol = "$"
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 4
    return formatter.string(from: NSNumber(value: cost)) ?? String(format: "$%.4f", cost)
}
