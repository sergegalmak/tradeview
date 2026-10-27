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
    @Published private(set) var publicQuote: PublicQuote?
    @Published private(set) var isRefreshingPublicQuote = false
    @Published private(set) var publicQuoteError: String?
    @Published private(set) var nextPublicQuoteRefreshAt = Date.distantPast
    @Published var stockSearchQuery = ""
    @Published private(set) var instruments: [PublicInstrument] = []
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var catalogError: String?
    @Published private(set) var catalogUpdatedAt: Date?
    @Published private(set) var nextCatalogRefreshAt = Date.distantPast
    @Published private(set) var publicQuotes: [String: PublicQuote] = [:]
    @Published private(set) var quoteErrors: [String: String] = [:]
    @Published private(set) var selectedPublicSymbol = "AAPL"
    @Published private(set) var hasPersonalAPIKey = false
    @Published private(set) var credentialError: String?

    private let provider: any MarketDataProviding
    private let publicQuoteProvider: (any PublicQuoteProviding)?
    private let catalogProvider: any StockCatalogProviding
    private let credentialStore: any APICredentialStore
    private var personalAPIKey: String?
    private var credentialGeneration = 0
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
        preferences: any AppPreferenceStore = UserDefaultsPreferenceStore(),
        publicQuoteProvider: (any PublicQuoteProviding)? = nil,
        catalogProvider: any StockCatalogProviding = TwelveDataPublicClient(),
        credentialStore: any APICredentialStore = KeychainAPICredentialStore()
    ) {
        self.provider = provider
        self.publicQuoteProvider = publicQuoteProvider
        self.catalogProvider = catalogProvider
        self.credentialStore = credentialStore
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
        // Injected providers are self-contained and never touch the user's Keychain.
        if publicQuoteProvider == nil {
            do {
                personalAPIKey = try credentialStore.read()
                hasPersonalAPIKey = personalAPIKey != nil
            } catch { credentialError = error.localizedDescription }
        }
    }

    @discardableResult
    func saveAPIKey(_ input: String) -> Bool {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "demo", value.count <= 256,
              value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            credentialError = "Введите личный ключ Twelve Data (без пробелов)."
            return false
        }
        do {
            try credentialStore.save(value)
            personalAPIKey = value
            hasPersonalAPIKey = true
            credentialError = nil
            resetPublicQuotes()
            return true
        } catch { credentialError = error.localizedDescription; return false }
    }

    func removeAPIKey() {
        do {
            try credentialStore.remove()
            personalAPIKey = nil
            hasPersonalAPIKey = false
            credentialError = nil
            resetPublicQuotes()
        } catch { credentialError = error.localizedDescription }
    }

    private func resetPublicQuotes() {
        credentialGeneration += 1
        publicQuote = nil
        publicQuotes = [:]
        quoteErrors = [:]
        publicQuoteError = nil
        nextPublicQuoteRefreshAt = .distantPast
    }

    func selectPublicSymbol(_ symbol: String) {
        selectedPublicSymbol = symbol
        publicQuote = publicQuotes[symbol]
        publicQuoteError = quoteErrors[symbol]
    }

    /// One lifecycle per active window, independent of the selected page.
    /// Multiple windows share request coalescing and rate limits below.
    func runPublicUpdates() async {
        while !Task.isCancelled {
            async let quote: Void = refreshPublicQuote()
            async let catalog: Void = refreshStockCatalog()
            _ = await (quote, catalog)
            do { try await Task.sleep(for: .seconds(60)) }
            catch { return }
        }
    }

    func refreshStockCatalog(at now: Date = Date()) async {
        guard !isLoadingCatalog, now >= nextCatalogRefreshAt else { return }
        isLoadingCatalog = true
        nextCatalogRefreshAt = now.addingTimeInterval(60)
        defer { isLoadingCatalog = false }
        do {
            let incoming = try await catalogProvider.loadInstruments()
            try Task.checkCancellation()
            guard !incoming.isEmpty else { throw PublicQuoteError.invalidData }
            instruments = incoming
            catalogUpdatedAt = now
            nextCatalogRefreshAt = now.addingTimeInterval(24 * 3_600)
            catalogError = nil
        } catch is CancellationError {
            nextCatalogRefreshAt = .distantPast
        } catch let error as URLError where error.code == .cancelled {
            nextCatalogRefreshAt = .distantPast
        } catch { catalogError = error.localizedDescription }
    }

    func toggleWatchlist(ticker: String) {
        let ticker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !ticker.isEmpty else { return }
        if watchlist.contains(ticker) { watchlist.remove(ticker) }
        else { watchlist.insert(ticker) }
        persist(watchlist, key: Key.watchlist)
    }

    /// Independent of research snapshots: never archives or fabricates a signal.
    func refreshPublicQuote(at now: Date = Date()) async {
        let symbol = selectedPublicSymbol
        if let credentialError {
            publicQuoteError = credentialError
            quoteErrors[symbol] = credentialError
            return
        }
        if publicQuoteProvider == nil, !hasPersonalAPIKey, symbol != "AAPL" {
            let message = PublicQuoteError.personalKeyRequired.localizedDescription
            publicQuoteError = message
            quoteErrors[symbol] = message
            return
        }
        guard !isRefreshingPublicQuote, now >= nextPublicQuoteRefreshAt else { return }
        let generation = credentialGeneration
        isRefreshingPublicQuote = true
        nextPublicQuoteRefreshAt = now.addingTimeInterval(60)
        defer { isRefreshingPublicQuote = false }
        do {
            let source: any PublicQuoteProviding = publicQuoteProvider ?? TwelveDataPublicClient(apiKey: personalAPIKey)
            let incoming = try await source.loadQuote(symbol: symbol)
            try Task.checkCancellation()
            guard generation == credentialGeneration else { return }
            guard incoming.symbol == symbol else { throw PublicQuoteError.invalidData }
            if let previous = publicQuotes[symbol], incoming.quoteAt < previous.quoteAt {
                throw PublicQuoteError.invalidData
            }
            publicQuotes[symbol] = incoming
            quoteErrors[symbol] = nil
            if selectedPublicSymbol == symbol {
                publicQuote = incoming
                publicQuoteError = nil
            }
        } catch is CancellationError {
            if generation == credentialGeneration { nextPublicQuoteRefreshAt = .distantPast }
        } catch let error as URLError where error.code == .cancelled {
            if generation == credentialGeneration { nextPublicQuoteRefreshAt = .distantPast }
        } catch {
            guard generation == credentialGeneration else { return }
            var message = error.localizedDescription
            if let personalAPIKey { message = message.replacingOccurrences(of: personalAPIKey, with: "[redacted]") }
            quoteErrors[symbol] = message
            if selectedPublicSymbol == symbol { publicQuoteError = message }
            if case PublicQuoteError.provider(429, _) = error {
                nextPublicQuoteRefreshAt = now.addingTimeInterval(15 * 60)
            } else if case DataSourceError.serverStatus(429) = error {
                nextPublicQuoteRefreshAt = now.addingTimeInterval(15 * 60)
            }
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
