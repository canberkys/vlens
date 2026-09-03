import SwiftUI
import vLensCore

struct VUSBTabView: View {
    let rows: [USBInfo]
    @State private var sortOrder = [FieldComparator<USBInfo>.value("vm", \.vmName)]

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No USB devices",
                systemImage: "cable.connector.slash",
                description: Text("No VM in this environment has a USB device attached.")
            )
        } else {
            Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn("VM", sortUsing: FieldComparator.value("vm", \.vmName)) { Text($0.vmName) }
                TableColumn("Power", sortUsing: FieldComparator.value("power", \.powerState.rawValue)) { Text($0.powerState.rawValue) }
                TableColumn("Connected") { Text($0.connected ? "Yes" : "No") }
                TableColumn("Vendor", sortUsing: FieldComparator.optional("vendor", \.vendor)) { Text($0.vendor.map { String(format: "0x%04X", $0) } ?? "—") }
                TableColumn("Product", sortUsing: FieldComparator.optional("product", \.product)) { Text($0.product.map { String(format: "0x%04X", $0) } ?? "—") }
            }
        }
    }
}
