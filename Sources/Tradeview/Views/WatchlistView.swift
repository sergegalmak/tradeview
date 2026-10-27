import SwiftUI
#if SWIFT_PACKAGE
import TradeviewCore
#endif

struct WatchlistView: View {
    @EnvironmentObject private var store: AppStore
    let openStock: (String) -> Void

    private var watchedStocks: [Stock] {
        store.snapshot.stocks.filter { store.watchlist.contains($0.ticker) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Наблюдение")
                .font(.largeTitle.bold())
            Text("Локально сохранённый список бумаг для повторного просмотра.")
                .foregroundStyle(.secondary)

            if watchedStocks.isEmpty {
                EmptyState(
                    title: "Список наблюдения пуст",
                    message: store.watchlist.isEmpty ? "Добавьте бумагу из её карточки, чтобы отслеживать сигнал и риски." : "Бумаги сохранены, но отсутствуют в текущем срезе данных.",
                    icon: "eye"
                )
            } else {
                List(watchedStocks) { stock in
                    HStack {
                        Button {
                            openStock(stock.ticker)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(stock.ticker).font(.headline)
                                Text(stock.name).font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                        Spacer()
                        Text(stock.price, format: .currency(code: "USD"))
                        PublishedActionBadge(action: stock.signal.action)
                        Text(stock.signal.confidenceLabel)
                            .frame(width: 70, alignment: .trailing)
                        Button {
                            store.toggleWatchlist(stock)
                        } label: {
                            Image(systemName: "eye.slash")
                        }
                        .buttonStyle(.borderless)
                        .help("Убрать из наблюдения")
                        .accessibilityLabel("Убрать \(stock.ticker) из наблюдения")
                    }.padding(.vertical, 4)
                }
                .listStyle(.inset)
            }

            DataProvenanceView(source: store.snapshot.source)
            DisclosureBanner()
        }
        .pageLayout(title: "Наблюдение")
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
