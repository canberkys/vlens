import SwiftUI
import vLensCore

struct VClusterTabView: View {
    let rows: [ClusterInfo]
    @Binding var sortOrder: [FieldComparator<ClusterInfo>]

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No Clusters",
                systemImage: "square.grid.3x3",
                description: Text("An environment with only standalone hosts (no DRS/HA clusters) has none — check vHost instead.")
            )
        } else {
            Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn("Cluster", sortUsing: FieldComparator.value("name", \.name)) { Text($0.name) }
                TableColumn("Status", sortUsing: FieldComparator.value("status", \.configStatus.rawValue)) { Text($0.configStatus.rawValue) }
                TableColumn("Hosts", sortUsing: FieldComparator.value("hosts", \.numHosts)) { Text("\($0.numHosts)") }
                TableColumn("Effective Hosts", sortUsing: FieldComparator.value("effectiveHosts", \.numEffectiveHosts)) { Text("\($0.numEffectiveHosts)") }
                TableColumn("Total CPU MHz", sortUsing: FieldComparator.value("totalCpu", \.totalCpuMHz)) { Text("\($0.totalCpuMHz)") }
                TableColumn("Total Memory MiB", sortUsing: FieldComparator.value("totalMemory", \.totalMemoryMiB)) { Text("\($0.totalMemoryMiB)") }
                TableColumn("HA") { Text($0.haEnabled ? "Enabled" : "Disabled") }
                TableColumn("DRS") { Text($0.drsEnabled ? "Enabled" : "Disabled") }
                TableColumn("Admission Control") { Text($0.admissionControlEnabled ? "Enabled" : "Disabled") }
                TableColumn("Tags") { Text($0.tags.joined(separator: ", ")) }
            }
        }
    }
}
