import SwiftUI
import vLensCore

struct DVSwitchTabView: View {
    let rows: [DVSwitchInfo]
    @Binding var sortOrder: [FieldComparator<DVSwitchInfo>]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Switch", sortUsing: FieldComparator.value("name", \.name)) { Text($0.name) }
            TableColumn("UUID", sortUsing: FieldComparator.value("uuid", \.uuid)) { Text($0.uuid) }
            TableColumn("Ports", sortUsing: FieldComparator.value("ports", \.numPorts)) { Text("\($0.numPorts)") }
            TableColumn("Hosts", sortUsing: FieldComparator.value("hosts", \.numHosts)) { Text("\($0.numHosts)") }
            TableColumn("Port Groups", sortUsing: FieldComparator.value("pgCount", \.numPortGroups)) { Text("\($0.numPortGroups)") }
        }
    }
}
