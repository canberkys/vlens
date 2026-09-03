import SwiftUI
import vLensCore

struct VPartitionTabView: View {
    let rows: [PartitionInfo]
    @State private var sortOrder = [FieldComparator<PartitionInfo>.value("vm", \.vmName)]

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No partition data",
                systemImage: "internaldrive.fill",
                description: Text("Requires VMware Tools to be running and reporting guest disk usage.")
            )
        } else {
            Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn("VM", sortUsing: FieldComparator.value("vm", \.vmName)) { Text($0.vmName) }
                TableColumn("Disk Path", sortUsing: FieldComparator.value("path", \.diskPath)) { Text($0.diskPath) }
                TableColumn("Capacity MiB", sortUsing: FieldComparator.value("capacity", \.capacityMiB)) { Text("\($0.capacityMiB)") }
                TableColumn("Free MiB", sortUsing: FieldComparator.value("free", \.freeMiB)) { Text("\($0.freeMiB)") }
                TableColumn("Free %", sortUsing: FieldComparator.value("freePct", \.freePercent)) { row in
                    Text(String(format: "%.1f", row.freePercent))
                        .foregroundStyle(row.freePercent < 10 ? Color.red : Color.primary)
                }
            }
        }
    }
}
