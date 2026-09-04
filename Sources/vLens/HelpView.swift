import SwiftUI

/// Native in-app Help — replaces the default (empty) Help menu item rather
/// than opening an external site. Content is a short, user-facing summary,
/// not a port of `docs/vLens-Reference.md` (that doc is written for
/// contributors/maintainers, not end users). Styled loosely after macOS'
/// own Tips app — a colored icon badge per topic, sidebar and detail pane
/// both using it, rather than a plain text-only list.
enum HelpTopic: String, CaseIterable, Identifiable {
    case whatsNew, gettingStarted, tabs, snapshots, performance, securityAdvisories, exportReports, feedback, preferences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whatsNew: return "What's New"
        case .gettingStarted: return "Getting Started"
        case .tabs: return "Tabs"
        case .snapshots: return "Snapshots & Compare"
        case .performance: return "vPerformance"
        case .securityAdvisories: return "Security Advisories"
        case .exportReports: return "Export & Reports"
        case .feedback: return "Feedback & Bug Reports"
        case .preferences: return "Preferences"
        }
    }

    var systemImage: String {
        switch self {
        case .whatsNew: return "sparkles"
        case .gettingStarted: return "play.circle.fill"
        case .tabs: return "tablecells.fill"
        case .snapshots: return "clock.arrow.circlepath"
        case .performance: return "chart.line.uptrend.xyaxis"
        case .securityAdvisories: return "shield.lefthalf.filled"
        case .exportReports: return "square.and.arrow.up.fill"
        case .feedback: return "bubble.left.and.text.bubble.right.fill"
        case .preferences: return "gearshape.fill"
        }
    }

    /// One accent color per topic — matches Tips.app's own colored-icon
    /// convention, and doubles as a quick visual anchor when scanning the
    /// sidebar rather than reading every label.
    var accentColor: Color {
        switch self {
        case .whatsNew: return .yellow
        case .gettingStarted: return .green
        case .tabs: return .blue
        case .snapshots: return .purple
        case .performance: return .orange
        case .securityAdvisories: return .red
        case .exportReports: return .teal
        case .feedback: return .pink
        case .preferences: return .gray
        }
    }

    /// Unused for `.whatsNew` — that topic renders the bundled
    /// `CHANGELOG.md` as Markdown instead (see `HelpView.changelogText`),
    /// so its history can't drift from what `scripts/release.sh` actually
    /// ships. A hand-written string here would just be a second copy to
    /// keep in sync by hand.
    var body: String {
        switch self {
        case .whatsNew: return ""
        case .gettingStarted:
            return """
            Connect with your vCenter's FQDN, a username, and a password. The first time you connect to a given host, vLens shows you the certificate it presented and asks you to approve it — this is trust-on-first-use, the same idea as SSH host keys. If that certificate ever changes unexpectedly later, vLens blocks the connection instead of silently allowing it.

            Don't have a vCenter handy? Try Demo Mode from the connect screen — it fills every tab with realistic mock data so you can explore the app risk-free.

            Check "Remember this connection" to save the host and username (and, if you choose, the password in Keychain) for next time.
            """
        case .tabs:
            return """
            Tabs are grouped in the sidebar: VM, Infrastructure, Networking, Storage, Licensing, Health, and History. Most tabs mirror a specific RVTools tab (vInfo, vCPU, vDisk, and so on) — if you know RVTools, the data will look familiar. vLens isn't just a port, though — several tabs and features here don't exist in RVTools at all.

            Every column header is clickable to sort. The search box in the toolbar filters whatever tab you're currently looking at.
            """
        case .snapshots:
            return """
            Snapshots here are not vSphere VM snapshots — vLens' own idea. Press "Take Snapshot" to record a set of aggregate counts (VM/host/cluster/datastore counts, the worst datastore's free space, active vSphere snapshots, VMware Tools issues, vHealth findings) for the vCenter you're connected to.

            Once you have two or more snapshots, the Compare panel shows a baseline vs. current table with a colored delta — green or red depending on whether that particular metric actually improved or got worse. Use "Export" in the Compare panel to save that exact comparison as a CSV.

            Which metrics show up in Compare is configurable in Preferences, under "Snapshot comparison metrics." Snapshot data is stored locally at ~/Library/Application Support/vLens/inventory-snapshots.json.
            """
        case .performance:
            return """
            vPerformance shows historical CPU/RAM usage and disk I/O size sampled over a time window you choose (1 hour to 30 days) — unlike every other tab's numbers, which are instantaneous. This is not something RVTools has.

            It's collected separately from the rest of your data, via its own "Collect" button — connecting or refreshing the other tabs doesn't automatically pull performance history, since it's a heavier, per-VM query. Only powered-on VMs report performance samples.
            """
        case .securityAdvisories:
            return """
            vLens quietly checks Broadcom's public VMware security advisory list once per launch — not from your vCenter, a plain internet request, independent of any connection. Also not something RVTools has.

            A shield badge appears in the toolbar only when there's a CRITICAL or HIGH severity advisory recently published — no badge, no interruption, when there's nothing notable. Click it to see the list, grouped by how recently each was published, tagged with which VMware products each one affects (ESXi, vCenter, Workstation, and so on) so you can tell at a glance whether it's worth a click.
            """
        case .exportReports:
            return """
            Every tab can be exported as CSV or XLSX from the toolbar's Export menu — whatever the current tab shows, already filtered by your search, in that format.

            The "Report" button generates something different: a one-page PDF management summary (vCenter identity, VM/host/cluster/datastore counts, a couple of charts, a vHealth summary) — meant to be skimmed by a manager, not read as a data export.
            """
        case .feedback:
            return """
            Found a bug, or want a feature? Help menu → "Send Feedback…" opens a form right in the app — pick Bug Report or Feature Request, write what's on your mind, and vLens shows you exactly what diagnostic info (app version, macOS version, connected vCenter version — never your host, username, or password) would go along with it before you send anything.

            Nothing is ever sent automatically or silently: "Send via Email" opens a prefilled draft in your own mail client, and "Open as GitHub Issue" opens a prefilled issue in your browser — you review and send either one yourself.
            """
        case .preferences:
            return """
            Cmd+, opens Preferences. vHealth thresholds (datastore free space, vCPU-per-core ratio, guest disk free space, max VMs per datastore) control when a finding shows up on the vHealth tab — change one and every already-collected finding re-evaluates immediately, no reconnect needed.

            Preferences also controls which metrics the Snapshots tab's Compare panel shows.
            """
        }
    }
}

