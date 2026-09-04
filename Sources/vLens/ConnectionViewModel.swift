import Foundation
import vLensCore

@Observable
@MainActor
final class ConnectionViewModel {
    var host: String = ""
    var username: String = ""
    var password: String = ""
    var saveCredentials: Bool = false

    var isConnecting: Bool = false
    var errorMessage: String?
    var isDemoMode: Bool = false
    var lastRefreshedAt: Date?
    var searchText: String = ""

    /// Set when `fetchCertificate` returns a certificate this host has never
    /// been seen presenting before. The Connect screen shows a confirmation
    /// sheet bound to this; resolved via `approvePendingCertificate()` or
    /// `cancelPendingCertificate()`. `nil` means no approval is pending.
    var pendingCertificateApproval: PendingCertificateApproval?

    struct PendingCertificateApproval: Identifiable {
        var id: String { host }
        let host: String
        let fingerprint: CertificateFingerprint
        let subject: String
        let issuer: String
        let notAfter: String
    }

    // One array per MVP tab. Populated together on connect/demo-load so
    // every tab has data as soon as the table appears — matches RVTools'
    // own "collect everything up front" behavior rather than per-tab lazy
    // loading, which would mean re-authenticating per tab click.
    var vms: [VirtualMachineInfo] = []
    var cpus: [VMCpuInfo] = []
    var memory: [VMMemoryInfo] = []
    var disks: [VMDiskInfo] = []
    var snapshots: [VMSnapshotInfo] = []
    var tools: [VMToolsInfo] = []
    var networks: [VMNetworkInfo] = []
    var hosts: [HostInfo] = []
    var datastores: [DatastoreInfo] = []
    var clusters: [ClusterInfo] = []
    var licenses: [LicenseInfo] = []
    var vSwitches: [VSwitchInfo] = []
    var ports: [VPortInfo] = []
    var dvSwitches: [DVSwitchInfo] = []
    var dvPorts: [DVPortInfo] = []
    var resourcePools: [ResourcePoolInfo] = []
    var vApps: [VAppInfo] = []
    var hbas: [HBAInfo] = []
    var nics: [NicInfo] = []
    var vmKernels: [VMKernelInfo] = []
    var multipaths: [MultipathInfo] = []
    var cds: [CDInfo] = []
    var usbs: [USBInfo] = []
    var partitions: [PartitionInfo] = []
    var healthChecks: [HealthCheckResult] = []
    /// Backs the executive report's header (`ReportView`) — not a tab.
    var vCenterInfo: VCenterInfo?

    /// Recent VMware/Broadcom security advisories — not vCenter data, a
    /// plain internet fetch. See `checkSecurityAdvisories()`.
    var securityAdvisories: [SecurityAdvisory] = []
    var notableAdvisoryCount: Int { securityAdvisories.filter(\.isNotable).count }

    /// Not part of `collectAll` — see `collectPerformance()` below and
    /// `collectPerformanceAction`'s doc comment in `helper/main.go`.
    var performanceMetrics: [VMPerformanceInfo] = []
    var isCollectingPerformance = false
    var performanceErrorMessage: String?

    /// Local, persisted history for the currently-connected vCenter host —
    /// see `SnapshotsTabView`/`InventorySnapshot`. Reloaded (filtered by
    /// host) whenever a connection or demo load succeeds.
    var snapshotHistory: [InventorySnapshot] = []

    /// Which `SnapshotMetricDescriptor` rows the Compare panel shows —
    /// mirrors `healthCheckThresholds`'s didSet-persists pattern.
    var enabledSnapshotMetricKeys: Set<String> {
        didSet {
            guard enabledSnapshotMetricKeys != oldValue else { return }
            snapshotPreferencesStore.save(enabledMetricKeys: enabledSnapshotMetricKeys)
        }
    }

    var savedProfiles: [ConnectionProfile] = []
    private var activeProfileID: UUID?

