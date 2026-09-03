import SwiftUI
import vLensCore

struct VMemoryTabView: View {
    let rows: [VMMemoryInfo]
    @State private var sortOrder = [FieldComparator<VMMemoryInfo>.value("vm", \.vmName)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("VM", sortUsing: FieldComparator.value("vm", \.vmName)) { Text($0.vmName) }
            TableColumn("Power", sortUsing: FieldComparator.value("power", \.powerState.rawValue)) { Text($0.powerState.rawValue) }
            TableColumn("Size MiB", sortUsing: FieldComparator.value("size", \.sizeMiB)) { Text("\($0.sizeMiB)") }
            TableColumn("Consumed MiB", sortUsing: FieldComparator.optional("consumed", \.consumedMiB)) { Text($0.consumedMiB.map(String.init) ?? "—") }
            TableColumn("Active MiB", sortUsing: FieldComparator.optional("active", \.activeMiB)) { Text($0.activeMiB.map(String.init) ?? "—") }
            TableColumn("Shared MiB", sortUsing: FieldComparator.optional("shared", \.sharedMiB)) { Text($0.sharedMiB.map(String.init) ?? "—") }
            TableColumn("Swapped MiB", sortUsing: FieldComparator.optional("swapped", \.swappedMiB)) { Text($0.swappedMiB.map(String.init) ?? "—") }
            TableColumn("Ballooned MiB", sortUsing: FieldComparator.optional("ballooned", \.balloonedMiB)) { Text($0.balloonedMiB.map(String.init) ?? "—") }
            TableColumn("Host", sortUsing: FieldComparator.value("host", \.hostName)) { Text($0.hostName) }
            TableColumn("Cluster", sortUsing: FieldComparator.optional("cluster", \.clusterName)) { Text($0.clusterName ?? "—") }
        }
    }
}
