import Foundation

/// A quote is not a research signal and cannot enter the signal archive or alert engine.
public struct PublicQuote: Sendable, Equatable {
    public let symbol: String
    public let name: String
    public let exchange: String
    public let currency: String
    public let price: Double
    public let changePercentage: Double
    public let quoteAt: Date
    public let receivedAt: Date
    public let exchangeTimeZone: String
    public let isMarketOpen: Bool
    public let dailyPrices: [PublicDailyPrice]

    public func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(quoteAt) > (isMarketOpen ? 15 * 60 : 96 * 3_600)
    }
}

public struct PublicDailyPrice: Identifiable, Sendable, Equatable {
    /// Start of the bar's calendar day in the exchange timezone, not its publication time.
    public let date: Date
    public let close: Double
    public var id: Date { date }
}

public protocol PublicQuoteProviding: Sendable {
    func loadQuote() async throws -> PublicQuote
    func loadQuote(symbol: String) async throws -> PublicQuote
}

public extension PublicQuoteProviding {
    func loadQuote(symbol: String) async throws -> PublicQuote {
        guard symbol == "AAPL" else { throw PublicQuoteError.personalKeyRequired }
        return try await loadQuote()
    }
}

public struct PublicInstrument: Identifiable, Sendable, Equatable, Codable {
    public let symbol: String
    public let name: String
    public let exchange: String
    public let currency: String
    public var id: String { "\(symbol):\(exchange)" }

    public init(symbol: String, name: String, exchange: String, currency: String) {
        self.symbol = symbol
        self.name = name
        self.exchange = exchange
        self.currency = currency
    }
}

public protocol StockCatalogProviding: Sendable {
    func loadInstruments() async throws -> [PublicInstrument]
}

public enum PublicStockSearch {
    public static func results(_ instruments: [PublicInstrument], query: String,
                               exchange: String? = nil) -> [PublicInstrument] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return instruments.filter {
            (exchange == nil || $0.exchange == exchange) &&
            (query.isEmpty || $0.symbol.localizedCaseInsensitiveContains(query) ||
             $0.name.localizedCaseInsensitiveContains(query))
        }.sorted {
            let leftExact = $0.symbol.caseInsensitiveCompare(query) == .orderedSame
            let rightExact = $1.symbol.caseInsensitiveCompare(query) == .orderedSame
            if leftExact != rightExact { return leftExact }
            return $0.id < $1.id
        }
    }
}

public enum PublicQuoteError: LocalizedError, Equatable {
    case provider(Int, String)
    case invalidData
    case personalKeyRequired

    public var errorDescription: String? {
        switch self {
        case .provider(let code, let message): return "Twelve Data (\(code)): \(message)"
        case .invalidData: return "Twelve Data: ответ содержит неполные или некорректные котировки."
        case .personalKeyRequired: return "Для этого тикера добавьте личный API-ключ Twelve Data."
        }
    }
}

/// Personal credentials travel only in the Authorization header, never in the URL.
public struct TwelveDataPublicClient: PublicQuoteProviding, StockCatalogProviding {
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let apiKey: String

    public init(session: URLSession? = nil, apiKey: String? = nil,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session ?? URLSession(configuration: .ephemeral,
            delegate: NoQuoteRedirects(), delegateQueue: nil)
        self.apiKey = apiKey ?? "demo"
        self.now = now
    }

    public func loadInstruments() async throws -> [PublicInstrument] {
        let response: CatalogResponse = try await request("stocks", parameters: [
            URLQueryItem(name: "country", value: "United States")
        ], includeSymbol: false)
        guard response.status == "ok", !response.data.isEmpty else { throw PublicQuoteError.invalidData }
        var known = Set<String>()
        let instruments = response.data.compactMap { item -> PublicInstrument? in
            guard item.type == "Common Stock", item.currency == "USD",
                  !item.symbol.isEmpty, !item.name.isEmpty, !item.exchange.isEmpty else { return nil }
            let instrument = PublicInstrument(symbol: item.symbol, name: item.name,
                exchange: item.exchange, currency: item.currency)
            return known.insert(instrument.id).inserted ? instrument : nil
        }
        guard !instruments.isEmpty else { throw PublicQuoteError.invalidData }
        return instruments.sorted { $0.id < $1.id }
    }

    public func loadQuote() async throws -> PublicQuote {
        try await loadQuote(symbol: "AAPL")
    }

