import SwiftUI
import vLensCore

struct VDatastoreTabView: View {
    let rows: [DatastoreInfo]
    @State private var sortOrder = [FieldComparator<DatastoreInfo>.value("name", \.name)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Datastore", sortUsing: FieldComparator.value("name", \.name)) { Text($0.name) }
            TableColumn("Type", sortUsing: FieldComparator.value("type", \.type)) { Text($0.type) }
            TableColumn("Capacity MiB", sortUsing: FieldComparator.value("capacity", \.capacityMiB)) { Text("\($0.capacityMiB)") }
            TableColumn("Free MiB", sortUsing: FieldComparator.value("free", \.freeMiB)) { Text("\($0.freeMiB)") }
            TableColumn("Free %", sortUsing: FieldComparator.value("freePercent", \.freePercent)) { row in
                Text(String(format: "%.1f", row.freePercent))
                    .foregroundStyle(row.freePercent < 10 ? Color.red : Color.primary)
            }
            TableColumn("VMs", sortUsing: FieldComparator.value("vms", \.numVMsTotal)) { Text("\($0.numVMsTotal)") }
            TableColumn("Hosts", sortUsing: FieldComparator.value("hosts", \.numHostsConnected)) { Text("\($0.numHostsConnected)") }
        }
    }
}
