import SwiftUI
#if SWIFT_PACKAGE
import TradeviewCore
#endif

struct WatchlistView: View {
    @EnvironmentObject private var store: AppStore
    let openStock: (String) -> Void

    var body: some View {
        let tickers = store.watchlist.sorted()
        let instrumentsByTicker = Dictionary(grouping: store.instruments, by: \.symbol)
        TimelineView(.periodic(from: .now, by: 30)) { context in
            List {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Наблюдение")
                        .font(.largeTitle.bold())
                    Text("Сохранено бумаг: \(tickers.count). Список хранится локально; тикеры сохраняются, даже если их нет в каталоге.")
                        .foregroundStyle(.secondary)
                    Text("Каталог — не котировки. Цены загружаются при открытии; доступ зависит от тарифа. Нет инвестиционных сигналов.")
                        .foregroundStyle(.secondary)
                    PublicCatalogStatusView(now: context.date)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)

                if tickers.isEmpty {
                    ContentUnavailableView("Список наблюдения пуст", systemImage: "eye",
                        description: Text("Найдите компанию в скринере и нажмите значок глаза рядом с бумагой или добавьте её из публичной карточки. Открытие бумаги загружает доступную котировку."))
                } else {
                    ForEach(tickers, id: \.self) { ticker in
                        let candidates = instrumentsByTicker[ticker] ?? []
                        let quote = store.publicQuotes[ticker]
                        let instrument = candidates.first {
                            $0.exchange == quote?.exchange && $0.currency == quote?.currency
                        } ?? candidates.min { $0.id < $1.id }

                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                openStock(ticker)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ticker).font(.headline)
                                    if let instrument {
                                        Text(instrument.name)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text("\(instrument.exchange) · \(instrument.currency)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Нет в текущем каталоге · карточку можно открыть")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    PublicCatalogQuoteView(ticker: ticker, now: context.date)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Открыть публичную карточку \(ticker)")
                            Button {
                                store.toggleWatchlist(ticker: ticker)
                            } label: {
                                Image(systemName: "eye.slash")
                            }
                            .buttonStyle(.borderless)
                            .help("Убрать из наблюдения")
                            .accessibilityLabel("Убрать \(ticker) из наблюдения")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.inset)
        }
        .pageLayout(title: "Наблюдение")
        .task { await store.refreshStockCatalog() }
    }
}

struct AlertsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var ticker = ""
    @State private var kind: AlertKind = .actionChanged
    @State private var threshold = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Уведомления").font(.largeTitle.bold())
                Text("Локальная лента: проверка при успешном обновлении открытого приложения. Это не e-mail, web push или фоновый мониторинг.")
                    .foregroundStyle(.secondary)
                GroupBox("Создать правило") {
                    HStack {
                        TextField("Тикер", text: $ticker).frame(width: 100)
                        Picker("Событие", selection: $kind) {
                            ForEach(AlertKind.allCases) { Text($0.title).tag($0) }
                        }
                        if kind.needsThreshold {
                            TextField("Уровень, USD", text: $threshold).frame(width: 130)
                        }
                        Button("Добавить") {
                            error = store.addAlert(ticker: ticker, kind: kind,
                                threshold: kind.needsThreshold ? Double(threshold.replacingOccurrences(of: ",", with: ".")) : nil)
                            if error == nil { ticker = ""; threshold = "" }
                        }
                    }.textFieldStyle(.roundedBorder)
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }
                Text("Правила").font(.headline)
                if store.alertRules.isEmpty { Text("Нет правил.").foregroundStyle(.secondary) }
                ForEach(store.alertRules) { rule in
                    HStack {
                        Text(rule.ticker).bold()
                        Text(rule.kind.title)
                        if let threshold = rule.threshold { Text(threshold, format: .currency(code: "USD")) }
                        Spacer()
                        Button(role: .destructive) { store.removeAlert(id: rule.id) } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Удалить правило для \(rule.ticker)")
                    }
                }
                Divider()
                Text("События · последние 500").font(.headline)
                if store.notifications.isEmpty {
                    Text("Нет событий. Демо и неполные данные не вызывают уведомления; первое обновление только устанавливает исходный уровень.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.notifications) { notification in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(notification.ticker) · \(notification.message)")
                        Text(notification.createdAt.auditTimestamp).font(.caption).foregroundStyle(.secondary)
                    }
                }
                DisclosureBanner()
            }.pageLayout(title: "Уведомления")
        }
    }
}
