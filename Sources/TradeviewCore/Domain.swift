import Foundation

public enum InvestmentAction: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case buy, watch, hold, reduce, avoid
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .buy: "Покупать"
        case .watch: "Наблюдать"
        case .hold: "Держать"
        case .reduce: "Сокращать"
        case .avoid: "Избегать"
        }
    }
}

public enum InvestmentHorizon: Int, Codable, CaseIterable, Hashable, Sendable {
    case oneMonth = 1, threeMonths = 3, sixMonths = 6, twelveMonths = 12
    public var title: String {
        switch self {
        case .oneMonth: "1 месяц"
        case .threeMonths: "3 месяца"
        case .sixMonths: "6 месяцев"
        case .twelveMonths: "12 месяцев"
        }
    }
}

public enum DataQuality: String, Codable, Sendable {
    case complete, degraded, unavailable
}

public struct DataSourceInfo: Codable, Hashable, Sendable {
    public let name: String
    public let updatedAt: Date
    public let modelVersion: String
    public let isOfflineDemo: Bool
    public let schemaVersion: Int
    public let featureVersion: String
    public let validUntil: Date
    public let quality: DataQuality
    public let issues: [String]
    public let displayRightsConfirmed: Bool

    public init(name: String, updatedAt: Date, modelVersion: String, isOfflineDemo: Bool,
                schemaVersion: Int = 2, featureVersion: String, validUntil: Date,
                quality: DataQuality = .complete, issues: [String] = [], displayRightsConfirmed: Bool = false) {
        self.name = name
        self.updatedAt = updatedAt
        self.modelVersion = modelVersion
        self.isOfflineDemo = isOfflineDemo
        self.schemaVersion = schemaVersion
        self.featureVersion = featureVersion
        self.validUntil = validUntil
        self.quality = quality
        self.issues = issues
        self.displayRightsConfirmed = displayRightsConfirmed
    }

    public func blockingIssues(at now: Date) -> [String] {
        var result = issues
        if isOfflineDemo { result.append("Демонстрационные данные — не действующие рекомендации.") }
        if quality != .complete { result.append("Данные неполные или недоступны.") }
        if updatedAt > now { result.append("Дата среза находится в будущем.") }
        if now >= validUntil { result.append("Срок актуальности данных истёк.") }
        if !isOfflineDemo && !displayRightsConfirmed { result.append("Права на отображение данных не подтверждены.") }
        return result
    }
}

/// Timestamps belong to each metric, not just the enclosing API response.
public struct MetricProvenance: Codable, Hashable, Sendable {
    public let metric: String
    public let eventAt: Date
    public let publishedAt: Date
    public let receivedAt: Date
    public let provider: String
    public let sourceID: String
    public let schemaVersion: Int
    public let quality: DataQuality
    public let limitation: String
}

public struct MarketIndex: Identifiable, Codable, Hashable, Sendable {
    public let symbol: String
    public let name: String
    public let changePercentage: Double
    public var id: String { symbol }
}

public struct PricePoint: Identifiable, Codable, Hashable, Sendable {
    public let date: Date
    public let close: Double
    public var id: Date { date }
}

public struct CalibrationEvidence: Codable, Hashable, Sendable {
    public let eventID: String
    public let modelVersion: String
    public let horizon: InvestmentHorizon
    public let sampleCount: Int
    public let brierScore: Double
    public let evaluatedAt: Date
    public let reportID: String

    // A conservative publication gate, not a substitute for research approval.
    public static let minimumSampleCount = 200
}

public struct SignalEvent: Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let benchmark: String
    public let probability: Double?
    public let expectedBy: Date
    public let calibration: CalibrationEvidence?
}

public struct Scenario: Identifiable, Codable, Hashable, Sendable {
    public let title: String
    public let description: String
    public let minimumReturn: Double
    public let maximumReturn: Double
    public var id: String { title }
}

