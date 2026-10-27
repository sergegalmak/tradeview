import SwiftUI
#if SWIFT_PACKAGE
import TradeviewCore
#endif

struct ScreenerView: View {
    @EnvironmentObject private var store: AppStore
    let openStock: (String) -> Void

    @State private var exchange: String?
    @State private var visibleLimit = 100

    private var exchanges: [String] {
        Array(Set(store.instruments.map(\.exchange))).sorted()
    }

    private var results: [PublicInstrument] {
        PublicStockSearch.results(store.instruments, query: store.stockSearchQuery, exchange: exchange)
    }

    var body: some View {
        let matches = results
        TimelineView(.periodic(from: .now, by: 30)) { context in
            List {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Скринер акций")
                        .font(.largeTitle.bold())
                    Text("Каталог — не котировки. Цены загружаются при открытии; доступ зависит от тарифа. Нет инвестиционных сигналов.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("Тикер или компания", text: $store.stockSearchQuery)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Поиск по тикеру или названию компании")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            exchangePicker
                            resetButton
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            exchangePicker
                            resetButton
                        }
                    }
                    if !store.instruments.isEmpty {
                        Text("Найдено: \(matches.count) · Показано: \(min(visibleLimit, matches.count)) · В каталоге: \(store.instruments.count)")
                            .font(.subheadline.weight(.medium))
                    }
                    PublicCatalogStatusView(now: context.date)
                }
                .padding(.vertical, 4)

