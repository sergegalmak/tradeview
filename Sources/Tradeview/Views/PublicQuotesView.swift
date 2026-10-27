import Charts
import SwiftUI
#if SWIFT_PACKAGE
import TradeviewCore
#endif

struct PublicQuotesView: View {
    @EnvironmentObject private var store: AppStore
    var ticker: String = "AAPL"
    @State private var keyInput = ""
    @State private var showCredentials = false

    private var quote: PublicQuote? { store.publicQuotes[ticker] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(ticker) · Котировки").font(.largeTitle.bold())
                        Text("Twelve Data · USD").foregroundStyle(.secondary)
                    }
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Button {
                            Task { await store.refreshPublicQuote() }
                        } label: {
                            Label(store.isRefreshingPublicQuote ? "Загрузка…" : "Обновить", systemImage: "arrow.clockwise")
                        }
                        .disabled(store.isRefreshingPublicQuote || context.date < store.nextPublicQuoteRefreshAt)
                    }
                    Button {
                        store.toggleWatchlist(ticker: ticker)
                    } label: {
                        Image(systemName: store.watchlist.contains(ticker) ? "star.fill" : "star")
                    }.help("Добавить или убрать из наблюдения")
                }
                Label(store.hasPersonalAPIKey
                    ? "Личный доступ Twelve Data. Наличие котировок, задержка и лимиты зависят от вашего тарифа. Это не гарантия real-time."
                    : "Без личного ключа доступен только AAPL через публичный demo-доступ поставщика. Для других акций настройте ключ ниже.", systemImage: "network")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                credentialSettings
                HStack {
                    Link("Источник: Twelve Data", destination: URL(string: "https://twelvedata.com/docs")!)
                    Link("Условия использования", destination: URL(string: "https://twelvedata.com/terms")!)
                }.font(.caption)
                if let error = store.quoteErrors[ticker] {
                    Label("Обновление не удалось: \(error) Предыдущий ответ, если есть, оставлен без изменений.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let quote {
                    quoteContent(quote)
                } else if store.isRefreshingPublicQuote {
                    ProgressView("Получение \(ticker) из API…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    EmptyState(title: "Котировка пока недоступна", message: "Требуется интернет и успешный ответ Twelve Data. Ошибка не подменяется демо-данными.", icon: "wifi.exclamationmark")
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("При активном приложении выбранный тикер обновляется раз в минуту; смена раздела не сбрасывает лимит. В фоне опрос приостановлен. Наблюдение хранит последние загруженные цены, без массового опроса.")
                        if context.date < store.nextPublicQuoteRefreshAt {
                            Text("Следующий запрос не раньше: \(store.nextPublicQuoteRefreshAt.formatted(date: .omitted, time: .standard)). После 429 — пауза 15 минут; после исчерпания дневной квоты может потребоваться больше времени.")
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                GroupBox("Без инвестиционных сигналов") {
                    Text("В этом режиме нет модели, вероятностей, фундаментальных показателей и рекомендаций. Котировки не смешиваются с демонстрационным портфелем, архивом или алертами. Права на production-отображение и распространение не подтверждены.")
                        .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(24)
        }
        .navigationTitle("Публичные котировки")
        .task(id: ticker) {
            store.selectPublicSymbol(ticker)
            await store.refreshPublicQuote()
        }
        .onDisappear { keyInput = "" }
    }

    private var credentialSettings: some View {
        DisclosureGroup("\(store.hasPersonalAPIKey ? "Личный ключ сохранён" : "Настроить личный API-ключ") · Связка ключей macOS", isExpanded: $showCredentials) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Введите ключ непосредственно здесь. Он хранится в Связке ключей, передаётся только в HTTPS-заголовке и не записывается в исходники или UserDefaults. Не отправляйте ключ в чат; опубликованный ключ лучше перевыпустить.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    SecureField("Личный ключ Twelve Data", text: $keyInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Сохранить") {
                        if store.saveAPIKey(keyInput) {
                            keyInput = ""
                            Task { await store.refreshPublicQuote() }
                        }
                    }.disabled(keyInput.isEmpty)
                    if store.hasPersonalAPIKey {
                        Button("Удалить ключ") {
                            store.removeAPIKey()
                            Task { await store.refreshPublicQuote() }
                        }
                    }
                }
                if let error = store.credentialError {
                    Label(error, systemImage: "lock.trianglebadge.exclamationmark").foregroundStyle(.orange)
                }
                Text("Сохранение не проверяет тариф. Ошибки авторизации или доступа отображаются без переключения на demo.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 8)
        }
    }

    private func quoteContent(_ quote: PublicQuote) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                MetricCard(title: "\(quote.symbol) · \(quote.name)",
                    value: quote.price.formatted(.currency(code: quote.currency)),
                    detail: "Последняя цена из /quote · \(quote.exchange)", tint: .secondary)
                MetricCard(title: "Изменение к предыдущему закрытию",
                    value: (quote.changePercentage / 100).formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())),
                    detail: quote.isMarketOpen ? "Сессия открыта по ответу API" : "Сессия закрыта по ответу API",
                    tint: quote.changePercentage >= 0 ? .green : .red)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if quote.isStale(at: context.date) {
                    Label("Котировка устарела по локальному порогу. Время получения не означает свежесть цены.", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
            }
            GroupBox("Дневные бары · \(quote.dailyPrices.count) торговых дней") {
                VStack(alignment: .leading, spacing: 10) {
                    Chart(quote.dailyPrices) { point in
                        LineMark(x: .value("Дата бара", point.date), y: .value("Цена USD", point.close))
                            .foregroundStyle(.blue)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 6)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let date = value.as(Date.self) { Text(barDate(date, quote: quote)) }
                            }
                        }
                    }
                    .frame(height: 280)
                    .accessibilityLabel("Дневные цены \(quote.symbol) из Twelve Data, в долларах США")
                    Text("Дата бара — начало дня в \(quote.exchangeTimeZone). Последний бар может быть незавершённым; это не подтверждённое EOD-закрытие. История скорректирована поставщиком на сплиты, не является total return.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Время цены (last_quote_at): \(quote.quoteAt.auditTimestamp)")
                Text("Ответы получены: \(quote.receivedAt.auditTimestamp)")
                Text("Выбор — по тикеру. Биржа показана из ответа API; это не выбор листинга по ISIN/MIC.")
                Text("Точное время публикации поставщиком не предоставлено. Ответы /quote и /time_series не атомарны и могут различаться.")
            }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    private func barDate(_ date: Date, quote: PublicQuote) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: quote.exchangeTimeZone)
        formatter.dateFormat = "dd MMM"
        return formatter.string(from: date)
    }
}

struct CatalogStockDetailView: View {
    let ticker: String
    var body: some View { PublicQuotesView(ticker: ticker).id(ticker) }
}