public struct InvestmentSignal: Codable, Hashable, Sendable {
    public let action: InvestmentAction
    public let horizon: InvestmentHorizon
    /// Internal evidence consistency score; never a probability of investment success.
    public let confidence: Double
    public let explicitEvent: SignalEvent
    public let scenarios: [Scenario]
    public let drivers: [String]
    public let risks: [String]
    public let invalidationConditions: [String]
    public let rationale: String
    public let generatedAt: Date
    public let dataCutoff: Date
    public let modelVersion: String
    public let featureVersion: String
    public let featureSnapshotID: String

    public var confidenceLabel: String {
        confidence >= 0.75 ? "Высокая" : confidence >= 0.60 ? "Средняя" : "Низкая"
    }

    public var publishedProbability: Double? {
        guard let value = explicitEvent.probability, value.isFinite, (0...1).contains(value),
              let evidence = explicitEvent.calibration,
              evidence.eventID == explicitEvent.id, evidence.modelVersion == modelVersion,
              evidence.horizon == horizon, evidence.sampleCount >= CalibrationEvidence.minimumSampleCount,
              evidence.brierScore.isFinite, (0...1).contains(evidence.brierScore),
              evidence.evaluatedAt <= generatedAt, !evidence.reportID.isEmpty else { return nil }
        return value
    }
}

public struct Stock: Identifiable, Codable, Hashable, Sendable {
    public let ticker: String
    public let name: String
    public let sector: String
    public let price: Double
    public let dailyChangePercentage: Double
    public let marketCapBillions: Double
    public let peRatio: Double?
    public let priceHistory: [PricePoint]
    public let signal: InvestmentSignal
    public let provenance: [MetricProvenance]
    public var id: String { ticker }
}

/// The issued signal is immutable. Realized outcomes must be separate, audited server records.
public struct SignalHistoryItem: Identifiable, Codable, Hashable, Sendable {
    public let ticker: String
    public let signal: InvestmentSignal
    public let source: DataSourceInfo
    public let provenance: [MetricProvenance]
    public var id: String { "\(source.isOfflineDemo ? "demo" : "live")-\(ticker)-\(signal.generatedAt.timeIntervalSince1970)-\(signal.modelVersion)" }
}

public enum SignalArchive {
    public static func merging(_ existing: [SignalHistoryItem], with incoming: [SignalHistoryItem]) throws -> [SignalHistoryItem] {
        var records: [String: SignalHistoryItem] = [:]
        for item in existing + incoming {
            if let previous = records[item.id], previous != item {
                throw DataSourceError.invalidSnapshot("Попытка изменить опубликованный сигнал \(item.ticker).")
            }
            records[item.id] = item
        }
        return records.values.sorted { $0.signal.generatedAt == $1.signal.generatedAt
            ? $0.id < $1.id : $0.signal.generatedAt > $1.signal.generatedAt }
    }
}

public struct MarketSnapshot: Codable, Equatable, Sendable {
    public let source: DataSourceInfo
    public let indices: [MarketIndex]
    public let stocks: [Stock]
    public let signalHistory: [SignalHistoryItem]

    public static var empty: MarketSnapshot {
        MarketSnapshot(source: DataSourceInfo(name: "Данные ещё не загружены", updatedAt: .distantPast,
            modelVersion: "—", isOfflineDemo: false, featureVersion: "—", validUntil: .distantPast,
            quality: .unavailable), indices: [], stocks: [], signalHistory: [])
    }

    public func stock(ticker: String) -> Stock? { stocks.first { $0.ticker == ticker } }

    public func archiveRecords(preserving existing: [SignalHistoryItem]) throws -> [SignalHistoryItem] {
        let merged = try SignalArchive.merging(existing, with: signalHistory)
        var records = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
        for stock in stocks {
            let record = SignalHistoryItem(ticker: stock.ticker, signal: stock.signal, source: source, provenance: stock.provenance)
            if let original = records[record.id] {
                // A new market-response envelope must not rewrite issuance-time metadata.
                guard original.signal == record.signal, original.provenance == record.provenance else {
                    throw DataSourceError.invalidSnapshot("Изменены входные данные опубликованного сигнала \(stock.ticker).")
                }
            } else { records[record.id] = record }
        }
        return try SignalArchive.merging([], with: Array(records.values))
    }

