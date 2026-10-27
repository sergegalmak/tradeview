import Foundation

public protocol MarketDataProviding: Sendable {
    func loadSnapshot() async throws -> MarketSnapshot
}

public enum MarketDataConfiguration: MarketDataProviding {
    case demo
    case backend(URL)
    case invalid

    public init(environment: [String: String]) {
        guard let value = environment["TRADEVIEW_API_URL"] else { self = .demo; return }
        guard let url = URL(string: value), url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else { self = .invalid; return }
        self = .backend(url)
    }

    public func loadSnapshot() async throws -> MarketSnapshot {
        switch self {
        case .demo: return try await MockMarketDataProvider().loadSnapshot()
        case .backend(let endpoint): return try await BackendAPIClient(endpoint: endpoint).loadSnapshot()
        case .invalid: throw DataSourceError.insecureEndpoint
        }
    }
}

public enum DataSourceError: LocalizedError, Equatable {
    case insecureEndpoint
    case invalidResponse
    case serverStatus(Int)
    case invalidSnapshot(String)

    public var errorDescription: String? {
        switch self {
        case .insecureEndpoint:
            return "Для внешнего API разрешены только HTTPS-адреса."
        case .invalidResponse:
            return "Источник данных вернул некорректный ответ."
        case .serverStatus(let status):
            return "Источник данных вернул HTTP \(status)."
        case .invalidSnapshot(let reason):
            return "Снимок данных отклонён: \(reason)"
        }
    }
}

public struct BackendAPIClient: MarketDataProviding {
    public let endpoint: URL
    private let session: URLSession

    public init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func loadSnapshot() async throws -> MarketSnapshot {
        guard endpoint.scheme?.lowercased() == "https", endpoint.host != nil,
              endpoint.user == nil, endpoint.password == nil else {
            throw DataSourceError.insecureEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DataSourceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw DataSourceError.serverStatus(httpResponse.statusCode)
        }
        guard httpResponse.url?.scheme?.lowercased() == "https", data.count <= 10_000_000 else {
            throw DataSourceError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MarketSnapshot.self, from: data).validated()
    }
}

public struct MockMarketDataProvider: MarketDataProviding {
    public static let snapshot = MockMarketData.makeSnapshot()
    public init() {}

    public func loadSnapshot() async throws -> MarketSnapshot {
        Self.snapshot
    }
}

public enum MockMarketData {
    // Fixed, explicitly historical fixture. Never restamped as current market data.
    private static let referenceDate = ISO8601DateFormatter().date(from: "2026-10-23T20:00:00Z")!

    private static func source(at date: Date) -> DataSourceInfo {
        DataSourceInfo(name: "Синтетический офлайн-набор", updatedAt: date,
            modelVersion: "demo-2.0", isOfflineDemo: true, featureVersion: "demo-features-2.0",
            validUntil: date.addingTimeInterval(96 * 3_600))
    }