    public func loadQuote(symbol: String) async throws -> PublicQuote {
        guard !symbol.isEmpty, symbol.count <= 20,
              symbol.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").contains($0) }) else {
            throw PublicQuoteError.invalidData
        }
        guard apiKey != "demo" || symbol == "AAPL" else { throw PublicQuoteError.personalKeyRequired }
        let quote: QuoteResponse = try await request("quote", parameters: [], symbol: symbol)
        let quoteReceivedAt = now()
        let series: SeriesResponse = try await request("time_series", parameters: [
            URLQueryItem(name: "interval", value: "1day"),
            URLQueryItem(name: "outputsize", value: "90"),
            URLQueryItem(name: "adjust", value: "splits"),
            URLQueryItem(name: "order", value: "asc")
        ], symbol: symbol)
        let receivedAt = now()
        guard quote.symbol == symbol, series.meta.symbol == quote.symbol,
              quote.currency == "USD", series.meta.currency == quote.currency,
              series.meta.interval == "1day", series.status == "ok",
              quote.exchange == series.meta.exchange, !quote.name.isEmpty,
              let timeZone = TimeZone(identifier: series.meta.exchange_timezone),
              let price = Double(quote.close), price.isFinite, price > 0,
              let change = Double(quote.percent_change), change.isFinite,
              quote.last_quote_at > 0, quote.last_quote_at.isFinite,
              (2...90).contains(series.values.count) else { throw PublicQuoteError.invalidData }
        let quoteAt = Date(timeIntervalSince1970: quote.last_quote_at)
        guard quoteAt <= quoteReceivedAt else { throw PublicQuoteError.invalidData }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: receivedAt)
        let points = try series.values.map { bar -> PublicDailyPrice in
            guard let date = formatter.date(from: bar.datetime),
                  formatter.string(from: date) == bar.datetime, date <= today,
                  let close = Double(bar.close), close.isFinite, close > 0 else {
                throw PublicQuoteError.invalidData
            }
            return PublicDailyPrice(date: date, close: close)
        }.sorted { $0.date < $1.date }
        guard Set(points.map(\.date)).count == points.count else { throw PublicQuoteError.invalidData }
        return PublicQuote(symbol: quote.symbol, name: quote.name, exchange: quote.exchange,
            currency: quote.currency, price: price, changePercentage: change,
            quoteAt: quoteAt, receivedAt: receivedAt,
            exchangeTimeZone: timeZone.identifier, isMarketOpen: quote.is_market_open,
            dailyPrices: points)
    }

    private func request<T: Decodable>(_ path: String, parameters: [URLQueryItem],
                                      includeSymbol: Bool = true, symbol: String = "AAPL") async throws -> T {
        guard !apiKey.isEmpty, apiKey.count <= 256,
              apiKey.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            throw PublicQuoteError.invalidData
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.twelvedata.com"
        components.path = "/\(path)"
        components.queryItems = (includeSymbol ? [URLQueryItem(name: "symbol", value: symbol)] : []) + parameters
        guard let url = components.url else { throw PublicQuoteError.invalidData }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("apikey \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              http.url?.scheme == "https", http.url?.host == "api.twelvedata.com",
              data.count <= 10_000_000 else { throw DataSourceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw DataSourceError.serverStatus(http.statusCode)
        }
        let decoder = JSONDecoder()
        if let failure = try? decoder.decode(ErrorResponse.self, from: data), failure.status == "error" {
            let safeMessage = apiKey == "demo" ? failure.message :
                failure.message.replacingOccurrences(of: apiKey, with: "[redacted]")
            throw PublicQuoteError.provider(failure.code, String(safeMessage.prefix(500)))
        }
        do { return try decoder.decode(T.self, from: data) }
        catch { throw PublicQuoteError.invalidData }
    }

    private struct QuoteResponse: Decodable {
        let symbol, name, exchange, currency, close, percent_change: String
        let last_quote_at: Double
        let is_market_open: Bool
    }
    private struct SeriesResponse: Decodable {
        struct Meta: Decodable {
            let symbol, currency, interval, exchange_timezone, exchange: String
        }
        struct Bar: Decodable { let datetime, close: String }
        let meta: Meta
        let values: [Bar]
        let status: String
    }
    private struct ErrorResponse: Decodable {
        let code: Int
        let message, status: String
    }
    private struct CatalogResponse: Decodable {
        struct Item: Decodable {
            let symbol, name, exchange, currency, type: String
        }
        let data: [Item]
        let status: String
    }
}

/// Never forward credentials through a provider redirect.
private final class NoQuoteRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}