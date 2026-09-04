import SwiftUI
import vLensCore

/// Popover content for the toolbar's security-advisory indicator — see
/// `ConnectionViewModel.checkSecurityAdvisories()`. Not RVTools' concept.
///
/// Grouped by recency (so the newest, most-worth-a-look advisories aren't
/// buried in a flat list) and tagged with affected products (parsed from
/// `SecurityAdvisory.affectedProducts`) — a user who doesn't run, say,
/// Workstation can tell that at a glance without opening the link.
struct SecurityAdvisoriesView: View {
    let advisories: [SecurityAdvisory]

    private enum RecencyBucket: CaseIterable {
        case new, thisMonth, thisYear, older

        var title: String {
            switch self {
            case .new: return "New (last 7 days)"
            case .thisMonth: return "This Month"
            case .thisYear: return "This Year"
            case .older: return "Older"
            }
        }
    }

    private var grouped: [(bucket: RecencyBucket, advisories: [SecurityAdvisory])] {
        RecencyBucket.allCases.compactMap { bucket in
            let matches = advisories.filter { recencyBucket(for: $0.publishedDate) == bucket }
            return matches.isEmpty ? nil : (bucket, matches)
        }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.bucket) { group in
                Section(group.bucket.title) {
                    ForEach(group.advisories) { advisory in
                        row(for: advisory)
                    }
                }
            }
        }
        .frame(width: 440, height: 400)
    }

    private func row(for advisory: SecurityAdvisory) -> some View {
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
                let products = parsedProducts(advisory.affectedProducts)
                if !products.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(products, id: \.self) { product in
                            Text(product)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func recencyBucket(for date: Date?) -> RecencyBucket {
        guard let date, let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day else {
            return .older
        }
        if days <= 7 { return .new }
        if days <= 30 { return .thisMonth }
        if days <= 365 { return .thisYear }
        return .older
    }

    /// Broadcom's API truncates long product lists with a trailing "..."
    /// fragment (e.g. "VMware Fusion,VMware Work..." — observed, not a bug
    /// on vLens' side, see VMSAClient.swift). Strip the "..." and drop
    /// whatever's left of a truncated entry rather than showing a
    /// meaningless partial word as its own tag.
    private func parsedProducts(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasSuffix("...") ? String($0.dropLast(3)).trimmingCharacters(in: .whitespaces) : $0 }
            .filter { $0.count >= 3 }
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
