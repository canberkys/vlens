import SwiftUI
import vLensCore

struct VCDTabView: View {
    let rows: [CDInfo]
    @State private var sortOrder = [FieldComparator<CDInfo>.value("vm", \.vmName)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("VM", sortUsing: FieldComparator.value("vm", \.vmName)) { Text($0.vmName) }
            TableColumn("Power", sortUsing: FieldComparator.value("power", \.powerState.rawValue)) { Text($0.powerState.rawValue) }
            TableColumn("Connected") { Text($0.connected ? "Yes" : "No") }
            TableColumn("ISO Path", sortUsing: FieldComparator.optional("iso", \.isoPath)) { Text($0.isoPath ?? "—") }
            TableColumn("Device", sortUsing: FieldComparator.optional("device", \.deviceName)) { Text($0.deviceName ?? "—") }
        }
    }
}
