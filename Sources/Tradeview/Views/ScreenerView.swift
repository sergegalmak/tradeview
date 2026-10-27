import SwiftUI

struct ScreenerView: View {
    @EnvironmentObject private var store: AppStore
    let openStock: (String) -> Void

    @State private var filters = ScreenerFilters()
    @State private var sort: ScreenerSort = .signalStrength

    private var sectors: [String] {
        Array(Set(store.snapshot.stocks.map(\.sector))).sorted()
    }

    private var results: [Stock] {
        ScreenerEngine.filteredStocks(store.snapshot.stocks, filters: filters, sort: sort)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Скринер перспективных акций")
                .font(.largeTitle.bold())
            Text("Фильтры применяются к текущему локальному снимку данных; это не торговый сигнал.")
                .foregroundStyle(.secondary)

            GroupBox("Фильтры") {
                HStack(spacing: 16) {
                    TextField("Тикер или компания", text: $filters.query)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    Picker("Сектор", selection: $filters.sector) {
                        Text("Все секторы").tag(nil as String?)
                        ForEach(sectors, id: \.self) { sector in
                            Text(sector).tag(sector as String?)
                        }
                    }
                    .frame(maxWidth: 180)
                    Picker("Действие", selection: $filters.action) {
                        Text("Все действия").tag(nil as InvestmentAction?)
                        ForEach(InvestmentAction.allCases) { action in
                            Text(action.rawValue).tag(action as InvestmentAction?)
                        }
                    }
                    .frame(maxWidth: 170)
                    Picker("Сортировка", selection: $sort) {
                        ForEach(ScreenerSort.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .frame(maxWidth: 170)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Мин. уверенность: \(filters.minimumConfidence.percentString)")
                            .font(.caption)
                        Slider(value: $filters.minimumConfidence, in: 0.50...0.90, step: 0.05)
                    }
                    .frame(width: 170)
                }
                .padding(.vertical, 4)
            }

            HStack {
                Text("Найдено: \(results.count)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                DataProvenanceView(source: store.snapshot.source)
                    .frame(maxWidth: 420)
            }

            if results.isEmpty {
                EmptyState(
                    title: "Подходящих бумаг нет",
                    message: "Снизьте порог уверенности или измените фильтры.",
                    icon: "line.3.horizontal.decrease.circle"
                )
            } else {
                List {
                    HStack {
                        Text("БУМАГА").frame(maxWidth: .infinity, alignment: .leading)
                        Text("ЦЕНА").frame(width: 96, alignment: .trailing)
                        Text("ЗА ДЕНЬ").frame(width: 92, alignment: .trailing)
                        Text("СИГНАЛ").frame(width: 130, alignment: .leading)
                        Text("УВЕРЕННОСТЬ").frame(width: 112, alignment: .trailing)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                    ForEach(results) { stock in
                        Button {
                            openStock(stock.ticker)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stock.ticker).fontWeight(.semibold)
                                    Text("\(stock.name) · \(stock.sector)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(stock.price, format: .currency(code: "USD"))
                                    .frame(width: 96, alignment: .trailing)
                                Text(stock.dailyChangePercentage, format: .number.sign(strategy: .always()).precision(.fractionLength(2)))
                                    .foregroundStyle(stock.dailyChangePercentage >= 0 ? .green : .red)
                                    .frame(width: 92, alignment: .trailing)
                                ActionBadge(action: stock.signal.action)
                                    .frame(width: 130, alignment: .leading)
                                Text(stock.signal.confidence.percentString)
                                    .monospacedDigit()
                                    .frame(width: 112, alignment: .trailing)
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.inset)
            }

            DisclosureBanner()
        }
        .pageLayout(title: "Скринер")
    }
}
