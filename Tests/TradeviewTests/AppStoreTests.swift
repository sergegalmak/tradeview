import XCTest
@testable import Tradeview
#if SWIFT_PACKAGE
@testable import TradeviewCore
#endif

@MainActor
final class AppStoreTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_793_112_600)

    func testPublicQuoteIsIsolatedThrottledAndRetainedAfterFailure() async {
        let provider = SequencePublicProvider()
        let store = AppStore(preferences: MemoryPreferences(), publicQuoteProvider: provider,
                             credentialStore: MemoryCredentials())
        let now = Date()
        await store.refreshPublicQuote(at: now)
        let initial = store.publicQuote
        XCTAssertNotNil(initial)
        XCTAssertTrue(store.snapshot.stocks.isEmpty)
        XCTAssertTrue(store.signalHistory.isEmpty)
        XCTAssertTrue(store.notifications.isEmpty)
        await store.refreshPublicQuote(at: now.addingTimeInterval(1))
        let calls = await provider.calls
        XCTAssertEqual(calls, 1)
        await store.refreshPublicQuote(at: now.addingTimeInterval(61))
        XCTAssertEqual(store.publicQuote, initial)
        XCTAssertNotNil(store.publicQuoteError)
        XCTAssertTrue(store.signalHistory.isEmpty)
    }

    func testBackendFailureDoesNotSubstituteDemo() async {
        let store = AppStore(provider: FailingProvider(), preferences: MemoryPreferences(),
                             credentialStore: MemoryCredentials())
        XCTAssertTrue(store.snapshot.stocks.isEmpty)
        await store.refresh()
        XCTAssertTrue(store.snapshot.stocks.isEmpty)
        XCTAssertNotNil(store.refreshError)
        XCTAssertFalse(store.blockingIssues(at: Date()).isEmpty)
    }

    func testCSVImportIsAtomicAndUnknownQuotesAreRetained() {
        let store = AppStore(preferences: MemoryPreferences(), credentialStore: MemoryCredentials())
        XCTAssertNil(store.importPortfolioCSV("ticker,shares,average_cost\nUNKNOWN,2,100"))
        XCTAssertEqual(store.portfolio.count, 1)
        XCTAssertNotNil(store.importPortfolioCSV("ticker,shares,average_cost\nMSFT,2,100\nJPM,bad,10"))
        XCTAssertEqual(store.portfolio.count, 1)
    }

    func testPortfolioPersistsAndRejectsInfiniteValues() {
        let preferences = MemoryPreferences()
        let store = AppStore(preferences: preferences, credentialStore: MemoryCredentials())
        XCTAssertNil(store.addPortfolioPosition(ticker: " msft ", shares: 2, averageCost: 400))
        XCTAssertNotNil(store.addPortfolioPosition(ticker: "MSFT", shares: .infinity, averageCost: 1))
        let restored = AppStore(preferences: preferences, credentialStore: MemoryCredentials())
        XCTAssertEqual(restored.portfolio.count, 1)
        XCTAssertEqual(restored.portfolio[0].ticker, "MSFT")
    }

    func testArchiveSurvivesRestartAndRepeatRefresh() async {
        let preferences = MemoryPreferences()
        let store = AppStore(provider: MockMarketDataProvider(), preferences: preferences,
                             credentialStore: MemoryCredentials())
        await store.refresh()
        let history = store.signalHistory
        XCTAssertFalse(history.isEmpty)
        await store.refresh()
        XCTAssertEqual(store.signalHistory, history)
        let restored = AppStore(provider: MockMarketDataProvider(), preferences: preferences,
                                credentialStore: MemoryCredentials())
        XCTAssertEqual(restored.signalHistory, history)
    }

    func testCorruptArchiveIsNotOverwritten() async {
        let preferences = MemoryPreferences()
        let corrupt = Data("broken".utf8)
        preferences.set(corrupt, forKey: "tradeview.signalHistory.v2")
        let store = AppStore(provider: MockMarketDataProvider(), preferences: preferences,
                             credentialStore: MemoryCredentials())
        await store.refresh()
        XCTAssertNotNil(store.persistenceError)
        XCTAssertTrue(store.snapshot.stocks.isEmpty)
        XCTAssertEqual(preferences.data(forKey: "tradeview.signalHistory.v2"), corrupt)
    }

    func testAlertRulesPersistButDemoDoesNotGenerateNotifications() async {
        let preferences = MemoryPreferences()
        let store = AppStore(provider: MockMarketDataProvider(), preferences: preferences,
                             credentialStore: MemoryCredentials())
        XCTAssertNil(store.addAlert(ticker: "MSFT", kind: .priceAbove, threshold: 400))
        XCTAssertNotNil(store.addAlert(ticker: "MSFT", kind: .priceAbove, threshold: 400))
        await store.refresh()
        XCTAssertTrue(store.notifications.isEmpty)
        let restored = AppStore(preferences: preferences, credentialStore: MemoryCredentials())
        XCTAssertEqual(restored.alertRules, store.alertRules)
        restored.removeAlert(id: restored.alertRules[0].id)
        XCTAssertTrue(restored.alertRules.isEmpty)
    }

    func testConcurrentRefreshRequestsAreCoalesced() async {
        let provider = CountingProvider()
        let store = AppStore(provider: provider, preferences: MemoryPreferences(),
                             credentialStore: MemoryCredentials())
        let first = Task { await store.refresh() }
        await provider.waitUntilStarted()
        await store.refresh()
        await provider.finish()
        await first.value
        let calls = await provider.calls
        XCTAssertEqual(calls, 1)
    }

    func testAPIKeySavesRestoresAndDeletesWithoutWritingPreferences() {
        let preferences = MemoryPreferences()
        let credentials = MemoryCredentials()
        let store = AppStore(preferences: preferences, credentialStore: credentials)
        XCTAssertFalse(store.hasPersonalAPIKey)
        XCTAssertEqual(credentials.reads, 1)
        XCTAssertTrue(store.saveAPIKey(" \n testcredential \t"))
        XCTAssertTrue(store.hasPersonalAPIKey)
        XCTAssertNil(store.credentialError)
        XCTAssertEqual(credentials.value, "testcredential")
        XCTAssertEqual(credentials.saves, 1)
        XCTAssertTrue(preferences.values.isEmpty, "Credentials must never be written to the UserDefaults abstraction")

        let restored = AppStore(preferences: preferences, credentialStore: credentials)
        XCTAssertTrue(restored.hasPersonalAPIKey)
        XCTAssertNil(restored.credentialError)
        XCTAssertEqual(credentials.reads, 2)
        restored.removeAPIKey()
        XCTAssertFalse(restored.hasPersonalAPIKey)
        XCTAssertNil(restored.credentialError)
        XCTAssertNil(credentials.value)
        XCTAssertEqual(credentials.removals, 1)

        let afterRemoval = AppStore(preferences: preferences, credentialStore: credentials)
        XCTAssertFalse(afterRemoval.hasPersonalAPIKey)
        XCTAssertNil(afterRemoval.credentialError)
        XCTAssertTrue(preferences.values.isEmpty)
    }

    func testInvalidAPIKeysNeverReachCredentialStoreOrPreferences() {
        let preferences = MemoryPreferences()
        let credentials = MemoryCredentials()
        let store = AppStore(preferences: preferences, credentialStore: credentials)
        for value in ["", " \n", "demo", "testcredential testcredential", "testcredential\nAuthorization",
                      "testcredential?", "testcredential/", String(repeating: "testcredential", count: 20)] {
            XCTAssertFalse(store.saveAPIKey(value))
            XCTAssertNotNil(store.credentialError)
            XCTAssertFalse(store.hasPersonalAPIKey)
        }
        XCTAssertEqual(credentials.saves, 0)
        XCTAssertNil(credentials.value)
        XCTAssertTrue(preferences.values.isEmpty)
    }

    func testFailedCredentialWriteBlocksQuotesInsteadOfSilentlyUsingDemoAndCanRecover() async {
        let preferences = MemoryPreferences()
        let credentials = MemoryCredentials()
        credentials.saveError = MemoryCredentialFailure.save
        let provider = ScriptedPublicProvider([.quote(makePublicQuote())])
        let store = AppStore(preferences: preferences, publicQuoteProvider: provider, credentialStore: credentials)
        XCTAssertEqual(credentials.reads, 0, "An injected provider must not read stored credentials")
        XCTAssertFalse(store.saveAPIKey("testcredential"))
        XCTAssertFalse(store.hasPersonalAPIKey)
        XCTAssertNil(credentials.value)
        XCTAssertEqual(store.credentialError, MemoryCredentialFailure.save.localizedDescription)
        await store.refreshPublicQuote(at: referenceDate)
        let blockedRequests = await provider.requestedSymbols
        XCTAssertTrue(blockedRequests.isEmpty)
        XCTAssertNil(store.publicQuote)
        XCTAssertEqual(store.publicQuoteError, store.credentialError)
        XCTAssertEqual(store.quoteErrors["AAPL"], store.credentialError)
        XCTAssertEqual(store.nextPublicQuoteRefreshAt, .distantPast)
        XCTAssertTrue(store.snapshot.stocks.isEmpty)

        credentials.saveError = nil
        XCTAssertTrue(store.saveAPIKey("testcredential"))
        XCTAssertNil(store.credentialError)
        await store.refreshPublicQuote(at: referenceDate)
        XCTAssertEqual(store.publicQuote?.symbol, "AAPL")
        XCTAssertNil(store.publicQuoteError)
        XCTAssertTrue(preferences.values.isEmpty)
    }

    func testFailedCredentialReadIsSurfacedInsteadOfSilentlyTreatingItAsDemo() async {
        let credentials = MemoryCredentials(value: "testcredential")
        credentials.readError = MemoryCredentialFailure.read
        let preferences = MemoryPreferences()
        let store = AppStore(preferences: preferences, credentialStore: credentials)
        XCTAssertEqual(credentials.reads, 1)
        XCTAssertFalse(store.hasPersonalAPIKey)
        XCTAssertEqual(store.credentialError, MemoryCredentialFailure.read.localizedDescription)
        // A non-demo symbol also makes this test network-free if credential handling regresses.
        store.selectPublicSymbol("MSFT")
        await store.refreshPublicQuote(at: referenceDate)
        XCTAssertEqual(store.publicQuoteError, MemoryCredentialFailure.read.localizedDescription)
        XCTAssertEqual(store.quoteErrors["MSFT"], store.credentialError)
        XCTAssertNil(store.publicQuote)
        XCTAssertTrue(store.publicQuotes.isEmpty)
        XCTAssertTrue(store.snapshot.stocks.isEmpty)
        XCTAssertEqual(store.nextPublicQuoteRefreshAt, .distantPast)
        XCTAssertEqual(credentials.value, "testcredential")
        XCTAssertTrue(preferences.values.isEmpty)
    }

    func testFailedCredentialDeletionRetainsCredentialAndBlocksFurtherQuotes() async {
        let credentials = MemoryCredentials(value: "testcredential")
        let preferences = MemoryPreferences()
        let store = AppStore(preferences: preferences, credentialStore: credentials)
        credentials.removeError = MemoryCredentialFailure.remove
        store.removeAPIKey()
        XCTAssertTrue(store.hasPersonalAPIKey)
        XCTAssertEqual(credentials.value, "testcredential")
        XCTAssertEqual(store.credentialError, MemoryCredentialFailure.remove.localizedDescription)
        store.selectPublicSymbol("MSFT")
        // Stay before the throttle's initial boundary as an extra network safety guard.
        await store.refreshPublicQuote(at: Date.distantPast.addingTimeInterval(-1))
        XCTAssertEqual(store.publicQuoteError, MemoryCredentialFailure.remove.localizedDescription)
        XCTAssertNil(store.publicQuote)
        XCTAssertTrue(preferences.values.isEmpty)
        credentials.removeError = nil
        store.removeAPIKey()
        XCTAssertFalse(store.hasPersonalAPIKey)
        XCTAssertNil(store.credentialError)
        XCTAssertNil(credentials.value)
    }

    func testCredentialChangesClearCachedQuotesErrorsAndThrottleWithoutPersistingSecrets() async {
        let preferences = MemoryPreferences()
        let credentials = MemoryCredentials()
        let provider = ScriptedPublicProvider([.quote(makePublicQuote()), .httpFailure(503),
                                               .quote(makePublicQuote(symbol: "MSFT"))])
        let store = AppStore(preferences: preferences, publicQuoteProvider: provider, credentialStore: credentials)
        store.toggleWatchlist(ticker: "MSFT")
        await store.refreshPublicQuote(at: referenceDate)
        store.selectPublicSymbol("MSFT")
        await store.refreshPublicQuote(at: referenceDate.addingTimeInterval(60))
        XCTAssertNotNil(store.quoteErrors["MSFT"])
        XCTAssertNotNil(store.publicQuotes["AAPL"])

        XCTAssertTrue(store.saveAPIKey("testcredential"))
        XCTAssertTrue(store.publicQuotes.isEmpty)
        XCTAssertTrue(store.quoteErrors.isEmpty)
        XCTAssertNil(store.publicQuote)
        XCTAssertNil(store.publicQuoteError)
        XCTAssertEqual(store.nextPublicQuoteRefreshAt, .distantPast)
        XCTAssertEqual(store.selectedPublicSymbol, "MSFT")
        await store.refreshPublicQuote(at: referenceDate.addingTimeInterval(60))
        XCTAssertEqual(store.publicQuote?.symbol, "MSFT")

        store.removeAPIKey()
        XCTAssertFalse(store.hasPersonalAPIKey)
        XCTAssertTrue(store.publicQuotes.isEmpty)
        XCTAssertTrue(store.quoteErrors.isEmpty)
        XCTAssertNil(store.publicQuote)
        XCTAssertNil(store.publicQuoteError)
        XCTAssertEqual(store.nextPublicQuoteRefreshAt, .distantPast)
        XCTAssertEqual(store.watchlist, ["MSFT"])
        XCTAssertEqual(Set(preferences.values.keys), ["tradeview.watchlist"])
        XCTAssertFalse(preferences.values.values.contains { String(decoding: $0, as: UTF8.self).contains("testcredential") })
    }

    func testSelectedSymbolCachesAndErrorsRemainIsolatedAndRecoverIndependently() async {
        let apple = makePublicQuote()
        let microsoft = makePublicQuote(symbol: "MSFT", price: 200)
        let provider = ScriptedPublicProvider([.quote(apple), .failure(.provider(500, "MSFT unavailable")),
                                               .quote(microsoft), .httpFailure(503)])
        let store = AppStore(preferences: MemoryPreferences(), publicQuoteProvider: provider,
                             credentialStore: MemoryCredentials())
        await store.refreshPublicQuote(at: referenceDate)
        XCTAssertEqual(store.publicQuote, apple)
        store.selectPublicSymbol("MSFT")
        XCTAssertNil(store.publicQuote)
        XCTAssertNil(store.publicQuoteError)
        await store.refreshPublicQuote(at: referenceDate.addingTimeInterval(60))
        let microsoftError = store.publicQuoteError
        XCTAssertNotNil(microsoftError)
        XCTAssertNil(store.publicQuotes["MSFT"])
        XCTAssertEqual(store.publicQuotes["AAPL"], apple)

        store.selectPublicSymbol("AAPL")
        XCTAssertEqual(store.publicQuote, apple)
        XCTAssertNil(store.publicQuoteError)
        store.selectPublicSymbol("MSFT")
        XCTAssertNil(store.publicQuote)
        XCTAssertEqual(store.publicQuoteError, microsoftError)
        await store.refreshPublicQuote(at: referenceDate.addingTimeInterval(120))
        XCTAssertEqual(store.publicQuote, microsoft)
        XCTAssertNil(store.publicQuoteError)
        XCTAssertNil(store.quoteErrors["MSFT"])

        store.selectPublicSymbol("AAPL")
        await store.refreshPublicQuote(at: referenceDate.addingTimeInterval(180))
        XCTAssertEqual(store.publicQuote, apple)
        XCTAssertNotNil(store.publicQuoteError)
        XCTAssertNotNil(store.quoteErrors["AAPL"])
        store.selectPublicSymbol("MSFT")
        XCTAssertEqual(store.publicQuote, microsoft)
        XCTAssertNil(store.publicQuoteError)
        XCTAssertTrue(store.snapshot.stocks.isEmpty)
        XCTAssertTrue(store.signalHistory.isEmpty)
        XCTAssertTrue(store.notifications.isEmpty)
        let symbols = await provider.requestedSymbols
        XCTAssertEqual(symbols, ["AAPL", "MSFT", "MSFT", "AAPL"])
    }

    func testQuoteThrottleAndBoth429BackoffsAreGlobalAcrossSymbols() async {
        let failures: [ScriptedPublicProvider.Step] = [.failure(.provider(429, "Rate limited")), .httpFailure(429)]
        for failure in failures {
            let provider = ScriptedPublicProvider([.quote(makePublicQuote()), failure,
                                                   .quote(makePublicQuote(symbol: "MSFT"))])
            let store = AppStore(preferences: MemoryPreferences(), publicQuoteProvider: provider,
                                 credentialStore: MemoryCredentials())
            await store.refreshPublicQuote(at: referenceDate)
            XCTAssertEqual(store.nextPublicQuoteRefreshAt, referenceDate.addingTimeInterval(60))
            store.selectPublicSymbol("MSFT")
            await store.refreshPublicQuote(at: referenceDate.addingTimeInterval(59))
            let throttled = await provider.requestedSymbols
            XCTAssertEqual(throttled, ["AAPL"])
            await store.refreshPublicQuote(at: referenceDate.addingTimeInterval(60))
            XCTAssertNotNil(store.publicQuoteError)
            XCTAssertEqual(store.nextPublicQuoteRefreshAt, referenceDate.addingTimeInterval(960))

            store.selectPublicSymbol("AAPL")
            await store.refreshPublicQuote(at: referenceDate.addingTimeInterval(959))
            XCTAssertNil(store.publicQuoteError, "MSFT's error must not leak to AAPL during global backoff")
            let backoffRequests = await provider.requestedSymbols
            XCTAssertEqual(backoffRequests, ["AAPL", "MSFT"])
            store.selectPublicSymbol("MSFT")
            await store.refreshPublicQuote(at: referenceDate.addingTimeInterval(960))
            XCTAssertEqual(store.publicQuote?.symbol, "MSFT")
            XCTAssertNil(store.publicQuoteError)
            XCTAssertNil(store.quoteErrors["MSFT"])
            XCTAssertEqual(store.nextPublicQuoteRefreshAt, referenceDate.addingTimeInterval(1_020))
            let recovered = await provider.requestedSymbols
            XCTAssertEqual(recovered, ["AAPL", "MSFT", "MSFT"])
        }
    }

    func testQuoteTimestampsAreMonotonicPerSymbolNotAcrossSymbols() async {
        let apple = makePublicQuote(quoteAt: referenceDate)
        let microsoft = makePublicQuote(symbol: "MSFT", quoteAt: referenceDate.addingTimeInterval(-100))
        let older = makePublicQuote(symbol: "MSFT", quoteAt: referenceDate.addingTimeInterval(-101), price: 1)
        let newer = makePublicQuote(symbol: "MSFT", quoteAt: referenceDate.addingTimeInterval(1), price: 201)
        let provider = ScriptedPublicProvider([.quote(apple), .quote(microsoft), .quote(older), .quote(newer)])
        let store = AppStore(preferences: MemoryPreferences(), publicQuoteProvider: provider,
                             credentialStore: MemoryCredentials())
        await store.refreshPublicQuote(at: referenceDate)
        store.selectPublicSymbol("MSFT")
        await store.refreshPublicQuote(at: referenceDate.addingTimeInterval(60))
        XCTAssertEqual(store.publicQuote, microsoft, "MSFT is allowed to be older than a different symbol")
        XCTAssertNil(store.publicQuoteError)
        await store.refreshPublicQuote(at: referenceDate.addingTimeInterval(120))
        XCTAssertEqual(store.publicQuote, microsoft)
        XCTAssertEqual(store.publicQuotes["MSFT"], microsoft)
        XCTAssertEqual(store.publicQuoteError, PublicQuoteError.invalidData.localizedDescription)
        await store.refreshPublicQuote(at: referenceDate.addingTimeInterval(180))
        XCTAssertEqual(store.publicQuote, newer)
        XCTAssertNil(store.publicQuoteError)
        XCTAssertEqual(store.publicQuotes["AAPL"], apple)
    }

    func testWrongSymbolResponseIsNotCachedUnderRequestedSymbol() async {
        let provider = ScriptedPublicProvider([.quote(makePublicQuote())])
        let store = AppStore(preferences: MemoryPreferences(), publicQuoteProvider: provider,
                             credentialStore: MemoryCredentials())
        store.selectPublicSymbol("MSFT")
        await store.refreshPublicQuote(at: referenceDate)
        XCTAssertTrue(store.publicQuotes.isEmpty)
        XCTAssertNil(store.publicQuote)
        XCTAssertEqual(store.quoteErrors["MSFT"], PublicQuoteError.invalidData.localizedDescription)
        XCTAssertNil(store.quoteErrors["AAPL"])
    }

    func testInFlightQuoteCoalescesRequestsAndDoesNotReplaceNewSelection() async {
        let provider = ControlledPublicProvider()
        let store = AppStore(preferences: MemoryPreferences(), publicQuoteProvider: provider,
                             credentialStore: MemoryCredentials())
        let now = referenceDate
        let first = Task { await store.refreshPublicQuote(at: now) }
        await provider.waitUntilStarted()
        XCTAssertTrue(store.isRefreshingPublicQuote)
        store.selectPublicSymbol("MSFT")
        await store.refreshPublicQuote(at: now.addingTimeInterval(120))
        let requests = await provider.requestedSymbols
        XCTAssertEqual(requests, ["AAPL"])
        let apple = makePublicQuote()
        await provider.finish(with: apple)
        await first.value
        XCTAssertFalse(store.isRefreshingPublicQuote)
        XCTAssertEqual(store.selectedPublicSymbol, "MSFT")
        XCTAssertNil(store.publicQuote)
        XCTAssertNil(store.publicQuoteError)
        XCTAssertEqual(store.publicQuotes["AAPL"], apple)
        XCTAssertNil(store.publicQuotes["MSFT"])
        XCTAssertEqual(store.nextPublicQuoteRefreshAt, now.addingTimeInterval(60))
        store.selectPublicSymbol("AAPL")
        XCTAssertEqual(store.publicQuote, apple)
    }

    func testCredentialChangesDiscardInFlightQuoteAndErrorFromOldGeneration() async {
        for remove in [false, true] {
            let provider = ControlledPublicProvider()
            let credentials = MemoryCredentials()
            let store = AppStore(preferences: MemoryPreferences(), publicQuoteProvider: provider,
                                 credentialStore: credentials)
            XCTAssertTrue(store.saveAPIKey("testcredential"))
            let now = referenceDate
            let first = Task { await store.refreshPublicQuote(at: now) }
            await provider.waitUntilStarted()
            if remove { store.removeAPIKey() }
            else { XCTAssertTrue(store.saveAPIKey("testcredential")) }
            if remove { await provider.fail(with: .provider(429, "Old request failed")) }
            else { await provider.finish(with: makePublicQuote()) }
            await first.value
            XCTAssertEqual(store.hasPersonalAPIKey, !remove)
            XCTAssertFalse(store.isRefreshingPublicQuote)
            XCTAssertNil(store.publicQuote)
            XCTAssertNil(store.publicQuoteError)
            XCTAssertTrue(store.publicQuotes.isEmpty)
            XCTAssertTrue(store.quoteErrors.isEmpty)
            XCTAssertEqual(store.nextPublicQuoteRefreshAt, .distantPast)
        }
    }

    func testAppStoreRedactsEchoedCredentialInInjectedProviderFailure() async {
        let provider = ScriptedPublicProvider([.failure(.provider(401, "Invalid testcredential; testcredential"))])
        let store = AppStore(preferences: MemoryPreferences(), publicQuoteProvider: provider,
                             credentialStore: MemoryCredentials())
        XCTAssertTrue(store.saveAPIKey("testcredential"))
        await store.refreshPublicQuote(at: referenceDate)
        XCTAssertEqual(store.publicQuoteError, "Twelve Data (401): Invalid [redacted]; [redacted]")
        XCTAssertEqual(store.quoteErrors["AAPL"], store.publicQuoteError)
        XCTAssertFalse(store.publicQuoteError?.contains("testcredential") ?? true)
    }

    func testCatalogLoadsWithoutSyntheticSnapshotThrottlesDailyAndRetainsDataAfterFailure() async {
        let instruments = [PublicInstrument(symbol: "MSFT", name: "Microsoft Corporation", exchange: "NASDAQ", currency: "USD")]
        let provider = SequenceCatalogProvider([.instruments(instruments), .failure, .instruments(instruments)])
        let preferences = MemoryPreferences()
        let store = AppStore(provider: FailingProvider(), preferences: preferences, catalogProvider: provider,
                             credentialStore: MemoryCredentials())
        await store.refreshStockCatalog(at: referenceDate)
        XCTAssertEqual(store.instruments, instruments)
        XCTAssertEqual(store.catalogUpdatedAt, referenceDate)
        XCTAssertEqual(store.nextCatalogRefreshAt, referenceDate.addingTimeInterval(86_400))
        XCTAssertNil(store.catalogError)
        XCTAssertFalse(store.isLoadingCatalog)
        await store.refreshStockCatalog(at: referenceDate.addingTimeInterval(86_399))
        let dailyCalls = await provider.calls
        XCTAssertEqual(dailyCalls, 1)

        await store.refreshStockCatalog(at: referenceDate.addingTimeInterval(86_400))
        XCTAssertEqual(store.instruments, instruments)
        XCTAssertEqual(store.catalogUpdatedAt, referenceDate)
        XCTAssertEqual(store.nextCatalogRefreshAt, referenceDate.addingTimeInterval(86_460))
        XCTAssertEqual(store.catalogError, DataSourceError.serverStatus(503).localizedDescription)
        XCTAssertFalse(store.isLoadingCatalog)
        await store.refreshStockCatalog(at: referenceDate.addingTimeInterval(86_459))
        let failedCalls = await provider.calls
        XCTAssertEqual(failedCalls, 2)
        await store.refreshStockCatalog(at: referenceDate.addingTimeInterval(86_460))
        XCTAssertEqual(store.instruments, instruments)
        XCTAssertEqual(store.catalogUpdatedAt, referenceDate.addingTimeInterval(86_460))
        XCTAssertEqual(store.nextCatalogRefreshAt, referenceDate.addingTimeInterval(172_860))
        XCTAssertNil(store.catalogError)
        let recoveredCalls = await provider.calls
        XCTAssertEqual(recoveredCalls, 3)
        XCTAssertTrue(store.snapshot.stocks.isEmpty)
        XCTAssertTrue(store.signalHistory.isEmpty)
        XCTAssertTrue(store.notifications.isEmpty)
        XCTAssertTrue(store.alertRules.isEmpty)
        XCTAssertNil(store.refreshError)
        XCTAssertNil(store.publicQuote)
        XCTAssertTrue(preferences.values.isEmpty)
    }

    func testEmptyCatalogIsAnErrorAndCannotReplacePreviouslyLoadedInstruments() async {
        let instruments = [PublicInstrument(symbol: "AAPL", name: "Apple Inc.", exchange: "NASDAQ", currency: "USD")]
        let provider = SequenceCatalogProvider([.instruments([]), .instruments(instruments), .instruments([])])
        let store = AppStore(preferences: MemoryPreferences(), catalogProvider: provider,
                             credentialStore: MemoryCredentials())
        await store.refreshStockCatalog(at: referenceDate)
        XCTAssertTrue(store.instruments.isEmpty)
        XCTAssertNil(store.catalogUpdatedAt)
        XCTAssertEqual(store.catalogError, PublicQuoteError.invalidData.localizedDescription)
        XCTAssertEqual(store.nextCatalogRefreshAt, referenceDate.addingTimeInterval(60))
        await store.refreshStockCatalog(at: referenceDate.addingTimeInterval(59))
        let throttledCalls = await provider.calls
        XCTAssertEqual(throttledCalls, 1)
        await store.refreshStockCatalog(at: referenceDate.addingTimeInterval(60))
        XCTAssertEqual(store.instruments, instruments)
        XCTAssertNil(store.catalogError)
        await store.refreshStockCatalog(at: referenceDate.addingTimeInterval(86_460))
        XCTAssertEqual(store.instruments, instruments)
        XCTAssertEqual(store.catalogUpdatedAt, referenceDate.addingTimeInterval(60))
        XCTAssertEqual(store.catalogError, PublicQuoteError.invalidData.localizedDescription)
        XCTAssertTrue(store.snapshot.stocks.isEmpty)
    }

    func testTickerWatchlistNormalizesPersistsRestoresAndTogglesWithoutSnapshot() throws {
        let preferences = MemoryPreferences()
        let store = AppStore(preferences: preferences, credentialStore: MemoryCredentials())
        store.toggleWatchlist(ticker: " \nmsft ")
        store.toggleWatchlist(ticker: "brk.b")
        store.toggleWatchlist(ticker: " \n\t")
        XCTAssertEqual(store.watchlist, ["MSFT", "BRK.B"])
        XCTAssertTrue(store.snapshot.stocks.isEmpty)
        let data = try XCTUnwrap(preferences.data(forKey: "tradeview.watchlist"))
        XCTAssertEqual(try JSONDecoder().decode(Set<String>.self, from: data), ["MSFT", "BRK.B"])
        let restored = AppStore(preferences: preferences, credentialStore: MemoryCredentials())
        XCTAssertEqual(restored.watchlist, store.watchlist)
        restored.toggleWatchlist(ticker: " mSfT \n")
        XCTAssertEqual(restored.watchlist, ["BRK.B"])
        let afterRemoval = AppStore(preferences: preferences, credentialStore: MemoryCredentials())
        XCTAssertEqual(afterRemoval.watchlist, ["BRK.B"])
        XCTAssertEqual(Set(preferences.values.keys), ["tradeview.watchlist"])
    }

    func testNavigationBackTraversesHistoryAndSafelyStopsAtHome() {
        var navigation = AppNavigation()
        XCTAssertEqual(navigation.route, .publicQuotes)
        XCTAssertFalse(navigation.canGoBack)
        navigation.back()
        XCTAssertEqual(navigation.route, .publicQuotes)
        navigation.navigate(.screener)
        navigation.navigate(.publicStock("MSFT"))
        navigation.navigate(.watchlist)
        XCTAssertTrue(navigation.canGoBack)
        navigation.back()
        XCTAssertEqual(navigation.route, .publicStock("MSFT"))
        navigation.back()
        XCTAssertEqual(navigation.route, .screener)
        navigation.back()
        XCTAssertEqual(navigation.route, .publicQuotes)
        XCTAssertTrue(navigation.history.isEmpty)
        XCTAssertFalse(navigation.canGoBack)
        navigation.back()
        XCTAssertEqual(navigation, AppNavigation())
    }

    func testNavigationHomeClearsHistoryAndIsIdempotentWithoutShowingSidebar() {
        var navigation = AppNavigation()
        navigation.navigate(.portfolio)
        navigation.navigate(.stock("MSFT"))
        navigation.toggleSidebar()
        navigation.home()
        XCTAssertEqual(navigation.route, .publicQuotes)
        XCTAssertTrue(navigation.history.isEmpty)
        XCTAssertFalse(navigation.canGoBack)
        XCTAssertFalse(navigation.isSidebarVisible)
        let home = navigation
        navigation.home()
        navigation.back()
        XCTAssertEqual(navigation, home)
    }

    func testNavigationIgnoresConsecutiveDuplicatesButRetainsRealRevisits() {
        var navigation = AppNavigation()
        navigation.navigate(.publicQuotes)
        XCTAssertTrue(navigation.history.isEmpty)
        navigation.navigate(.publicStock("MSFT"))
        let first = navigation
        navigation.navigate(.publicStock("MSFT"))
        XCTAssertEqual(navigation, first)
        navigation.navigate(.publicStock("AAPL"))
        navigation.navigate(.publicStock("MSFT"))
        XCTAssertEqual(navigation.history, [.publicQuotes, .publicStock("MSFT"), .publicStock("AAPL")])
        navigation.back()
        XCTAssertEqual(navigation.route, .publicStock("AAPL"))
        navigation.navigate(.publicQuotes)
        XCTAssertTrue(navigation.canGoBack, "Navigating home is distinct from clearing history with home()")
    }

    func testNavigationSidebarToggleOnlyChangesVisibility() {
        var navigation = AppNavigation()
        navigation.navigate(.screener)
        navigation.navigate(.publicStock("MSFT"))
        let before = navigation
        navigation.toggleSidebar()
        XCTAssertFalse(navigation.isSidebarVisible)
        XCTAssertEqual(navigation.route, before.route)
        XCTAssertEqual(navigation.history, before.history)
        XCTAssertEqual(navigation.canGoBack, before.canGoBack)
        navigation.toggleSidebar()
        XCTAssertEqual(navigation, before)
    }

    func testOnlyResearchRoutesRequestResearchSnapshots() {
        for route in [AppRoute.publicQuotes, .screener, .watchlist, .publicStock("MSFT")] {
            XCTAssertFalse(route.isResearch)
        }
        for route in [AppRoute.overview, .portfolio, .signals, .alerts, .disclosure, .stock("MSFT")] {
            XCTAssertTrue(route.isResearch)
        }
    }
}

