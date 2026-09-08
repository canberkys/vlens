import SwiftUI
import vLensCore

struct VPortTabView: View {
    let rows: [VPortInfo]
    @Binding var sortOrder: [FieldComparator<VPortInfo>]

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No Standard Port Groups",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("An environment fully migrated to Distributed Switches has none — check dvPort instead.")
            )
        } else {
            Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn("Port Group", sortUsing: FieldComparator.value("name", \.name)) { Text($0.name) }
                TableColumn("Switch", sortUsing: FieldComparator.value("switch", \.switchName)) { Text($0.switchName) }
                TableColumn("Host", sortUsing: FieldComparator.value("host", \.hostName)) { Text($0.hostName) }
                TableColumn("VLAN", sortUsing: FieldComparator.value("vlan", \.vlanId)) { Text("\($0.vlanId)") }
            }
        }
    }
}
