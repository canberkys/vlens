import SwiftUI
import vLensCore

struct DVPortTabView: View {
    let rows: [DVPortInfo]
    @Binding var sortOrder: [FieldComparator<DVPortInfo>]

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No Distributed Port Groups",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("Requires vSphere Distributed Switch (Enterprise Plus or vSAN) — most environments using only standard vSwitches have none.")
            )
        } else {
            Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn("Port Group", sortUsing: FieldComparator.value("name", \.name)) { Text($0.name) }
                TableColumn("Switch", sortUsing: FieldComparator.value("switch", \.switchName)) { Text($0.switchName) }
                TableColumn("Ports", sortUsing: FieldComparator.value("ports", \.numPorts)) { Text("\($0.numPorts)") }
                TableColumn("VLAN", sortUsing: FieldComparator.optional("vlan", \.vlanId)) { Text($0.vlanId.map(String.init) ?? "—") }
            }
        }
    }
}
