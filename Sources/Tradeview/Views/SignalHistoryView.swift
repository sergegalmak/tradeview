import SwiftUI
#if SWIFT_PACKAGE
import TradeviewCore
#endif

struct SignalHistoryView: View {
    @EnvironmentObject private var store: AppStore
    let openStock: (String) -> Void
    @State private var selectedRecord: SignalHistoryItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("История и прозрачность сигналов")
                .font(.largeTitle.bold())
            Text("Сохранённые снимки не заменяются новой рекомендацией. Результаты и backtest ещё не рассчитаны.")
                .foregroundStyle(.secondary)

            if let item = selectedRecord {
                Button {
                    selectedRecord = nil
                } label: {
                    Label("Назад к истории", systemImage: "chevron.left")
                }

                ScrollView {
                    archivedRecord(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            } else {
                if store.signalHistory.isEmpty {
                    EmptyState(
                        title: "История сигналов пока пуста",
                        message: "Здесь появятся неизменяемые снимки сохранённых сигналов с источниками и временем расчёта. Публичные котировки сами по себе не создают инвестиционных сигналов. Отсутствие записей не означает нулевую доходность или рассчитанный backtest.",
                        icon: "clock.arrow.circlepath"
                    )
                } else {
                    historyList
                }

                DataProvenanceView(source: store.snapshot.source)
                DisclosureBanner()
            }
        }
        .pageLayout(title: "История сигналов")
    }

    private var historyList: some View {
        List(store.signalHistory) { item in
            Button {
                selectedRecord = item
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.ticker).font(.headline)
                        Text(item.signal.generatedAt.auditTimestamp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading) {
                        Text(item.source.isOfflineDemo ? "Архив демо" : "Архив").font(.caption2)
                        ActionBadge(action: item.signal.action)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.signal.rationale)
                            .lineLimit(2)
                        Text("Горизонт: \(item.signal.horizon.title) · Уверенность: \(item.signal.confidenceLabel) · Модель: \(item.signal.modelVersion)")
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
    }

    private func archivedRecord(_ item: SignalHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Архив: \(item.ticker)").font(.title.bold())
            Text("Историческая запись, не текущая рекомендация.").foregroundStyle(.secondary)
            Text(item.source.isOfflineDemo ? "Архив демо" : "Архив").font(.caption2)
            ActionBadge(action: item.signal.action)
            Text("Расчёт: \(item.signal.generatedAt.auditTimestamp)")
            Text("Срез: \(item.signal.dataCutoff.auditTimestamp)")
            Text("Горизонт: \(item.signal.horizon.title) · Уверенность: \(item.signal.confidenceLabel)")
            Text("Модель: \(item.signal.modelVersion) · Признаки: \(item.signal.featureVersion)")
            Text("Снимок признаков: \(item.signal.featureSnapshotID)")
            Text(item.signal.rationale)
            Text(item.signal.explicitEvent.title)
            Text("Бенчмарк: \(item.signal.explicitEvent.benchmark)")
            Text("Срок: \(item.signal.explicitEvent.expectedBy.auditTimestamp)")
            Text("Фактический результат: ещё не рассчитан. Вероятности и доходность не выдумываются.")
                .foregroundStyle(.secondary)
            ForEach(item.signal.scenarios) { scenario in
                Text("\(scenario.title): \(scenario.minimumReturn.percentString)…\(scenario.maximumReturn.percentString)")
            }
            Text("Драйверы: \(item.signal.drivers.joined(separator: "; "))")
            Text("Риски: \(item.signal.risks.joined(separator: "; "))")
            Text("Отмена идеи: \(item.signal.invalidationConditions.joined(separator: "; "))")
            MetricLineageView(provenance: item.provenance)
            DataProvenanceView(source: item.source)
            DisclosureBanner()
            Button("Текущая карточка \(item.ticker)") { selectedRecord = nil; openStock(item.ticker) }
        }
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
                    Text("Tradeview — macOS-прототип. Демо содержит синтетические данные и шаблонные сценарии, а не работающую модель. Вероятность допускается только при наличии калибровочного отчёта для того же события, горизонта и версии модели. Порог в 200 наблюдений — защитный минимум, не доказательство качества модели.")
                        .fixedSize(horizontal: false, vertical: true)
                }

                GroupBox("Чего приложение не делает") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Не исполняет сделки и не подключается к брокеру.", systemImage: "xmark.shield")
                        Label("Не запрашивает и не хранит брокерские ключи.", systemImage: "key.slash")
                        Label("Не учитывает цели, доход, налоговый статус и приемлемый риск конкретного пользователя.", systemImage: "person.crop.circle.badge.questionmark")
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Данные") {
                    Text("Для исследовательских данных без TRADEVIEW_API_URL включено офлайн-демо. Публичные котировки загружаются отдельно и не создают инвестиционных сигналов. HTTPS-backend должен возвращать схему v2 с источниками, временными метками, качеством и версиями. Ошибки backend не подменяются демо-данными. Устаревшие или неполные данные блокируют публикацию действующих рекомендаций. Локальный архив не является защищённым серверным аудитом.")
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                }

                GroupBox("Ключи и лицензирование") {
                    Text("Личный ключ Twelve Data для настольного режима хранится в macOS Keychain и передаётся поставщику только в HTTP-заголовке, не в URL. Ключ не сохраняется в исходном коде или UserDefaults. Для production необходим серверный прокси: ключи провайдеров остаются на сервере. Также необходимы лицензии поставщиков и права на отображение и распространение данных; личный ключ сам по себе их не предоставляет.")
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
