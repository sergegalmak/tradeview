import SwiftUI

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
                    message: "Добавьте бумагу из её карточки, чтобы отслеживать сигнал и риски.",
                    icon: "eye"
                )
            } else {
                List(watchedStocks) { stock in
                    Button {
                        openStock(stock.ticker)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(stock.ticker).font(.headline)
                                Text(stock.name).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(stock.price, format: .currency(code: "USD"))
                            ActionBadge(action: stock.signal.action)
                            Text(stock.signal.confidence.percentString)
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                            Button {
                                store.toggleWatchlist(stock)
                            } label: {
                                Image(systemName: "eye.slash")
                            }
                            .buttonStyle(.borderless)
                            .help("Убрать из наблюдения")
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }

            DataProvenanceView(source: store.snapshot.source)
            DisclosureBanner()
        }
        .pageLayout(title: "Наблюдение")
    }
}
