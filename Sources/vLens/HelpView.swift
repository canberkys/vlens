import SwiftUI

/// Native in-app Help — replaces the default (empty) Help menu item rather
/// than opening an external site. Content is a short, user-facing summary,
/// not a port of `docs/vLens-Reference.md` (that doc is written for
/// contributors/maintainers, not end users).
enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted, tabs, snapshots, performance, exportReports, preferences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: return "Getting Started"
        case .tabs: return "Tabs"
        case .snapshots: return "Snapshots & Compare"
        case .performance: return "vPerformance"
        case .exportReports: return "Export & Reports"
        case .preferences: return "Preferences"
        }
    }

    var systemImage: String {
        switch self {
        case .gettingStarted: return "play.circle"
        case .tabs: return "tablecells"
        case .snapshots: return "clock.arrow.circlepath"
        case .performance: return "chart.line.uptrend.xyaxis"
        case .exportReports: return "square.and.arrow.up"
        case .preferences: return "gearshape"
        }
    }

    var body: String {
        switch self {
        case .gettingStarted:
            return """
            Connect with your vCenter's FQDN, a username, and a password. The first time you connect to a given host, vLens shows you the certificate it presented and asks you to approve it — this is trust-on-first-use, the same idea as SSH host keys. If that certificate ever changes unexpectedly later, vLens blocks the connection instead of silently allowing it.

            Don't have a vCenter handy? Try Demo Mode from the connect screen — it fills every tab with realistic mock data so you can explore the app risk-free.

            Check "Remember this connection" to save the host and username (and, if you choose, the password in Keychain) for next time.
            """
        case .tabs:
            return """
            Tabs are grouped in the sidebar: VM, Infrastructure, Networking, Storage, Licensing, Health, and History. Most tabs mirror a specific RVTools tab (vInfo, vCPU, vDisk, and so on) — if you know RVTools, the data will look familiar.

            Every column header is clickable to sort. The search box in the toolbar filters whatever tab you're currently looking at.

            A few tabs are vLens' own, not from RVTools: vPerformance (historical CPU/RAM/IOPS trends) and Snapshots (point-in-time comparison) — see their own Help topics.
            """
        case .snapshots:
            return """
            Snapshots here are not vSphere VM snapshots — vLens' own idea. Press "Take Snapshot" to record a set of aggregate counts (VM/host/cluster/datastore counts, the worst datastore's free space, active vSphere snapshots, VMware Tools issues, vHealth findings) for the vCenter you're connected to.

            Once you have two or more snapshots, the Compare panel shows a baseline vs. current table with a colored delta — green or red depending on whether that particular metric actually improved or got worse. Use "Export" in the Compare panel to save that exact comparison as a CSV.

            Which metrics show up in Compare is configurable in Preferences, under "Snapshot comparison metrics."
            """
        case .performance:
            return """
            vPerformance shows historical CPU/RAM usage and disk I/O size sampled over a time window you choose (1 hour to 30 days) — unlike every other tab's numbers, which are instantaneous. This is not something RVTools has.

            It's collected separately from the rest of your data, via its own "Collect" button — connecting or refreshing the other tabs doesn't automatically pull performance history, since it's a heavier, per-VM query. Only powered-on VMs report performance samples.
            """
        case .exportReports:
            return """
            Every tab can be exported as CSV or XLSX from the toolbar's Export menu — whatever the current tab shows, already filtered by your search, in that format.

            The "Report" button generates something different: a one-page PDF management summary (vCenter identity, VM/host/cluster/datastore counts, a couple of charts, a vHealth summary) — meant to be skimmed by a manager, not read as a data export.
            """
        case .preferences:
            return """
            Cmd+, opens Preferences. vHealth thresholds (datastore free space, vCPU-per-core ratio, guest disk free space, max VMs per datastore) control when a finding shows up on the vHealth tab — change one and every already-collected finding re-evaluates immediately, no reconnect needed.

            Preferences also controls which metrics the Snapshots tab's Compare panel shows.
            """
        }
    }
}

struct HelpView: View {
    @State private var selectedTopic: HelpTopic = .gettingStarted

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selectedTopic) { topic in
                Label(topic.title, systemImage: topic.systemImage).tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedTopic.title)
                        .font(.title2.bold())
                    Text(selectedTopic.body)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 640, height: 420)
    }
}

#Preview {
    HelpView()
}
