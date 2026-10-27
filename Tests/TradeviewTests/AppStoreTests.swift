import XCTest
@testable import Tradeview
#if SWIFT_PACKAGE
@testable import TradeviewCore
#endif

@MainActor
final class AppStoreTests: XCTestCase {
    func testBackendFailureDoesNotSubstituteDemo() async {
        let store = AppStore(provider: FailingProvider(), preferences: MemoryPreferences())
        XCTAssertTrue(store.snapshot.stocks.isEmpty)
        await store.refresh()
        XCTAssertTrue(store.snapshot.stocks.isEmpty)
        XCTAssertNotNil(store.refreshError)
        XCTAssertFalse(store.blockingIssues(at: Date()).isEmpty)
    }

    func testCSVImportIsAtomicAndUnknownQuotesAreRetained() {
        let store = AppStore(preferences: MemoryPreferences())
        XCTAssertNil(store.importPortfolioCSV("ticker,shares,average_cost\nUNKNOWN,2,100"))
        XCTAssertEqual(store.portfolio.count, 1)
        XCTAssertNotNil(store.importPortfolioCSV("ticker,shares,average_cost\nMSFT,2,100\nJPM,bad,10"))
        XCTAssertEqual(store.portfolio.count, 1)
    }

    func testPortfolioPersistsAndRejectsInfiniteValues() {
        let preferences = MemoryPreferences()
        let store = AppStore(preferences: preferences)
        XCTAssertNil(store.addPortfolioPosition(ticker: " msft ", shares: 2, averageCost: 400))
        XCTAssertNotNil(store.addPortfolioPosition(ticker: "MSFT", shares: .infinity, averageCost: 1))
        let restored = AppStore(preferences: preferences)
        XCTAssertEqual(restored.portfolio.count, 1)
        XCTAssertEqual(restored.portfolio[0].ticker, "MSFT")
    }

    func testArchiveSurvivesRestartAndRepeatRefresh() async {
        let preferences = MemoryPreferences()
        let store = AppStore(provider: MockMarketDataProvider(), preferences: preferences)
        await store.refresh()
        let history = store.signalHistory
        XCTAssertFalse(history.isEmpty)
        await store.refresh()
        XCTAssertEqual(store.signalHistory, history)
        let restored = AppStore(provider: MockMarketDataProvider(), preferences: preferences)
        XCTAssertEqual(restored.signalHistory, history)
    }

    func testCorruptArchiveIsNotOverwritten() async {
        let preferences = MemoryPreferences()
        let corrupt = Data("broken".utf8)
        preferences.set(corrupt, forKey: "tradeview.signalHistory.v2")
        let store = AppStore(provider: MockMarketDataProvider(), preferences: preferences)
        await store.refresh()
        XCTAssertNotNil(store.persistenceError)
        XCTAssertTrue(store.snapshot.stocks.isEmpty)
        XCTAssertEqual(preferences.data(forKey: "tradeview.signalHistory.v2"), corrupt)
    }

    func testAlertRulesPersistButDemoDoesNotGenerateNotifications() async {
        let preferences = MemoryPreferences()
        let store = AppStore(provider: MockMarketDataProvider(), preferences: preferences)
        XCTAssertNil(store.addAlert(ticker: "MSFT", kind: .priceAbove, threshold: 400))
        XCTAssertNotNil(store.addAlert(ticker: "MSFT", kind: .priceAbove, threshold: 400))
        await store.refresh()
        XCTAssertTrue(store.notifications.isEmpty)
        let restored = AppStore(preferences: preferences)
        XCTAssertEqual(restored.alertRules, store.alertRules)
        restored.removeAlert(id: restored.alertRules[0].id)
        XCTAssertTrue(restored.alertRules.isEmpty)
    }

    func testConcurrentRefreshRequestsAreCoalesced() async {
        let provider = CountingProvider()
        let store = AppStore(provider: provider, preferences: MemoryPreferences())
        let first = Task { await store.refresh() }
        await provider.waitUntilStarted()
        await store.refresh()
        await provider.finish()
        await first.value
        let calls = await provider.calls
        XCTAssertEqual(calls, 1)
    }
}

private final class MemoryPreferences: AppPreferenceStore {
    private var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data, forKey key: String) { values[key] = data }
}

private struct FailingProvider: MarketDataProviding {
    func loadSnapshot() async throws -> MarketSnapshot { throw DataSourceError.serverStatus(503) }
}

private actor CountingProvider: MarketDataProviding {
    private(set) var calls = 0
    private var started: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<MarketSnapshot, Never>?
    func loadSnapshot() async throws -> MarketSnapshot {
        calls += 1
        started?.resume(); started = nil
        return await withCheckedContinuation { pending = $0 }
    }
    func waitUntilStarted() async {
        if calls == 0 { await withCheckedContinuation { started = $0 } }
    }
    func finish() {
        pending?.resume(returning: MockMarketData.makeSnapshot()); pending = nil
    }
}