    public func validated(at now: Date = Date()) throws -> MarketSnapshot {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw DataSourceError.invalidSnapshot(message) }
        }
        try require(source.schemaVersion == 2, "Не поддерживается версия схемы данных.")
        try require(!source.name.isEmpty && !source.modelVersion.isEmpty && !source.featureVersion.isEmpty,
                    "Отсутствует источник или версия модели/признаков.")
        try require(source.updatedAt <= now && source.validUntil >= source.updatedAt &&
                source.validUntil.timeIntervalSince(source.updatedAt) <= 96 * 3_600, "Некорректные даты среза (максимальный срок актуальности — 96 часов).")
        try require(Set(stocks.map(\.ticker)).count == stocks.count, "Повторяющиеся тикеры в снимке.")
        try require(Set(indices.map(\.id)).count == indices.count, "Повторяющиеся индексы.")
        try require(indices.allSatisfy { $0.changePercentage.isFinite }, "Некорректные значения индексов.")
        try require(!stocks.isEmpty || source.quality != .complete, "Пустой снимок помечен как полный.")
        for stock in stocks {
            try require(!stock.ticker.isEmpty && stock.ticker == stock.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), "Некорректный тикер.")
            try require(stock.price.isFinite && stock.price > 0 && stock.marketCapBillions.isFinite && stock.marketCapBillions > 0 && stock.dailyChangePercentage.isFinite,
                        "Некорректные рыночные значения \(stock.ticker).")
            try require(stock.peRatio?.isFinite ?? true, "Некорректный P/E.")
            try require(Set(stock.priceHistory.map(\.date)).count == stock.priceHistory.count && stock.priceHistory.allSatisfy {
                $0.close.isFinite && $0.close > 0 && $0.date <= source.updatedAt
            }, "Некорректная история цен.")
            try Self.validate(signal: stock.signal, provenance: stock.provenance, source: source)
        }
        for item in signalHistory {
            try Self.validate(signal: item.signal, provenance: item.provenance, source: item.source)
            try require(item.source.schemaVersion == 2 && item.source.updatedAt <= source.updatedAt && item.source.isOfflineDemo == source.isOfflineDemo,
                        "Некорректный источник исторического сигнала.")
        }
        _ = try archiveRecords(preserving: [])
        return self
    }

    private static func validate(signal: InvestmentSignal, provenance: [MetricProvenance], source: DataSourceInfo) throws {
        let event = signal.explicitEvent
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let expectedBy = calendar.date(byAdding: .month, value: signal.horizon.rawValue, to: signal.generatedAt)
        let requiredMetrics: Set<String> = ["price", "marketCapBillions", "peRatio", "priceHistory", "signal"]
        guard signal.confidence.isFinite, (0...1).contains(signal.confidence),
              signal.dataCutoff <= signal.generatedAt, signal.generatedAt <= source.updatedAt,
              source.updatedAt.timeIntervalSince(signal.generatedAt) <= 96 * 3_600,
              signal.modelVersion == source.modelVersion, signal.featureVersion == source.featureVersion,
              !signal.featureSnapshotID.isEmpty, !signal.rationale.isEmpty, !signal.risks.isEmpty,
              !signal.invalidationConditions.isEmpty, !event.id.isEmpty, !event.title.isEmpty,
              !event.benchmark.isEmpty, event.expectedBy == expectedBy,
              event.probability.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
              signal.scenarios.count == 3, Set(signal.scenarios.map(\.id)).count == 3,
              signal.scenarios.allSatisfy({ $0.minimumReturn.isFinite && $0.maximumReturn.isFinite && $0.minimumReturn >= -1 && $0.minimumReturn <= $0.maximumReturn }),
              requiredMetrics.isSubset(of: Set(provenance.map(\.metric))),
              Set(provenance.map(\.metric)).count == provenance.count,
              provenance.allSatisfy({ !$0.provider.isEmpty && !$0.sourceID.isEmpty && $0.schemaVersion > 0 && $0.eventAt <= $0.publishedAt && $0.publishedAt <= $0.receivedAt && $0.receivedAt <= signal.dataCutoff && (source.quality != .complete || $0.quality == .complete) }),
              provenance.filter({ $0.metric == "price" }).allSatisfy({ signal.dataCutoff.timeIntervalSince($0.eventAt) <= 96 * 3_600 }) else {
            throw DataSourceError.invalidSnapshot("Неполный сигнал или нарушена временная последовательность исходных данных.")
        }
    }
}

