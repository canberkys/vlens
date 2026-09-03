import SwiftUI
import vLensCore

struct VToolsTabView: View {
    let rows: [VMToolsInfo]
    @State private var sortOrder = [FieldComparator<VMToolsInfo>.value("vm", \.vmName)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("VM", sortUsing: FieldComparator.value("vm", \.vmName)) { Text($0.vmName) }
            TableColumn("Power", sortUsing: FieldComparator.value("power", \.powerState.rawValue)) { Text($0.powerState.rawValue) }
            TableColumn("HW Version", sortUsing: FieldComparator.value("hwVersion", \.hardwareVersion)) { Text($0.hardwareVersion) }
            TableColumn("Tools", sortUsing: FieldComparator.value("tools", \.toolsStatus.rawValue)) { row in
                Text(row.toolsStatus.rawValue)
                    .foregroundStyle(row.toolsStatus == .toolsOk ? Color.primary : Color.orange)
            }
            TableColumn("Tools Version", sortUsing: FieldComparator.optional("toolsVersion", \.toolsVersion)) { Text($0.toolsVersion ?? "—") }
            TableColumn("Host", sortUsing: FieldComparator.value("host", \.hostName)) { Text($0.hostName) }
            TableColumn("Cluster", sortUsing: FieldComparator.optional("cluster", \.clusterName)) { Text($0.clusterName ?? "—") }
        }
    }
}
