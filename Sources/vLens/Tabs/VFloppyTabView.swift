import SwiftUI
import vLensCore

struct VFloppyTabView: View {
    let rows: [FloppyInfo]
    @Binding var sortOrder: [FieldComparator<FloppyInfo>]

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No Floppy Devices",
                systemImage: "opticaldiscdrive",
                description: Text("Floppy devices are legacy hardware most VM templates no longer include.")
            )
        } else {
            Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn("VM", sortUsing: FieldComparator.value("vm", \.vmName)) { Text($0.vmName) }
                TableColumn("Power", sortUsing: FieldComparator.value("power", \.powerState.rawValue)) { Text($0.powerState.rawValue) }
                TableColumn("Connected") { Text($0.connected ? "Yes" : "No") }
            }
        }
    }
}
