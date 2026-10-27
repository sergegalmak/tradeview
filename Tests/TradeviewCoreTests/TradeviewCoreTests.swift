import XCTest
#if SWIFT_PACKAGE
@testable import TradeviewCore
#else
@testable import Tradeview
#endif

final class TradeviewCoreTests: XCTestCase {
    func testScreenerFiltersByActionAndConfidence() {
        let snapshot = MockMarketData.makeSnapshot()
        let filters = ScreenerFilters(
            query: "",
            sector: nil,
            action: .buy,
            minimumConfidence: 0.75
        )

        let results = ScreenerEngine.filteredStocks(
            snapshot.stocks,
            filters: filters,
            sort: .signalStrength
        )

        XCTAssertEqual(results.map(\.ticker), ["MSFT", "GOOGL"])
        XCTAssertTrue(results.allSatisfy { $0.signal.action == .buy && $0.signal.confidence >= 0.75 })
    }

    func testPortfolioAnalysisFlagsSinglePositionConcentration() {
        let snapshot = MockMarketData.makeSnapshot()
        let analysis = PortfolioAnalyzer.analyze(
            positions: [PortfolioPosition(ticker: "MSFT", shares: 10, averageCost: 400)],
            stocks: snapshot.stocks
        )

        XCTAssertEqual(analysis.allocations.count, 1)
        XCTAssertEqual(analysis.allocations.first?.weight ?? 0, 1, accuracy: 0.0001)
        XCTAssertTrue(analysis.warnings.contains { $0.contains("MSFT") })
        XCTAssertTrue(analysis.warnings.contains { $0.contains("диверсификация") })
    }