/// One `## [version] - date` block from `CHANGELOG.md`.
private struct ChangelogEntry: Identifiable {
    let id = UUID()
    let version: String
    let dateText: String
    let sections: [ChangelogSection]
}

/// One `### Added`/`### Changed`/`### Fixed` block within a version.
private struct ChangelogSection: Identifiable {
    let id = UUID()
    let heading: String
    let bullets: [String]
}

struct HelpView: View {
    @State private var selectedTopic: HelpTopic = .gettingStarted

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selectedTopic) { topic in
                HStack(spacing: 10) {
                    iconBadge(for: topic, size: 28, iconSize: 14)
                    Text(topic.title)
                }
                .padding(.vertical, 2)
                .tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        iconBadge(for: selectedTopic, size: 56, iconSize: 26)
                        Text(selectedTopic.title)
                            .font(.title.bold())
                    }
                    if selectedTopic == .whatsNew {
                        let entries = Self.changelogEntries
                        if entries.isEmpty {
                            Text("Changelog unavailable.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 22) {
                                ForEach(entries) { entry in
                                    changelogEntryView(entry)
                                }
                            }
                        }
                    } else {
                        Text(selectedTopic.body)
                            .font(.body)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 680, height: 460)
    }

    /// The bundled `CHANGELOG.md` (`Package.swift` copies it into this
    /// target's resources — see the comment on `Resources/CHANGELOG.md`),
    /// parsed by hand into `ChangelogEntry`/`ChangelogSection` and laid out
    /// as real SwiftUI views below. Dumping the whole file through
    /// Foundation's `AttributedString(markdown:)` into one `Text` was tried
    /// first — it doesn't apply any heading/list visual hierarchy on its
    /// own (every line renders as same-size body text with no spacing
    /// between entries), which looked bad in practice. Inline styling
    /// (`**bold**`, `` `code` ``) *does* work well through that API when
    /// applied to a single bullet's text, so `changelogInlineText(_:)`
    /// still uses it for that narrower purpose.
    private static var changelogEntries: [ChangelogEntry] {
        guard let url = Bundle.module.url(forResource: "CHANGELOG", withExtension: "md"),
            let raw = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return parseChangelog(raw)
    }

    private static func parseChangelog(_ text: String) -> [ChangelogEntry] {
        var entries: [ChangelogEntry] = []
        var version: String?
        var dateText = ""
        var sections: [ChangelogSection] = []
        var heading: String?
        var bullets: [String] = []

        func flushSection() {
            // A version can have bullets with no preceding "### " heading
            // at all (e.g. 1.0.0's single-line summary) — `heading == nil`
            // must still flush those bullets under an empty heading rather
            // than silently dropping them, which the first version of this
            // parser did.
            if heading != nil || !bullets.isEmpty {
                sections.append(ChangelogSection(heading: heading ?? "", bullets: bullets))
            }
            heading = nil
            bullets = []
        }
        func flushEntry() {
            flushSection()
            if let version {
                entries.append(ChangelogEntry(version: version, dateText: dateText, sections: sections))
            }
            sections = []
        }

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ["), let close = line.firstIndex(of: "]") {
                flushEntry()
                let versionStart = line.index(line.startIndex, offsetBy: 4)
                version = String(line[versionStart..<close])
                let rest = line[line.index(after: close)...]
                dateText = rest.trimmingCharacters(in: CharacterSet(charactersIn: " -"))
            } else if line.hasPrefix("### ") {
                flushSection()
                heading = String(line.dropFirst(4))
            } else if line.hasPrefix("- ") {
                bullets.append(String(line.dropFirst(2)))
            } else {
                // A wrapped continuation line (CHANGELOG.md's own
                // convention: an indented line right after a "- " bullet,
                // no marker of its own) — fold it into the previous bullet
                // instead of dropping it or treating it as a new item.
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, !bullets.isEmpty {
                    bullets[bullets.count - 1] += " " + trimmed
                }
            }
        }
        flushEntry()
        return entries
    }

    private func changelogEntryView(_ entry: ChangelogEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Version \(entry.version)")
                    .font(.title3.bold())
                Text(entry.dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(entry.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    if !section.heading.isEmpty {
                        Text(section.heading)
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                    }
                    ForEach(section.bullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundStyle(.secondary)
                            Self.changelogInlineText(bullet)
                        }
                    }
                }
            }
            Divider()
        }
    }

    /// Renders a single bullet's inline Markdown (`**bold**`, `` `code` ``)
    /// — unlike whole-document parsing, this narrow case works well with
    /// Foundation's native parser since there's no block-level structure to
    /// get lost, just character-level styling within one line.
    private static func changelogInlineText(_ raw: String) -> Text {
        if let attributed = try? AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(raw)
    }

    private func iconBadge(for topic: HelpTopic, size: CGFloat, iconSize: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(topic.accentColor.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: topic.systemImage)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(.white)
            )
    }
}

#Preview {
    HelpView()
}
