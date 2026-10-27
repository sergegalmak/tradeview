import XCTest
#if SWIFT_PACKAGE
@testable import TradeviewCore
#else
@testable import Tradeview
#endif

final class PublicQuotesTests: XCTestCase {
    private let receivedAt = Date(timeIntervalSince1970: 1_793_112_600)

    func testParsesStringsSortsBarsAndPreservesProviderTimestamp() async throws {
        let quote = try await client().loadQuote()
        XCTAssertEqual(quote.symbol, "AAPL")
        XCTAssertEqual(quote.price, 346.03)
        XCTAssertEqual(quote.changePercentage, 0.61643928)
        XCTAssertEqual(quote.quoteAt, Date(timeIntervalSince1970: 1_793_112_540))
        XCTAssertEqual(quote.receivedAt, receivedAt)
        XCTAssertEqual(quote.dailyPrices.map(\.close), [343.91, 346.03])
        // October 27 midnight in New York is 04:00 UTC, not midnight UTC.
        XCTAssertEqual(quote.dailyPrices.last?.date, ISO8601DateFormatter().date(from: "2026-10-27T04:00:00Z"))
        XCTAssertFalse(quote.isStale(at: receivedAt))
        XCTAssertTrue(quote.isStale(at: receivedAt.addingTimeInterval(901)))
    }

    func testHTTP200ProviderErrorIsNotDecodedAsAQuote() async {
        do {
            _ = try await client(mode: "providerError").loadQuote()
            XCTFail("Expected rate limit error")
        } catch {
            XCTAssertEqual(error as? PublicQuoteError, .provider(429, "Trial limit reached"))
        }
    }

    func testHTTPFailureIsSurfaced() async {
        do {
            _ = try await client(mode: "httpError").loadQuote()
            XCTFail("Expected HTTP error")
        } catch { XCTAssertEqual(error as? DataSourceError, .serverStatus(503)) }
    }

    func testRejectsWrongSymbolCurrencyAndInterval() async {
        for mode in ["symbol", "currency", "interval"] { await assertInvalid(mode) }
    }

    func testRejectsNonFiniteAndNegativePrices() async {
        for mode in ["nan", "negative", "badBar"] { await assertInvalid(mode) }
    }

    func testRejectsFutureQuoteOrBar() async {
        for mode in ["futureQuote", "futureBar"] { await assertInvalid(mode) }
    }

    func testRejectsDuplicateDatesAndInvalidTimezone() async {
        for mode in ["duplicate", "timezone", "badDate"] { await assertInvalid(mode) }
    }

    func testRejectsMalformedAndMissingData() async {
        for mode in ["malformed", "empty", "missingTimestamp"] { await assertInvalid(mode) }
    }

    func testAuthenticatedSymbolsUseMatchingQuoteAndSeriesWithHeaderOnlyCredentials() async throws {
        // This fixture accepts only the exact Authorization header and endpoint parameters;
        // a credential in the URL or a mismatched request symbol fails the request.
        let provider = client(mode: "authenticatedMSFT", apiKey: "testcredential")
        for symbol in ["AAPL", "MSFT", "AAPL"] {
            let quote = try await provider.loadQuote(symbol: symbol)
            XCTAssertEqual(quote.symbol, symbol)
            XCTAssertEqual(quote.name, symbol == "MSFT" ? "Microsoft Corporation" : "Apple Inc.")
            XCTAssertEqual(quote.currency, "USD")
            XCTAssertEqual(quote.exchange, "NASDAQ")
            XCTAssertEqual(quote.dailyPrices.map(\.close), [343.91, 346.03])
            XCTAssertEqual(quote.receivedAt, receivedAt)
        }
    }

    func testMalformedSymbolsAreRejectedBeforeAnyRequest() async {
        let provider = client(mode: "unexpectedRequest", apiKey: "testcredential")
        for symbol in ["", "msft", " MSFT ", "MSFT/quote", "MSFT&apikey=testcredential",
                       "MSFT\n", "MS_FT", "МSFT", String(repeating: "M", count: 21)] {
            do {
                _ = try await provider.loadQuote(symbol: symbol)
                XCTFail("Expected invalid symbol: \(symbol.debugDescription)")
            } catch {
                XCTAssertEqual(error as? PublicQuoteError, .invalidData, symbol.debugDescription)
            }
        }
    }

