import SwiftUI
import vLensCore

struct VHBATabView: View {
    let rows: [HBAInfo]
    @State private var sortOrder = [FieldComparator<HBAInfo>.value("host", \.hostName)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Host", sortUsing: FieldComparator.value("host", \.hostName)) { Text($0.hostName) }
            TableColumn("Device", sortUsing: FieldComparator.value("device", \.device)) { Text($0.device) }
            TableColumn("Model", sortUsing: FieldComparator.value("model", \.model)) { Text($0.model) }
            TableColumn("Driver", sortUsing: FieldComparator.value("driver", \.driver)) { Text($0.driver) }
            TableColumn("Status", sortUsing: FieldComparator.value("status", \.status)) { Text($0.status) }
        }
    }
}
