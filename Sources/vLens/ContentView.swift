import SwiftUI
import AppKit
import vLensCore

struct ContentView: View {
    @Bindable var viewModel: ConnectionViewModel
    @State private var selectedTab: AppTab = .vInfo
    private let tutorialStore = TutorialStore()
    @State private var showWelcome = false
    @State private var showAdvisories = false
    @State private var showEOLWarnings = false
    @FocusState private var isSearchFocused: Bool

    /// Sidebar navigation (vInfo, vCPU, ... the 27-tab list) is this app's
    /// only way to switch tabs — there's no menu-bar equivalent — so it must
    /// never fully disappear. Left as system `.automatic`, `NavigationSplitView`
    /// can (and, per a real user report, did) auto-collapse the sidebar
    /// column into a hidden/overlay state during an interactive window
    /// resize, even though the window's `.frame(minWidth: 1000)` comfortably
    /// exceeds the sidebar+detail minimums (160+440≈600pt). Once collapsed,
    /// there was no way back — this app's "toolbar" (below) is a plain
    /// `HStack` inside the content area, not a real `.toolbar()`, so none of
    /// the automatic sidebar-toggle affordances SwiftUI normally adds to a
    /// window's titlebar toolbar ever appear. Binding `columnVisibility`
    /// explicitly to `.all` (rather than leaving it to the opaque
    /// system-automatic default) plus `.navigationSplitViewStyle(.balanced)`
    /// (see `body`) keeps the sidebar a real, always-present column instead
    /// of a collapsible overlay.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// `List(selection:)` wants `Binding<AppTab?>`; the rest of this file
    /// switches on plain `AppTab` (simpler, and a sidebar row is never
    /// truly "no selection" once connected) — this just bridges the two.
    private var sidebarSelection: Binding<AppTab?> {
        Binding(get: { selectedTab }, set: { if let newValue = $0 { selectedTab = newValue } })
    }