                if matches.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(matches.prefix(visibleLimit))) { instrument in
                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                openStock(instrument.symbol)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(instrument.symbol).font(.headline)
                                    Text(instrument.name)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("\(instrument.exchange) · \(instrument.currency)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    PublicCatalogQuoteView(ticker: instrument.symbol,
                                        instrument: instrument, now: context.date)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Открыть публичную карточку \(instrument.symbol)")

                            Button {
                                store.toggleWatchlist(ticker: instrument.symbol)
                            } label: {
                                Image(systemName: store.watchlist.contains(instrument.symbol) ? "eye.fill" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .help(store.watchlist.contains(instrument.symbol) ? "Убрать из наблюдения" : "Добавить в наблюдение")
                            .accessibilityLabel("\(store.watchlist.contains(instrument.symbol) ? "Убрать из наблюдения" : "Добавить в наблюдение"): \(instrument.symbol)")
                        }
                        .padding(.vertical, 5)
                    }
                    if visibleLimit < matches.count {
                        Button("Загрузить ещё \(min(100, matches.count - visibleLimit))") {
                            visibleLimit += 100
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .pageLayout(title: "Скринер")
        .task { await store.refreshStockCatalog() }
        .onChange(of: store.stockSearchQuery) { _, _ in visibleLimit = 100 }
        .onChange(of: exchange) { _, _ in visibleLimit = 100 }
        .onChange(of: store.catalogUpdatedAt) { _, _ in
            visibleLimit = 100
            if let exchange, !exchanges.contains(exchange) { self.exchange = nil }
        }
    }

    private var exchangePicker: some View {
        Picker("Биржа", selection: $exchange) {
            Text("Все биржи").tag(nil as String?)
            ForEach(exchanges, id: \.self) { value in
                Text(value).tag(value as String?)
            }
        }
    }

    private var resetButton: some View {
        Button("Сбросить") {
            store.stockSearchQuery = ""
            exchange = nil
            visibleLimit = 100
        }
        .disabled(store.stockSearchQuery.isEmpty && exchange == nil)
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.instruments.isEmpty {
            if store.isLoadingCatalog {
                ContentUnavailableView("Загрузка каталога", systemImage: "network",
                    description: Text("Получаем список бумаг Twelve Data. Котировки всего каталога не запрашиваются."))
            } else if store.catalogError != nil {
                ContentUnavailableView("Каталог недоступен", systemImage: "exclamationmark.triangle",
                    description: Text("Проверьте подключение и повторите загрузку после указанного выше времени. Демо-бумаги не подставляются."))
            } else {
                ContentUnavailableView("Каталог пока пуст", systemImage: "list.bullet.rectangle",
                    description: Text("Загрузите каталог, чтобы искать реальные бумаги по тикеру или названию."))
            }
        } else {
            ContentUnavailableView("Ничего не найдено", systemImage: "magnifyingglass",
                description: Text("Измените тикер или название компании, выберите другую биржу либо сбросьте фильтры."))
        }
    }
}

/// Shared by the catalog and watchlist; refreshing the catalog never requests universe quotes.
struct PublicCatalogStatusView: View {
    @EnvironmentObject private var store: AppStore
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Link("Источник каталога: Twelve Data · акции США",
                destination: URL(string: "https://twelvedata.com/docs#stocks")!)
            if let updatedAt = store.catalogUpdatedAt {
                Text("Каталог получен: \(updatedAt.auditTimestamp). Обновляется не чаще раза в сутки после успешной загрузки.")
                    .foregroundStyle(.secondary)
            }
            if store.isLoadingCatalog {
                ProgressView("Загрузка каталога…")
                    .controlSize(.small)
            }
            if let error = store.catalogError {
                Text("Ошибка каталога: \(error)")
                    .foregroundStyle(.red)
                if !store.instruments.isEmpty {
                    Text("Показан последний успешно полученный каталог.")
                        .foregroundStyle(.secondary)
                }
            }
            if now < store.nextCatalogRefreshAt {
                Text("Следующая загрузка доступна: \(store.nextCatalogRefreshAt.auditTimestamp)")
                    .foregroundStyle(.secondary)
            }
            Button(store.catalogError == nil ? "Обновить каталог" : "Повторить загрузку каталога") {
                Task { await store.refreshStockCatalog() }
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoadingCatalog || now < store.nextCatalogRefreshAt)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Only displays an existing provider quote, never a synthetic price or signal.
struct PublicCatalogQuoteView: View {
    @EnvironmentObject private var store: AppStore
    let ticker: String
    var instrument: PublicInstrument? = nil
    let now: Date

    private var quote: PublicQuote? {
        guard let quote = store.publicQuotes[ticker],
              quote.symbol.caseInsensitiveCompare(ticker) == .orderedSame else { return nil }
        if let instrument {
            guard quote.exchange.caseInsensitiveCompare(instrument.exchange) == .orderedSame,
                  quote.currency.caseInsensitiveCompare(instrument.currency) == .orderedSame else { return nil }
        }
        return quote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let quote {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        price(quote)
                        change(quote)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        price(quote)
                        change(quote)
                    }
                }
                Text("Котировка: \(quote.quoteAt.auditTimestamp)")
                    .foregroundStyle(.secondary)
                Text("Получена: \(quote.receivedAt.auditTimestamp)")
                    .foregroundStyle(.secondary)
                if quote.isStale(at: now) {
                    Label("Устаревшая котировка", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
            } else {
                Text(store.hasPersonalAPIKey || ticker.caseInsensitiveCompare("AAPL") == .orderedSame
                    ? "Откройте для загрузки" : "Нужен API-ключ")
                    .foregroundStyle(.secondary)
            }
            if let error = store.quoteErrors[ticker] {
                Text("Ошибка котировки: \(error)")
                    .foregroundStyle(.red)
                if quote != nil {
                    Text("Показана последняя полученная котировка.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func price(_ quote: PublicQuote) -> some View {
        Text(quote.price, format: .currency(code: quote.currency))
            .fontWeight(.semibold)
            .monospacedDigit()
    }

    private func change(_ quote: PublicQuote) -> some View {
        Text(quote.changePercentage.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))) + "%")
            .foregroundStyle(quote.changePercentage >= 0 ? .green : .red)
            .monospacedDigit()
    }
}
