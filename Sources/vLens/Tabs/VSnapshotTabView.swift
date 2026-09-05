import SwiftUI
import vLensCore

struct VSnapshotTabView: View {
    let rows: [VMSnapshotInfo]
    @State private var sortOrder = [FieldComparator<VMSnapshotInfo>.value("created", \.createdDate)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("VM", sortUsing: FieldComparator.value("vm", \.vmName)) { Text($0.vmName) }
            TableColumn("Snapshot", sortUsing: FieldComparator.value("snapshot", \.snapshotName)) { Text($0.snapshotName) }
            TableColumn("Description", sortUsing: FieldComparator.optional("description", \.snapshotDescription)) { Text($0.snapshotDescription ?? "—") }
            TableColumn("Created", sortUsing: FieldComparator.value("created", \.createdDate)) { Text($0.createdDate.formatted(date: .abbreviated, time: .shortened)) }
            TableColumn("Age (days)", sortUsing: FieldComparator.value("age", \.ageInDays)) { Text("\($0.ageInDays)") }
            TableColumn("Size MiB (excl. deltas)", sortUsing: FieldComparator.optional("size", \.sizeMiBTotal)) { Text($0.sizeMiBTotal.map(String.init) ?? "—") }
            TableColumn("Quiesced") { Text($0.quiesced ? "Yes" : "No") }
            TableColumn("Host", sortUsing: FieldComparator.value("host", \.hostName)) { Text($0.hostName) }
            TableColumn("Cluster", sortUsing: FieldComparator.optional("cluster", \.clusterName)) { Text($0.clusterName ?? "—") }
        }
    }
}
