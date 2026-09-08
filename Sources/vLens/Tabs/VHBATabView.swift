import SwiftUI
import vLensCore

struct VHBATabView: View {
    let rows: [HBAInfo]
    @Binding var sortOrder: [FieldComparator<HBAInfo>]

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No HBAs",
                systemImage: "cable.connector.slash",
                description: Text("Storage-only-over-NFS or vSAN-without-Fibre-Channel hosts report none — this doesn't necessarily mean anything is wrong.")
            )
        } else {
            Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn("Host", sortUsing: FieldComparator.value("host", \.hostName)) { Text($0.hostName) }
                TableColumn("Device", sortUsing: FieldComparator.value("device", \.device)) { Text($0.device) }
                TableColumn("Model", sortUsing: FieldComparator.value("model", \.model)) { Text($0.model) }
                TableColumn("Driver", sortUsing: FieldComparator.value("driver", \.driver)) { Text($0.driver) }
                TableColumn("Status", sortUsing: FieldComparator.value("status", \.status)) { Text($0.status) }
            }
        }
    }
}
