import SwiftUI
import vLensCore

struct VNetworkTabView: View {
    let rows: [VMNetworkInfo]
    @State private var sortOrder = [FieldComparator<VMNetworkInfo>.value("vm", \.vmName)]

    var body: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("VM", sortUsing: FieldComparator.value("vm", \.vmName)) { Text($0.vmName) }
            TableColumn("Power", sortUsing: FieldComparator.value("power", \.powerState.rawValue)) { Text($0.powerState.rawValue) }
            TableColumn("NIC Label", sortUsing: FieldComparator.value("label", \.nicLabel)) { Text($0.nicLabel) }
            TableColumn("Adapter Type", sortUsing: FieldComparator.value("adapter", \.adapterType)) { Text($0.adapterType) }
            TableColumn("Network", sortUsing: FieldComparator.value("network", \.network)) { Text($0.network) }
            TableColumn("Connected") { Text($0.connected ? "Yes" : "No") }
            TableColumn("MAC Address", sortUsing: FieldComparator.value("mac", \.macAddress)) { Text($0.macAddress) }
            TableColumn("IPv4 Address", sortUsing: FieldComparator.optional("ipv4", \.ipv4Address)) { Text($0.ipv4Address ?? "—") }
            TableColumn("IPv6 Address", sortUsing: FieldComparator.optional("ipv6", \.ipv6Address)) { Text($0.ipv6Address ?? "—") }
        }
        .tutorialPopover(
            id: TutorialID.network, title: "vNetwork",
            text: "Per-VM virtual NIC info — which port group each VM's NIC is on. Not the same as vNic (a host's physical NICs) or vSC+VMK (a host's VMkernel adapters)."
        )
    }
}