    func testMalformedCredentialsAreRejectedBeforeQuoteOrCatalogRequests() async {
        for key in ["", "testcredential testcredential", "testcredential\nAuthorization",
                    "testcredential?", "testcredential/", String(repeating: "testcredential", count: 20)] {
            let provider = client(mode: "unexpectedRequest", apiKey: key)
            do {
                _ = try await provider.loadQuote()
                XCTFail("Expected invalid credential")
            } catch { XCTAssertEqual(error as? PublicQuoteError, .invalidData) }
            do {
                _ = try await provider.loadInstruments()
                XCTFail("Expected invalid credential for catalog")
            } catch { XCTAssertEqual(error as? PublicQuoteError, .invalidData) }
        }
    }

    func testDemoAccessToAnotherSymbolFailsExplicitlyBeforeAnyRequest() async {
        let keys: [String?] = [nil, "demo"]
        for key in keys {
            do {
                _ = try await client(mode: "unexpectedRequest", apiKey: key).loadQuote(symbol: "MSFT")
                XCTFail("Demo must not substitute an AAPL quote for MSFT")
            } catch { XCTAssertEqual(error as? PublicQuoteError, .personalKeyRequired) }
        }
    }

    func testCatalogFiltersToNonemptyUSDCommonStocks() async throws {
        let instruments = try await client(mode: "catalog").loadInstruments()
        XCTAssertEqual(instruments.map(\.id), ["AAPL:NASDAQ", "AAPL:NYSE", "MSFT:NASDAQ"])
        XCTAssertTrue(instruments.allSatisfy {
            $0.currency == "USD" && !$0.symbol.isEmpty && !$0.name.isEmpty && !$0.exchange.isEmpty
        })
    }

