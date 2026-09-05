import SwiftUI
import vLensCore

/// Popover content for the toolbar's VMware end-of-life indicator — see
/// `ConnectionViewModel.checkVMwareEndOfLife()`. Not RVTools' concept
/// (GitHub issue #19). Sourced from endoflife.date, matched against
/// already-collected host ESXi versions and the connected vCenter's own
/// version — no extra vCenter call. vCenter shown as its own row at the
/// top rather than a separate tab (there's only ever one per connection,
/// and a tab that always shows exactly one row doesn't fit this app's
/// "one row per real inventory item" pattern).
struct VMwareEOLView: View {
    let hostStatuses: [HostEOLStatus]
    let vCenterStatus: VCenterEOLStatus?

    private var sortedHosts: [HostEOLStatus] {
        hostStatuses.sorted { ($0.cycle.eolDate ?? .distantFuture) < ($1.cycle.eolDate ?? .distantFuture) }
    }

    var body: some View {
        List {
            if let vCenterStatus {
                Section("vCenter") {
                    row(name: "vCenter Server", versionLabel: "vCenter \(vCenterStatus.version)", severity: vCenterStatus.severity(), eolDate: vCenterStatus.cycle.eolDate)
                }
            }
            if !sortedHosts.isEmpty {
                Section("ESXi Hosts") {
                    ForEach(sortedHosts) { status in
                        row(name: status.hostName, versionLabel: "ESXi \(status.esxVersion)", severity: status.severity(), eolDate: status.cycle.eolDate)
                    }
                }
            }
        }
        .frame(width: 380, height: 320)
    }

    private func row(name: String, versionLabel: String, severity: EOLSeverity, eolDate: Date?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.callout)
                Text(versionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Label(label(for: severity), systemImage: icon(for: severity))
                    .font(.caption.bold())
                    .foregroundStyle(color(for: severity))
                if let eolDate {
                    Text(eolDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func label(for severity: EOLSeverity) -> String {
        switch severity {
        case .red: return "EOL reached"
        case .orange: return "EOL approaching"
        case .green: return "Supported"
        }
    }

    private func icon(for severity: EOLSeverity) -> String {
        switch severity {
        case .red: return "xmark.octagon.fill"
        case .orange: return "exclamationmark.triangle.fill"
        case .green: return "checkmark.circle.fill"
        }
    }

    private func color(for severity: EOLSeverity) -> Color {
        switch severity {
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        }
    }
}
