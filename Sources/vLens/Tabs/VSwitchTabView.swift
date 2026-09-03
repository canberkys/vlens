import SwiftUI
import vLensCore

struct VSwitchTabView: View {
    let rows: [VSwitchInfo]
    @State private var sortOrder = [FieldComparator<VSwitchInfo>.value("host", \.hostName)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Switch", sortUsing: FieldComparator.value("name", \.name)) { Text($0.name) }
            TableColumn("Host", sortUsing: FieldComparator.value("host", \.hostName)) { Text($0.hostName) }
            TableColumn("Ports", sortUsing: FieldComparator.value("ports", \.numPorts)) { Text("\($0.numPorts)") }
            TableColumn("Ports Available", sortUsing: FieldComparator.value("portsAvail", \.numPortsAvailable)) { Text("\($0.numPortsAvailable)") }
            TableColumn("MTU", sortUsing: FieldComparator.value("mtu", \.mtu)) { Text("\($0.mtu)") }
            TableColumn("Uplinks", sortUsing: FieldComparator.value("uplinks", \.numUplinks)) { Text("\($0.numUplinks)") }
            TableColumn("Port Groups", sortUsing: FieldComparator.value("pgCount", \.numPortGroups)) { Text("\($0.numPortGroups)") }
        }
    }
}
