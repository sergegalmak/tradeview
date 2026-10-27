import XCTest
#if SWIFT_PACKAGE
@testable import TradeviewCore
#else
@testable import Tradeview
#endif

final class TradeviewTests: XCTestCase {
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
        XCTAssertTrue(history.contains { $0.ticker == "MSFT" && $0.action == .hold })
        XCTAssertTrue(history.contains { $0.ticker == "MSFT" && $0.action == .buy })
    }
}
