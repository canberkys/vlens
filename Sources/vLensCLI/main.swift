import Foundation
import vLensCore

/// `vlens-cli` — headless snapshot/export for a saved connection, meant to
/// be driven by `launchd` (Faz 10B) or run by hand. One process per
/// invocation, same "no long-lived daemon" philosophy as `vlens-helper`
/// itself: a crash or hang can't leak into the next scheduled run.
///
/// Reuses `vLensCore` end to end (`ConnectionProfileStore`,
/// `KeychainCredentialStore`, `LocalJSONCertificateTrustStore`,
/// `VSphereHelperClient`, `SnapshotStore`, `HealthCheckEngine`,
/// `CSVWriter`/`XLSXWriter`) — none of it is AppKit/SwiftUI-bound, so
/// nothing here duplicates GUI logic beyond the short connect/cert-trust
/// orchestration in `collect(profile:password:)`, which intentionally
/// resolves `.unknown` differently than `ConnectionViewModel` does (the GUI
/// shows an approval sheet; the CLI can't, so it fails instead).

/// Every `*PreferencesStore` in vLensCore defaults to `UserDefaults.standard`,
/// which is fine for the GUI app (its real bundle ID, `com.canberkki.vlens`,
/// names the domain) but wrong for this bare executable in **dev** mode
/// (`swift run vlens-cli` has no bundle ID at all, so `.standard` would
/// resolve to a domain keyed off the process name, silently missing
/// whatever the GUI has configured). In the **packaged** app, though,
/// `vlens-cli` sits at `Contents/MacOS/vlens-cli` right next to `vLens`'s
/// own `Contents/Info.plist` — `Bundle.main` resolution walks up from the
/// executable looking for a nearby Info.plist, so it picks up the *same*
/// bundle identifier as the GUI, meaning `.standard` already targets the
/// right domain there. Passing `suiteName: "com.canberkki.vlens"` in that
/// case is a documented no-op (macOS logs "using your own bundle
/// identifier as a suite name does not make sense") — harmless, but noisy
/// — so only use the explicit suite when the bundle ID doesn't already
/// match (confirmed against a real packaged build, Faz 10B).
nonisolated func sharedDefaults() -> UserDefaults {
    if Bundle.main.bundleIdentifier == "com.canberkki.vlens" {
        return .standard
    }
    return UserDefaults(suiteName: "com.canberkki.vlens") ?? .standard
}

/// Set once `--profile-id` is parsed (the shape `LaunchdScheduler` always
/// invokes this binary with) — a single chokepoint so `fail(_:)` can record
/// this as the scheduled automation's failed last-run result no matter
/// which function down the call chain actually calls `fail` (profile
/// resolution, password lookup, certificate trust, the collection itself
/// all can), without threading a parameter through every one of them.
/// `nil` for a manual, human-run `--profile <name>` invocation, which isn't
/// the scheduled job and shouldn't overwrite its last-run status.
nonisolated(unsafe) var currentAutomationProfileID: UUID?

func fail(_ message: String) -> Never {
    if currentAutomationProfileID != nil {
        AutomationPreferencesStore(defaults: sharedDefaults())
            .recordRunResult(AutomationRunResult(succeeded: false, message: message))
    }
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    exit(1)
}

func printUsage() {
    print("""
    vlens-cli — headless vLens snapshot/export

    Usage:
      vlens-cli list-profiles
      vlens-cli list-tabs
      vlens-cli snapshot --profile <name> [--label <text>] [--full-detail]
      vlens-cli export --profile <name> --tab <key> --format csv|xlsx --output <path>

    <name> matches a connection already saved (with "Save this connection to
    Keychain" enabled) from the vLens app. The host's TLS certificate must
    already be trusted too — connect once via the app to approve it.

    --profile-id <uuid> resolves by the profile's stable id instead of its
    name — used internally by scheduled automation (Preferences), not meant
    for manual use.
    """)
}

/// Minimal hand-rolled `--flag value` / `--flag` (boolean) parser — the
/// surface here is small enough that swift-argument-parser would be a
/// dependency for its own sake.
struct Options {
    private var values: [String: String] = [:]
    private var flags: Set<String> = []

    init(_ args: [String]) {
        var i = 0
        while i < args.count {
            let arg = args[i]
            guard arg.hasPrefix("--") else { i += 1; continue }
            let key = String(arg.dropFirst(2))
            if i + 1 < args.count, !args[i + 1].hasPrefix("--") {
                values[key] = args[i + 1]
                i += 2
            } else {
                flags.insert(key)
                i += 1
            }
        }
    }

