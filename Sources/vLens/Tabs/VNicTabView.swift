import SwiftUI
import vLensCore

struct VNicTabView: View {
    let rows: [NicInfo]
    @State private var sortOrder = [FieldComparator<NicInfo>.value("host", \.hostName)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Host", sortUsing: FieldComparator.value("host", \.hostName)) { Text($0.hostName) }
            TableColumn("Device", sortUsing: FieldComparator.value("device", \.device)) { Text($0.device) }
            TableColumn("MAC", sortUsing: FieldComparator.value("mac", \.mac)) { Text($0.mac) }
            TableColumn("Link Speed Mb", sortUsing: FieldComparator.optional("speed", \.linkSpeedMb)) { Text($0.linkSpeedMb.map(String.init) ?? "—") }
            TableColumn("Driver", sortUsing: FieldComparator.optional("driver", \.driver)) { Text($0.driver ?? "—") }
        }
    }
}
