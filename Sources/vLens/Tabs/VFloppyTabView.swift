import SwiftUI
import vLensCore

struct VFloppyTabView: View {
    let rows: [FloppyInfo]
    @State private var sortOrder = [FieldComparator<FloppyInfo>.value("vm", \.vmName)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("VM", sortUsing: FieldComparator.value("vm", \.vmName)) { Text($0.vmName) }
            TableColumn("Power", sortUsing: FieldComparator.value("power", \.powerState.rawValue)) { Text($0.powerState.rawValue) }
            TableColumn("Connected") { Text($0.connected ? "Yes" : "No") }
        }
    }
}