    /// Faz 10B — Preferences' "Automation" section. `nil` means no schedule
    /// configured; a non-nil schedule with `enabled == false` means the
    /// user configured one but toggled it off (the launchd job stays torn
    /// down either way — see `saveAutomationSchedule`).
    var automationSchedule: AutomationSchedule?
    var automationError: String?

    /// RVTools' equivalent is its Health Properties panel. Changing this
    /// (from `PreferencesView`, the app's Settings scene) re-evaluates
    /// vHealth immediately against whatever's already collected — no
    /// reconnect needed.
    var healthCheckThresholds: HealthCheckThresholds {
        didSet {
            guard healthCheckThresholds != oldValue else { return }
            healthCheckPreferencesStore.save(healthCheckThresholds)
            recomputeHealthChecks()
        }
    }

    private let helperClient = VSphereHelperClient(helperURL: HelperLocator.resolve())
    private let profileStore = ConnectionProfileStore()
    private let credentialStore: CredentialStoreProtocol = KeychainCredentialStore()
    private let certificateTrustStore: CertificateTrustStoreProtocol = LocalJSONCertificateTrustStore()
    private let healthCheckPreferencesStore = HealthCheckPreferencesStore()
    /// Recomputed each access (cheap — `SnapshotStore` just wraps a URL) so
    /// a location change in Preferences takes effect immediately, no
    /// invalidation needed.
    private var snapshotStore: SnapshotStore {
        SnapshotStore(fileURL: SnapshotStore.url(inDirectory: snapshotPreferencesStore.customStorageDirectory))
    }
    private let snapshotPreferencesStore = SnapshotPreferencesStore()
    private let automationPreferencesStore = AutomationPreferencesStore()
    private let vmsaClient = VMSAClient()

    init() {
        savedProfiles = profileStore.loadAll()
        healthCheckThresholds = healthCheckPreferencesStore.load()
        enabledSnapshotMetricKeys = snapshotPreferencesStore.loadEnabledMetricKeys()
        automationSchedule = automationPreferencesStore.load()
    }

    /// Persists the schedule and (re)installs the launchd job — called from
    /// Preferences' "Automation" section on Save. `LaunchdScheduler.install`
    /// throws (e.g. missing `vlens-cli` in a dev build, or a `launchctl`
    /// failure) — surfaced via `automationError` rather than silently no-op'd,
    /// since a schedule that looks saved but never actually runs would be a
    /// real, confusing footgun.
    func saveAutomationSchedule(_ schedule: AutomationSchedule) {
        automationError = nil
        guard let profile = savedProfiles.first(where: { $0.id == schedule.profileID }) else {
            automationError = "Selected connection no longer exists."
            return
        }
        automationSchedule = schedule
        automationPreferencesStore.save(schedule)

        guard schedule.enabled else {
            LaunchdScheduler.uninstall()
            return
        }
        do {
            try LaunchdScheduler.install(schedule: schedule, profile: profile)
        } catch {
            automationError = error.localizedDescription
        }
    }

    func removeAutomationSchedule() {
        automationError = nil
        automationSchedule = nil
        automationPreferencesStore.save(nil)
        LaunchdScheduler.uninstall()
    }

    /// Fills the form from a saved profile and tries to recall its password
    /// from Keychain — the user still presses Connect, this never auto-connects.
    func selectSavedProfile(_ profile: ConnectionProfile) {
        host = profile.host
        username = profile.username
        activeProfileID = profile.id
        saveCredentials = true
        password = (try? credentialStore.readSecret(for: ConnectionProfile.keychainReferenceID(for: profile.id))) ?? ""
    }

    func deleteSavedProfile(_ profile: ConnectionProfile) {
        try? profileStore.delete(id: profile.id)
        try? credentialStore.deleteSecret(for: ConnectionProfile.keychainReferenceID(for: profile.id))
        savedProfiles = profileStore.loadAll()
        if activeProfileID == profile.id { activeProfileID = nil }
    }