public struct ScreenerFilters: Equatable {
    public var query: String
    public var sector: String?
    public var action: InvestmentAction?
    public var minimumConfidence: Double
    public var minimumMarketCapBillions: Double
    public var maximumPE: Double?

    public init(query: String = "", sector: String? = nil, action: InvestmentAction? = nil,
                minimumConfidence: Double = 0, minimumMarketCapBillions: Double = 0, maximumPE: Double? = nil) {
        self.query = query; self.sector = sector; self.action = action
        self.minimumConfidence = minimumConfidence
        self.minimumMarketCapBillions = minimumMarketCapBillions; self.maximumPE = maximumPE
    }
}

public enum ScreenerSort: String, CaseIterable, Identifiable {
    case signalStrength = "Согласованность данных"
    case dailyChange = "Изменение за день"
    case valuation = "P/E"
    case capitalization = "Капитализация"
    public var id: String { rawValue }
}

public enum ScreenerEngine {
    public static func filteredStocks(_ stocks: [Stock], filters: ScreenerFilters, sort: ScreenerSort) -> [Stock] {
        let query = filters.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return stocks.filter { stock in
            (query.isEmpty || stock.ticker.localizedCaseInsensitiveContains(query) || stock.name.localizedCaseInsensitiveContains(query)) &&
            (filters.sector == nil || stock.sector == filters.sector) &&
            (filters.action == nil || stock.signal.action == filters.action) &&
            stock.signal.confidence >= filters.minimumConfidence && stock.marketCapBillions >= filters.minimumMarketCapBillions &&
            (filters.maximumPE.map { ceiling in stock.peRatio.map { $0 > 0 && $0 <= ceiling } ?? false } ?? true)
        }.sorted { lhs, rhs in
            let left: Double
            let right: Double
            switch sort {
            case .signalStrength: left = lhs.signal.confidence; right = rhs.signal.confidence
            case .dailyChange: left = lhs.dailyChangePercentage; right = rhs.dailyChangePercentage
            case .valuation:
                left = lhs.peRatio.flatMap { $0 > 0 ? $0 : nil } ?? .greatestFiniteMagnitude
                right = rhs.peRatio.flatMap { $0 > 0 ? $0 : nil } ?? .greatestFiniteMagnitude
            case .capitalization: left = lhs.marketCapBillions; right = rhs.marketCapBillions
            }
            if left == right { return lhs.ticker < rhs.ticker }
            return sort == .valuation ? left < right : left > right
        }
    }
}

public struct PortfolioPosition: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let ticker: String
    public let shares: Double
    public let averageCost: Double
    public init(id: UUID = UUID(), ticker: String, shares: Double, averageCost: Double) {
        self.id = id
        self.ticker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.shares = shares; self.averageCost = averageCost
    }
    public var isValid: Bool {
        !ticker.isEmpty && shares.isFinite && shares > 0 && averageCost.isFinite && averageCost >= 0 && (shares * averageCost).isFinite
    }
}

