import SwiftUI
import vLensCore

struct VDiskTabView: View {
    let rows: [VMDiskInfo]
    @State private var sortOrder = [FieldComparator<VMDiskInfo>.value("vm", \.vmName)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("VM", sortUsing: FieldComparator.value("vm", \.vmName)) { Text($0.vmName) }
            TableColumn("Disk", sortUsing: FieldComparator.value("disk", \.diskLabel)) { Text($0.diskLabel) }
            TableColumn("Capacity MiB", sortUsing: FieldComparator.value("capacity", \.capacityMiB)) { Text("\($0.capacityMiB)") }
            TableColumn("Thin") { Text($0.thinProvisioned ? "Yes" : "No") }
            TableColumn("Disk Mode", sortUsing: FieldComparator.value("mode", \.diskMode)) { Text($0.diskMode) }
            TableColumn("Controller", sortUsing: FieldComparator.value("controller", \.controller)) { Text($0.controller) }
            TableColumn("Path", sortUsing: FieldComparator.value("path", \.datastorePath)) { Text($0.datastorePath) }
            TableColumn("Host", sortUsing: FieldComparator.value("host", \.hostName)) { Text($0.hostName) }
        }
    }
}
