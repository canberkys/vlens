import SwiftUI
import vLensCore

struct VMultipathTabView: View {
    let rows: [MultipathInfo]
    @State private var sortOrder = [FieldComparator<MultipathInfo>.value("host", \.hostName)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Host", sortUsing: FieldComparator.value("host", \.hostName)) { Text($0.hostName) }
            TableColumn("Display Name", sortUsing: FieldComparator.value("name", \.displayName)) { Text($0.displayName) }
            TableColumn("Paths", sortUsing: FieldComparator.value("paths", \.numPaths)) { Text("\($0.numPaths)") }
            TableColumn("State", sortUsing: FieldComparator.value("state", \.operationalStateJoined)) { row in
                Text(row.operationalStateJoined)
                    .foregroundStyle(row.operationalState.contains(where: { $0 != "ok" }) ? Color.orange : Color.primary)
            }
            TableColumn("Vendor", sortUsing: FieldComparator.value("vendor", \.vendor)) { Text($0.vendor) }
            TableColumn("Model", sortUsing: FieldComparator.value("model", \.model)) { Text($0.model) }
        }
    }
}

private extension MultipathInfo {
    var operationalStateJoined: String { operationalState.isEmpty ? "—" : operationalState.joined(separator: ", ") }
}
