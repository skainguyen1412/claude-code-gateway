import SwiftUI

struct RequestLogView: View {
    @EnvironmentObject var server: GatewayServer
    @State private var autoScroll = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Request Log")
                    .font(.largeTitle)
                    .fontWeight(.heavy)
                Spacer()

                Toggle("Auto-Scroll", isOn: $autoScroll)

                Button(
                    role: .destructive,
                    action: {
                        server.clearLogs()
                    }
                ) {
                    Label("Clear", systemImage: "trash")
                }
                .padding(.leading, 10)
            }
            .padding()

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(server.requestLogs) { log in
                            HStack(spacing: 12) {
                                // Status Pill
                                Group {
                                    if log.success {
                                        Text("200 OK")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.green.opacity(0.2))
                                            .foregroundColor(.green)
                                            .clipShape(Capsule())
                                    } else {
                                        Text("ERROR")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.red.opacity(0.2))
                                            .foregroundColor(.red)
                                            .clipShape(Capsule())
                                    }
                                }
                                .frame(width: 55, alignment: .leading)

                                Text("[\(formattedTime(log.timestamp))]")
                                    .foregroundColor(.secondary)
                                    .font(.system(.caption, design: .monospaced))

                                HStack(spacing: 6) {
                                    ProviderIconView(providerName: log.providerName, size: 16)
                                    Text("\(log.slot) -> \(log.providerModel)")
                                        .fontWeight(.medium)
                                        .font(.system(.body, design: .rounded))
                                }

                                Spacer()

                                Text("\(log.inputTokens + log.outputTokens) tok")
                                    .foregroundColor(.secondary)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 80, alignment: .trailing)

                                Text(String(format: "$%.4f", log.cost))
                                    .foregroundColor(.secondary)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 80, alignment: .trailing)

                                Text("\(log.latencyMs)ms")
                                    .foregroundColor(latencyColor(log.latencyMs))
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 60, alignment: .trailing)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                log.id == server.requestLogs.last?.id
                                    ? Color.blue.opacity(0.1)
                                    : Color.secondary.opacity(0.05)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .id(log.id)
                        }
                    }
                    .padding(.vertical)
                }
                .onChange(of: server.requestLogs.count) { _ in
                    if autoScroll, let lastAdded = server.requestLogs.last {
                        withAnimation {
                            proxy.scrollTo(lastAdded.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }

    private func latencyColor(_ ms: Int) -> Color {
        if ms < 1000 { return .green }
        if ms < 3000 { return .orange }
        return .red
    }
}
