import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case providers = "Providers"
    case presets = "Presets"
    case logs = "Request Log"
    case usage = "Usage & Cost"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "gauge"
        case .providers: return "network"
        case .presets: return "slider.horizontal.3"
        case .logs: return "list.bullet.rectangle.fill"
        case .usage: return "chart.bar.fill"
        case .settings: return "gearshape"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var config: GatewayConfig
    @EnvironmentObject var server: GatewayServer
    @State private var selectedTab: DashboardTab = .overview

    var body: some View {
        NavigationSplitView {
            List(DashboardTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationTitle("CCGateWay")
        } detail: {
            detailView(for: selectedTab)
                .environmentObject(config)
                .environmentObject(server)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    @ViewBuilder
    private func detailView(for tab: DashboardTab) -> some View {
        switch tab {
        case .overview:
            OverviewView()
        case .providers:
            ProvidersView()
        case .presets:
            PresetsView()
        case .logs:
            RequestLogView()
        case .usage:
            UsageCostView()
        case .settings:
            SettingsView()
        }
    }
}
