import SwiftUI

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
        Label(action.rawValue, systemImage: action.symbol)
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
                Text("Обновлено: \(source.updatedAt.formatted(date: .abbreviated, time: .shortened)) · Модель: \(source.modelVersion)")
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
            "Материал носит информационный характер, не гарантирует результат и не является персональной инвестиционной рекомендацией.",
            systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
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