    /// Loads mock data for every MVP tab so the UI can be exercised without
    /// a live vCenter — the product is still early-stage and shouldn't be
    /// pointed at a real environment yet.
    func loadDemoData() {
        errorMessage = nil
        isDemoMode = true
        vms = DemoData.virtualMachines()
        cpus = DemoData.cpus(for: vms)
        memory = DemoData.memory(for: vms)
        disks = DemoData.disks(for: vms)
        snapshots = DemoData.snapshots(for: vms)
        tools = DemoData.tools(for: vms)
        networks = DemoData.networks(for: vms)
        hosts = DemoData.hosts()
        datastores = DemoData.datastores()
        clusters = DemoData.clusterInfos()
        licenses = DemoData.licenses()
        vSwitches = DemoData.vSwitches()
        ports = DemoData.vPorts()
        dvSwitches = DemoData.dvSwitches()
        dvPorts = DemoData.dvPorts()
        resourcePools = DemoData.resourcePools()
        vApps = DemoData.vApps()
        hbas = DemoData.hbas()
        nics = DemoData.nics()
        vmKernels = DemoData.vmKernels()
        multipaths = DemoData.multipaths()
        cds = DemoData.cds(for: vms)
        usbs = DemoData.usbs(for: vms)
        partitions = DemoData.partitions(for: vms)
        performanceMetrics = DemoData.performanceMetrics(for: vms, intervalMinutes: 60)
        vCenterInfo = VCenterInfo(fullName: "VMware vCenter Server 8.0.3 build-24022515", version: "8.0.3", build: "24022515", apiVersion: "8.0.3.0")
        recomputeHealthChecks()
        lastRefreshedAt = Date()
        loadSnapshotHistory()
    }

    func exitDemoMode() {
        isDemoMode = false
        clearAllTabs()
    }

    private func clearAllTabs() {
        vms = []
        cpus = []
        memory = []
        disks = []
        snapshots = []
        tools = []
        networks = []
        hosts = []
        datastores = []
        clusters = []
        licenses = []
        vSwitches = []
        ports = []
        dvSwitches = []
        dvPorts = []
        resourcePools = []
        vApps = []
        hbas = []
        nics = []
        vmKernels = []
        multipaths = []
        cds = []
        usbs = []
        partitions = []
        performanceMetrics = []
        healthChecks = []
        vCenterInfo = nil
        lastRefreshedAt = nil
        snapshotHistory = []
    }

    private func recomputeHealthChecks() {
        healthChecks = HealthCheckEngine.evaluate(
            snapshots: snapshots,
            tools: tools,
            datastores: datastores,
            hosts: hosts,
            cpus: cpus,
            cds: cds,
            partitions: partitions,
            multipaths: multipaths,
            vms: vms,
            thresholds: healthCheckThresholds
        )
    }

    // MARK: - Connect flow (certificate trust-on-first-use, then collect)

    func connectAndListVMs() async {
        guard !host.isEmpty, !username.isEmpty, !password.isEmpty else {
            errorMessage = "Host, username, and password are required."
            return
        }

        isConnecting = true
        errorMessage = nil

        let sdkURL = normalizedSDKURL()

        do {
            guard try await ensureCertificateTrusted(sdkURL: sdkURL) else {
                // Unknown certificate — pendingCertificateApproval is now
                // set, the Connect screen shows a confirmation sheet. Not
                // an error, just paused waiting on the user.
                isConnecting = false
                return
            }
        } catch {
            errorMessage = Self.describe(error)
            isConnecting = false
            return
        }

        await performCollection(sdkURL: sdkURL)
        isConnecting = false
    }

    /// User approved the certificate shown in the pending-approval sheet.
    func approvePendingCertificate() async {
        guard let pending = pendingCertificateApproval else { return }
        do {
            try certificateTrustStore.trust(
                host: pending.host, fingerprint: pending.fingerprint,
                subject: pending.subject, issuer: pending.issuer
            )
        } catch {
            errorMessage = "Couldn't save certificate trust: \(error.localizedDescription)"
            pendingCertificateApproval = nil
            return
        }

        pendingCertificateApproval = nil
        isConnecting = true
        await performCollection(sdkURL: normalizedSDKURL())
        isConnecting = false
    }

