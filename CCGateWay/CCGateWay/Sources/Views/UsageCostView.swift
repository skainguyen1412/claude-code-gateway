import Charts
import SwiftUI

struct UsageCostView: View {
    @EnvironmentObject var server: GatewayServer
    @EnvironmentObject var config: GatewayConfig
    @EnvironmentObject var usageStore: UsageStore

    let columns = [
        GridItem(.flexible()), GridItem(.flexible()),
        GridItem(.flexible()), GridItem(.flexible()),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Usage & Cost")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // ZONE 1: Summary Cards
                LazyVGrid(columns: columns, spacing: 16) {
                    MetricCard(
                        title: "Today's Cost",
                        value: formatCost(usageStore.todayRecord.totalCost),
                        icon: "dollarsign.circle.fill"
                    )
                    MetricCard(
                        title: "Today's Requests",
                        value: "\(usageStore.todayRecord.requestCount)",
                        icon: "arrow.left.arrow.right"
                    )
                    MetricCard(
                        title: "7-Day Total",
                        value: formatCost(usageStore.last7DaysCost),
                        icon: "calendar.badge.clock"
                    )
                    MetricCard(
                        title: "30-Day Total",
                        value: formatCost(usageStore.last30DaysCost),
                        icon: "calendar"
                    )
                }

                // ZONE 2: 30-Day Cost Trend
                VStack(alignment: .leading, spacing: 10) {
                    Text("30-Day Cost Trend")
                        .font(.headline)

                    Chart(usageStore.chartData) { record in
                        if let date = UsageStore.parseDate(record.date) {
                            BarMark(
                                x: .value("Date", date, unit: .day),
                                y: .value("Cost", record.totalCost)
                            )
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .cornerRadius(4)
                        }
                    }
                    .frame(height: 250)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            AxisGridLine()
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let cost = value.as(Double.self) {
                                    Text(formatCost(cost))
                                }
                            }
                            AxisGridLine()
                        }
                    }
                }
                .padding(20)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )

                // ZONE 3: Provider Breakdown (Today)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Today's Provider Breakdown")
                        .font(.headline)

                    if usageStore.todayRecord.providers.isEmpty {
                        HStack {
                            Image(systemName: "tray")
                                .foregroundColor(.secondary)
                            Text("No usage today")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        let sorted = usageStore.todayRecord.providers
                            .sorted { $0.value.cost > $1.value.cost }
                        let maxCost = sorted.first?.value.cost ?? 1.0
                        let totalCost = usageStore.todayRecord.totalCost

                        ForEach(sorted, id: \.key) { providerName, usage in
                            ProviderBreakdownRow(
                                name: providerName,
                                cost: usage.cost,
                                requests: usage.requests,
                                percentage: totalCost > 0 ? usage.cost / totalCost : 0,
                                barFraction: maxCost > 0 ? usage.cost / maxCost : 0
                            )
                        }
                    }
                }
                .padding(20)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )

                Spacer()
            }
            .padding()
        }
    }

    private func formatCost(_ cost: Double) -> String {
        if cost == 0 { return "$0" }
        if cost < 0.0001 { return "<$0.0001" }
        if cost >= 1.0 {
            return String(format: "$%.2f", cost)
        }
        return String(format: "$%.4f", cost)
    }
}

struct ProviderBreakdownRow: View {
    let name: String
    let cost: Double
    let requests: Int
    let percentage: Double
    let barFraction: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(name)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                Text("\(requests) req")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Text(String(format: "$%.4f", cost))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))

                Text(String(format: "%.0f%%", percentage * 100))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * barFraction, 4), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}