    func testBackendClientRejectsNonHTTPSAPI() async {
        let client = BackendAPIClient(endpoint: URL(string: "http://example.test/market")!)

        do {
            _ = try await client.loadSnapshot()
            XCTFail("Expected insecure endpoint to be rejected")
        } catch let error as DataSourceError {
            XCTAssertEqual(error, .insecureEndpoint)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDemoSignalHistoryContainsPriorAndCurrentSignals() {
        let history = MockMarketData.makeSnapshot().signalHistory

        XCTAssertGreaterThan(history.count, 1)
        XCTAssertTrue(history.contains { $0.ticker == "MSFT" && $0.signal.action == .hold })
        XCTAssertTrue(history.contains { $0.ticker == "MSFT" && $0.signal.action == .buy })
    }

    func testDemoIsValidHistoricalAndHasNoPublishedProbabilities() throws {
        let snapshot = MockMarketData.makeSnapshot()
        _ = try snapshot.validated(at: snapshot.source.updatedAt.addingTimeInterval(60))
        XCTAssertTrue(snapshot.stocks.allSatisfy { $0.signal.publishedProbability == nil })
        XCTAssertFalse(snapshot.source.blockingIssues(at: snapshot.source.updatedAt).isEmpty)
    }

    func testExactHorizons() {
        XCTAssertEqual(InvestmentHorizon.allCases.map(\.rawValue), [1, 3, 6, 12])
    }

    func testDuplicateLotsAreAggregated() {
        let stocks = MockMarketData.makeSnapshot().stocks
        let result = PortfolioAnalyzer.analyze(positions: [
            PortfolioPosition(ticker: " msft ", shares: 2, averageCost: 400),
            PortfolioPosition(ticker: "MSFT", shares: 3, averageCost: 420)
        ], stocks: stocks)
        XCTAssertEqual(result.allocations.count, 1)
        XCTAssertEqual(result.totalMarketValue ?? 0, 5 * 462.8, accuracy: 0.001)
        XCTAssertEqual(result.pricedCost, 2 * 400 + 3 * 420)
        XCTAssertEqual(result.allocations[0].weight, 1)
    }

    func testMissingQuoteDoesNotBecomeZeroOrInventLoss() {
        let result = PortfolioAnalyzer.analyze(positions: [
            PortfolioPosition(ticker: "MSFT", shares: 1, averageCost: 400),
            PortfolioPosition(ticker: "UNKNOWN", shares: 1, averageCost: 800)
        ], stocks: MockMarketData.makeSnapshot().stocks)
        XCTAssertNil(result.totalMarketValue)
        XCTAssertNil(result.unrealizedGain)
        XCTAssertEqual(result.pricedCost, 400)
        XCTAssertEqual(result.unpricedTickers, ["UNKNOWN"])
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testDuplicateQuotesDoNotCrashOrChooseAnArbitraryPrice() {
        let stock = MockMarketData.makeSnapshot().stocks[0]
        let result = PortfolioAnalyzer.analyze(positions: [PortfolioPosition(ticker: stock.ticker, shares: 1, averageCost: 1)], stocks: [stock, stock])
        XCTAssertNil(result.totalMarketValue)
        XCTAssertEqual(result.unpricedTickers, [stock.ticker])
    }

    func testInvalidPortfolioNumbersAreRejected() {
        for value in [Double.infinity, -.infinity, .nan, -1, 0] {
            XCTAssertFalse(PortfolioPosition(ticker: "MSFT", shares: value, averageCost: 1).isValid)
        }
        XCTAssertFalse(PortfolioPosition(ticker: "MSFT", shares: 1, averageCost: .infinity).isValid)
        XCTAssertTrue(PortfolioPosition(ticker: "MSFT", shares: 1, averageCost: 0).isValid)
        let result = PortfolioAnalyzer.analyze(positions: [PortfolioPosition(ticker: "MSFT", shares: .nan, averageCost: 1)], stocks: [])
        XCTAssertNil(result.unrealizedGain)
        XCTAssertEqual(result.invalidPositionCount, 1)
    }

    func testEmptyPortfolioIsWellDefined() {
        let result = PortfolioAnalyzer.analyze(positions: [], stocks: [])
        XCTAssertEqual(result.totalMarketValue, 0)
        XCTAssertEqual(result.unrealizedGain, 0)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testCSVQuotedCRLFBOMAndSeparateLots() throws {
        let rows = try PortfolioCSV.parse("\u{FEFF}ticker,shares,average_cost\r\n\" msft \",2,400.5\r\nMSFT,3,420\r\n")
        XCTAssertEqual(rows.map(\.ticker), ["MSFT", "MSFT"])
        XCTAssertEqual(rows[0].averageCost, 400.5)
    }

    func testCSVRejectsBadHeadersRowsAndNonFiniteValues() {
        for text in ["symbol,shares,cost\nMSFT,1,1", "ticker,shares,average_cost", "ticker,shares,average_cost\nMSFT,1",
                     "ticker,shares,average_cost\nMSFT,inf,1", "ticker,shares,average_cost\nMSFT,-1,1",
                     "ticker,shares,average_cost\n\"MSFT,1,1", "ticker,shares,average_cost\n\"MSFT\"x,1,1"] {
            XCTAssertThrowsError(try PortfolioCSV.parse(text), text)
        }
    }

    func testValidationRejectsDuplicateTickersAndOutOfRangeConfidence() throws {
        let snapshot = MockMarketData.makeSnapshot()
        let duplicate = MarketSnapshot(source: snapshot.source, indices: snapshot.indices,
            stocks: [snapshot.stocks[0], snapshot.stocks[0]], signalHistory: [])
        XCTAssertThrowsError(try duplicate.validated(at: snapshot.source.updatedAt))
        let invalid = try transformed(snapshot) { object in
            var stocks = object["stocks"] as! [[String: Any]]
            var signal = stocks[0]["signal"] as! [String: Any]
            signal["confidence"] = 1.01
            stocks[0]["signal"] = signal; object["stocks"] = stocks
        }
        XCTAssertThrowsError(try invalid.validated(at: snapshot.source.updatedAt))
    }

    func testPointInTimeRejectsPublicationAfterCutoff() throws {
        let snapshot = MockMarketData.makeSnapshot()
        let invalid = try transformed(snapshot) { object in
            var stocks = object["stocks"] as! [[String: Any]]
            var provenance = stocks[0]["provenance"] as! [[String: Any]]
            provenance[0]["receivedAt"] = snapshot.source.updatedAt.timeIntervalSinceReferenceDate + 1
            stocks[0]["provenance"] = provenance; object["stocks"] = stocks
        }
        XCTAssertThrowsError(try invalid.validated(at: snapshot.source.updatedAt))
        XCTAssertThrowsError(try snapshot.validated(at: snapshot.source.updatedAt.addingTimeInterval(-1)))
    }

    func testProbabilityRequiresEnoughMatchingCalibrationEvidence() throws {
        let signal = MockMarketData.makeSnapshot().stocks[0].signal
        XCTAssertNil(signal.publishedProbability)
        func calibrated(samples: Int, model: String, horizon: InvestmentHorizon = signal.horizon) throws -> InvestmentSignal {
            try transformed(signal) { object in
                var event = object["explicitEvent"] as! [String: Any]
                event["probability"] = 0.68
                let evidence = CalibrationEvidence(eventID: signal.explicitEvent.id, modelVersion: model,
                    horizon: horizon, sampleCount: samples, brierScore: 0.2, evaluatedAt: signal.generatedAt, reportID: "held-out-report")
                event["calibration"] = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence))
                object["explicitEvent"] = event
            }
        }
        XCTAssertNil(try calibrated(samples: 199, model: signal.modelVersion).publishedProbability)
        XCTAssertNil(try calibrated(samples: 500, model: "wrong-model").publishedProbability)
        XCTAssertNil(try calibrated(samples: 500, model: signal.modelVersion, horizon: .oneMonth).publishedProbability)
        XCTAssertEqual(try calibrated(samples: 500, model: signal.modelVersion).publishedProbability, 0.68)
    }

    func testDataQualityFreshnessAndRightsGate() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func source(quality: DataQuality = .complete, validUntil: Date = now.addingTimeInterval(60), rights: Bool = true) -> DataSourceInfo {
            DataSourceInfo(name: "Licensed feed", updatedAt: now, modelVersion: "1", isOfflineDemo: false,
                featureVersion: "1", validUntil: validUntil, quality: quality, displayRightsConfirmed: rights)
        }
        XCTAssertTrue(source().blockingIssues(at: now).isEmpty)
        XCTAssertFalse(source(quality: .degraded).blockingIssues(at: now).isEmpty)
        XCTAssertFalse(source(validUntil: now).blockingIssues(at: now).isEmpty)
        XCTAssertFalse(source(rights: false).blockingIssues(at: now).isEmpty)
    }

    func testArchiveDeduplicatesAndRejectsRewrites() throws {
        let item = MockMarketData.makeSnapshot().signalHistory[0]
        XCTAssertEqual(try SignalArchive.merging([item], with: [item]), [item])
        let changed = try transformed(item) { object in
            var signal = object["signal"] as! [String: Any]
            signal["rationale"] = "Переписанный прошлый прогноз"
            object["signal"] = signal
        }
        XCTAssertThrowsError(try SignalArchive.merging([item], with: [changed]))
    }

    func testFinancialFiltersAndWhitespaceSearch() {
        let stocks = MockMarketData.makeSnapshot().stocks
        let results = ScreenerEngine.filteredStocks(stocks,
            filters: ScreenerFilters(query: "  googl ", minimumMarketCapBillions: 100, maximumPE: 30), sort: .valuation)
        XCTAssertEqual(results.map(\.ticker), ["GOOGL"])
        XCTAssertTrue(ScreenerEngine.filteredStocks(stocks,
            filters: ScreenerFilters(query: "MSFT", maximumPE: 30), sort: .valuation).isEmpty)
    }

    func testArchivePreservesOriginalIssuanceWhenEnvelopeChanges() throws {
        let snapshot = MockMarketData.makeSnapshot()
        let original = try snapshot.archiveRecords(preserving: [])
        let refreshed = try transformed(snapshot) { object in
            var source = object["source"] as! [String: Any]
            source["updatedAt"] = snapshot.source.updatedAt.timeIntervalSinceReferenceDate + 60
            object["source"] = source
            object["signalHistory"] = []
        }
        _ = try refreshed.validated(at: snapshot.source.updatedAt.addingTimeInterval(120))
        XCTAssertEqual(try refreshed.archiveRecords(preserving: original), original)
    }

    func testEventDeadlineMustMatchSignalHorizon() throws {
        let snapshot = MockMarketData.makeSnapshot()
        let invalid = try transformed(snapshot) { object in
            var stocks = object["stocks"] as! [[String: Any]]
            var signal = stocks[0]["signal"] as! [String: Any]
            var event = signal["explicitEvent"] as! [String: Any]
            event["expectedBy"] = snapshot.source.updatedAt.timeIntervalSinceReferenceDate + 3_600
            signal["explicitEvent"] = event; stocks[0]["signal"] = signal; object["stocks"] = stocks
        }
        XCTAssertThrowsError(try invalid.validated(at: snapshot.source.updatedAt))
    }

    func testLocalAlertsFireOnlyOnFreshTransitions() throws {
        let demo = MockMarketData.makeSnapshot()
        let before = try transformed(demo) { object in
            var source = object["source"] as! [String: Any]
            source["isOfflineDemo"] = false; source["displayRightsConfirmed"] = true
            object["source"] = source
        }
        let after = try transformed(before) { object in
            var source = object["source"] as! [String: Any]
            source["updatedAt"] = before.source.updatedAt.timeIntervalSinceReferenceDate + 60
            object["source"] = source
            var stocks = object["stocks"] as! [[String: Any]]
            stocks[0]["price"] = 250.0
            var signal = stocks[0]["signal"] as! [String: Any]
            signal["action"] = InvestmentAction.buy.rawValue
            stocks[0]["signal"] = signal; object["stocks"] = stocks
        }
        let rules = [AlertRule(ticker: "AAPL", kind: .newBuy), AlertRule(ticker: "AAPL", kind: .priceAbove, threshold: 240)]
        let now = after.source.updatedAt
        let events = AlertEngine.evaluate(rules: rules, previous: before, current: after, at: now)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events, AlertEngine.evaluate(rules: rules, previous: before, current: after, at: now))
        XCTAssertTrue(AlertEngine.evaluate(rules: rules, previous: after, current: after, at: now).isEmpty)
        XCTAssertTrue(AlertEngine.evaluate(rules: rules, previous: .empty, current: after, at: now).isEmpty)
        XCTAssertTrue(AlertEngine.evaluate(rules: rules, previous: demo, current: after, at: now).isEmpty)
        XCTAssertTrue(AlertEngine.evaluate(rules: rules, previous: before, current: after, at: after.source.validUntil).isEmpty)
    }