    func cancelPendingCertificate() {
        pendingCertificateApproval = nil
    }

    private func normalizedSDKURL() -> String {
        host.hasSuffix("/sdk") ? host : "https://\(host)/sdk"
    }

    /// Returns `true` if the connection is already trusted and safe to
    /// proceed immediately. Returns `false` after setting
    /// `pendingCertificateApproval` for an unknown certificate — the caller
    /// should stop and wait for the user. Throws `CertificateMismatchError`
    /// when a previously-pinned certificate disagrees with what's presented
    /// now: always a hard block, never a silent "connect anyway".
    private func ensureCertificateTrusted(sdkURL: String) async throws -> Bool {
        let cert = try await helperClient.fetchCertificate(url: sdkURL)
        let fingerprint = CertificateFingerprint(sha256Hex: cert.sha256Fingerprint)

        switch certificateTrustStore.decision(for: host, fingerprint: fingerprint) {
        case .trusted:
            return true
        case .mismatch(let expected):
            throw CertificateMismatchError(host: host, expected: expected, presented: fingerprint)
        case .unknown:
            pendingCertificateApproval = PendingCertificateApproval(
                host: host, fingerprint: fingerprint,
                subject: cert.subject, issuer: cert.issuer, notAfter: cert.notAfter
            )
            return false
        }
    }

