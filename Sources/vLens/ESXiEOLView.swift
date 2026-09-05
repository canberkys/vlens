import SwiftUI
import vLensCore

/// Popover content for the toolbar's ESXi end-of-life indicator — see
/// `ConnectionViewModel.checkESXiEndOfLife()`. Not RVTools' concept
/// (GitHub issue #19). Sourced from endoflife.date, matched against each
/// host's already-collected ESXi version — no extra vCenter call.
struct ESXiEOLView: View {
    let statuses: [HostEOLStatus]

    private var sorted: [HostEOLStatus] {
        statuses.sorted { ($0.cycle.eolDate ?? .distantFuture) < ($1.cycle.eolDate ?? .distantFuture) }
    }

    var body: some View {
        List(sorted) { status in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.hostName).font(.callout)
                    Text("ESXi \(status.esxVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Label(label(for: status), systemImage: icon(for: status))
                        .font(.caption.bold())
                        .foregroundStyle(color(for: status))
                    if let eolDate = status.cycle.eolDate {
                        Text(eolDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(width: 380, height: 320)
    }

    private func label(for status: HostEOLStatus) -> String {
        switch status.severity() {
        case .red: return "EOL reached"
        case .orange: return "EOL approaching"
        case .green: return "Supported"
        }
    }

    private func icon(for status: HostEOLStatus) -> String {
        switch status.severity() {
        case .red: return "xmark.octagon.fill"
        case .orange: return "exclamationmark.triangle.fill"
        case .green: return "checkmark.circle.fill"
        }
    }

    private func color(for status: HostEOLStatus) -> Color {
        switch status.severity() {
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        }
    }
}
