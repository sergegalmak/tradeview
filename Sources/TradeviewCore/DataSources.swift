import Foundation

protocol MarketDataProviding: Sendable {
    func loadSnapshot() async throws -> MarketSnapshot
}

enum DataSourceError: LocalizedError, Equatable {
    case insecureEndpoint
    case invalidResponse
    case serverStatus(Int)

    var errorDescription: String? {
        switch self {
        case .insecureEndpoint:
            return "Для внешнего API разрешены только HTTPS-адреса."
        case .invalidResponse:
            return "Источник данных вернул некорректный ответ."
        case .serverStatus(let status):
            return "Источник данных вернул HTTP \(status)."
        }
    }
}

struct BackendAPIClient: MarketDataProviding {
    let endpoint: URL

    func loadSnapshot() async throws -> MarketSnapshot {
        guard endpoint.scheme?.lowercased() == "https" else {
            throw DataSourceError.insecureEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DataSourceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw DataSourceError.serverStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MarketSnapshot.self, from: data)
    }
}

struct MockMarketDataProvider: MarketDataProviding {
    static let snapshot = MockMarketData.makeSnapshot()

    func loadSnapshot() async throws -> MarketSnapshot {
        Self.snapshot
    }
}

enum MockMarketData {
    private static let referenceDate = Date(timeIntervalSince1970: 1_793_269_200)