    func testCatalogDeduplicatesBySymbolAndExchangeAndHasStableOrdering() async throws {
        let provider = client(mode: "catalog")
        let first = try await provider.loadInstruments()
        let second = try await provider.loadInstruments()
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.id), first.map(\.id).sorted())
        XCTAssertEqual(Set(first.map(\.id)).count, first.count)
        XCTAssertEqual(first.filter { $0.symbol == "AAPL" }.count, 2)
        XCTAssertEqual(first.first { $0.id == "MSFT:NASDAQ" }?.name, "Microsoft Corporation")
    }

    func testCatalogRejectsInvalidStatusEmptyFilteredAndMalformedResponses() async {
        for mode in ["catalogStatus", "catalogEmpty", "catalogFiltered", "catalogMalformed", "catalogMissingFields"] {
            do {
                _ = try await client(mode: mode).loadInstruments()
                XCTFail("Expected invalid catalog: \(mode)")
            } catch { XCTAssertEqual(error as? PublicQuoteError, .invalidData, mode) }
        }
    }

    func testCatalogSurfacesProviderAndHTTPFailures() async {
        do {
            _ = try await client(mode: "catalogProviderError").loadInstruments()
            XCTFail("Expected provider catalog failure")
        } catch { XCTAssertEqual(error as? PublicQuoteError, .provider(403, "Catalog unavailable")) }
        do {
            _ = try await client(mode: "catalogHTTPError").loadInstruments()
            XCTFail("Expected HTTP catalog failure")
        } catch { XCTAssertEqual(error as? DataSourceError, .serverStatus(503)) }
    }

    func testSearchRanksExactTickersBeforeSubstringMatches() {
        let results = PublicStockSearch.results(searchInstruments, query: " mSfT \n")
        XCTAssertEqual(results.map(\.id), ["MSFT:NASDAQ", "MSFT:NYSE", "AMSFT:NYSE"])
    }

    func testSearchMatchesNamesCaseInsensitivelyAndTrimsWhitespace() {
        XCTAssertEqual(PublicStockSearch.results(searchInstruments, query: " \naPpLe InC. \t").map(\.id),
                       ["AAPL:NASDAQ"])
        XCTAssertEqual(PublicStockSearch.results(searchInstruments, query: "international business").map(\.id),
                       ["IBM:NYSE"])
    }

    func testSearchCombinesExchangeFilterWithQueryAndSortsEmptyQuery() {
        XCTAssertEqual(PublicStockSearch.results(searchInstruments, query: "msft", exchange: "NYSE").map(\.id),
                       ["MSFT:NYSE", "AMSFT:NYSE"])
        XCTAssertEqual(PublicStockSearch.results(searchInstruments, query: " \n", exchange: "NASDAQ").map(\.id),
                       ["AAPL:NASDAQ", "MSFT:NASDAQ"])
        XCTAssertEqual(PublicStockSearch.results(searchInstruments, query: "").map(\.id),
                       searchInstruments.map(\.id).sorted())
    }

    func testSearchReturnsEmptyForMissingMatchesExchangeOrCatalog() {
        XCTAssertTrue(PublicStockSearch.results(searchInstruments, query: "not a listed company").isEmpty)
        XCTAssertTrue(PublicStockSearch.results(searchInstruments, query: "AAPL", exchange: "NYSE").isEmpty)
        XCTAssertTrue(PublicStockSearch.results(searchInstruments, query: "", exchange: "UNKNOWN").isEmpty)
        XCTAssertTrue(PublicStockSearch.results([], query: "MSFT").isEmpty)
    }

    func testProviderErrorRedactsEveryEchoOfPersonalCredential() async {
        do {
            _ = try await client(mode: "echoedKey", apiKey: "testcredential").loadQuote()
            XCTFail("Expected provider failure")
        } catch {
            XCTAssertEqual(error as? PublicQuoteError,
                           .provider(401, "Invalid key [redacted]; echoed [redacted]"))
            XCTAssertFalse(error.localizedDescription.contains("testcredential"))
        }
    }

    /// Opt-in smoke test, never a dependency of normal offline CI.
    func testLivePublicAPIWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["TRADEVIEW_TEST_PUBLIC_API"] == "1" else {
            throw XCTSkip("Live API check is opt-in")
        }
        let quote = try await TwelveDataPublicClient().loadQuote()
        XCTAssertEqual(quote.symbol, "AAPL")
        XCTAssertGreaterThan(quote.price, 0)
        XCTAssertEqual(quote.dailyPrices.count, 90)
        print("PUBLIC_API_OK \(quote.symbol) \(quote.price) \(quote.currency), bars=\(quote.dailyPrices.count), quoteAt=\(quote.quoteAt)")
        let instruments = try await TwelveDataPublicClient().loadInstruments()
        XCTAssertFalse(instruments.isEmpty)
        XCTAssertTrue(instruments.allSatisfy { $0.currency == "USD" })
        XCTAssertTrue(instruments.contains { $0.symbol == "AAPL" })
        XCTAssertFalse(PublicStockSearch.results(instruments, query: "Microsoft").isEmpty)
        print("PUBLIC_CATALOG_OK instruments=\(instruments.count), searchMicrosoft=true")
    }

    private var searchInstruments: [PublicInstrument] {
        [PublicInstrument(symbol: "MSFT", name: "Microsoft secondary listing", exchange: "NYSE", currency: "USD"),
         PublicInstrument(symbol: "IBM", name: "International Business Machines", exchange: "NYSE", currency: "USD"),
         PublicInstrument(symbol: "AMSFT", name: "MSFT Holdings", exchange: "NYSE", currency: "USD"),
         PublicInstrument(symbol: "MSFT", name: "Microsoft Corporation", exchange: "NASDAQ", currency: "USD"),
         PublicInstrument(symbol: "AAPL", name: "Apple Inc.", exchange: "NASDAQ", currency: "USD")]
    }

    private func client(mode: String = "valid", apiKey: String? = nil) -> TwelveDataPublicClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QuoteFixtureProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Quote-Test": mode]
        let date = receivedAt
        return TwelveDataPublicClient(session: URLSession(configuration: configuration), apiKey: apiKey, now: { date })
    }

    private func assertInvalid(_ mode: String) async {
        do {
            _ = try await client(mode: mode).loadQuote()
            XCTFail("Expected invalid data: \(mode)")
        } catch { XCTAssertEqual(error as? PublicQuoteError, .invalidData, mode) }
    }
}

