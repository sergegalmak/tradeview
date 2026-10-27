import Charts
import SwiftUI
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import TradeviewCore
#endif

struct PortfolioView: View {
    @EnvironmentObject private var store: AppStore
    @State private var ticker = ""
    @State private var shares = ""
    @State private var averageCost = ""
    @State private var inputError: String?
    @State private var isImporting = false
    @State private var confirmClear = false
    @State private var confirmDemo = false

    private var analysis: PortfolioAnalysis {
        PortfolioAnalyzer.analyze(positions: store.portfolio, stocks: store.snapshot.stocks)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Портфель")
                            .font(.largeTitle.bold())
                        Text("Ручной учёт позиций для анализа концентрации; брокерская авторизация отсутствует.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Загрузить демо") {
                        confirmDemo = true
                    }
                    Button("Импорт CSV") {
                        isImporting = true
                    }
                    Button("Очистить", role: .destructive) {
                        confirmClear = true
                    }
                    .disabled(store.portfolio.isEmpty)
                }

                GroupBox("Добавить позицию") {
                    HStack {
                        TextField("Тикер", text: $ticker)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        TextField("Количество", text: $shares)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                        TextField("Средняя цена, USD", text: $averageCost)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                        Button("Добавить", action: addPosition)
                    }
                    if let inputError {
                        Text(inputError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if store.portfolio.isEmpty {
                    EmptyState(
                        title: "Портфель пуст",
                        message: "Добавьте позиции вручную или загрузите демо-портфель для анализа концентрации.",
                        icon: "briefcase"
                    )
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                        spacing: 12
                    ) {
                        MetricCard(
                            title: "Рыночная стоимость",
                            value: analysis.totalMarketValue?.formatted(.currency(code: "USD")) ?? "Недоступна",
                            detail: "Оценено бумаг: \(analysis.allocations.count)",
                            tint: .blue
                        )
                        MetricCard(
                            title: "Нереализованный P/L",
                            value: analysis.unrealizedGain?.formatted(.currency(code: "USD").sign(strategy: .always())) ?? "Недоступен",
                            detail: analysis.isComplete ? "против средней цены" : "есть позиции без оценки",
                            tint: (analysis.unrealizedGain ?? 0) >= 0 ? .green : .red
                        )
                        MetricCard(
                            title: "Крупнейшая позиция",
                            value: analysis.allocations.first?.ticker ?? "—",
                            detail: analysis.allocations.first?.weight.percentString ?? "—",
                            tint: .orange
                        )
                    }

                    HStack(alignment: .top, spacing: 18) {
                        GroupBox("Распределение позиций") {
                            Chart(analysis.allocations) { allocation in
                                BarMark(
                                    x: .value("Вес", allocation.weight),
                                    y: .value("Тикер", allocation.ticker)
                                )
                                .foregroundStyle(by: .value("Сектор", allocation.sector))
                            }
                            .chartXAxis {
                                AxisMarks(format: FloatingPointFormatStyle<Double>.Percent())
                            }
                            .frame(height: 190)
                            .accessibilityLabel("Распределение оценённой части портфеля по бумагам")
                            .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity)

                        GroupBox("Предупреждения о концентрации") {
                            if analysis.warnings.isEmpty {
                                Label("Существенных концентрационных рисков по текущим порогам не обнаружено.", systemImage: "checkmark.shield")
                                    .foregroundStyle(.green)
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(analysis.warnings, id: \.self) { warning in
                                        Label(warning, systemImage: "exclamationmark.triangle")
                                            .font(.subheadline)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Позиции") {
                        List {
                            ForEach(store.portfolio) { position in
                                positionRow(position)
                            }
                            .onDelete(perform: store.removePortfolioPositions)
                        }
                        .frame(minHeight: 180)
                    }
                }

                DataProvenanceView(source: store.snapshot.source)
                DisclosureBanner()
            }
            .pageLayout(title: "Портфель")
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.commaSeparatedText], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 1_000_000 else { inputError = "CSV превышает 1 МБ."; return }
                inputError = store.importPortfolioCSV(try String(contentsOf: url, encoding: .utf8))
            } catch { inputError = error.localizedDescription }
        }
        .confirmationDialog("Удалить все позиции портфеля?", isPresented: $confirmClear) {
            Button("Удалить все", role: .destructive) { store.clearPortfolio() }
        }
        .confirmationDialog("Заменить текущий портфель демонстрационным?", isPresented: $confirmDemo) {
            Button("Заменить", role: .destructive) { store.loadDemoPortfolio() }
        }
    }

    private func positionRow(_ position: PortfolioPosition) -> some View {
        let currentPrice = store.stock(ticker: position.ticker)?.price
        let marketValue = currentPrice.map { position.shares * $0 }
        return HStack {
            Text(position.ticker).fontWeight(.semibold)
            Text("\(position.shares.formatted(.number)) шт.")
                .foregroundStyle(.secondary)
            Spacer()
            Text("Ср. \(position.averageCost, format: .currency(code: "USD"))")
                .foregroundStyle(.secondary)
            Text(marketValue?.formatted(.currency(code: "USD")) ?? "Нет котировки")
                .frame(width: 120, alignment: .trailing)
        }
    }

    private func addPosition() {
        let parsedShares = Double(shares.replacingOccurrences(of: ",", with: "."))
        let parsedAverageCost = Double(averageCost.replacingOccurrences(of: ",", with: "."))
        guard let parsedShares, let parsedAverageCost else {
            inputError = "Введите числовые количество и среднюю цену."
            return
        }

        inputError = store.addPortfolioPosition(
            ticker: ticker,
            shares: parsedShares,
            averageCost: parsedAverageCost
        )
        guard inputError == nil else { return }
        ticker = ""
        shares = ""
        averageCost = ""
    }
}
