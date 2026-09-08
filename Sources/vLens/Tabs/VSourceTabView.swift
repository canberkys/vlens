import SwiftUI
import vLensCore

struct VSourceTabView: View {
    let rows: [VCenterInfo]
    @Binding var sortOrder: [FieldComparator<VCenterInfo>]

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No vCenter Identity",
                systemImage: "server.rack",
                description: Text("Only populated once connected — this is the connected SDK/vCenter server's own identity, not inventory data.")
            )
        } else {
            Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn("Name", sortUsing: FieldComparator.value("name", \.name)) { Text($0.name) }
                TableColumn("Full Name", sortUsing: FieldComparator.value("fullName", \.fullName)) { Text($0.fullName) }
                TableColumn("Vendor", sortUsing: FieldComparator.value("vendor", \.vendor)) { Text($0.vendor) }
                TableColumn("Version", sortUsing: FieldComparator.value("version", \.version)) { Text($0.version) }
                TableColumn("Build", sortUsing: FieldComparator.value("build", \.build)) { Text($0.build) }
                TableColumn("OS Type", sortUsing: FieldComparator.value("osType", \.osType)) { Text($0.osType) }
                TableColumn("API Type", sortUsing: FieldComparator.value("apiType", \.apiType)) { Text($0.apiType) }
                TableColumn("API Version", sortUsing: FieldComparator.value("apiVersion", \.apiVersion)) { Text($0.apiVersion) }
                TableColumn("Instance UUID", sortUsing: FieldComparator.optional("instanceUUID", \.instanceUUID)) { Text($0.instanceUUID ?? "—") }
            }
        }
    }
}
