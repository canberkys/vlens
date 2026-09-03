import SwiftUI
import vLensCore

struct VAppTabView: View {
    let rows: [VAppInfo]
    @State private var sortOrder = [FieldComparator<VAppInfo>.value("name", \.name)]

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No vApps found",
                systemImage: "shippingbox",
                description: Text("vApps group related VMs with shared power-on order and product metadata — most environments don't use them.")
            )
        } else {
            Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn("vApp", sortUsing: FieldComparator.value("name", \.name)) { Text($0.name) }
                TableColumn("Owner", sortUsing: FieldComparator.optional("owner", \.ownerName)) { Text($0.ownerName ?? "—") }
                TableColumn("VMs", sortUsing: FieldComparator.value("vms", \.numVMs)) { Text("\($0.numVMs)") }
                TableColumn("Product", sortUsing: FieldComparator.optional("product", \.productName)) { Text($0.productName ?? "—") }
                TableColumn("Version", sortUsing: FieldComparator.optional("version", \.productVersion)) { Text($0.productVersion ?? "—") }
            }
        }
    }
}
