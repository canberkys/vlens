import SwiftUI
import vLensCore

struct VMKTabView: View {
    let rows: [VMKernelInfo]
    @State private var sortOrder = [FieldComparator<VMKernelInfo>.value("host", \.hostName)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Host", sortUsing: FieldComparator.value("host", \.hostName)) { Text($0.hostName) }
            TableColumn("Device", sortUsing: FieldComparator.value("device", \.device)) { Text($0.device) }
            TableColumn("Port Group", sortUsing: FieldComparator.value("pg", \.portGroup)) { Text($0.portGroup) }
            TableColumn("IP Address", sortUsing: FieldComparator.optional("ip", \.ipAddress)) { Text($0.ipAddress ?? "—") }
            TableColumn("MAC", sortUsing: FieldComparator.value("mac", \.mac)) { Text($0.mac) }
        }
    }
}
