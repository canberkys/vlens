import SwiftUI
import vLensCore

struct DVPortTabView: View {
    let rows: [DVPortInfo]
    @State private var sortOrder = [FieldComparator<DVPortInfo>.value("name", \.name)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Port Group", sortUsing: FieldComparator.value("name", \.name)) { Text($0.name) }
            TableColumn("Switch", sortUsing: FieldComparator.value("switch", \.switchName)) { Text($0.switchName) }
            TableColumn("Ports", sortUsing: FieldComparator.value("ports", \.numPorts)) { Text("\($0.numPorts)") }
            TableColumn("VLAN", sortUsing: FieldComparator.optional("vlan", \.vlanId)) { Text($0.vlanId.map(String.init) ?? "—") }
        }
    }
}
