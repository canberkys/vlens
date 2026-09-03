import SwiftUI
import vLensCore

struct VHostTabView: View {
    let rows: [HostInfo]
    @State private var sortOrder = [FieldComparator<HostInfo>.value("name", \.name)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Host", sortUsing: FieldComparator.value("name", \.name)) { Text($0.name) }
            TableColumn("Datacenter", sortUsing: FieldComparator.optional("datacenter", \.datacenterName)) { Text($0.datacenterName ?? "—") }
            TableColumn("Cluster", sortUsing: FieldComparator.optional("cluster", \.clusterName)) { Text($0.clusterName ?? "—") }
            TableColumn("Status", sortUsing: FieldComparator.value("status", \.configStatus.rawValue)) { row in
                Text(row.configStatus.rawValue)
                    .foregroundStyle(row.configStatus == .green ? Color.primary : Color.orange)
            }
            TableColumn("CPU Model", sortUsing: FieldComparator.value("cpuModel", \.cpuModel)) { Text($0.cpuModel) }
            TableColumn("CPU %", sortUsing: FieldComparator.optional("cpuPercent", \.cpuUsagePercent)) { Text($0.cpuUsagePercent.map { String(format: "%.0f", $0) } ?? "—") }
            TableColumn("Memory MiB", sortUsing: FieldComparator.value("memory", \.memoryTotalMiB)) { Text("\($0.memoryTotalMiB)") }
            TableColumn("Mem %", sortUsing: FieldComparator.optional("memPercent", \.memoryUsagePercent)) { Text($0.memoryUsagePercent.map { String(format: "%.0f", $0) } ?? "—") }
            TableColumn("VMs", sortUsing: FieldComparator.value("vms", \.numVMsRunning)) { Text("\($0.numVMsRunning)/\($0.numVMsTotal)") }
            TableColumn("ESXi Version", sortUsing: FieldComparator.value("esxVersion", \.esxVersion)) { Text($0.esxVersion) }
        }
    }
}