public struct PortfolioAllocation: Identifiable, Hashable {
    public let ticker: String
    public let sector: String
    public let marketValue: Double
    public let weight: Double
    public var id: String { ticker }
}

public struct PortfolioAnalysis: Equatable {
    public let pricedMarketValue: Double
    public let pricedCost: Double
    public let unpricedTickers: [String]
    public let invalidPositionCount: Int
    public let allocations: [PortfolioAllocation]
    public let warnings: [String]
    public var isComplete: Bool { unpricedTickers.isEmpty && invalidPositionCount == 0 }
    public var totalMarketValue: Double? { isComplete ? pricedMarketValue : nil }
    public var unrealizedGain: Double? { isComplete ? pricedMarketValue - pricedCost : nil }
}

public enum PortfolioAnalyzer {
    public static func analyze(positions: [PortfolioPosition], stocks: [Stock]) -> PortfolioAnalysis {
        // Ambiguous/duplicate quotes are treated as unavailable instead of trapping.
        let quotes = Dictionary(grouping: stocks, by: \.ticker)
        var values: [String: (sector: String, value: Double)] = [:]
        var missing = Set<String>()
        var invalid = 0
        var cost = 0.0 // Only the cost basis of positions with a matched, valid quote.
        for position in positions {
            guard position.isValid else { invalid += 1; continue }
            let ticker = position.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard let matches = quotes[ticker], matches.count == 1, let stock = matches.first,
                  stock.price.isFinite, stock.price > 0, (stock.price * position.shares).isFinite else {
                missing.insert(ticker); continue
            }
            let previous = values[ticker]?.value ?? 0
            values[ticker] = (stock.sector, previous + stock.price * position.shares)
            cost += position.shares * position.averageCost
        }
        let total = values.values.reduce(0) { $0 + $1.value }
        // Overflow must never leak NaN/Inf into money values or concentration charts.
        if !total.isFinite || !cost.isFinite {
            return PortfolioAnalysis(pricedMarketValue: 0, pricedCost: 0, unpricedTickers: [], invalidPositionCount: positions.count,
                allocations: [], warnings: ["Слишком большие числовые значения; оценка портфеля недоступна."])
        }
        let unsortedAllocations: [PortfolioAllocation] = values.map { ticker, item in
            PortfolioAllocation(ticker: ticker, sector: item.sector, marketValue: item.value, weight: total == 0 ? 0 : item.value / total)
        }
        let allocations = unsortedAllocations.sorted { lhs, rhs in
            if lhs.marketValue == rhs.marketValue { return lhs.ticker < rhs.ticker }
            return lhs.marketValue > rhs.marketValue
        }
        var warnings: [String] = []
        if !missing.isEmpty { warnings.append("Нет однозначной котировки: \(missing.sorted().joined(separator: ", ")). Итоговая стоимость и P/L недоступны; веса рассчитаны только по оценённой части.") }
        if invalid > 0 { warnings.append("Некорректных позиций: \(invalid). Итоговая оценка недоступна.") }
        if let largest = allocations.first, largest.weight >= 0.35 {
            warnings.append("\(largest.ticker) составляет \(largest.weight.percentString) оценённой части; это повышает риск концентрации.")
        }
        let sectors = Dictionary(grouping: allocations, by: \.sector).mapValues { $0.reduce(0) { $0 + $1.weight } }
        for sector in sectors.keys.sorted() where sectors[sector, default: 0] >= 0.5 {
            warnings.append("Сектор «\(sector)» составляет \(sectors[sector, default: 0].percentString) оценённой части.")
        }
        if allocations.count == 1 { warnings.append("Оценена одна бумага; диверсификация этой части отсутствует.") }
        return PortfolioAnalysis(pricedMarketValue: total, pricedCost: cost, unpricedTickers: missing.sorted(),
            invalidPositionCount: invalid, allocations: allocations, warnings: warnings)
    }
}

extension Double {
    public var percentString: String { formatted(.percent.precision(.fractionLength(0))) }
}