private final class QuoteFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let mode = request.value(forHTTPHeaderField: "X-Quote-Test") ?? "valid"
        // A distinct error prevents preflight-validation tests from passing merely
        // because the fixture rejected a request that should never have been sent.
        guard mode != "unexpectedRequest" else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let usesPersonalKey = mode == "authenticatedMSFT" || mode == "echoedKey"
        guard let url = request.url, url.scheme == "https", url.host == "api.twelvedata.com",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              request.value(forHTTPHeaderField: "Authorization") == "apikey \(usesPersonalKey ? "testcredential" : "demo")",
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              components.queryItems?.contains(where: { $0.name.lowercased() == "apikey" }) != true,
              !url.absoluteString.contains("testcredential") else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let items = components.queryItems ?? []
        let symbols = items.filter { $0.name == "symbol" }.compactMap(\.value)
        let symbol = mode == "authenticatedMSFT" ? (symbols.first ?? "") : "AAPL"
        let expectedItems: [URLQueryItem]
        switch url.path {
        case "/stocks":
            expectedItems = [URLQueryItem(name: "country", value: "United States")]
        case "/quote":
            expectedItems = [URLQueryItem(name: "symbol", value: symbol)]
        case "/time_series":
            expectedItems = [URLQueryItem(name: "symbol", value: symbol),
                URLQueryItem(name: "interval", value: "1day"), URLQueryItem(name: "outputsize", value: "90"),
                URLQueryItem(name: "adjust", value: "splits"), URLQueryItem(name: "order", value: "asc")]
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        guard items.count == expectedItems.count, expectedItems.allSatisfy({ items.contains($0) }),
              ["AAPL", "MSFT"].contains(symbol),
              (mode.hasPrefix("catalog") ? url.path == "/stocks" : url.path != "/stocks") else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        var quote: [String: Any] = ["symbol": symbol,
            "name": symbol == "MSFT" ? "Microsoft Corporation" : "Apple Inc.", "exchange": "NASDAQ",
            "currency": "USD", "close": "346.03", "percent_change": "0.61643928",
            "last_quote_at": 1_793_112_540, "is_market_open": true]
        var meta = ["symbol": symbol, "currency": "USD", "interval": "1day",
            "exchange_timezone": "America/New_York", "exchange": "NASDAQ"]
        var bars = [["datetime": "2026-10-27", "close": "346.03"],
                    ["datetime": "2026-10-26", "close": "343.91"]]
        switch mode {
        case "symbol": meta["symbol"] = "MSFT"
        case "currency": quote["currency"] = "EUR"
        case "interval": meta["interval"] = "1min"
        case "nan": quote["close"] = "nan"
        case "negative": quote["close"] = "-1"
        case "badBar": bars[0]["close"] = "inf"
        case "futureQuote": quote["last_quote_at"] = 1_793_112_601
        case "futureBar": bars[0]["datetime"] = "2027-01-01"
        case "duplicate": bars[1]["datetime"] = "2026-10-27"
        case "timezone": meta["exchange_timezone"] = "Invalid/Timezone"
        case "badDate": bars[0]["datetime"] = "2026-02-30"
        case "empty": bars = []
        case "missingTimestamp": quote.removeValue(forKey: "last_quote_at")
        default: break
        }
        let object: [String: Any]
        switch mode {
        case "providerError": object = ["status": "error", "code": 429, "message": "Trial limit reached"]
        case "echoedKey": object = ["status": "error", "code": 401,
            "message": "Invalid key testcredential; echoed testcredential"]
        case "catalogProviderError": object = ["status": "error", "code": 403, "message": "Catalog unavailable"]
        default:
            if url.path == "/stocks" {
                let valid = [
                    catalogItem("MSFT", "Microsoft Corporation"),
                    catalogItem("AAPL", "Apple secondary listing", exchange: "NYSE"),
                    catalogItem("AAPL", "Apple Inc."),
                    catalogItem("MSFT", "Duplicate must not replace the first entry")]
                let filtered = [
                    catalogItem("FUND", "ETF excluded", type: "ETF"),
                    catalogItem("PREF", "Preferred excluded", type: "Preferred Stock"),
                    catalogItem("EUR", "Non-dollar stock", currency: "EUR"),
                    catalogItem("", "Missing symbol"), catalogItem("NAME", ""),
                    catalogItem("EXCHANGE", "Missing exchange", exchange: "")]
                let data = mode == "catalogEmpty" ? [] : mode == "catalogFiltered" ? filtered : valid + filtered
                object = mode == "catalogMissingFields"
                    ? ["status": "ok", "data": [["symbol": "MSFT"]]]
                    : ["status": mode == "catalogStatus" ? "pending" : "ok", "data": data]
            } else {
                object = url.path == "/quote" ? quote : ["meta": meta, "values": bars, "status": "ok"]
            }
        }
        let data = ["malformed", "catalogMalformed"].contains(mode)
            ? Data("broken".utf8) : try! JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(url: url, statusCode: ["httpError", "catalogHTTPError"].contains(mode) ? 503 : 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func catalogItem(_ symbol: String, _ name: String, exchange: String = "NASDAQ",
                             currency: String = "USD", type: String = "Common Stock") -> [String: String] {
        ["symbol": symbol, "name": name, "exchange": exchange, "currency": currency, "type": type]
    }
}