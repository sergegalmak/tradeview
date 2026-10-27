import SwiftUI
#if SWIFT_PACKAGE
import TradeviewCore
#endif

extension InvestmentAction {
    var tint: Color {
        switch self {
        case .buy: .green
        case .watch: .blue
        case .hold: .orange
        case .reduce: .purple
        case .avoid: .red
        }
    }

    var symbol: String {
        switch self {
        case .buy: "arrow.up.right"
        case .watch: "eye"
        case .hold: "minus"
        case .reduce: "arrow.down.right"
        case .avoid: "xmark"
        }
    }
}

extension View {
    func pageLayout(title: String) -> some View {
        navigationTitle(title)
            .padding(24)
    }
}

struct ActionBadge: View {
    let action: InvestmentAction

    var body: some View {
        Label(action.title, systemImage: action.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(action.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(action.tint.opacity(0.13), in: Capsule())
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct DataProvenanceView: View {
    let source: DataSourceInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: source.isOfflineDemo ? "internaldrive" : "network")
            VStack(alignment: .leading, spacing: 2) {
                Text(source.isOfflineDemo ? "Офлайн-демо: \(source.name)" : "Источник: \(source.name)")
                    .font(.caption.weight(.medium))
                Text("Срез: \(source.updatedAt.auditTimestamp) · Модель: \(source.modelVersion) · Признаки: \(source.featureVersion)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
    }
}

struct DisclosureBanner: View {
    var body: some View {
        Label(
            "Модельная аналитика, не персональная рекомендация. Прошлые результаты не гарантируют будущие. Сервис не исполняет сделки; исходные данные могут быть неполными.",
            systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct DataHealthBanner: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let issues = store.blockingIssues(at: context.date)
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Публикация действующих рекомендаций заблокирована", systemImage: "exclamationmark.shield")
                        .font(.subheadline.bold())
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Text(issue).font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct MetricLineageView: View {
    let provenance: [MetricProvenance]
    var body: some View {
        GroupBox("Источники и время исходных показателей") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(provenance, id: \.metric) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(item.metric) · \(item.provider)").font(.caption.bold())
                        Text("Событие: \(item.eventAt.auditTimestamp)")
                        Text("Опубликовано: \(item.publishedAt.auditTimestamp)")
                        Text("Получено: \(item.receivedAt.auditTimestamp)")
                        Text("Задержка получения после публикации: \(Int(item.receivedAt.timeIntervalSince(item.publishedAt))) с")
                        Text("ID: \(item.sourceID) · Схема: \(item.schemaVersion) · Качество: \(item.quality.rawValue)")
                        Text(item.limitation).foregroundStyle(.secondary)
                    }.font(.caption2).textSelection(.enabled)
                    Divider()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// All active recommendation surfaces use this gate; stale/demo actions are not actionable badges.
struct PublishedActionBadge: View {
    @EnvironmentObject private var store: AppStore
    let action: InvestmentAction
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if store.blockingIssues(at: context.date).isEmpty {
                ActionBadge(action: action)
            } else if store.snapshot.source.isOfflineDemo {
                Text("Демо: \(action.title)").font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Сигнал недоступен", systemImage: "exclamationmark.shield").font(.caption)
            }
        }
    }
}

extension Date {
    var auditTimestamp: String {
        formatted(.dateTime.year().month().day().hour().minute().timeZone(.identifier(.long)))
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    let icon: String

    var body: some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(message))
            .frame(maxWidth: .infinity, minHeight: 280)
    }
}
