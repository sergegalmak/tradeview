import SwiftUI

enum AppRoute: Hashable {
    case publicQuotes
    case overview
    case screener
    case watchlist
    case portfolio
    case signals
    case alerts
    case disclosure
    case stock(String)
    case publicStock(String)

    var title: String {
        switch self {
        case .publicQuotes: return "Публичные котировки"
        case .overview: return "Обзор рынка"
        case .screener: return "Скринер акций"
        case .watchlist: return "Наблюдение"
        case .portfolio: return "Портфель"
        case .signals: return "История сигналов"
        case .alerts: return "Уведомления"
        case .disclosure: return "Ограничения"
        case .stock(let ticker): return "\(ticker) · Исследование"
        case .publicStock(let ticker): return ticker
        }
    }

    var isResearch: Bool {
        switch self {
        case .overview, .portfolio, .signals, .alerts, .disclosure, .stock:
            return true
        case .publicQuotes, .screener, .watchlist, .publicStock:
            return false
        }
    }
}

struct AppNavigation: Equatable {
    private(set) var route: AppRoute = .publicQuotes
    private(set) var history: [AppRoute] = []
    private(set) var isSidebarVisible = true

    var canGoBack: Bool {
        route != .publicQuotes || !history.isEmpty
    }

    mutating func navigate(_ destination: AppRoute) {
        guard destination != route else { return }
        history.append(route)
        route = destination
    }

    mutating func back() {
        route = history.popLast() ?? .publicQuotes
    }

    mutating func home() {
        route = .publicQuotes
        history.removeAll()
    }

    mutating func toggleSidebar() {
        isSidebarVisible.toggle()
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = AppNavigation()

    var body: some View {
        HStack(spacing: 0) {
            if navigation.isSidebarVisible {
                sidebar
                    .frame(width: 235)
                    .frame(maxHeight: .infinity)
                    .clipped()
                    .layoutPriority(1)
                Divider()
            }

            VStack(spacing: 0) {
                topBar
                Divider()

                if navigation.route.isResearch {
                    DataHealthBanner().padding([.horizontal, .top])
                }

                detailView
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .task(id: navigation.route) {
            if navigation.route.isResearch, store.snapshot.stocks.isEmpty {
                await store.refresh()
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active {
                await store.runPublicUpdates()
            }
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Tradeview")
                    .font(.title2.bold())
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 4) {
                    sidebarHeading("Рынок")
                    sidebarItem(.publicQuotes, icon: "network")
                    sidebarItem(.overview, icon: "chart.line.uptrend.xyaxis")
                    sidebarItem(.screener, icon: "line.3.horizontal.decrease.circle")
                }

                VStack(alignment: .leading, spacing: 4) {
                    sidebarHeading("Мои решения")
                    sidebarItem(.watchlist, icon: "eye")
                    sidebarItem(.portfolio, icon: "briefcase")
                    sidebarItem(.alerts, icon: "bell")
                }

                VStack(alignment: .leading, spacing: 4) {
                    sidebarHeading("Прозрачность")
                    sidebarItem(.signals, icon: "clock.arrow.circlepath")
                    sidebarItem(.disclosure, icon: "exclamationmark.shield")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.bar)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                navigation.back()
            } label: {
                Label("Назад", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .disabled(!navigation.canGoBack)
            .help("Назад")

            Button {
                navigation.home()
            } label: {
                Label("Главное меню", systemImage: "house")
            }
            .fixedSize()

            Button {
                navigation.toggleSidebar()
            } label: {
                Label(navigation.isSidebarVisible ? "Скрыть меню" : "Показать меню", systemImage: "sidebar.left")
            }
            .fixedSize()

            Spacer(minLength: 0)

            TextField("Поиск по тикеру или названию", text: $store.stockSearchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140, maxWidth: 420)
                .onSubmit { navigation.navigate(.screener) }
                .accessibilityLabel("Поиск по тикеру или названию")

            Button {
                navigation.navigate(.screener)
            } label: {
                Label("Поиск", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .help("Найти акции")
        }
        .padding(12)
        .background(.bar)
    }

    @ViewBuilder
    private var detailView: some View {
        switch navigation.route {
        case .publicQuotes:
            PublicQuotesView()
        case .overview:
            MarketOverviewView(openStock: openResearchStock)
        case .screener:
            ScreenerView(openStock: openPublicStock)
        case .watchlist:
            WatchlistView(openStock: openPublicStock)
        case .portfolio:
            PortfolioView()
        case .signals:
            SignalHistoryView(openStock: openResearchStock)
        case .alerts:
            AlertsView()
        case .disclosure:
            DisclosureView()
        case .stock(let ticker):
            StockDetailView(ticker: ticker)
        case .publicStock(let ticker):
            CatalogStockDetailView(ticker: ticker)
        }
    }

    private func sidebarHeading(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
    }

    private func sidebarItem(_ route: AppRoute, icon: String) -> some View {
        Button {
            navigation.navigate(route)
        } label: {
            Label(route.title, systemImage: icon)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
                .background {
                    if navigation.route == route {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.accentColor.opacity(0.16))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func openResearchStock(_ ticker: String) {
        navigation.navigate(.stock(ticker))
    }

    private func openPublicStock(_ ticker: String) {
        navigation.navigate(.publicStock(ticker))
    }
}
