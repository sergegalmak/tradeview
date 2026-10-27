import Charts
import SwiftUI
#if SWIFT_PACKAGE
import TradeviewCore
#endif

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

                        Group {
                            let event = stock.signal.explicitEvent
                            GroupBox("Определённое событие") {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.title).font(.headline)
                                        Text("Ожидаемый срок: \(event.expectedBy.auditTimestamp)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text("Бенчмарк: \(event.benchmark)").font(.caption)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        TimelineView(.periodic(from: .now, by: 30)) { context in
                                            if store.blockingIssues(at: context.date).isEmpty,
                                               let probability = stock.signal.publishedProbability {
                                                Text(probability.percentString).font(.title2.bold().monospacedDigit())
                                                Text("Модельная вероятность события").font(.caption)
                                            } else {
                                                Text(stock.signal.publishedProbability == nil
                                                    ? "Недостаточно исторических наблюдений или нет подтверждённой калибровки"
                                                    : "Вероятность скрыта: данные недоступны для публикации")
                                                    .font(.caption).foregroundStyle(.secondary)
                                                    .frame(maxWidth: 250)
                                            }
                                        }
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
                                    Text(store.snapshot.source.isOfflineDemo ? "Шаблонные диапазоны для демонстрации интерфейса, не прогноз." : "Диапазоны модельной доходности на указанный горизонт, не обещание результата.")
                                        .font(.caption).foregroundStyle(.secondary)
                                    ForEach(stock.signal.scenarios) { scenario in
                                        HStack(alignment: .top) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(scenario.title).fontWeight(.semibold)
                                                Text(scenario.description)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text("\(scenario.minimumReturn.percentString)…\(scenario.maximumReturn.percentString)")
                                                .foregroundStyle(scenario.minimumReturn >= 0 ? .green : .red)
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

                        GroupBox("Условия отмены идеи") {
                            factorList(title: "Идея требует пересмотра, если", items: stock.signal.invalidationConditions, tint: .orange)
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
                            .accessibilityLabel("Исторические цены закрытия \(stock.ticker) в USD")
                            .padding(.top, 8)
                        }

                        GroupBox("Воспроизводимость сигнала") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Расчёт: \(stock.signal.generatedAt.auditTimestamp)")
                                Text("Срез входных данных: \(stock.signal.dataCutoff.auditTimestamp)")
                                Text("Модель: \(stock.signal.modelVersion) · Признаки: \(stock.signal.featureVersion)")
                                Text("Снимок признаков: \(stock.signal.featureSnapshotID)")
                            }.font(.caption).textSelection(.enabled)
                        }
                        MetricLineageView(provenance: stock.provenance)
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
                PublishedActionBadge(action: stock.signal.action)
                    .font(.title3)
                LabeledContent("Горизонт", value: stock.signal.horizon.title)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Уверенность")
                        Spacer()
                        Text(stock.signal.confidenceLabel)
                    }
                    ProgressView(value: stock.signal.confidence)
                        .tint(stock.signal.action.tint)
                        .accessibilityLabel("Уверенность: \(stock.signal.confidenceLabel). Не вероятность успеха.")
                    Text("Оценка полноты и согласованности данных, не вероятность доходности.")
                        .font(.caption).foregroundStyle(.secondary)
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
