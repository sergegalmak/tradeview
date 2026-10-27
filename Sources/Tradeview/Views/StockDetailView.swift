import Charts
import SwiftUI

struct StockDetailView: View {
    @EnvironmentObject private var store: AppStore
    let ticker: String

    var body: some View {
        Group {
            if let stock = store.stock(ticker: ticker) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(stock.ticker) · \(stock.name)")
                                    .font(.largeTitle.bold())
                                Text("\(stock.sector) · \(stock.price, format: .currency(code: "USD"))")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                store.toggleWatchlist(stock)
                            } label: {
                                Label(
                                    store.isWatched(stock) ? "В наблюдении" : "В наблюдение",
                                    systemImage: store.isWatched(stock) ? "eye.fill" : "eye"
                                )
                            }
                        }

                        HStack(spacing: 16) {
                            recommendationCard(stock)
                            priceCard(stock)
                        }

                        if let event = stock.signal.explicitEvent {
                            GroupBox("Определённое событие") {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.title).font(.headline)
                                        Text("Ожидаемый срок: \(event.expectedBy.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(event.probability.percentString)
                                            .font(.title2.bold().monospacedDigit())
                                        Text("вероятность события")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }

                        GroupBox("Обоснование сигнала") {
                            Text(stock.signal.rationale)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 4)
                        }

                        HStack(alignment: .top, spacing: 18) {
                            GroupBox("Сценарии") {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(stock.signal.scenarios) { scenario in
                                        HStack(alignment: .top) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(scenario.title).fontWeight(.semibold)
                                                Text(scenario.description)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text(scenario.expectedPriceChange, format: .percent.precision(.fractionLength(0)).sign(strategy: .always()))
                                                .foregroundStyle(scenario.expectedPriceChange >= 0 ? .green : .red)
                                                .font(.subheadline.monospacedDigit())
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .frame(maxWidth: .infinity)

                            GroupBox("Драйверы и риски") {
                                HStack(alignment: .top, spacing: 24) {
                                    factorList(title: "Драйверы", items: stock.signal.drivers, tint: .green)
                                    factorList(title: "Риски", items: stock.signal.risks, tint: .red)
                                }
                                .padding(.vertical, 4)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        GroupBox("Динамика закрытия") {
                            Chart(stock.priceHistory) { point in
                                LineMark(
                                    x: .value("Дата", point.date),
                                    y: .value("Цена", point.close)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(stock.signal.action.tint)
                            }
                            .chartYAxisLabel("USD")
                            .frame(height: 210)
                            .padding(.top, 8)
                        }

                        DataProvenanceView(source: store.snapshot.source)
                        DisclosureBanner()
                    }
                    .pageLayout(title: stock.ticker)
                }
            } else {
                EmptyState(
                    title: "Бумага не найдена",
                    message: "Эта запись отсутствует в текущем снимке данных.",
                    icon: "magnifyingglass"
                )
            }
        }
    }

    private func recommendationCard(_ stock: Stock) -> some View {
        GroupBox("Рекомендация") {
            VStack(alignment: .leading, spacing: 12) {
                ActionBadge(action: stock.signal.action)
                    .font(.title3)
                LabeledContent("Горизонт", value: stock.signal.horizon.rawValue)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Уверенность")
                        Spacer()
                        Text(stock.signal.confidence.percentString).monospacedDigit()
                    }
                    ProgressView(value: stock.signal.confidence)
                        .tint(stock.signal.action.tint)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func priceCard(_ stock: Stock) -> some View {
        GroupBox("Рыночные показатели") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Цена", value: stock.price.formatted(.currency(code: "USD")))
                LabeledContent(
                    "За день",
                    value: stock.dailyChangePercentage.formatted(
                        .number.sign(strategy: .always()).precision(.fractionLength(2))
                    ) + "%"
                )
                LabeledContent("P/E", value: stock.peRatio?.formatted(.number.precision(.fractionLength(1))) ?? "—")
                LabeledContent("Капитализация", value: "\(stock.marketCapBillions.formatted(.number.precision(.fractionLength(0)))) млрд USD")
            }
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func factorList(title: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
