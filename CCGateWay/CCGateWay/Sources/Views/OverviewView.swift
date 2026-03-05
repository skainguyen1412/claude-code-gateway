import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var config: GatewayConfig
    @EnvironmentObject var server: GatewayServer
    @EnvironmentObject var usageStore: UsageStore

    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Dashboard")
                    .font(.largeTitle)
                    .fontWeight(.heavy)

                // Hero Component: Server Status
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle()
                                .fill(server.isRunning ? Color.green : Color.red)
                                .frame(width: 14, height: 14)
                                .shadow(
                                    color: server.isRunning
                                        ? .green.opacity(0.8) : .red.opacity(0.8), radius: 6)
                            Text("Server Status")
                                .font(.headline)
                        }
                        Text(server.statusMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    if server.isRunning {
                        Button("Restart") {
                            server.restart()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Button(action: {
                        if server.isRunning {
                            server.stop()
                        } else {
                            server.start()
                        }
                    }) {
                        Text(server.isRunning ? "Stop" : "Start Server")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(server.isRunning ? .red : .green)
                    .controlSize(.large)
                }
                .padding(20)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                LazyVGrid(columns: columns, spacing: 16) {
                    MetricCard(
                        title: "Today's Cost",
                        value: "$\(String(format: "%.4f", usageStore.todayRecord.totalCost))",
                        icon: "dollarsign.circle.fill"
                    )
                    MetricCard(
                        title: "Requests Today",
                        value: "\(usageStore.todayRecord.requestCount)",
                        icon: "arrow.left.arrow.right"
                    )
                }

                // Active Provider Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "network.badge.shield.half.filled")
                            .foregroundColor(.blue)
                        Text("Active Provider")
                            .font(.headline)
                    }
                    Divider()

                    if let active = config.activeProviderConfig {
                        HStack(spacing: 12) {
                            ProviderIconView(icon: active.providerIcon, size: 28)
                                .frame(width: 40, height: 40)
                                .background(active.providerIcon.color.opacity(0.12))
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous))

                            Text(active.name)
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(active.type.capitalized)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                        }
                        Text(active.baseUrl)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        Text("No provider selected.")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(20)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.purple)
                        Text("Routing Mode")
                            .font(.headline)
                    }
                    Divider()

                    if let activePreset = config.activePresetConfig {
                        Text("Preset Mode: \(activePreset.name)")
                            .font(.title3)
                            .fontWeight(.semibold)

                        ForEach(PresetValidator.requiredSlots, id: \.self) { slot in
                            if let target = activePreset.slots[slot] {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("\(displayName(for: slot)):")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 95, alignment: .leading)
                                    Text("\(target.providerName) -> \(target.modelId)")
                                        .font(.caption)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    } else {
                        Text("Provider Mode")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Using models from the active provider.")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(20)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(32)
        }
    }

    private func displayName(for slot: String) -> String {
        switch slot {
        case "default": return "Default"
        case "background": return "Background"
        case "think": return "Think"
        case "longContext": return "Long Context"
        default: return slot
        }
    }
}

// Helper view for metrics
struct MetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .font(.title3)
                Spacer()
            }

            Text(value)
                .font(.system(.title, design: .rounded))
                .fontWeight(.bold)

            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