private final class MemoryPreferences: AppPreferenceStore {
    private(set) var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data, forKey key: String) { values[key] = data }
}

private final class MemoryCredentials: APICredentialStore {
    private(set) var value: String?
    private(set) var reads = 0
    private(set) var saves = 0
    private(set) var removals = 0
    var readError: (any Error)?
    var saveError: (any Error)?
    var removeError: (any Error)?

    init(value: String? = nil) { self.value = value }

    func read() throws -> String? {
        reads += 1
        if let readError { throw readError }
        return value
    }

    func save(_ value: String) throws {
        saves += 1
        if let saveError { throw saveError }
        self.value = value
    }

    func remove() throws {
        removals += 1
        if let removeError { throw removeError }
        value = nil
    }
}

private enum MemoryCredentialFailure: LocalizedError {
    case read, save, remove
    var errorDescription: String? {
        switch self {
        case .read: return "Credential fixture read failed"
        case .save: return "Credential fixture write failed"
        case .remove: return "Credential fixture deletion failed"
        }
    }
}

private func makePublicQuote(symbol: String = "AAPL",
                             quoteAt: Date = Date(timeIntervalSince1970: 1_793_112_540),
                             price: Double = 100) -> PublicQuote {
    PublicQuote(symbol: symbol, name: symbol == "MSFT" ? "Microsoft Corporation" : "Apple Inc.",
        exchange: "NASDAQ", currency: "USD", price: price, changePercentage: 1, quoteAt: quoteAt,
        receivedAt: Date(timeIntervalSince1970: 1_793_112_600), exchangeTimeZone: "America/New_York",
        isMarketOpen: true, dailyPrices: [])
}

