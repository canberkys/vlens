import SwiftUI
import vLensCore

struct VHealthTabView: View {
    let rows: [HealthCheckResult]
    @State private var sortOrder = [FieldComparator<HealthCheckResult>.value("severity", \.severity.rawValue)]

    var body: some View {
        Group {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No issues found",
                    systemImage: "checkmark.circle",
                    description: Text("No findings from the health checks currently implemented.")
                )
            } else {
                Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
                    TableColumn("Severity", sortUsing: FieldComparator.value("severity", \.severity.rawValue)) { row in
                        Text(row.severity.rawValue)
                            .foregroundStyle(color(for: row.severity))
                    }
                    TableColumn("Rule", sortUsing: FieldComparator.value("rule", \.rule)) { Text($0.rule) }
                    TableColumn("Object", sortUsing: FieldComparator.value("object", \.relatedObject)) { Text($0.relatedObject) }
                    TableColumn("Message", sortUsing: FieldComparator.value("message", \.message)) { Text($0.message) }
                }
            }
        }
        .tutorialPopover(
            id: TutorialID.health, title: "vHealth",
            text: "Unlike every other tab, this isn't collected from vCenter directly — it's computed from data already gathered for the other tabs (snapshots, Tools status, datastore space, etc.). Thresholds are adjustable in Preferences."
        )
    }

    private func color(for severity: EntityStatus) -> Color {
        switch severity {
        case .red: return .red
        case .yellow: return .orange
        case .green: return .primary
        case .gray: return .secondary
        }
    }
}
