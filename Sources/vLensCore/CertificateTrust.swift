import Foundation

/// Trust-on-first-use for vCenter's TLS certificate, mirroring Docky's SSH
/// `HostKeyTrust.swift` pattern (same shape: fingerprint + trust store +
/// TOFU evaluation + hard-block on mismatch) adapted from SSH host keys to
/// TLS certs. On-prem vCenter overwhelmingly uses self-signed or
/// internal-CA certificates, so — like Docky does for SSH — vLens always
/// pins on first contact rather than trying to distinguish "real CA" from
/// "self-signed": every connection's cert is fingerprinted and pinned, no
/// exceptions. This is a deliberate simplification, not an oversight.
public struct CertificateFingerprint: Codable, Equatable, Hashable, Sendable {
    public var sha256Hex: String

    public init(sha256Hex: String) {
        self.sha256Hex = sha256Hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Colon-separated uppercase hex, matching the format vSphere admins
    /// already recognize from ESXi host SSL thumbprints (`AA:BB:CC:...`).
    public var displayValue: String {
        stride(from: 0, to: sha256Hex.count, by: 2).map { start in
            let s = sha256Hex.index(sha256Hex.startIndex, offsetBy: start)
            let e = sha256Hex.index(s, offsetBy: 2, limitedBy: sha256Hex.endIndex) ?? sha256Hex.endIndex
            return sha256Hex[s..<e].uppercased()
        }.joined(separator: ":")
    }
}

public struct TrustedCertificate: Codable, Equatable, Identifiable, Sendable {
    public var id: String { host.lowercased() }
    public var host: String
    public var fingerprint: CertificateFingerprint
    public var subject: String
    public var issuer: String
    public var trustedAt: Date

    public init(host: String, fingerprint: CertificateFingerprint, subject: String, issuer: String, trustedAt: Date = Date()) {
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.fingerprint = fingerprint
        self.subject = subject
        self.issuer = issuer
        self.trustedAt = trustedAt
    }
}

public enum CertificateTrustDecision: Equatable, Sendable {
    case trusted
    case unknown
    case mismatch(expected: CertificateFingerprint)
}

public enum TOFUResult: Equatable, Sendable {
    case firstContactTrusted(TrustedCertificate)
    case alreadyKnown(TrustedCertificate)
}

/// Thrown when a previously-pinned certificate disagrees with what the
/// server just presented. This is the actual MITM defense: once pinned,
/// mismatch is always a hard block, never a "connect anyway" toggle.
public struct CertificateMismatchError: LocalizedError, Equatable, Sendable {
    public let host: String
    public let expected: CertificateFingerprint
    public let presented: CertificateFingerprint

    public init(host: String, expected: CertificateFingerprint, presented: CertificateFingerprint) {
        self.host = host
        self.expected = expected
        self.presented = presented
    }

    public var errorDescription: String? {
        "Certificate for \(host) changed since it was last trusted. Expected \(expected.displayValue), got \(presented.displayValue). This could mean the certificate was legitimately renewed, or that traffic is being intercepted — verify with your vSphere admin before trusting the new certificate."
    }
}

public protocol CertificateTrustStoreProtocol: Sendable {
    func trustedCertificate(for host: String) throws -> TrustedCertificate?
    func decision(for host: String, fingerprint: CertificateFingerprint) -> CertificateTrustDecision
    func trust(host: String, fingerprint: CertificateFingerprint, subject: String, issuer: String) throws
    func removeTrust(for host: String) throws
}

/// JSON at Application Support/vLens/trusted-certificates.json — mirrors
/// Docky's `LocalJSONHostKeyTrustStore` on disk shape and locking approach.
public final class LocalJSONCertificateTrustStore: CertificateTrustStoreProtocol, @unchecked Sendable {
    private let storageURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(storageURL: URL? = nil, fileManager: FileManager = .default) {
        self.storageURL = storageURL ?? Self.defaultStorageURL(fileManager: fileManager)
        self.fileManager = fileManager
    }

    public func trustedCertificate(for host: String) throws -> TrustedCertificate? {
        try loadAll().first { $0.id == Self.normalize(host) }
    }

    public func decision(for host: String, fingerprint: CertificateFingerprint) -> CertificateTrustDecision {
        guard let trusted = try? trustedCertificate(for: host) else { return .unknown }
        guard trusted.fingerprint == fingerprint else { return .mismatch(expected: trusted.fingerprint) }
        return .trusted
    }

    public func trust(host: String, fingerprint: CertificateFingerprint, subject: String, issuer: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var all = try loadAll()
        let normalized = Self.normalize(host)
        let record = TrustedCertificate(host: normalized, fingerprint: fingerprint, subject: subject, issuer: issuer)
        if let index = all.firstIndex(where: { $0.id == normalized }) {
            all[index] = record
        } else {
            all.append(record)
        }
        try save(all)
    }

    public func removeTrust(for host: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var all = try loadAll()
        all.removeAll { $0.id == Self.normalize(host) }
        try save(all)
    }

    private func loadAll() throws -> [TrustedCertificate] {
        guard fileManager.fileExists(atPath: storageURL.path) else { return [] }
        let data = try Data(contentsOf: storageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TrustedCertificate].self, from: data)
    }

    private func save(_ certs: [TrustedCertificate]) throws {
        let dir = storageURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(certs)
        try data.write(to: storageURL, options: .atomic)
    }

    private static func normalize(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("vLens", isDirectory: true).appendingPathComponent("trusted-certificates.json")
    }
}
