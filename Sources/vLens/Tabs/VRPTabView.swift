import SwiftUI
import vLensCore

struct VRPTabView: View {
    let rows: [ResourcePoolInfo]
    @State private var sortOrder = [FieldComparator<ResourcePoolInfo>.value("name", \.name)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Resource Pool", sortUsing: FieldComparator.value("name", \.name)) { Text($0.name) }
            TableColumn("Owner", sortUsing: FieldComparator.optional("owner", \.ownerName)) { Text($0.ownerName ?? "—") }
            TableColumn("CPU Reservation MHz", sortUsing: FieldComparator.value("cpuRes", \.cpuReservationMHz)) { Text("\($0.cpuReservationMHz)") }
            TableColumn("CPU Limit MHz", sortUsing: FieldComparator.value("cpuLimit", \.cpuLimitMHz)) { Text($0.cpuLimitMHz == -1 ? "Unlimited" : "\($0.cpuLimitMHz)") }
            TableColumn("Memory Reservation MiB", sortUsing: FieldComparator.value("memRes", \.memoryReservationMiB)) { Text("\($0.memoryReservationMiB)") }
            TableColumn("Memory Limit MiB", sortUsing: FieldComparator.value("memLimit", \.memoryLimitMiB)) { Text($0.memoryLimitMiB == -1 ? "Unlimited" : "\($0.memoryLimitMiB)") }
            TableColumn("VMs", sortUsing: FieldComparator.value("vms", \.numVMs)) { Text("\($0.numVMs)") }
        }
    }
}