    subscript(key: String) -> String? { values[key] }
    func has(_ key: String) -> Bool { flags.contains(key) }
}

func resolveProfile(named name: String) -> ConnectionProfile {
    let profiles = ConnectionProfileStore().loadAll()
    guard let profile = profiles.first(where: { $0.name == name || $0.host == name }) else {
        let available = profiles.map(\.name).joined(separator: ", ")
        fail("No saved connection named \"\(name)\". Available: \(available.isEmpty ? "(none — save one from the vLens app first)" : available)")
    }
    return profile
}

/// Used exclusively for `--profile-id` (`LaunchdScheduler`'s own generated
/// invocations) — resolves by the profile's stable UUID rather than its
/// name, which isn't guaranteed unique and can be changed by the user at
/// any time without that renaming this schedule's actual target.
func resolveProfile(id: UUID) -> ConnectionProfile {
    let profiles = ConnectionProfileStore().loadAll()
    guard let profile = profiles.first(where: { $0.id == id }) else {
        fail("No saved connection with id \(id.uuidString) — it may have been deleted. Re-save the automation schedule in Preferences.")
    }
    return profile
}

/// Resolves `--profile-id <uuid>` if present (also arming
/// `currentAutomationProfileID` so `fail(_:)` records this run's outcome),
/// otherwise falls back to the human-facing `--profile <name>`.
func resolveProfileFromOptions(_ opts: Options) -> ConnectionProfile {
    if let idString = opts["profile-id"] {
        guard let id = UUID(uuidString: idString) else {
            fail("--profile-id must be a UUID, got \"\(idString)\"")
        }
        currentAutomationProfileID = id
        return resolveProfile(id: id)
    }
    guard let name = opts["profile"] else {
        fail("--profile <name> (or --profile-id <uuid>) is required")
    }
    return resolveProfile(named: name)
}

func resolvePassword(for profile: ConnectionProfile) -> String {
    let password: String?
    do {
        password = try KeychainCredentialStore().readSecret(for: ConnectionProfile.keychainReferenceID(for: profile.id))
    } catch {
        password = nil
    }
    guard let password, !password.isEmpty else {
        fail("No saved password for \"\(profile.name)\". Connect once via the vLens app with \"Save this connection to Keychain\" enabled, then retry.")
    }
    return password
}

/// Counterpart to `fail(_:)`'s failure recording — called at the end of a
/// `snapshot`/`export` run that completed without hitting `fail`. A no-op
/// for a manual `--profile <name>` invocation (`currentAutomationProfileID`
/// stays nil in that case).
func recordAutomationSuccessIfNeeded() {
    guard currentAutomationProfileID != nil else { return }
    AutomationPreferencesStore(defaults: sharedDefaults())
        .recordRunResult(AutomationRunResult(succeeded: true, message: nil))
}

func normalizedSDKURL(_ host: String) -> String {
    host.hasSuffix("/sdk") ? host : "https://\(host)/sdk"
}

/// Same fetchCertificate → decision flow as
/// `ConnectionViewModel.ensureCertificateTrusted`, but `.unknown` fails
/// instead of pausing for a GUI approval sheet the CLI has no way to show —
/// trust-on-first-use still requires a human, just via the app, not here.
/// Returns the verified fingerprint's `displayValue` so the caller can pass
/// it to `collectAll`/`collectPerformance` — the Go helper binds the actual
/// login connection to it via thumbprint pinning (see `helper/main.go`'s
/// `newPinnedClient`), rather than the two being unrelated TLS connections.
func ensureCertificateTrusted(helperClient: VSphereHelperClient, host: String, sdkURL: String) async -> String {
    let trustStore = LocalJSONCertificateTrustStore()
    let cert: HelperCertificateInfo
    do {
        cert = try await helperClient.fetchCertificate(url: sdkURL)
    } catch {
        fail("Couldn't fetch certificate for \(host): \(error)")
    }
    let fingerprint = CertificateFingerprint(sha256Hex: cert.sha256Fingerprint)

    switch trustStore.decision(for: host, fingerprint: fingerprint) {
    case .trusted:
        return fingerprint.displayValue
    case .unknown:
        fail("Certificate for \(host) isn't trusted yet. Connect once via the vLens app to review and approve it, then retry.")
    case .mismatch(let expected):
        let mismatch = CertificateMismatchError(host: host, expected: expected, presented: fingerprint)
        fail(mismatch.errorDescription ?? "certificate mismatch for \(host)")
    }
}

