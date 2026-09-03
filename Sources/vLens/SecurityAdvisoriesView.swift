import SwiftUI
import vLensCore

/// Popover content for the toolbar's security-advisory indicator — see
/// `ConnectionViewModel.checkSecurityAdvisories()`. Not RVTools' concept.
struct SecurityAdvisoriesView: View {
    let advisories: [SecurityAdvisory]

    var body: some View {
        List(advisories) { advisory in
            Link(destination: URL(string: advisory.url) ?? URL(string: "https://support.broadcom.com/support/vmware-security-advisories")!) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(advisory.severity.capitalized)
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(color(for: advisory.severity).opacity(0.15))
                            .foregroundStyle(color(for: advisory.severity))
                            .clipShape(Capsule())
                        if let date = advisory.publishedDate {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(advisory.title)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 420, height: 360)
    }

    private func color(for severity: String) -> Color {
        switch severity {
        case "CRITICAL": return .red
        case "HIGH": return .orange
        case "MEDIUM": return .yellow
        default: return .secondary
        }
    }
}
