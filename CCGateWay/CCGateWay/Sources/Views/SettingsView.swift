import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var config: GatewayConfig
    @EnvironmentObject var server: GatewayServer

    // UI state
    @State private var portStr: String = ""
    @State private var autoStart: Bool = false

    @State private var showResetConfirmAlert = false
    @State private var showResetSuccessAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.heavy)

                // Server Settings Card
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundColor(.blue)
                        Text("Server Settings")
                            .font(.headline)
                    }
                    Divider()

                    HStack {
                        Text("Port")
                            .frame(width: 120, alignment: .leading)
                        TextField("3456", text: $portStr)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .onChange(of: portStr) {
                                if let p = Int(portStr) {
                                    config.port = p
                                }
                            }
                    }

                    Toggle("Start Server on Login", isOn: $autoStart)
                        .onChange(of: autoStart) {
                            config.autoStartOnLogin = autoStart
                        }

                    Divider()

                    HStack {
                        Spacer()
                        Button("Apply & Restart Server") {
                            config.save()
                            server.restart()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
                .padding(20)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                // Claude Code Integration Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "link.badge.plus")
                            .foregroundColor(.blue)
                        Text("Claude Code Integration")
                            .font(.headline)
                    }
                    Divider()

                    Text(
                        "CCGateWay routes requests at http://127.0.0.1:\(config.port). Your local Claude Code configuration (~/.claude/settings.json) is automatically kept in sync when you switch providers."
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reset Claude Code Settings")
                                .font(.subheadline)
                            Text("Remove all CCGateWay env vars from ~/.claude/settings.json")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Reset") {
                            showResetConfirmAlert = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
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
        .onAppear {
            portStr = "\(config.port)"
            autoStart = config.autoStartOnLogin
        }

        .alert("Reset Claude Code Settings?", isPresented: $showResetConfirmAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                config.resetClaudeCodeSettings()
                showResetSuccessAlert = true
            }
        } message: {
            Text(
                "This will remove all CCGateWay environment variables from ~/.claude/settings.json. You can re-sync anytime by switching providers."
            )
        }
        .alert("Settings Reset", isPresented: $showResetSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("CCGateWay env vars have been removed from ~/.claude/settings.json.")
        }
    }
}
