import SwiftUI

struct SignalHistoryView: View {
    @EnvironmentObject private var store: AppStore
    let openStock: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("История и прозрачность сигналов")
                .font(.largeTitle.bold())
            Text("Каждая запись показывает исходное действие, факторы, риски, горизонт и уровень уверенности модели.")
                .foregroundStyle(.secondary)

            List(store.snapshot.signalHistory) { item in
                Button {
                    openStock(item.ticker)
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.ticker).font(.headline)
                            Text(item.generatedAt, format: .dateTime.day().month().year().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ActionBadge(action: item.action)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.rationale)
                                .lineLimit(2)
                            Text("Горизонт: \(item.horizon.rawValue) · Уверенность: \(item.confidence.percentString)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)

            DataProvenanceView(source: store.snapshot.source)
            DisclosureBanner()
        }
        .pageLayout(title: "История сигналов")
    }
}

struct DisclosureView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Ограничения и методология")
                    .font(.largeTitle.bold())

                GroupBox("Что показывает приложение") {
                    Text("Tradeview объединяет детерминированный демонстрационный набор данных с объяснимыми сигналами: действием, горизонтом, уверенностью, сценариями, драйверами и рисками. Вероятность показывается только для конкретно сформулированного события.")
                        .fixedSize(horizontal: false, vertical: true)
                }

                GroupBox("Чего приложение не делает") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Не исполняет сделки и не подключается к брокеру.", systemImage: "xmark.shield")
                        Label("Не запрашивает и не хранит брокерские или ключи поставщиков данных.", systemImage: "key.slash")
                        Label("Не учитывает цели, доход, налоговый статус и приемлемый риск конкретного пользователя.", systemImage: "person.crop.circle.badge.questionmark")
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Данные") {
                    Text("Сейчас используется локальный офлайн-демо-набор. Для производственного использования внешний backend должен передавать нормализованный снимок MarketSnapshot по HTTPS. Ключи поставщиков остаются на backend, а не в приложении.")
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                }

                DataProvenanceView(source: store.snapshot.source)
                DisclosureBanner()
            }
            .pageLayout(title: "Ограничения")
        }
    }
}
