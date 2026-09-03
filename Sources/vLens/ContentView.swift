import SwiftUI
import AppKit
import vLensCore

struct ContentView: View {
    @Bindable var viewModel: ConnectionViewModel
    @State private var selectedTab: AppTab = .vInfo
    private let tutorialStore = TutorialStore()
    @State private var showWelcome = false
    @State private var showAdvisories = false

    /// `List(selection:)` wants `Binding<AppTab?>`; the rest of this file
    /// switches on plain `AppTab` (simpler, and a sidebar row is never
    /// truly "no selection" once connected) — this just bridges the two.
    private var sidebarSelection: Binding<AppTab?> {
        Binding(get: { selectedTab }, set: { if let newValue = $0 { selectedTab = newValue } })
    }

    var body: some View {
        Group {
            if viewModel.vms.isEmpty {
                connectForm
                    .frame(width: 480, height: 580)
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
                NavigationSplitView {
                    sidebar
                } detail: {
                    VStack(spacing: 0) {
                        if viewModel.isDemoMode {
                            demoBanner
                        }
                        toolbar
                        Divider()
                        tabContent
                        Divider()
                        statusBar
                    }
                }
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
    }

    // MARK: - Connect form

    private var connectForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("vLens").font(.largeTitle.bold())
            Text("Connect to vCenter").font(.headline)

            if !viewModel.savedProfiles.isEmpty {
                savedProfilesMenu
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

            HStack {
                Button("Try demo mode") {
                    viewModel.loadDemoData()
                }
                .buttonStyle(.link)
                .disabled(viewModel.isConnecting)

                Spacer()
                Button {
                    Task { await viewModel.connectAndListVMs() }
                } label: {
                    if viewModel.isConnecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isConnecting)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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
            Label("Saved connections", systemImage: "clock.arrow.circlepath")
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
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search (VM, host, cluster...)", text: $viewModel.searchText)
                .textFieldStyle(.plain)
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
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
    private var filteredUSBs: [USBInfo] { viewModel.usbs.filter { $0.matches(viewModel.searchText) } }
    private var filteredPartitions: [PartitionInfo] { viewModel.partitions.filter { $0.matches(viewModel.searchText) } }
    private var filteredPerformance: [VMPerformanceInfo] { viewModel.performanceMetrics.filter { $0.matches(viewModel.searchText) } }
    private var filteredHealthChecks: [HealthCheckResult] { viewModel.healthChecks.filter { $0.matches(viewModel.searchText) } }
    private var filteredSnapshotHistory: [InventorySnapshot] { viewModel.snapshotHistory.filter { $0.matches(viewModel.searchText) } }

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
        case .vInfo: VInfoTabView(vms: filteredVMs)
        case .vCpu: VCpuTabView(rows: filteredCpus)
        case .vMemory: VMemoryTabView(rows: filteredMemory)
        case .vDisk: VDiskTabView(rows: filteredDisks)
        case .vSnapshot: VSnapshotTabView(rows: filteredSnapshots)
        case .vTools: VToolsTabView(rows: filteredTools)
        case .vNetwork: VNetworkTabView(rows: filteredNetworks)
        case .vHost: VHostTabView(rows: filteredHosts)
        case .vDatastore: VDatastoreTabView(rows: filteredDatastores)
        case .vCluster: VClusterTabView(rows: filteredClusters)
        case .vLicense: VLicenseTabView(rows: filteredLicenses)
        case .vSwitch: VSwitchTabView(rows: filteredVSwitches)
        case .vPort: VPortTabView(rows: filteredPorts)
        case .dvSwitch: DVSwitchTabView(rows: filteredDVSwitches)
        case .dvPort: DVPortTabView(rows: filteredDVPorts)
        case .vRP: VRPTabView(rows: filteredResourcePools)
        case .vApp: VAppTabView(rows: filteredVApps)
        case .vHBA: VHBATabView(rows: filteredHBAs)
        case .vNic: VNicTabView(rows: filteredNics)
        case .vmk: VMKTabView(rows: filteredVMKernels)
        case .vMultipath: VMultipathTabView(rows: filteredMultipaths)
        case .vCD: VCDTabView(rows: filteredCDs)
        case .vUSB: VUSBTabView(rows: filteredUSBs)
        case .vPartition: VPartitionTabView(rows: filteredPartitions)
        case .vPerformance: VPerformanceTabView(viewModel: viewModel, rows: filteredPerformance)
        case .vHealth: VHealthTabView(rows: filteredHealthChecks)
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
        case .vInfo: export(filteredVMs, format: format)
        case .vCpu: export(filteredCpus, format: format)
        case .vMemory: export(filteredMemory, format: format)
        case .vDisk: export(filteredDisks, format: format)
        case .vSnapshot: export(filteredSnapshots, format: format)
        case .vTools: export(filteredTools, format: format)
        case .vNetwork: export(filteredNetworks, format: format)
        case .vHost: export(filteredHosts, format: format)
        case .vDatastore: export(filteredDatastores, format: format)
        case .vCluster: export(filteredClusters, format: format)
        case .vLicense: export(filteredLicenses, format: format)
        case .vSwitch: export(filteredVSwitches, format: format)
        case .vPort: export(filteredPorts, format: format)
        case .dvSwitch: export(filteredDVSwitches, format: format)
        case .dvPort: export(filteredDVPorts, format: format)
        case .vRP: export(filteredResourcePools, format: format)
        case .vApp: export(filteredVApps, format: format)
        case .vHBA: export(filteredHBAs, format: format)
        case .vNic: export(filteredNics, format: format)
        case .vmk: export(filteredVMKernels, format: format)
        case .vMultipath: export(filteredMultipaths, format: format)
        case .vCD: export(filteredCDs, format: format)
        case .vUSB: export(filteredUSBs, format: format)
        case .vPartition: export(filteredPartitions, format: format)
        case .vPerformance: export(filteredPerformance, format: format)
        case .vHealth: export(filteredHealthChecks, format: format)
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
