import Combine
import Foundation
#if SWIFT_PACKAGE
import TradeviewCore
#endif

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot: MarketSnapshot
    @Published private(set) var watchlist: Set<String>
    @Published private(set) var portfolio: [PortfolioPosition]
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshError: String?
    @Published private(set) var signalHistory: [SignalHistoryItem]
    @Published private(set) var persistenceError: String?
    @Published private(set) var alertRules: [AlertRule]
    @Published private(set) var notifications: [AlertNotification]

    private let provider: any MarketDataProviding
    private let preferences: any AppPreferenceStore
    private let encoder = JSONEncoder()

    private enum Key {
        static let watchlist = "tradeview.watchlist"
        static let portfolio = "tradeview.portfolio"
        static let history = "tradeview.signalHistory.v2"
        static let alerts = "tradeview.alertRules.v1"
        static let notifications = "tradeview.notifications.v1"
    }

    init(
        provider: any MarketDataProviding = MarketDataConfiguration(environment: ProcessInfo.processInfo.environment),
        preferences: any AppPreferenceStore = UserDefaultsPreferenceStore()
    ) {
        self.provider = provider
        self.preferences = preferences
        self.snapshot = .empty
        self.watchlist = Self.load(Set<String>.self, from: preferences, key: Key.watchlist) ?? []
        self.portfolio = Self.load([PortfolioPosition].self, from: preferences, key: Key.portfolio) ?? []
        self.alertRules = Self.load([AlertRule].self, from: preferences, key: Key.alerts) ?? []
        self.notifications = Self.load([AlertNotification].self, from: preferences, key: Key.notifications) ?? []
        if let data = preferences.data(forKey: Key.history) {
            do {
                self.signalHistory = try SignalArchive.merging([], with: JSONDecoder().decode([SignalHistoryItem].self, from: data))
            } catch {
                self.signalHistory = []
                self.persistenceError = "Архив повреждён; обновление заблокировано, исходные данные сохранены."
            }
        } else {
            self.signalHistory = []
        }
    }

    func refresh() async {
        guard !isRefreshing, persistenceError == nil else { return }
        let recoveringFromFailure = refreshError != nil
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let incoming = try await provider.loadSnapshot().validated()
            try Task.checkCancellation()
            guard snapshot.stocks.isEmpty || incoming.source.isOfflineDemo != snapshot.source.isOfflineDemo ||
                  incoming.source.updatedAt >= snapshot.source.updatedAt else {
                throw DataSourceError.invalidSnapshot("Получен более старый срез данных.")
            }
            // Demo/live IDs are namespaced; switching providers never erases old records.
            let merged = try incoming.archiveRecords(preserving: signalHistory)
            let data = try encoder.encode(merged)
            preferences.set(data, forKey: Key.history)
            if !recoveringFromFailure {
                let newNotifications = AlertEngine.evaluate(rules: alertRules, previous: snapshot, current: incoming, at: Date())
                let knownIDs = Set(notifications.map(\.id))
                notifications = Array((newNotifications.filter { !knownIDs.contains($0.id) } + notifications).prefix(500))
                persist(notifications, key: Key.notifications)
            }
            signalHistory = merged
            snapshot = incoming
            refreshError = nil
        } catch is CancellationError {
            // Cancellation is not a provider failure.
        } catch {
            refreshError = error.localizedDescription
        }
    }

    func stock(ticker: String) -> Stock? {
        snapshot.stock(ticker: ticker)
    }

    func blockingIssues(at now: Date) -> [String] {
        snapshot.source.blockingIssues(at: now) + [refreshError, persistenceError].compactMap { $0 }
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
        let position = PortfolioPosition(ticker: normalizedTicker, shares: shares, averageCost: averageCost)
        guard position.isValid else {
            return "Укажите тикер, конечное положительное количество и неотрицательную цену."
        }
        // Separate lots are retained for editing; the analyzer aggregates exposure by ticker.
        portfolio.append(position)
        persist(portfolio, key: Key.portfolio)
        return nil
    }

    func removePortfolioPositions(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where portfolio.indices.contains(index) { portfolio.remove(at: index) }
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

    func importPortfolioCSV(_ text: String) -> String? {
        do {
            let imported = try PortfolioCSV.parse(text)
            let candidate = portfolio + imported
            let data = try encoder.encode(candidate)
            portfolio = candidate
            preferences.set(data, forKey: Key.portfolio)
            return nil
        } catch { return error.localizedDescription }
    }

    func addAlert(ticker: String, kind: AlertKind, threshold: Double?) -> String? {
        let rule = AlertRule(ticker: ticker, kind: kind, threshold: threshold)
        guard rule.isValid else { return "Укажите тикер и положительный конечный уровень цены." }
        guard !alertRules.contains(where: { $0.ticker == rule.ticker && $0.kind == rule.kind && $0.threshold == rule.threshold }) else {
            return "Такое правило уже существует."
        }
        alertRules.append(rule)
        persist(alertRules, key: Key.alerts)
        return nil
    }

    func removeAlert(id: UUID) {
        alertRules.removeAll { $0.id == id }
        persist(alertRules, key: Key.alerts)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        do {
            preferences.set(try encoder.encode(value), forKey: key)
        } catch {
            persistenceError = "Не удалось сохранить изменения: \(error.localizedDescription)"
        }
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