    private func performCollection(sdkURL: String) async {
        do {
            // Always `insecure: true` at the transport layer — standard CA
            // validation is superseded by the fingerprint pinning that just
            // happened in ensureCertificateTrusted/approvePendingCertificate.
            // By the time we get here, the certificate has already been
            // explicitly trusted (either previously, or just now by the user).
            let inventory = try await helperClient.collectAll(
                url: sdkURL, username: username, password: password, insecure: true
            )
            vms = inventory.vms
            cpus = inventory.cpus
            memory = inventory.memory
            disks = inventory.disks
            snapshots = inventory.snapshots
            tools = inventory.tools
            networks = inventory.networks
            hosts = inventory.hosts
            datastores = inventory.datastores
            clusters = inventory.clusters
            licenses = inventory.licenses
            vSwitches = inventory.vSwitches
            ports = inventory.ports
            dvSwitches = inventory.dvSwitches
            dvPorts = inventory.dvPorts
            resourcePools = inventory.resourcePools
            vApps = inventory.vApps
            hbas = inventory.hbas
            nics = inventory.nics
            vmKernels = inventory.vmKernels
            multipaths = inventory.multipaths
            cds = inventory.cds
            usbs = inventory.usbs
            partitions = inventory.partitions
            performanceMetrics = [] // separate action, doesn't carry over from a previous connection
            vCenterInfo = inventory.vCenter
            recomputeHealthChecks()
            isDemoMode = false
            lastRefreshedAt = Date()
            loadSnapshotHistory()
            if saveCredentials {
                persistCurrentConnection()
            }
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    // MARK: - Security advisories (not vCenter data, see VMSAClient)

    /// Called once per app launch (`ContentView`'s `.task`) — silently does
    /// nothing on failure (no network, Broadcom's endpoint changed shape,
    /// etc.). This is a nice-to-have awareness feature, not something that
    /// should ever interrupt or alarm the user with an error dialog.
    func checkSecurityAdvisories() async {
        securityAdvisories = (try? await vmsaClient.fetchRecentAdvisories()) ?? []
    }

    // MARK: - Snapshots (local history, see SnapshotsTabView)

    /// Demo mode gets its own fixed key so demo snapshots never mix with a
    /// real vCenter's history.
    private var currentSnapshotHost: String { isDemoMode ? "demo" : host }

    func loadSnapshotHistory() {
        let currentHost = currentSnapshotHost
        snapshotHistory = snapshotStore.loadAll()
            .filter { $0.vCenterHost == currentHost }
            .sorted { $0.takenAt > $1.takenAt }
    }

    /// Where `inventory-snapshots.json` currently lives — shown in
    /// Preferences with a "Reveal in Finder" button.
    var snapshotStorageURL: URL { snapshotStore.url }

    /// Switches where snapshot history is read/written. Migrates by
    /// **copying** the existing file to the new location (never moving —
    /// the old file stays as a safety net) only when the new location
    /// doesn't already have one, so switching back and forth never clobbers
    /// data. See Preferences' "Snapshot Storage" section.
    func changeSnapshotStorageDirectory(to directory: URL?) {
        let oldURL = snapshotStore.url
        let newURL = SnapshotStore.url(inDirectory: directory)
        if oldURL != newURL, FileManager.default.fileExists(atPath: oldURL.path),
            !FileManager.default.fileExists(atPath: newURL.path) {
            try? FileManager.default.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: oldURL, to: newURL)
        }
        snapshotPreferencesStore.customStorageDirectory = directory
        loadSnapshotHistory()
    }

    /// Computes metrics from whatever's already loaded — no vCenter call.
    func takeSnapshot(label: String?, includeFullDetail: Bool = false) {
        let metrics = InventorySnapshotMetrics.compute(
            vms: vms, hosts: hosts, clusters: clusters, datastores: datastores,
            snapshots: snapshots, tools: tools, healthChecks: healthChecks
        )
        let snapshot = InventorySnapshot(
            vCenterHost: currentSnapshotHost, label: label, metrics: metrics,
            fullVMList: includeFullDetail ? vms : nil
        )
        try? snapshotStore.add(snapshot)
        loadSnapshotHistory()
    }

    func deleteSnapshot(_ snapshot: InventorySnapshot) {
        try? snapshotStore.delete(id: snapshot.id)
        loadSnapshotHistory()
    }

    /// Multi-select "Delete Selected" in the Snapshots tab.
    func deleteSnapshots(ids: Set<UUID>) {
        try? snapshotStore.delete(ids: ids)
        loadSnapshotHistory()
    }

    /// Standalone action, not part of `connectAndListVMs`/`performCollection`
    /// — see the doc comment on `collectPerformanceAction` in
    /// `helper/main.go`. Safe to call repeatedly with a different
    /// `intervalMinutes` from the vPerformance tab's own refresh control.
    func collectPerformance(intervalMinutes: Int) async {
        guard !isDemoMode else {
            performanceMetrics = DemoData.performanceMetrics(for: vms, intervalMinutes: intervalMinutes)
            return
        }
        isCollectingPerformance = true
        performanceErrorMessage = nil
        do {
            performanceMetrics = try await helperClient.collectPerformance(
                url: normalizedSDKURL(), username: username, password: password, insecure: true,
                intervalMinutes: intervalMinutes
            )
        } catch {
            performanceErrorMessage = Self.describe(error)
        }
        isCollectingPerformance = false
    }

    private func persistCurrentConnection() {
        let id = activeProfileID ?? UUID()
        activeProfileID = id
        let profile = ConnectionProfile(id: id, name: host, host: host, username: username)
        do {
            try profileStore.upsert(profile)
            try credentialStore.saveSecret(password, for: ConnectionProfile.keychainReferenceID(for: id))
            savedProfiles = profileStore.loadAll()
        } catch {
            // Non-fatal: the connection itself already succeeded, only the
            // "remember this" convenience failed. Surface it but don't
            // clear the data that's already on screen.
            errorMessage = "Couldn't save connection: \(error.localizedDescription)"
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case HelperClientError.helperBinaryNotFound:
            return "vlens-helper binary not found. Did you run `cd helper && go build -o vlens-helper .`?"
        case HelperClientError.processFailed(let code, let stderr):
            return "Helper process exited with code \(code): \(stderr)"
        case HelperClientError.helperReportedError(let message):
            return message
        case let localized as LocalizedError where localized.errorDescription != nil:
            return localized.errorDescription!
        default:
            return String(describing: error)
        }
    }
}
