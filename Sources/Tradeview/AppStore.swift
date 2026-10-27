import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot: MarketSnapshot
    @Published private(set) var watchlist: Set<String>
    @Published private(set) var portfolio: [PortfolioPosition]
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshError: String?

    private let provider: any MarketDataProviding
    private let preferences: any AppPreferenceStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Key {
        static let watchlist = "tradeview.watchlist"
        static let portfolio = "tradeview.portfolio"
    }

    init(
        provider: any MarketDataProviding = MockMarketDataProvider(),
        preferences: any AppPreferenceStore = UserDefaultsPreferenceStore()
    ) {
        self.provider = provider
        self.preferences = preferences
        self.snapshot = MockMarketDataProvider.snapshot
        self.watchlist = Self.load(Set<String>.self, from: preferences, key: Key.watchlist) ?? []
        self.portfolio = Self.load([PortfolioPosition].self, from: preferences, key: Key.portfolio) ?? []
    }

    func refresh() async {
        isRefreshing = true
        refreshError = nil
        defer { isRefreshing = false }

        do {
            snapshot = try await provider.loadSnapshot()
        } catch {
            refreshError = error.localizedDescription
        }
    }

    func stock(ticker: String) -> Stock? {
        snapshot.stock(ticker: ticker)
    }

    func isWatched(_ stock: Stock) -> Bool {
        watchlist.contains(stock.ticker)
    }

    func toggleWatchlist(_ stock: Stock) {
        if watchlist.contains(stock.ticker) {
            watchlist.remove(stock.ticker)
        } else {
            watchlist.insert(stock.ticker)
        }
        persist(watchlist, key: Key.watchlist)
    }

    func addPortfolioPosition(ticker: String, shares: Double, averageCost: Double) -> String? {
        let normalizedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard snapshot.stock(ticker: normalizedTicker) != nil else {
            return "Тикер \(normalizedTicker.isEmpty ? "не указан" : normalizedTicker) отсутствует в текущем наборе данных."
        }
        guard shares > 0, averageCost > 0 else {
            return "Количество и средняя цена должны быть больше нуля."
        }
        portfolio.append(
            PortfolioPosition(ticker: normalizedTicker, shares: shares, averageCost: averageCost)
        )
        persist(portfolio, key: Key.portfolio)
        return nil
    }

    func removePortfolioPositions(at offsets: IndexSet) {
        portfolio.remove(atOffsets: offsets)
        persist(portfolio, key: Key.portfolio)
    }

    func loadDemoPortfolio() {
        portfolio = [
            PortfolioPosition(ticker: "MSFT", shares: 12, averageCost: 420),
            PortfolioPosition(ticker: "GOOGL", shares: 16, averageCost: 172),
            PortfolioPosition(ticker: "JPM", shares: 18, averageCost: 286)
        ]
        persist(portfolio, key: Key.portfolio)
    }

    func clearPortfolio() {
        portfolio = []
        persist(portfolio, key: Key.portfolio)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        preferences.set(data, forKey: key)
    }

    private static func load<T: Decodable>(
        _ type: T.Type,
        from preferences: any AppPreferenceStore,
        key: String
    ) -> T? {
        guard let data = preferences.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
