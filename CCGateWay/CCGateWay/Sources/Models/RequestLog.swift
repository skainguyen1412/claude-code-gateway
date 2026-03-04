import Foundation

struct RequestLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let slot: String
    let providerModel: String
    let providerName: String
    let inputTokens: Int
    let outputTokens: Int
    let cost: Double
    let latencyMs: Int
    let success: Bool

    var formattedLine: String {
        let time = Self.timeFormatter.string(from: timestamp)
        let tokens = inputTokens + outputTokens
        let costStr = String(format: "$%.4f", cost)
        let latency = String(format: "%.1fs", Double(latencyMs) / 1000.0)
        let status = success ? "✓" : "✗"
        return
            "[\(time)] \(status) \(slot) → \(providerModel) | \(tokens) tok | \(costStr) | \(latency)"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
