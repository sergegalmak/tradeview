import Foundation

enum InvestmentAction: String, Codable, CaseIterable, Identifiable, Hashable {
    case buy = "Покупать"
    case watch = "Наблюдать"
    case hold = "Держать"
    case reduce = "Сокращать"
    case avoid = "Избегать"

    var id: String { rawValue }
}

enum InvestmentHorizon: String, Codable, CaseIterable, Hashable {
    case shortTerm = "1–3 месяца"
    case mediumTerm = "3–12 месяцев"
    case longTerm = "12+ месяцев"
}

struct DataSourceInfo: Codable, Equatable, Sendable {
    let name: String
    let updatedAt: Date
    let modelVersion: String
    let isOfflineDemo: Bool
}

struct MarketIndex: Identifiable, Codable, Hashable {
    let symbol: String
    let name: String
    let changePercentage: Double

    var id: String { symbol }
}

struct PricePoint: Identifiable, Codable, Hashable {
    let date: Date
    let close: Double

    var id: Date { date }
}

struct SignalEvent: Codable, Hashable {
    let title: String
    let probability: Double
    let expectedBy: Date
}

struct Scenario: Identifiable, Codable, Hashable {
    let title: String
    let description: String
    let expectedPriceChange: Double

    var id: String { title }
}

struct InvestmentSignal: Codable, Hashable {
    let action: InvestmentAction
    let horizon: InvestmentHorizon
    let confidence: Double
    let explicitEvent: SignalEvent?
    let scenarios: [Scenario]
    let drivers: [String]
    let risks: [String]
    let rationale: String
    let generatedAt: Date
}

struct Stock: Identifiable, Codable, Hashable {
    let ticker: String
    let name: String
    let sector: String
    let price: Double
    let dailyChangePercentage: Double
    let marketCapBillions: Double
    let peRatio: Double?
    let priceHistory: [PricePoint]
    let signal: InvestmentSignal

    var id: String { ticker }
}

struct SignalHistoryItem: Identifiable, Codable, Hashable {
    let ticker: String
    let action: InvestmentAction
    let horizon: InvestmentHorizon
    let confidence: Double
    let rationale: String
    let generatedAt: Date

    var id: String { "\(ticker)-\(generatedAt.timeIntervalSince1970)" }
}

struct MarketSnapshot: Codable, Equatable {
    let source: DataSourceInfo
    let indices: [MarketIndex]
    let stocks: [Stock]
    let signalHistory: [SignalHistoryItem]

    func stock(ticker: String) -> Stock? {
        stocks.first { $0.ticker == ticker }
    }
}

struct ScreenerFilters: Equatable {
    var query = ""
    var sector: String?
    var action: InvestmentAction?
    var minimumConfidence = 0.55
}

enum ScreenerSort: String, CaseIterable, Identifiable {
    case signalStrength = "Сила сигнала"
    case dailyChange = "Изменение за день"
    case valuation = "P/E"
    case capitalization = "Капитализация"

    var id: String { rawValue }
}

enum ScreenerEngine {
    static func filteredStocks(
        _ stocks: [Stock],
        filters: ScreenerFilters,
        sort: ScreenerSort
    ) -> [Stock] {
        let query = filters.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = stocks.filter { stock in
            let matchesQuery = query.isEmpty ||
                stock.ticker.localizedCaseInsensitiveContains(query) ||
                stock.name.localizedCaseInsensitiveContains(query)
            let matchesSector = filters.sector == nil || stock.sector == filters.sector
            let matchesAction = filters.action == nil || stock.signal.action == filters.action
            let matchesConfidence = stock.signal.confidence >= filters.minimumConfidence
            return matchesQuery && matchesSector && matchesAction && matchesConfidence
        }

        return filtered.sorted { lhs, rhs in
            switch sort {
            case .signalStrength:
                return lhs.signal.confidence == rhs.signal.confidence
                    ? lhs.dailyChangePercentage > rhs.dailyChangePercentage
                    : lhs.signal.confidence > rhs.signal.confidence
            case .dailyChange:
                return lhs.dailyChangePercentage > rhs.dailyChangePercentage
            case .valuation:
                return (lhs.peRatio ?? .greatestFiniteMagnitude) < (rhs.peRatio ?? .greatestFiniteMagnitude)
            case .capitalization:
                return lhs.marketCapBillions > rhs.marketCapBillions
            }
        }
    }
}

struct PortfolioPosition: Identifiable, Codable, Hashable {
    let id: UUID
    let ticker: String
    let shares: Double
    let averageCost: Double

    init(id: UUID = UUID(), ticker: String, shares: Double, averageCost: Double) {
        self.id = id
        self.ticker = ticker.uppercased()
        self.shares = shares
        self.averageCost = averageCost
    }
}

struct PortfolioAllocation: Identifiable, Hashable {
    let ticker: String
    let sector: String
    let marketValue: Double
    let weight: Double

    var id: String { ticker }
}

struct PortfolioAnalysis: Equatable {
    let totalMarketValue: Double
    let totalCost: Double
    let allocations: [PortfolioAllocation]
    let warnings: [String]

    var unrealizedGain: Double { totalMarketValue - totalCost }
}

enum PortfolioAnalyzer {
    static func analyze(positions: [PortfolioPosition], stocks: [Stock]) -> PortfolioAnalysis {
        let stockByTicker = Dictionary(uniqueKeysWithValues: stocks.map { ($0.ticker, $0) })
        let values = positions.compactMap { position -> (PortfolioPosition, Stock, Double)? in
            guard let stock = stockByTicker[position.ticker] else { return nil }
            return (position, stock, position.shares * stock.price)
        }
        let totalMarketValue = values.reduce(0) { $0 + $1.2 }
        let totalCost = positions.reduce(0) { $0 + $1.shares * $1.averageCost }

        let allocations = values
            .map { position, stock, value in
                PortfolioAllocation(
                    ticker: position.ticker,
                    sector: stock.sector,
                    marketValue: value,
                    weight: totalMarketValue == 0 ? 0 : value / totalMarketValue
                )
            }
            .sorted { $0.marketValue > $1.marketValue }

        var warnings: [String] = []
        if let largest = allocations.first, largest.weight >= 0.35 {
            warnings.append("\(largest.ticker) составляет \(largest.weight.percentString) портфеля; это повышает риск концентрации.")
        }

        let sectorWeights = Dictionary(grouping: allocations, by: \.sector)
            .mapValues { $0.reduce(0) { $0 + $1.weight } }
        if let concentratedSector = sectorWeights.max(by: { $0.value < $1.value }), concentratedSector.value >= 0.50 {
            warnings.append("Сектор «\(concentratedSector.key)» составляет \(concentratedSector.value.percentString) портфеля.")
        }

        if allocations.count == 1, let allocation = allocations.first {
            warnings.append("Портфель состоит из одной позиции (\(allocation.ticker)); диверсификация отсутствует.")
        }

        return PortfolioAnalysis(
            totalMarketValue: totalMarketValue,
            totalCost: totalCost,
            allocations: allocations,
            warnings: warnings
        )
    }
}

extension Double {
    var percentString: String {
        formatted(.percent.precision(.fractionLength(0)))
    }
}
