import SwiftUI
import vLensCore

struct VInfoTabView: View {
    let vms: [VirtualMachineInfo]
    @State private var sortOrder = [FieldComparator<VirtualMachineInfo>.value("name", \.name)]

    var body: some View {
        Table(vms.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("VM", sortUsing: FieldComparator.value("name", \.name)) { Text($0.name) }
            TableColumn("Power", sortUsing: FieldComparator.value("powerState", \.powerState.rawValue)) { Text($0.powerState.rawValue) }
            TableColumn("Guest OS", sortUsing: FieldComparator.optional("guestOS", \.guestOSFullName)) { Text($0.guestOSFullName ?? "—") }
            TableColumn("CPU", sortUsing: FieldComparator.value("cpu", \.cpuCount)) { Text("\($0.cpuCount)") }
            TableColumn("Memory MiB", sortUsing: FieldComparator.value("memory", \.memoryMiB)) { Text("\($0.memoryMiB)") }
            TableColumn("Host", sortUsing: FieldComparator.value("host", \.hostName)) { Text($0.hostName) }
            TableColumn("Cluster", sortUsing: FieldComparator.optional("cluster", \.clusterName)) { Text($0.clusterName ?? "—") }
            TableColumn("IP", sortUsing: FieldComparator.optional("ip", \.primaryIPAddress)) { Text($0.primaryIPAddress ?? "—") }
            TableColumn("VMware Tools", sortUsing: FieldComparator.optional("tools", \.vmwareToolsStatus)) { Text($0.vmwareToolsStatus ?? "—") }
        }
    }
}