private actor ScriptedPublicProvider: PublicQuoteProviding {
    enum Step: Sendable {
        case quote(PublicQuote)
        case failure(PublicQuoteError)
        case httpFailure(Int)
    }
    private var steps: [Step]
    private(set) var requestedSymbols: [String] = []

    init(_ steps: [Step]) { self.steps = steps }

    func loadQuote() async throws -> PublicQuote { try await loadQuote(symbol: "AAPL") }

    func loadQuote(symbol: String) async throws -> PublicQuote {
        requestedSymbols.append(symbol)
        guard !steps.isEmpty else { throw DataSourceError.invalidResponse }
        switch steps.removeFirst() {
        case .quote(let quote): return quote
        case .failure(let error): throw error
        case .httpFailure(let code): throw DataSourceError.serverStatus(code)
        }
    }
}

private actor ControlledPublicProvider: PublicQuoteProviding {
    private(set) var requestedSymbols: [String] = []
    private var started: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<PublicQuote, any Error>?

    func loadQuote() async throws -> PublicQuote { try await loadQuote(symbol: "AAPL") }

    func loadQuote(symbol: String) async throws -> PublicQuote {
        requestedSymbols.append(symbol)
        guard pending == nil else { throw DataSourceError.invalidResponse }
        return try await withCheckedThrowingContinuation {
            pending = $0
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if requestedSymbols.isEmpty { await withCheckedContinuation { started = $0 } }
    }

    func finish(with quote: PublicQuote) {
        pending?.resume(returning: quote)
        pending = nil
    }

    func fail(with error: PublicQuoteError) {
        pending?.resume(throwing: error)
        pending = nil
    }
}

private actor SequenceCatalogProvider: StockCatalogProviding {
    enum Step: Sendable {
        case instruments([PublicInstrument])
        case failure
    }
    private var steps: [Step]
    private(set) var calls = 0

    init(_ steps: [Step]) { self.steps = steps }

    func loadInstruments() async throws -> [PublicInstrument] {
        calls += 1
        guard !steps.isEmpty else { throw DataSourceError.invalidResponse }
        switch steps.removeFirst() {
        case .instruments(let instruments): return instruments
        case .failure: throw DataSourceError.serverStatus(503)
        }
    }
}

private struct FailingProvider: MarketDataProviding {
    func loadSnapshot() async throws -> MarketSnapshot { throw DataSourceError.serverStatus(503) }
}

private actor SequencePublicProvider: PublicQuoteProviding {
    private(set) var calls = 0
    func loadQuote() async throws -> PublicQuote {
        calls += 1
        guard calls == 1 else { throw DataSourceError.serverStatus(429) }
        return PublicQuote(symbol: "AAPL", name: "Apple Inc.", exchange: "NASDAQ", currency: "USD",
            price: 100, changePercentage: 1, quoteAt: Date(), receivedAt: Date(),
            exchangeTimeZone: "America/New_York", isMarketOpen: true, dailyPrices: [])
    }
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