    public static func makeSnapshot() -> MarketSnapshot {
        let indices = [
                MarketIndex(symbol: "S&P 500", name: "S&P 500", changePercentage: 0.48),
                MarketIndex(symbol: "NASDAQ", name: "NASDAQ Composite", changePercentage: 0.84),
                MarketIndex(symbol: "DOW", name: "Dow Jones", changePercentage: -0.12),
                MarketIndex(symbol: "VIX", name: "Volatility Index", changePercentage: -2.35)
            ]
        let stocks = [
                stock(
                    ticker: "AAPL", name: "Apple Inc.", sector: "Технологии", price: 228.40,
                    change: 0.71, cap: 3_470, pe: 34.1, trendStart: 210,
                    action: .hold, horizon: .sixMonths, confidence: 0.68,
                    rationale: "Сильный сервисный бизнес поддерживает денежный поток, но текущая оценка ограничивает запас прочности.",
                    drivers: ["Рост выручки сервисов", "Выкуп акций", "Экосистема устройств"],
                    risks: ["Высокая оценка", "Зависимость от цикла iPhone", "Регуляторное давление"]
                ),
                stock(
                    ticker: "MSFT", name: "Microsoft Corp.", sector: "Технологии", price: 462.80,
                    change: 1.06, cap: 3_440, pe: 35.6, trendStart: 418,
                    action: .buy, horizon: .twelveMonths, confidence: 0.79,
                    rationale: "Облачная выручка и корпоративное внедрение ИИ создают устойчивые драйверы роста при высокой прибыльности.",
                    drivers: ["Рост Azure", "Монетизация Copilot", "Высокая операционная маржа"],
                    risks: ["Капитальные расходы на ИИ", "Конкуренция в облаках", "Замедление корпоративного спроса"]
                ),
                stock(
                    ticker: "NVDA", name: "NVIDIA Corp.", sector: "Полупроводники", price: 187.30,
                    change: 2.64, cap: 4_550, pe: 49.2, trendStart: 151,
                    action: .watch, horizon: .sixMonths, confidence: 0.61,
                    rationale: "Спрос на вычисления для ИИ остаётся сильным, однако премия в оценке делает реакцию на отчётность чувствительной.",
                    drivers: ["Спрос на дата-центры", "Переход на Blackwell", "Экосистема CUDA"],
                    risks: ["Высокие ожидания", "Ограничения поставок", "Конкуренция собственных чипов клиентов"]
                ),
                stock(
                    ticker: "AMZN", name: "Amazon.com Inc.", sector: "Потребительский сектор", price: 224.10,
                    change: 0.31, cap: 2_370, pe: 37.3, trendStart: 205,
                    action: .buy, horizon: .twelveMonths, confidence: 0.74,
                    rationale: "AWS и рекламный бизнес расширяют маржу, а эффективность логистики поддерживает розницу.",
                    drivers: ["Рост AWS", "Реклама", "Операционный рычаг в рознице"],
                    risks: ["Капитальные расходы", "Давление на потребительский спрос", "Антимонопольные риски"]
                ),
                stock(
                    ticker: "GOOGL", name: "Alphabet Inc.", sector: "Коммуникации", price: 191.20,
                    change: 0.92, cap: 2_330, pe: 23.8, trendStart: 176,
                    action: .buy, horizon: .sixMonths, confidence: 0.76,
                    rationale: "Денежный поток и более умеренная оценка сочетаются с потенциалом монетизации ИИ-продуктов.",
                    drivers: ["Поиск и реклама", "Рост Cloud", "Чистая денежная позиция"],
                    risks: ["Изменение поиска из-за ИИ", "Регуляторные дела", "Давление на маржу Cloud"]
                ),
                stock(
                    ticker: "JPM", name: "JPMorgan Chase & Co.", sector: "Финансы", price: 308.60,
                    change: -0.44, cap: 850, pe: 15.1, trendStart: 293,
                    action: .hold, horizon: .sixMonths, confidence: 0.66,
                    rationale: "Диверсифицированная модель банка устойчива, но нормализация процентной маржи ограничивает краткосрочный потенциал.",
                    drivers: ["Комиссионный доход", "Качество активов", "Масштаб платформы"],
                    risks: ["Снижение ставок", "Рост кредитных резервов", "Регулирование капитала"]
                ),
                stock(
                    ticker: "XOM", name: "Exxon Mobil Corp.", sector: "Энергетика", price: 116.40,
                    change: -1.02, cap: 505, pe: 14.2, trendStart: 121,
                    action: .reduce, horizon: .threeMonths, confidence: 0.63,
                    rationale: "Качественный активный портфель компенсируется зависимостью от цен на сырьё и ослаблением краткосрочного импульса.",
                    drivers: ["Денежный поток", "Дисциплина капитала", "Низкая себестоимость добычи"],
                    risks: ["Снижение цен на нефть", "Геополитика", "Энергопереход"]
                ),
                stock(
                    ticker: "TSLA", name: "Tesla Inc.", sector: "Потребительский сектор", price: 341.20,
                    change: -2.91, cap: 1_095, pe: 96.4, trendStart: 372,
                    action: .avoid, horizon: .oneMonth, confidence: 0.72,
                    rationale: "Рыночные ожидания учитывают несколько долгосрочных опционов, а ценовая конкуренция сохраняет давление на основное направление.",
                    drivers: ["ПО и автономность", "Энергетический бизнес", "Масштаб производства"],
                    risks: ["Сжатие маржи", "Конкуренция из Китая", "Высокая оценка"]
                ),
                stock(
                    ticker: "KO", name: "The Coca-Cola Company", sector: "Защитный сектор", price: 70.90,
                    change: 0.18, cap: 305, pe: 23.2, trendStart: 67,
                    action: .hold, horizon: .twelveMonths, confidence: 0.69,
                    rationale: "Предсказуемый спрос и сильный бренд поддерживают защитную роль, но ограничивают потенциал ускорения.",
                    drivers: ["Ценообразование", "Глобальная дистрибуция", "Дивиденды"],
                    risks: ["Валютные колебания", "Рост стоимости сырья", "Оценка защитных активов"]
                ),
                stock(
                    ticker: "LLY", name: "Eli Lilly and Company", sector: "Здравоохранение", price: 841.70,
                    change: 1.47, cap: 800, pe: 62.9, trendStart: 752,
                    action: .watch, horizon: .sixMonths, confidence: 0.60,
                    rationale: "Спрос на ключевые препараты остаётся высоким, однако ожидания роста и оценка уже очень значительны.",
                    drivers: ["Спрос на GLP-1", "Расширение мощностей", "Новые показания"],
                    risks: ["Ограничения производства", "Ценовое регулирование", "Конкуренция"]
                )
            ]
        let priorDate = referenceDate.addingTimeInterval(-14 * 86_400)
        let prior = stock(ticker: "MSFT", name: "Microsoft Corp.", sector: "Технологии", price: 440,
            change: 0.5, cap: 3_300, pe: 34, trendStart: 415, action: .hold, horizon: .sixMonths,
            confidence: 0.67, rationale: "Предыдущий демонстрационный нейтральный сигнал.",
            drivers: ["Облачная выручка"], risks: ["Капитальные расходы"], asOf: priorDate)
        let history = stocks.map { SignalHistoryItem(ticker: $0.ticker, signal: $0.signal,
            source: source(at: referenceDate), provenance: $0.provenance) } + [
                SignalHistoryItem(ticker: prior.ticker, signal: prior.signal, source: source(at: priorDate), provenance: prior.provenance)
            ]
        return MarketSnapshot(source: source(at: referenceDate), indices: indices, stocks: stocks, signalHistory: history)
    }

