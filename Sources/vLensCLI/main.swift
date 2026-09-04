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

func fail(_ message: String) -> Never {
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
        hosts: inventory.hosts, cpus: inventory.cpus, cds: inventory.cds, partitions: inventory.partitions,
        multipaths: inventory.multipaths, vms: inventory.vms, thresholds: thresholds
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
    guard let profileName = opts["profile"] else { fail("--profile <name> is required") }
    let profile = resolveProfile(named: profileName)
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

case "export":
    guard let profileName = opts["profile"] else { fail("--profile <name> is required") }
    guard let tabKey = opts["tab"], let tab = ExportTab(rawValue: tabKey) else {
        fail("--tab <key> is required and must be one of: \(ExportTab.allCases.map(\.rawValue).joined(separator: ", "))")
    }
    guard let formatKey = opts["format"], let format = ExportFormat(rawValue: formatKey) else {
        fail("--format must be csv or xlsx")
    }
    guard let outputPath = opts["output"] else { fail("--output <path> is required") }

    let profile = resolveProfile(named: profileName)
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

case "help", "-h", "--help":
    printUsage()

default:
    fail("Unknown command \"\(command)\". Run \"vlens-cli help\" for usage.")
}
