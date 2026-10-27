import SwiftUI

enum AppRoute: Hashable {
    case overview
    case screener
    case watchlist
    case portfolio
    case signals
    case alerts
    case disclosure
    case stock(String)
}

struct ContentView: View {
    @State private var route: AppRoute? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $route) {
                Section("Рынок") {
                    sidebarItem("Обзор рынка", icon: "chart.line.uptrend.xyaxis", route: .overview)
                    sidebarItem("Скринер акций", icon: "line.3.horizontal.decrease.circle", route: .screener)
                }
                Section("Мои решения") {
                    sidebarItem("Наблюдение", icon: "eye", route: .watchlist)
                    sidebarItem("Портфель", icon: "briefcase", route: .portfolio)
                    sidebarItem("Уведомления", icon: "bell", route: .alerts)
                }
                Section("Прозрачность") {
                    sidebarItem("История сигналов", icon: "clock.arrow.circlepath", route: .signals)
                    sidebarItem("Ограничения", icon: "exclamationmark.shield", route: .disclosure)
                }
            }
            .navigationTitle("Tradeview")
            .listStyle(.sidebar)
        } detail: {
            VStack(spacing: 0) {
                DataHealthBanner().padding([.horizontal, .top])
                detailView
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch route ?? .overview {
        case .overview:
            MarketOverviewView(openStock: openStock)
        case .screener:
            ScreenerView(openStock: openStock)
        case .watchlist:
            WatchlistView(openStock: openStock)
        case .portfolio:
            PortfolioView()
        case .signals:
            SignalHistoryView(openStock: openStock)
        case .alerts:
            AlertsView()
        case .disclosure:
            DisclosureView()
        case .stock(let ticker):
            StockDetailView(ticker: ticker)
        }
    }

    private func sidebarItem(_ title: String, icon: String, route: AppRoute) -> some View {
        Label(title, systemImage: icon)
            .tag(route)
    }

    private func openStock(_ ticker: String) {
        route = .stock(ticker)
    }
}
