import Foundation

/// Spawns the embedded `vlens-helper` (govmomi) binary once per call, feeds
/// it a JSON request on stdin, reads a JSON response off stdout. No
/// long-lived daemon for the MVP — one process per collection run keeps
/// the failure mode simple (a crash or hang can't leak into the next call)
/// at the cost of re-authenticating with vCenter each time. Revisit only if
/// per-call login latency actually shows up as a problem once real tab
/// counts (10+) are hitting this per refresh.
public struct VSphereHelperClient: Sendable {
    private let helperURL: URL

    /// - Parameter helperURL: path to the `vlens-helper` binary. In the
    ///   packaged app this resolves to a Resources binary next to the app;
    ///   during development it points at the Go module's build output.
    public init(helperURL: URL) {
        self.helperURL = helperURL
    }

    public func collectAll(url: String, username: String, password: String, insecure: Bool) async throws -> CollectedInventory {
        let request = HelperRequest(action: .collectAll, url: url, username: username, password: password, insecure: insecure)
        let response = try await run(request)
        guard response.ok else {
            throw HelperClientError.helperReportedError(response.error ?? "unknown helper error")
        }
        return CollectedInventory(
            vms: response.vms ?? [],
            cpus: response.cpus ?? [],
            memory: response.memory ?? [],
            disks: response.disks ?? [],
            snapshots: response.snapshots ?? [],
            tools: response.tools ?? [],
            hosts: response.hosts ?? [],
            datastores: response.datastores ?? [],
            clusters: response.clusters ?? [],
            licenses: response.licenses ?? [],
            vSwitches: response.vSwitches ?? [],
            ports: response.ports ?? [],
            dvSwitches: response.dvSwitches ?? [],
            dvPorts: response.dvPorts ?? [],
            resourcePools: response.resourcePools ?? [],
            hbas: response.hbas ?? [],
            nics: response.nics ?? [],
            vmKernels: response.vmKernels ?? [],
            multipaths: response.multipaths ?? [],
            cds: response.cds ?? [],
            usbs: response.usbs ?? [],
            partitions: response.partitions ?? [],
            networks: response.networks ?? [],
            vCenter: response.vCenter
        )
    }

    /// Standalone action, deliberately not part of `collectAll` — see the
    /// doc comment on `collectPerformanceAction` in `helper/main.go` for why
    /// (QueryPerf is a per-entity call, not a single PropertyCollector pass).
    /// Its own login/logout, so it can be re-run from the vPerformance tab's
    /// own refresh control with a different time window without re-collecting
    /// everything else.
    public func collectPerformance(
        url: String, username: String, password: String, insecure: Bool, intervalMinutes: Int
    ) async throws -> [VMPerformanceInfo] {
        let request = HelperRequest(
            action: .collectPerformance, url: url, username: username, password: password,
            insecure: insecure, perfIntervalMinutes: intervalMinutes
        )
        let response = try await run(request)
        guard response.ok else {
            throw HelperClientError.helperReportedError(response.error ?? "unknown helper error")
        }
        return response.performance ?? []
    }

    /// Raw TLS certificate fetch — no login. Always passes `insecure: true`
    /// downstream regardless of the caller's value: the whole point of this
    /// call is to see whatever certificate is presented so it can be
    /// fingerprinted and pinned, not to have the OS silently reject it.
    public func fetchCertificate(url: String) async throws -> HelperCertificateInfo {
        let request = HelperRequest(action: .getCertificate, url: url, username: "", password: "", insecure: true)
        let response = try await run(request)
        guard response.ok else {
            throw HelperClientError.helperReportedError(response.error ?? "unknown helper error")
        }
        guard let certificate = response.certificate else {
            throw HelperClientError.decodingFailed("getCertificate response had no certificate field")
        }
        return certificate
    }

    private func run(_ request: HelperRequest) async throws -> HelperResponse {
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw HelperClientError.helperBinaryNotFound
        }

        let requestData = try JSONEncoder().encode(request)

        let process = Process()
        process.executableURL = helperURL

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        stdin.fileHandleForWriting.write(requestData)
        try stdin.fileHandleForWriting.close()

        let stdoutData = await Self.readAll(stdout.fileHandleForReading)
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = await Self.readAll(stderr.fileHandleForReading)
            let message = String(data: stderrData, encoding: .utf8) ?? ""
            throw HelperClientError.processFailed(exitCode: process.terminationStatus, stderr: message)
        }

        guard !stdoutData.isEmpty else {
            throw HelperClientError.emptyResponse
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601 // matches helper/main.go's time.RFC3339 encoding
            return try decoder.decode(HelperResponse.self, from: stdoutData)
        } catch {
            throw HelperClientError.decodingFailed(String(describing: error))
        }
    }

    private static func readAll(_ handle: FileHandle) async -> Data {
        await Task.detached {
            handle.readDataToEndOfFile()
        }.value
    }
}
