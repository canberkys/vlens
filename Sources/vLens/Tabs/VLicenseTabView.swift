import SwiftUI
import vLensCore

struct VLicenseTabView: View {
    let rows: [LicenseInfo]
    @State private var sortOrder = [FieldComparator<LicenseInfo>.value("name", \.name)]

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No license data",
                systemImage: "key.slash",
                description: Text("Either no licenses were returned, or the connected account doesn't have permission to see them (RVTools has the same restriction for read-only accounts).")
            )
        } else {
            Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn("Name", sortUsing: FieldComparator.value("name", \.name)) { Text($0.name) }
                TableColumn("Key", sortUsing: FieldComparator.value("key", \.key)) { Text($0.key) }
                TableColumn("Cost Unit", sortUsing: FieldComparator.value("costUnit", \.costUnit)) { Text($0.costUnit) }
                TableColumn("Total", sortUsing: FieldComparator.value("total", \.total)) { Text("\($0.total)") }
                TableColumn("Used", sortUsing: FieldComparator.value("used", \.used)) { Text("\($0.used)") }
                TableColumn("Expiration", sortUsing: FieldComparator.optional("expiration", \.expirationDate)) { Text($0.expirationDate ?? "—") }
                TableColumn("Labels") { Text($0.labels.joined(separator: ", ")) }
                TableColumn("Features") { Text($0.features.joined(separator: ", ")) }
            }
        }
    }
}
