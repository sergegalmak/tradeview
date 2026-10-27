import Charts
import SwiftUI
#if SWIFT_PACKAGE
import TradeviewCore
#endif

struct MarketOverviewView: View {
    @EnvironmentObject private var store: AppStore
    let openStock: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Обзор рынка")
                            .font(.largeTitle.bold())
                        Text(store.snapshot.source.isOfflineDemo ? "Синтетические исторические данные; не реальные котировки." : "Рыночный срез от настроенного backend.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label("Обновить", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isRefreshing)
                }

                if let error = store.refreshError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                    spacing: 12
                ) {
                    ForEach(store.snapshot.indices) { index in
                        MetricCard(
                            title: index.name,
                            value: index.symbol,
                            detail: index.changePercentage.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))) + "%",
                            tint: index.changePercentage >= 0 ? .green : .red
                        )
                    }
                }

                GroupBox("Движение индексов") {
                    Chart(store.snapshot.indices) { index in
                        BarMark(
                            x: .value("Индекс", index.symbol),
                            y: .value("Изменение", index.changePercentage)
                        )
                        .foregroundStyle(index.changePercentage >= 0 ? .green : .red)
                    }
                    .chartYAxisLabel("% за день")
                    .frame(height: 190)
                    .padding(.top, 8)
                }

                HStack(alignment: .top, spacing: 20) {
                    GroupBox("Выбранные сигналы") {
                        VStack(spacing: 0) {
                            ForEach(Array(store.snapshot.stocks.sorted { $0.signal.confidence > $1.signal.confidence }.prefix(5))) { stock in
                                Button {
                                    openStock(stock.ticker)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(stock.ticker).fontWeight(.semibold)
                                            Text(stock.name).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        PublishedActionBadge(action: stock.signal.action)
                                        Text(stock.signal.confidenceLabel)
                                            .font(.subheadline.monospacedDigit())
                                            .frame(width: 70, alignment: .trailing)
                                    }
                                    .padding(.vertical, 9)
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                        .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity)

                    GroupBox("Краткосрочный тренд") {
                        if let stock = store.snapshot.stock(ticker: "MSFT") {
                            Chart(stock.priceHistory) { point in
                                LineMark(
                                    x: .value("Дата", point.date),
                                    y: .value("Цена", point.close)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(.blue)
                                AreaMark(
                                    x: .value("Дата", point.date),
                                    y: .value("Цена", point.close)
                                )
                                .foregroundStyle(.blue.opacity(0.10))
                            }
                            .chartYAxisLabel("USD")
                            .frame(height: 195)
                            .accessibilityLabel("Исторические цены закрытия MSFT в USD")
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                HStack {
                    DataProvenanceView(source: store.snapshot.source)
                    Spacer()
                    Button("Открыть карточку MSFT") {
                        openStock("MSFT")
                    }
                }

                DisclosureBanner()
            }
            .pageLayout(title: "Обзор рынка")
        }
    }
}