func collect(profile: ConnectionProfile, password: String) async -> CollectedInventory {
    let helperClient = VSphereHelperClient(helperURL: CLIHelperLocator.resolve())
    let sdkURL = normalizedSDKURL(profile.host)
    let expectedFingerprint = await ensureCertificateTrusted(helperClient: helperClient, host: profile.host, sdkURL: sdkURL)
    do {
        return try await helperClient.collectAll(url: sdkURL, username: profile.username, password: password, expectedFingerprint: expectedFingerprint)
    } catch {
        fail("Collection failed: \(error)")
    }
}

func evaluateHealth(_ inventory: CollectedInventory) -> [HealthCheckResult] {
    let thresholds = HealthCheckPreferencesStore(defaults: sharedDefaults()).load()
    return HealthCheckEngine.evaluate(
        snapshots: inventory.snapshots, tools: inventory.tools, datastores: inventory.datastores,
        hosts: inventory.hosts, cpus: inventory.cpus, cds: inventory.cds, floppies: inventory.floppies, partitions: inventory.partitions,
        multipaths: inventory.multipaths, vms: inventory.vms, disks: inventory.disks, memory: inventory.memory,
        thresholds: thresholds
    )
}

// MARK: - Commands

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    printUsage()
    exit(0)
}
let opts = Options(Array(arguments.dropFirst()))

switch command {
case "list-profiles":
    let profiles = ConnectionProfileStore().loadAll()
    if profiles.isEmpty {
        print("No saved connections. Save one from the vLens app first.")
    } else {
        for profile in profiles {
            print("\(profile.name)\t\(profile.host)\t\(profile.username)")
        }
    }

case "list-tabs":
    for tab in ExportTab.allCases {
        print(tab.rawValue)
    }

case "snapshot":
    let profile = resolveProfileFromOptions(opts)
    let password = resolvePassword(for: profile)
    let inventory = await collect(profile: profile, password: password)
    let healthChecks = evaluateHealth(inventory)
    let metrics = InventorySnapshotMetrics.compute(
        vms: inventory.vms, hosts: inventory.hosts, clusters: inventory.clusters,
        datastores: inventory.datastores, snapshots: inventory.snapshots, tools: inventory.tools,
        healthChecks: healthChecks
    )
    let fullDetail = opts.has("full-detail")
    // The CLI always snapshots data it just collected in this same run —
    // never stale, unlike the GUI's refresh-can-fail-and-keep-old-data path
    // (see InventorySnapshot.dataCollectedAt) — so both timestamps are "now".
    let snapshot = InventorySnapshot(
        vCenterHost: profile.host, dataCollectedAt: Date(), label: opts["label"], metrics: metrics,
        fullVMList: fullDetail ? inventory.vms : nil
    )
    let snapshotPrefs = SnapshotPreferencesStore(defaults: sharedDefaults())
    let store = SnapshotStore(fileURL: SnapshotStore.url(inDirectory: snapshotPrefs.customStorageDirectory))
    do {
        try store.add(snapshot)
    } catch {
        fail("Couldn't save snapshot: \(error)")
    }
    print("Snapshot saved for \(profile.host)\(fullDetail ? " (full VM inventory included)" : "").")
    recordAutomationSuccessIfNeeded()

case "export":
    guard let tabKey = opts["tab"], let tab = ExportTab(rawValue: tabKey) else {
        fail("--tab <key> is required and must be one of: \(ExportTab.allCases.map(\.rawValue).joined(separator: ", "))")
    }
    guard let formatKey = opts["format"], let format = ExportFormat(rawValue: formatKey) else {
        fail("--format must be csv or xlsx")
    }
    guard let outputPath = opts["output"] else { fail("--output <path> is required") }

    let profile = resolveProfileFromOptions(opts)
    let password = resolvePassword(for: profile)
    let inventory = await collect(profile: profile, password: password)
    let healthChecks = evaluateHealth(inventory)
    do {
        let data = try exportData(tab: tab, format: format, inventory: inventory, healthChecks: healthChecks)
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    } catch {
        fail("Export failed: \(error)")
    }
    print("Exported \(tab.rawValue) as \(format.rawValue) to \(outputPath)")
    recordAutomationSuccessIfNeeded()

case "help", "-h", "--help":
    printUsage()

default:
    fail("Unknown command \"\(command)\". Run \"vlens-cli help\" for usage.")
}