    static func makeSnapshot() -> MarketSnapshot {
        MarketSnapshot(
            source: DataSourceInfo(
                name: "Локальный офлайн-демо-набор",
                updatedAt: referenceDate,
                modelVersion: "tradeview-mvp-1.0",
                isOfflineDemo: true
            ),
            indices: [
                MarketIndex(symbol: "S&P 500", name: "S&P 500", changePercentage: 0.48),
                MarketIndex(symbol: "NASDAQ", name: "NASDAQ Composite", changePercentage: 0.84),
                MarketIndex(symbol: "DOW", name: "Dow Jones", changePercentage: -0.12),
                MarketIndex(symbol: "VIX", name: "Volatility Index", changePercentage: -2.35)
            ],
            stocks: [
                stock(
                    ticker: "AAPL", name: "Apple Inc.", sector: "Технологии", price: 228.40,
                    change: 0.71, cap: 3_470, pe: 34.1, trendStart: 210,
                    action: .hold, horizon: .mediumTerm, confidence: 0.68,
                    event: nil,
                    rationale: "Сильный сервисный бизнес поддерживает денежный поток, но текущая оценка ограничивает запас прочности.",
                    drivers: ["Рост выручки сервисов", "Выкуп акций", "Экосистема устройств"],
                    risks: ["Высокая оценка", "Зависимость от цикла iPhone", "Регуляторное давление"]
                ),
                stock(
                    ticker: "MSFT", name: "Microsoft Corp.", sector: "Технологии", price: 462.80,
                    change: 1.06, cap: 3_440, pe: 35.6, trendStart: 418,
                    action: .buy, horizon: .longTerm, confidence: 0.79,
                    event: SignalEvent(
                        title: "Рост Azure выше 30% в следующем квартальном отчёте",
                        probability: 0.64,
                        expectedBy: date(daysAfterReference: 42)
                    ),
                    rationale: "Облачная выручка и корпоративное внедрение ИИ создают устойчивые драйверы роста при высокой прибыльности.",
                    drivers: ["Рост Azure", "Монетизация Copilot", "Высокая операционная маржа"],
                    risks: ["Капитальные расходы на ИИ", "Конкуренция в облаках", "Замедление корпоративного спроса"]
                ),
                stock(
                    ticker: "NVDA", name: "NVIDIA Corp.", sector: "Полупроводники", price: 187.30,
                    change: 2.64, cap: 4_550, pe: 49.2, trendStart: 151,
                    action: .watch, horizon: .mediumTerm, confidence: 0.61,
                    event: SignalEvent(
                        title: "Поставки ускорителей Blackwell выше ожиданий рынка",
                        probability: 0.58,
                        expectedBy: date(daysAfterReference: 35)
                    ),
                    rationale: "Спрос на вычисления для ИИ остаётся сильным, однако премия в оценке делает реакцию на отчётность чувствительной.",
                    drivers: ["Спрос на дата-центры", "Переход на Blackwell", "Экосистема CUDA"],
                    risks: ["Высокие ожидания", "Ограничения поставок", "Конкуренция собственных чипов клиентов"]
                ),
                stock(
                    ticker: "AMZN", name: "Amazon.com Inc.", sector: "Потребительский сектор", price: 224.10,
                    change: 0.31, cap: 2_370, pe: 37.3, trendStart: 205,
                    action: .buy, horizon: .longTerm, confidence: 0.74,
                    event: nil,
                    rationale: "AWS и рекламный бизнес расширяют маржу, а эффективность логистики поддерживает розницу.",
                    drivers: ["Рост AWS", "Реклама", "Операционный рычаг в рознице"],
                    risks: ["Капитальные расходы", "Давление на потребительский спрос", "Антимонопольные риски"]
                ),
                stock(
                    ticker: "GOOGL", name: "Alphabet Inc.", sector: "Коммуникации", price: 191.20,
                    change: 0.92, cap: 2_330, pe: 23.8, trendStart: 176,
                    action: .buy, horizon: .mediumTerm, confidence: 0.76,
                    event: SignalEvent(
                        title: "Сохранение двузначного роста рекламной выручки",
                        probability: 0.67,
                        expectedBy: date(daysAfterReference: 42)
                    ),
                    rationale: "Денежный поток и более умеренная оценка сочетаются с потенциалом монетизации ИИ-продуктов.",
                    drivers: ["Поиск и реклама", "Рост Cloud", "Чистая денежная позиция"],
                    risks: ["Изменение поиска из-за ИИ", "Регуляторные дела", "Давление на маржу Cloud"]
                ),
                stock(
                    ticker: "JPM", name: "JPMorgan Chase & Co.", sector: "Финансы", price: 308.60,
                    change: -0.44, cap: 850, pe: 15.1, trendStart: 293,
                    action: .hold, horizon: .mediumTerm, confidence: 0.66,
                    event: nil,
                    rationale: "Диверсифицированная модель банка устойчива, но нормализация процентной маржи ограничивает краткосрочный потенциал.",
                    drivers: ["Комиссионный доход", "Качество активов", "Масштаб платформы"],
                    risks: ["Снижение ставок", "Рост кредитных резервов", "Регулирование капитала"]
                ),
                stock(
                    ticker: "XOM", name: "Exxon Mobil Corp.", sector: "Энергетика", price: 116.40,
                    change: -1.02, cap: 505, pe: 14.2, trendStart: 121,
                    action: .reduce, horizon: .shortTerm, confidence: 0.63,
                    event: nil,
                    rationale: "Качественный активный портфель компенсируется зависимостью от цен на сырьё и ослаблением краткосрочного импульса.",
                    drivers: ["Денежный поток", "Дисциплина капитала", "Низкая себестоимость добычи"],
                    risks: ["Снижение цен на нефть", "Геополитика", "Энергопереход"]
                ),
                stock(
                    ticker: "TSLA", name: "Tesla Inc.", sector: "Потребительский сектор", price: 341.20,
                    change: -2.91, cap: 1_095, pe: 96.4, trendStart: 372,
                    action: .avoid, horizon: .shortTerm, confidence: 0.72,
                    event: SignalEvent(
                        title: "Снижение валовой маржи автомобилей в следующем отчёте",
                        probability: 0.62,
                        expectedBy: date(daysAfterReference: 28)
                    ),
                    rationale: "Рыночные ожидания учитывают несколько долгосрочных опционов, а ценовая конкуренция сохраняет давление на основное направление.",
                    drivers: ["ПО и автономность", "Энергетический бизнес", "Масштаб производства"],
                    risks: ["Сжатие маржи", "Конкуренция из Китая", "Высокая оценка"]
                ),
                stock(
                    ticker: "KO", name: "The Coca-Cola Company", sector: "Защитный сектор", price: 70.90,
                    change: 0.18, cap: 305, pe: 23.2, trendStart: 67,
                    action: .hold, horizon: .longTerm, confidence: 0.69,
                    event: nil,
                    rationale: "Предсказуемый спрос и сильный бренд поддерживают защитную роль, но ограничивают потенциал ускорения.",
                    drivers: ["Ценообразование", "Глобальная дистрибуция", "Дивиденды"],
                    risks: ["Валютные колебания", "Рост стоимости сырья", "Оценка защитных активов"]
                ),
                stock(
                    ticker: "LLY", name: "Eli Lilly and Company", sector: "Здравоохранение", price: 841.70,
                    change: 1.47, cap: 800, pe: 62.9, trendStart: 752,
                    action: .watch, horizon: .mediumTerm, confidence: 0.60,
                    event: SignalEvent(
                        title: "Расширение производственных мощностей препаратов для контроля веса",
                        probability: 0.59,
                        expectedBy: date(daysAfterReference: 65)
                    ),
                    rationale: "Спрос на ключевые препараты остаётся высоким, однако ожидания роста и оценка уже очень значительны.",
                    drivers: ["Спрос на GLP-1", "Расширение мощностей", "Новые показания"],
                    risks: ["Ограничения производства", "Ценовое регулирование", "Конкуренция"]
                )
            ],
            signalHistory: [
                SignalHistoryItem(
                    ticker: "MSFT", action: .buy, horizon: .longTerm, confidence: 0.79,
                    rationale: "Облачная выручка и корпоративное внедрение ИИ создают устойчивые драйверы роста при высокой прибыльности.",
                    generatedAt: referenceDate.addingTimeInterval(-3_600)
                ),
                SignalHistoryItem(
                    ticker: "GOOGL", action: .buy, horizon: .mediumTerm, confidence: 0.76,
                    rationale: "Более умеренная оценка сочетается с денежным потоком и потенциалом монетизации ИИ-продуктов.",
                    generatedAt: referenceDate.addingTimeInterval(-7_200)
                ),
                SignalHistoryItem(
                    ticker: "TSLA", action: .avoid, horizon: .shortTerm, confidence: 0.72,
                    rationale: "Ценовая конкуренция и риск сжатия маржи перевешивают краткосрочные драйверы.",
                    generatedAt: referenceDate.addingTimeInterval(-10_800)
                ),
                SignalHistoryItem(
                    ticker: "TSLA", action: .reduce, horizon: .shortTerm, confidence: 0.65,
                    rationale: "Сигнал снижен после сохранения ценового давления в основном автомобильном бизнесе.",
                    generatedAt: referenceDate.addingTimeInterval(-1_296_000)
                ),
                SignalHistoryItem(
                    ticker: "NVDA", action: .watch, horizon: .mediumTerm, confidence: 0.61,
                    rationale: "Спрос на вычисления для ИИ высок, однако оценка требует подтверждения поставками нового поколения.",
                    generatedAt: referenceDate.addingTimeInterval(-14_400)
                ),
                SignalHistoryItem(
                    ticker: "AMZN", action: .buy, horizon: .longTerm, confidence: 0.74,
                    rationale: "AWS, реклама и улучшение эффективности логистики поддерживают операционный рычаг.",
                    generatedAt: referenceDate.addingTimeInterval(-18_000)
                ),
                SignalHistoryItem(
                    ticker: "XOM", action: .reduce, horizon: .shortTerm, confidence: 0.63,
                    rationale: "Зависимость от цен на сырьё и ослабление импульса ограничивают краткосрочный потенциал.",
                    generatedAt: referenceDate.addingTimeInterval(-21_600)
                ),
                SignalHistoryItem(
                    ticker: "AAPL", action: .hold, horizon: .mediumTerm, confidence: 0.68,
                    rationale: "Рост сервисов поддерживает денежный поток, но высокая оценка сокращает запас прочности.",
                    generatedAt: referenceDate.addingTimeInterval(-25_200)
                ),
                SignalHistoryItem(
                    ticker: "JPM", action: .hold, horizon: .mediumTerm, confidence: 0.66,
                    rationale: "Диверсифицированная модель банка компенсирует риск нормализации процентной маржи.",
                    generatedAt: referenceDate.addingTimeInterval(-28_800)
                ),
                SignalHistoryItem(
                    ticker: "MSFT", action: .hold, horizon: .mediumTerm, confidence: 0.67,
                    rationale: "Ранее сигнал был нейтральнее до подтверждения динамики Azure и корпоративного спроса на ИИ.",
                    generatedAt: referenceDate.addingTimeInterval(-1_209_600)
                )
            ]
        )
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
        event: SignalEvent?,
        rationale: String,
        drivers: [String],
        risks: [String]
    ) -> Stock {
        return Stock(
            ticker: ticker,
            name: name,
            sector: sector,
            price: price,
            dailyChangePercentage: change,
            marketCapBillions: cap,
            peRatio: pe,
            priceHistory: trend(start: trendStart, finish: price),
            signal: InvestmentSignal(
                action: action,
                horizon: horizon,
                confidence: confidence,
                explicitEvent: event,
                scenarios: [
                    Scenario(
                        title: "Позитивный",
                        description: "Драйверы реализуются быстрее базовых ожиданий.",
                        expectedPriceChange: 0.14
                    ),
                    Scenario(
                        title: "Базовый",
                        description: "Финансовые результаты соответствуют текущему консенсусу.",
                        expectedPriceChange: 0.05
                    ),
                    Scenario(
                        title: "Негативный",
                        description: "Риски реализуются, а ожидания рынка пересматриваются.",
                        expectedPriceChange: -0.12
                    )
                ],
                drivers: drivers,
                risks: risks,
                rationale: rationale,
                generatedAt: referenceDate.addingTimeInterval(-Double(ticker.count) * 3_600)
            )
        )
    }

    private static func trend(start: Double, finish: Double) -> [PricePoint] {
        let offsets = [-0.06, -0.025, 0.018, -0.012, 0.032, 0.009, -0.018, 0.026, 0.045, 0]
        return offsets.enumerated().map { index, offset in
            let progress = Double(index) / Double(offsets.count - 1)
            let interpolated = start + (finish - start) * progress
            return PricePoint(
                date: referenceDate.addingTimeInterval(Double(index - offsets.count + 1) * 86_400),
                close: interpolated * (1 + offset)
            )
        }
    }

    private static func date(daysAfterReference days: Int) -> Date {
        referenceDate.addingTimeInterval(Double(days) * 86_400)
    }
}