    var body: some View {
        Group {
            if !viewModel.isConnected {
                connectForm
                    .frame(width: 420, height: 480)
                    .onAppear {
                        // Re-checked (not just computed once at init) so
                        // Preferences' "Reset Tutorials" takes effect without
                        // a relaunch — connectForm reappears whenever the
                        // user disconnects/exits demo mode.
                        showWelcome = !tutorialStore.hasSeen(TutorialID.onboardingWelcome)
                    }
                    .sheet(isPresented: $showWelcome) {
                        WelcomeOverlayView {
                            tutorialStore.markSeen(TutorialID.onboardingWelcome)
                            showWelcome = false
                        }
                    }
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebar
                } detail: {
                    VStack(spacing: 0) {
                        if viewModel.isDemoMode {
                            demoBanner
                        }
                        toolbar
                        Divider()
                        tabContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        Divider()
                        statusBar
                    }
                }
                // `.balanced` keeps the sidebar as a genuinely-present,
                // width-shared column. The alternative macOS can pick under
                // `.automatic` — `.prominentDetail` — is the style that turns
                // narrow-width handling into hiding the sidebar behind an
                // overlay toggle, which is the exact "sidebar just vanished"
                // failure mode this fixes.
                .navigationSplitViewStyle(.balanced)
                .frame(minWidth: 1000, minHeight: 640)
            }
        }
        .sheet(item: $viewModel.pendingCertificateApproval) { pending in
            certificateApprovalSheet(pending)
        }
        .task {
            // Fires once per launch, regardless of connect/demo state — a
            // plain internet fetch, independent of any vCenter connection.
            // Silently no-ops on failure; see checkSecurityAdvisories().
            await viewModel.checkSecurityAdvisories()
        }
        .task {
            // Same shape — see checkVMwareEndOfLife(). hostEOLStatuses/
            // vCenterEOLStatus only have anything to show once hosts/
            // vCenterInfo are populated (connect/demo).
            await viewModel.checkVMwareEndOfLife()
        }
    }

    // MARK: - Connect form

    private var connectForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            // One compact header instead of a hero title stacked above a
            // second "Connect to vCenter" headline — the form itself makes
            // the purpose obvious, a second headline was redundant weight.
            HStack(spacing: 12) {
                AppIconImage.image
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("vLens").font(.title2.bold())
                    Text("vCenter/ESXi inventory, built for Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                if !viewModel.savedProfiles.isEmpty {
                    HStack {
                        Spacer()
                        savedProfilesMenu
                    }
                }

                TextField("vCenter host (e.g. vcenter.local)", text: $viewModel.host)
                    .textFieldStyle(.roundedBorder)
                TextField("Username", text: $viewModel.username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $viewModel.password)
                    .textFieldStyle(.roundedBorder)
                Toggle("Save this connection to Keychain", isOn: $viewModel.saveCredentials)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                Button {
                    Task { await viewModel.connectAndListVMs() }
                } label: {
                    Group {
                        if viewModel.isConnecting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Connect")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isConnecting)

                // Secondary escape hatch, not a co-equal action next to
                // Connect — smaller, muted, below the primary button.
                Button("Try demo mode") {
                    viewModel.loadDemoData()
                }
                .buttonStyle(.link)
                .font(.footnote)
                .disabled(viewModel.isConnecting)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(28)
    }

    /// Tied visually to the host field it populates (small, right-aligned,
    /// directly above it) rather than a standalone row that used to read
    /// like a stray toolbar button.
    private var savedProfilesMenu: some View {
        Menu {
            ForEach(viewModel.savedProfiles) { profile in
                Button(profile.name) { viewModel.selectSavedProfile(profile) }
            }
            Divider()
            ForEach(viewModel.savedProfiles) { profile in
                Button("Delete: \(profile.name)", role: .destructive) { viewModel.deleteSavedProfile(profile) }
            }
        } label: {
            Label("Recent", systemImage: "clock.arrow.circlepath")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Certificate trust-on-first-use

    private func certificateApprovalSheet(_ pending: ConnectionViewModel.PendingCertificateApproval) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Verify this certificate", systemImage: "lock.shield")
                .font(.headline)

            Text("vLens hasn't connected to **\(pending.host)** before. On-prem vCenter servers almost always use a self-signed or internal-CA certificate, so this is expected — but you should confirm this is really your vCenter before trusting it, ideally by checking the fingerprint with your vSphere admin.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                labeledRow("Subject", pending.subject)
                labeledRow("Issuer", pending.issuer)
                labeledRow("Expires", pending.notAfter)
                HStack(alignment: .top) {
                    Text("SHA-256").foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                    Text(pending.fingerprint.displayValue)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button {
                        copyToPasteboard(pending.fingerprint.displayValue)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Copy fingerprint")
                    .accessibilityLabel("Copy fingerprint")
                }
                .font(.callout)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("This fingerprint will be remembered — if it ever changes without your vSphere admin renewing the certificate, vLens will refuse to connect and warn you.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", role: .cancel) { viewModel.cancelPendingCertificate() }
                Spacer()
                Button("Trust & Connect") { Task { await viewModel.approvePendingCertificate() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            Text(value).textSelection(.enabled)
        }
        .font(.callout)
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    // MARK: - Connected state chrome

    private var demoBanner: some View {
        HStack {
            Image(systemName: "wand.and.stars")
            Text("Demo mode — this data isn't from a real vCenter, it's mock data.")
            Spacer()
            Button("Exit demo") { viewModel.exitDemoMode() }
                .buttonStyle(.link)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.15))
    }

    private var toolbar: some View {
        HStack {
            // Safety-net sidebar toggle: this app's chrome is a plain HStack,
            // not a real `.toolbar()`, so SwiftUI never adds its automatic
            // sidebar-restore button to the window titlebar. Without this,
            // if `columnVisibility` (see its declaration for the collapse
            // bug this guards against) is ever driven to `.detailOnly` by
            // anything other than this button, the sidebar has no way back.
            Button {
                columnVisibility = columnVisibility == .all ? .detailOnly : .all
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .help("Toggle Sidebar")
            .accessibilityLabel("Toggle Sidebar")

            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search (VM, host, cluster...)", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
            // Cmd+F is the standard macOS "find/search" shortcut — this app
            // has no menu-based Find, so without this, Cmd+F silently does
            // nothing, which is worse than not having a shortcut at all.
            Button("Focus Search") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }

            Spacer()

            if viewModel.notableAdvisoryCount > 0 {
                Button {
                    showAdvisories = true
                } label: {
                    Label("\(viewModel.notableAdvisoryCount) advisories", systemImage: "shield.lefthalf.filled")
                        .foregroundStyle(.red)
                }
                .popover(isPresented: $showAdvisories) {
                    SecurityAdvisoriesView(advisories: viewModel.securityAdvisories)
                }
                .help("Recent VMware security advisories (CRITICAL/HIGH) — not from your vCenter, from Broadcom's public advisory list.")
            }

            if viewModel.notableEOLCount > 0 {
                Button {
                    showEOLWarnings = true
                } label: {
                    Label(
                        "\(viewModel.notableEOLCount) EOL",
                        systemImage: "calendar.badge.exclamationmark"
                    )
                    .foregroundStyle(
                        viewModel.hostEOLStatuses.contains { $0.severity() == .red }
                            || viewModel.vCenterEOLStatus?.severity() == .red
                            ? .red : .orange
                    )
                }
                .popover(isPresented: $showEOLWarnings) {
                    VMwareEOLView(hostStatuses: viewModel.hostEOLStatuses, vCenterStatus: viewModel.vCenterEOLStatus)
                }
                .help("ESXi hosts and/or vCenter nearing or past their VMware general-support end-of-life date — from endoflife.date's public lifecycle data, matched against each collected version.")
            }

            Button {
                Task { await viewModel.refresh() }
            } label: {
                if viewModel.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(viewModel.isRefreshing)
            .help("Re-collect the current inventory from vCenter. If this fails, the data already on screen is kept and marked as possibly stale rather than cleared.")

            if !viewModel.isDemoMode {
                Button(role: .destructive) {
                    viewModel.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .help("Disconnect and return to the connect screen — from there you can connect to a different saved connection.")
            }

            Button {
                generateReport()
            } label: {
                Label("Report", systemImage: "doc.richtext")
            }
            .disabled(viewModel.vms.isEmpty)

            Menu {
                Button("Export as CSV") { exportCurrentTab(as: .csv) }
                Button("Export as XLSX") { exportCurrentTab(as: .xlsx) }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(currentRowCount == 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Sidebar navigation

    private var sidebar: some View {
        List(selection: sidebarSelection) {
            ForEach(AppTabGroup.allCases, id: \.self) { group in
                Section(group.rawValue) {
                    ForEach(group.tabs) { tab in
                        sidebarRow(tab).tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
    }

    @ViewBuilder
    private func sidebarRow(_ tab: AppTab) -> some View {
        if tab == .vHealth && !viewModel.healthChecks.isEmpty {
            HStack {
                Text(tab.label)
                Spacer()
                Text("\(viewModel.healthChecks.count)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.orange, in: Capsule())
                    .foregroundStyle(.white)
            }
        } else {
            Text(tab.label)
        }
    }

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(viewModel.isDemoMode ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
            Text(viewModel.isDemoMode ? "Demo mode" : viewModel.host)
            Divider().frame(height: 12)
            Text("\(currentRowCount) rows")
            if let refreshed = viewModel.lastRefreshedAt {
                Divider().frame(height: 12)
                Text("Last refreshed: \(refreshed.formatted(date: .omitted, time: .shortened))")
            }
            if viewModel.isDataStale {
                Divider().frame(height: 12)
                Label("Refresh failed — data may be stale", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(viewModel.errorMessage ?? "The last refresh attempt failed; showing the previous successful collection.")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Tab content (filtered by search)

    private var filteredVMs: [VirtualMachineInfo] { viewModel.vms.filter { $0.matches(viewModel.searchText) } }
    private var filteredCpus: [VMCpuInfo] { viewModel.cpus.filter { $0.matches(viewModel.searchText) } }
    private var filteredMemory: [VMMemoryInfo] { viewModel.memory.filter { $0.matches(viewModel.searchText) } }
    private var filteredDisks: [VMDiskInfo] { viewModel.disks.filter { $0.matches(viewModel.searchText) } }
    private var filteredSnapshots: [VMSnapshotInfo] { viewModel.snapshots.filter { $0.matches(viewModel.searchText) } }
    private var filteredTools: [VMToolsInfo] { viewModel.tools.filter { $0.matches(viewModel.searchText) } }
    private var filteredNetworks: [VMNetworkInfo] { viewModel.networks.filter { $0.matches(viewModel.searchText) } }
    private var filteredHosts: [HostInfo] { viewModel.hosts.filter { $0.matches(viewModel.searchText) } }
    private var filteredDatastores: [DatastoreInfo] { viewModel.datastores.filter { $0.matches(viewModel.searchText) } }
    private var filteredClusters: [ClusterInfo] { viewModel.clusters.filter { $0.matches(viewModel.searchText) } }
    private var filteredLicenses: [LicenseInfo] { viewModel.licenses.filter { $0.matches(viewModel.searchText) } }
    private var filteredVSwitches: [VSwitchInfo] { viewModel.vSwitches.filter { $0.matches(viewModel.searchText) } }
    private var filteredPorts: [VPortInfo] { viewModel.ports.filter { $0.matches(viewModel.searchText) } }
    private var filteredDVSwitches: [DVSwitchInfo] { viewModel.dvSwitches.filter { $0.matches(viewModel.searchText) } }
    private var filteredDVPorts: [DVPortInfo] { viewModel.dvPorts.filter { $0.matches(viewModel.searchText) } }
    private var filteredResourcePools: [ResourcePoolInfo] { viewModel.resourcePools.filter { $0.matches(viewModel.searchText) } }
    private var filteredVApps: [VAppInfo] { viewModel.vApps.filter { $0.matches(viewModel.searchText) } }
    private var filteredHBAs: [HBAInfo] { viewModel.hbas.filter { $0.matches(viewModel.searchText) } }
    private var filteredNics: [NicInfo] { viewModel.nics.filter { $0.matches(viewModel.searchText) } }
    private var filteredVMKernels: [VMKernelInfo] { viewModel.vmKernels.filter { $0.matches(viewModel.searchText) } }
    private var filteredMultipaths: [MultipathInfo] { viewModel.multipaths.filter { $0.matches(viewModel.searchText) } }
    private var filteredCDs: [CDInfo] { viewModel.cds.filter { $0.matches(viewModel.searchText) } }
    private var filteredFloppies: [FloppyInfo] { viewModel.floppies.filter { $0.matches(viewModel.searchText) } }
    private var filteredUSBs: [USBInfo] { viewModel.usbs.filter { $0.matches(viewModel.searchText) } }
    private var filteredPartitions: [PartitionInfo] { viewModel.partitions.filter { $0.matches(viewModel.searchText) } }
    private var filteredPerformance: [VMPerformanceInfo] { viewModel.performanceMetrics.filter { $0.matches(viewModel.searchText) } }
    private var filteredHealthChecks: [HealthCheckResult] { viewModel.healthChecks.filter { $0.matches(viewModel.searchText) } }
    private var filteredSnapshotHistory: [InventorySnapshot] { viewModel.snapshotHistory.filter { $0.matches(viewModel.searchText) } }

    // MARK: - Sort order (per tab, lifted up from each Tab view's own local
    // @State so Export can sort by the same order the Table is showing —
    // previously each V*TabView owned this itself and Export always used
    // unsorted collection order regardless of what was on screen).

    @State private var vInfoSortOrder = [FieldComparator<VirtualMachineInfo>.value("name", \.name)]
    @State private var vCpuSortOrder = [FieldComparator<VMCpuInfo>.value("vm", \.vmName)]
    @State private var vMemorySortOrder = [FieldComparator<VMMemoryInfo>.value("vm", \.vmName)]
    @State private var vDiskSortOrder = [FieldComparator<VMDiskInfo>.value("vm", \.vmName)]
    @State private var vSnapshotSortOrder = [FieldComparator<VMSnapshotInfo>.value("created", \.createdDate)]
    @State private var vToolsSortOrder = [FieldComparator<VMToolsInfo>.value("vm", \.vmName)]
    @State private var vNetworkSortOrder = [FieldComparator<VMNetworkInfo>.value("vm", \.vmName)]
    @State private var vHostSortOrder = [FieldComparator<HostInfo>.value("name", \.name)]
    @State private var vDatastoreSortOrder = [FieldComparator<DatastoreInfo>.value("name", \.name)]
    @State private var vClusterSortOrder = [FieldComparator<ClusterInfo>.value("name", \.name)]
    @State private var vLicenseSortOrder = [FieldComparator<LicenseInfo>.value("name", \.name)]
    @State private var vSwitchSortOrder = [FieldComparator<VSwitchInfo>.value("host", \.hostName)]
    @State private var vPortSortOrder = [FieldComparator<VPortInfo>.value("host", \.hostName)]
    @State private var dvSwitchSortOrder = [FieldComparator<DVSwitchInfo>.value("name", \.name)]
    @State private var dvPortSortOrder = [FieldComparator<DVPortInfo>.value("name", \.name)]
    @State private var vRPSortOrder = [FieldComparator<ResourcePoolInfo>.value("name", \.name)]
    @State private var vAppSortOrder = [FieldComparator<VAppInfo>.value("name", \.name)]
    @State private var vHBASortOrder = [FieldComparator<HBAInfo>.value("host", \.hostName)]
    @State private var vNicSortOrder = [FieldComparator<NicInfo>.value("host", \.hostName)]
    @State private var vmkSortOrder = [FieldComparator<VMKernelInfo>.value("host", \.hostName)]
    @State private var vMultipathSortOrder = [FieldComparator<MultipathInfo>.value("host", \.hostName)]
    @State private var vCDSortOrder = [FieldComparator<CDInfo>.value("vm", \.vmName)]
    @State private var vFloppySortOrder = [FieldComparator<FloppyInfo>.value("vm", \.vmName)]
    @State private var vUSBSortOrder = [FieldComparator<USBInfo>.value("vm", \.vmName)]
    @State private var vPartitionSortOrder = [FieldComparator<PartitionInfo>.value("vm", \.vmName)]
    @State private var vPerformanceSortOrder = [FieldComparator<VMPerformanceInfo>.value("vm", \.vmName)]
    @State private var vHealthSortOrder = [FieldComparator<HealthCheckResult>.value("severity", \.severity.rawValue)]

    private var currentRowCount: Int {
        switch selectedTab {
        case .vInfo: return filteredVMs.count
        case .vCpu: return filteredCpus.count
        case .vMemory: return filteredMemory.count
        case .vDisk: return filteredDisks.count
        case .vSnapshot: return filteredSnapshots.count
        case .vTools: return filteredTools.count
        case .vNetwork: return filteredNetworks.count
        case .vHost: return filteredHosts.count
        case .vDatastore: return filteredDatastores.count
        case .vCluster: return filteredClusters.count
        case .vLicense: return filteredLicenses.count
        case .vSwitch: return filteredVSwitches.count
        case .vPort: return filteredPorts.count
        case .dvSwitch: return filteredDVSwitches.count
        case .dvPort: return filteredDVPorts.count
        case .vRP: return filteredResourcePools.count
        case .vApp: return filteredVApps.count
        case .vHBA: return filteredHBAs.count
        case .vNic: return filteredNics.count
        case .vmk: return filteredVMKernels.count
        case .vMultipath: return filteredMultipaths.count
        case .vCD: return filteredCDs.count
        case .vFloppy: return filteredFloppies.count
        case .vUSB: return filteredUSBs.count
        case .vPartition: return filteredPartitions.count
        case .vPerformance: return filteredPerformance.count
        case .vHealth: return filteredHealthChecks.count
        case .snapshots: return filteredSnapshotHistory.count
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .vInfo: VInfoTabView(vms: filteredVMs, sortOrder: $vInfoSortOrder)
        case .vCpu: VCpuTabView(rows: filteredCpus, sortOrder: $vCpuSortOrder)
        case .vMemory: VMemoryTabView(rows: filteredMemory, sortOrder: $vMemorySortOrder)
        case .vDisk: VDiskTabView(rows: filteredDisks, sortOrder: $vDiskSortOrder)
        case .vSnapshot: VSnapshotTabView(rows: filteredSnapshots, sortOrder: $vSnapshotSortOrder)
        case .vTools: VToolsTabView(rows: filteredTools, sortOrder: $vToolsSortOrder)
        case .vNetwork: VNetworkTabView(rows: filteredNetworks, sortOrder: $vNetworkSortOrder)
        case .vHost: VHostTabView(rows: filteredHosts, sortOrder: $vHostSortOrder)
        case .vDatastore: VDatastoreTabView(rows: filteredDatastores, sortOrder: $vDatastoreSortOrder)
        case .vCluster: VClusterTabView(rows: filteredClusters, sortOrder: $vClusterSortOrder)
        case .vLicense: VLicenseTabView(rows: filteredLicenses, sortOrder: $vLicenseSortOrder)
        case .vSwitch: VSwitchTabView(rows: filteredVSwitches, sortOrder: $vSwitchSortOrder)
        case .vPort: VPortTabView(rows: filteredPorts, sortOrder: $vPortSortOrder)
        case .dvSwitch: DVSwitchTabView(rows: filteredDVSwitches, sortOrder: $dvSwitchSortOrder)
        case .dvPort: DVPortTabView(rows: filteredDVPorts, sortOrder: $dvPortSortOrder)
        case .vRP: VRPTabView(rows: filteredResourcePools, sortOrder: $vRPSortOrder)
        case .vApp: VAppTabView(rows: filteredVApps, sortOrder: $vAppSortOrder)
        case .vHBA: VHBATabView(rows: filteredHBAs, sortOrder: $vHBASortOrder)
        case .vNic: VNicTabView(rows: filteredNics, sortOrder: $vNicSortOrder)
        case .vmk: VMKTabView(rows: filteredVMKernels, sortOrder: $vmkSortOrder)
        case .vMultipath: VMultipathTabView(rows: filteredMultipaths, sortOrder: $vMultipathSortOrder)
        case .vCD: VCDTabView(rows: filteredCDs, sortOrder: $vCDSortOrder)
        case .vFloppy: VFloppyTabView(rows: filteredFloppies, sortOrder: $vFloppySortOrder)
        case .vUSB: VUSBTabView(rows: filteredUSBs, sortOrder: $vUSBSortOrder)
        case .vPartition: VPartitionTabView(rows: filteredPartitions, sortOrder: $vPartitionSortOrder)
        case .vPerformance: VPerformanceTabView(viewModel: viewModel, rows: filteredPerformance, sortOrder: $vPerformanceSortOrder)
        case .vHealth: VHealthTabView(rows: filteredHealthChecks, sortOrder: $vHealthSortOrder)
        case .snapshots: SnapshotsTabView(viewModel: viewModel, rows: filteredSnapshotHistory)
        }
    }

    // MARK: - Report

    private func generateReport() {
        let reportData = ReportData(
            vCenterHost: viewModel.isDemoMode ? "Demo vCenter" : viewModel.host,
            vCenterInfo: viewModel.vCenterInfo,
            vms: viewModel.vms, hosts: viewModel.hosts, clusters: viewModel.clusters,
            datastores: viewModel.datastores, healthChecks: viewModel.healthChecks,
            generatedAt: Date()
        )
        guard let pdfData = ReportRenderer.renderPDF(ReportView(data: reportData)) else {
            let alert = NSAlert()
            alert.messageText = "Report generation failed"
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        ExportPanel.savePDF(data: pdfData, suggestedFilename: "\(reportData.vCenterHost)-vLens-Report.pdf")
    }

    // MARK: - Export

    private enum ExportFormat { case csv, xlsx }

    private func exportCurrentTab(as format: ExportFormat) {
        switch selectedTab {
        case .vInfo: export(filteredVMs.sorted(using: vInfoSortOrder), format: format)
        case .vCpu: export(filteredCpus.sorted(using: vCpuSortOrder), format: format)
        case .vMemory: export(filteredMemory.sorted(using: vMemorySortOrder), format: format)
        case .vDisk: export(filteredDisks.sorted(using: vDiskSortOrder), format: format)
        case .vSnapshot: export(filteredSnapshots.sorted(using: vSnapshotSortOrder), format: format)
        case .vTools: export(filteredTools.sorted(using: vToolsSortOrder), format: format)
        case .vNetwork: export(filteredNetworks.sorted(using: vNetworkSortOrder), format: format)
        case .vHost: export(filteredHosts.sorted(using: vHostSortOrder), format: format)
        case .vDatastore: export(filteredDatastores.sorted(using: vDatastoreSortOrder), format: format)
        case .vCluster: export(filteredClusters.sorted(using: vClusterSortOrder), format: format)
        case .vLicense: export(filteredLicenses.sorted(using: vLicenseSortOrder), format: format)
        case .vSwitch: export(filteredVSwitches.sorted(using: vSwitchSortOrder), format: format)
        case .vPort: export(filteredPorts.sorted(using: vPortSortOrder), format: format)
        case .dvSwitch: export(filteredDVSwitches.sorted(using: dvSwitchSortOrder), format: format)
        case .dvPort: export(filteredDVPorts.sorted(using: dvPortSortOrder), format: format)
        case .vRP: export(filteredResourcePools.sorted(using: vRPSortOrder), format: format)
        case .vApp: export(filteredVApps.sorted(using: vAppSortOrder), format: format)
        case .vHBA: export(filteredHBAs.sorted(using: vHBASortOrder), format: format)
        case .vNic: export(filteredNics.sorted(using: vNicSortOrder), format: format)
        case .vmk: export(filteredVMKernels.sorted(using: vmkSortOrder), format: format)
        case .vMultipath: export(filteredMultipaths.sorted(using: vMultipathSortOrder), format: format)
        case .vCD: export(filteredCDs.sorted(using: vCDSortOrder), format: format)
        case .vFloppy: export(filteredFloppies.sorted(using: vFloppySortOrder), format: format)
        case .vUSB: export(filteredUSBs.sorted(using: vUSBSortOrder), format: format)
        case .vPartition: export(filteredPartitions.sorted(using: vPartitionSortOrder), format: format)
        case .vPerformance: export(filteredPerformance.sorted(using: vPerformanceSortOrder), format: format)
        case .vHealth: export(filteredHealthChecks.sorted(using: vHealthSortOrder), format: format)
        case .snapshots: export(filteredSnapshotHistory, format: format)
        }
    }

    private func export<T: CSVExportable>(_ rows: [T], format: ExportFormat) {
        switch format {
        case .csv:
            ExportPanel.saveCSV(content: CSVWriter.write(rows), suggestedFilename: "\(selectedTab.label).csv")
        case .xlsx:
            do {
                let data = try XLSXWriter.data(for: rows, sheetName: selectedTab.label)
                ExportPanel.saveXLSX(data: data, suggestedFilename: "\(selectedTab.label).xlsx")
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}

#Preview {
    ContentView(viewModel: ConnectionViewModel())
}