    private static func stock(
        ticker: String,
        name: String,
        sector: String,
        price: Double,
        change: Double,
        cap: Double,
        pe: Double,
        trendStart: Double,
        action: InvestmentAction,
        horizon: InvestmentHorizon,
        confidence: Double,
        rationale: String,
        drivers: [String],
        risks: [String],
        asOf: Date = referenceDate
    ) -> Stock {
        let generatedAt = asOf.addingTimeInterval(-60)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let event = SignalEvent(id: "total-return-vs-SPY-\(horizon.rawValue)m",
            title: "Полная доходность акции в USD, включая дивиденды, выше полной доходности SPY за \(horizon.title).",
            benchmark: "SPY (S&P 500), total return, USD", probability: nil,
            expectedBy: calendar.date(byAdding: .month, value: horizon.rawValue, to: generatedAt)!, calibration: nil)
        let provenance = ["price", "marketCapBillions", "peRatio", "priceHistory", "signal"].map { metric in
            MetricProvenance(metric: metric, eventAt: asOf.addingTimeInterval(-900),
                publishedAt: asOf.addingTimeInterval(-600), receivedAt: asOf.addingTimeInterval(-300),
                provider: "Синтетический набор", sourceID: "demo-\(ticker)-\(metric)-\(asOf.timeIntervalSince1970)",
                schemaVersion: 2, quality: .complete, limitation: "Искусственные значения; не рыночные наблюдения.")
        }
        return Stock(
            ticker: ticker,
            name: name,
            sector: sector,
            price: price,
            dailyChangePercentage: change,
            marketCapBillions: cap,
            peRatio: pe,
            priceHistory: trend(start: trendStart, finish: price, asOf: asOf),
            signal: InvestmentSignal(
                action: action,
                horizon: horizon,
                confidence: confidence,
                explicitEvent: event,
                scenarios: [
                    Scenario(
                        title: "Позитивный",
                        description: "Драйверы реализуются быстрее базовых ожиданий.",
                        minimumReturn: 0.10, maximumReturn: 0.20
                    ),
                    Scenario(
                        title: "Базовый",
                        description: "Финансовые результаты соответствуют текущему консенсусу.",
                        minimumReturn: 0, maximumReturn: 0.09
                    ),
                    Scenario(
                        title: "Негативный",
                        description: "Риски реализуются, а ожидания рынка пересматриваются.",
                        minimumReturn: -0.25, maximumReturn: -0.10
                    )
                ],
                drivers: drivers,
                risks: risks,
                invalidationConditions: ["Устойчивое ухудшение денежного потока", "Критическое событие или утрата качества исходных данных"],
                rationale: rationale,
                generatedAt: generatedAt, dataCutoff: asOf.addingTimeInterval(-300),
                modelVersion: "demo-2.0", featureVersion: "demo-features-2.0",
                featureSnapshotID: "demo-\(ticker)-\(asOf.timeIntervalSince1970)"
            ),
            provenance: provenance
        )
    }

    private static func trend(start: Double, finish: Double, asOf: Date) -> [PricePoint] {
        let offsets = [-0.06, -0.025, 0.018, -0.012, 0.032, 0.009, -0.018, 0.026, 0.045, 0]
        return offsets.enumerated().map { index, offset in
            let progress = Double(index) / Double(offsets.count - 1)
            let interpolated = start + (finish - start) * progress
            return PricePoint(
                date: asOf.addingTimeInterval(Double(index - offsets.count + 1) * 86_400 - 900),
                close: interpolated * (1 + offset)
            )
        }
    }

}