    func testLocalAlertsSuppressDegradedDataAndRejectInvalidRules() throws {
        let snapshot = MockMarketData.makeSnapshot()
        let degraded = try transformed(snapshot) { object in
            var source = object["source"] as! [String: Any]
            source["quality"] = "degraded"; source["isOfflineDemo"] = false; source["displayRightsConfirmed"] = true
            object["source"] = source
        }
        XCTAssertTrue(AlertEngine.evaluate(rules: [AlertRule(ticker: "MSFT", kind: .newBuy)], previous: snapshot,
            current: degraded, at: degraded.source.updatedAt).isEmpty)
        XCTAssertFalse(AlertRule(ticker: "MSFT", kind: .priceAbove, threshold: .infinity).isValid)
        XCTAssertFalse(AlertRule(ticker: "MSFT", kind: .priceAbove).isValid)
    }

    func testAPIConfigurationNeverSilentlyFallsBackToDemo() async {
        let provider = MarketDataConfiguration(environment: ["TRADEVIEW_API_URL": "http://example.test/market"])
        do { _ = try await provider.loadSnapshot(); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? DataSourceError, .insecureEndpoint) }
    }

    func testAPIHandlesHTTPFailureMalformedJSONAndValidSnapshot() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); StubURLProtocol.responseData = nil }
        let client = BackendAPIClient(endpoint: URL(string: "https://example.test/market")!, session: session)
        StubURLProtocol.statusCode = 503
        do { _ = try await client.loadSnapshot(); XCTFail("Expected 503") }
        catch { XCTAssertEqual(error as? DataSourceError, .serverStatus(503)) }
        StubURLProtocol.statusCode = 200
        StubURLProtocol.responseData = Data("not JSON".utf8)
        do { _ = try await client.loadSnapshot(); XCTFail("Expected decoding error") } catch { }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        StubURLProtocol.responseData = try encoder.encode(MockMarketData.makeSnapshot())
        let snapshot = try await client.loadSnapshot()
        XCTAssertEqual(snapshot.stocks.count, 10)
    }

    private func transformed<T: Codable>(_ value: T, edit: (inout [String: Any]) -> Void) throws -> T {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        edit(&object)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

private final class StubURLProtocol: URLProtocol {
    static var statusCode = 200
    static var responseData: Data?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
