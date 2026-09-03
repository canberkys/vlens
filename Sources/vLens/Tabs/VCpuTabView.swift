import SwiftUI
import vLensCore

struct VCpuTabView: View {
    let rows: [VMCpuInfo]
    @State private var sortOrder = [FieldComparator<VMCpuInfo>.value("vm", \.vmName)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("VM", sortUsing: FieldComparator.value("vm", \.vmName)) { Text($0.vmName) }
            TableColumn("Power", sortUsing: FieldComparator.value("power", \.powerState.rawValue)) { Text($0.powerState.rawValue) }
            TableColumn("CPUs", sortUsing: FieldComparator.value("cpus", \.cpuCount)) { Text("\($0.cpuCount)") }
            TableColumn("Sockets", sortUsing: FieldComparator.value("sockets", \.sockets)) { Text("\($0.sockets)") }
            TableColumn("Cores p/s", sortUsing: FieldComparator.value("cores", \.coresPerSocket)) { Text("\($0.coresPerSocket)") }
            TableColumn("Overall MHz", sortUsing: FieldComparator.optional("mhz", \.overallUsageMHz)) { Text($0.overallUsageMHz.map(String.init) ?? "—") }
            TableColumn("Hot Add") { Text($0.hotAddEnabled ? "Yes" : "No") }
            TableColumn("Hot Remove") { Text($0.hotRemoveEnabled ? "Yes" : "No") }
            TableColumn("Host", sortUsing: FieldComparator.value("host", \.hostName)) { Text($0.hostName) }
            TableColumn("Cluster", sortUsing: FieldComparator.optional("cluster", \.clusterName)) { Text($0.clusterName ?? "—") }
        }
    }
}
