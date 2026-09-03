import SwiftUI
import vLensCore

struct VPortTabView: View {
    let rows: [VPortInfo]
    @State private var sortOrder = [FieldComparator<VPortInfo>.value("host", \.hostName)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Port Group", sortUsing: FieldComparator.value("name", \.name)) { Text($0.name) }
            TableColumn("Switch", sortUsing: FieldComparator.value("switch", \.switchName)) { Text($0.switchName) }
            TableColumn("Host", sortUsing: FieldComparator.value("host", \.hostName)) { Text($0.hostName) }
            TableColumn("VLAN", sortUsing: FieldComparator.value("vlan", \.vlanId)) { Text("\($0.vlanId)") }
        }
    }
}
