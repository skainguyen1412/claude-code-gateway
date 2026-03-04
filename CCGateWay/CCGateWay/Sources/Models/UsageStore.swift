import Foundation

struct ProviderUsage: Codable {
    var cost: Double
    var requests: Int
}

struct DailyUsageRecord: Codable, Identifiable {
    var id: String { date }
    let date: String
    var totalCost: Double
    var requestCount: Int
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var providers: [String: ProviderUsage]
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var history: [DailyUsageRecord] = []
    @Published private(set) var todayRecord: DailyUsageRecord

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var todayDateString: String {
        Self.dateFormatter.string(from: Date())
    }

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ccgateway")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("usage_history.json")

        // Temporary today record — will be replaced in loadHistory()
        let today = Self.dateFormatter.string(from: Date())
        self.todayRecord = DailyUsageRecord(
            date: today, totalCost: 0, requestCount: 0,
            totalInputTokens: 0, totalOutputTokens: 0, providers: [:]
        )
        loadHistory()
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            history = [todayRecord]
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            var records = try JSONDecoder().decode([DailyUsageRecord].self, from: data)

            // Find or create today's entry
            let today = todayDateString
            if let idx = records.firstIndex(where: { $0.date == today }) {
                todayRecord = records[idx]
            } else {
                let newToday = DailyUsageRecord(
                    date: today, totalCost: 0, requestCount: 0,
                    totalInputTokens: 0, totalOutputTokens: 0, providers: [:]
                )
                records.append(newToday)
                todayRecord = newToday
            }
            history = records
        } catch {
            print("[UsageStore] ⚠️ Failed to load history: \(error)")
            history = [todayRecord]
        }
    }

    func save() {
        do {
            // Update today's record in history before saving
            if let idx = history.firstIndex(where: { $0.date == todayRecord.date }) {
                history[idx] = todayRecord
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(history)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[UsageStore] ⚠️ Failed to save history: \(error)")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    // MARK: - Recording

    func recordRequest(
        cost: Double, inputTokens: Int, outputTokens: Int, providerName: String
    ) {
        // Check for day rollover
        let today = todayDateString
        if todayRecord.date != today {
            // Finalize yesterday's record
            if let idx = history.firstIndex(where: { $0.date == todayRecord.date }) {
                history[idx] = todayRecord
            }
            // Create new today
            let newToday = DailyUsageRecord(
                date: today, totalCost: 0, requestCount: 0,
                totalInputTokens: 0, totalOutputTokens: 0, providers: [:]
            )
            history.append(newToday)
            todayRecord = newToday
        }

        // Update today's record
        todayRecord.totalCost += cost
        todayRecord.requestCount += 1
        todayRecord.totalInputTokens += inputTokens
        todayRecord.totalOutputTokens += outputTokens

        var providerUsage =
            todayRecord.providers[providerName] ?? ProviderUsage(cost: 0, requests: 0)
        providerUsage.cost += cost
        providerUsage.requests += 1
        todayRecord.providers[providerName] = providerUsage

        // Update in history array
        if let idx = history.firstIndex(where: { $0.date == todayRecord.date }) {
            history[idx] = todayRecord
        }

        scheduleSave()
    }

    // MARK: - Computed Properties

    var last7DaysCost: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let cutoffStr = Self.dateFormatter.string(from: cutoff)
        return history.filter { $0.date >= cutoffStr }.reduce(0) { $0 + $1.totalCost }
    }

    var last30DaysCost: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let cutoffStr = Self.dateFormatter.string(from: cutoff)
        return history.filter { $0.date >= cutoffStr }.reduce(0) { $0 + $1.totalCost }
    }

    /// Returns last 30 days of records for chart display, filling gaps with zero-cost entries.
    var chartData: [DailyUsageRecord] {
        let calendar = Calendar.current
        var result: [DailyUsageRecord] = []
        let historyByDate = Dictionary(uniqueKeysWithValues: history.map { ($0.date, $0) })

        for dayOffset in (0..<30).reversed() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date())!
            let dateStr = Self.dateFormatter.string(from: date)
            if let record = historyByDate[dateStr] {
                result.append(record)
            } else {
                result.append(
                    DailyUsageRecord(
                        date: dateStr, totalCost: 0, requestCount: 0,
                        totalInputTokens: 0, totalOutputTokens: 0, providers: [:]
                    ))
            }
        }
        return result
    }

    /// Parse a date string back to Date for chart display.
    static func parseDate(_ dateString: String) -> Date? {
        dateFormatter.date(from: dateString)
    }
}
