import Foundation
import Testing
@testable import vLensCore

private func makeStore() -> LocalJSONCertificateTrustStore {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vLensTests-\(UUID().uuidString)", isDirectory: true)
    return LocalJSONCertificateTrustStore(storageURL: dir.appendingPathComponent("trusted-certificates.json"))
}

@Test func fingerprintDisplayValueIsColonSeparatedUppercaseHex() {
    let fp = CertificateFingerprint(sha256Hex: "aabbccdd")
    #expect(fp.displayValue == "AA:BB:CC:DD")
}

@Test func decisionIsUnknownForUnrecordedHost() {
    let store = makeStore()
    let decision = store.decision(for: "vcenter.local", fingerprint: CertificateFingerprint(sha256Hex: "ab"))
    #expect(decision == .unknown)
}

@Test func decisionIsTrustedAfterTrusting() throws {
    let store = makeStore()
    let fp = CertificateFingerprint(sha256Hex: "aabb")
    try store.trust(host: "vcenter.local", fingerprint: fp, subject: "CN=vcenter.local", issuer: "CN=Self-Signed")

    #expect(store.decision(for: "vcenter.local", fingerprint: fp) == .trusted)
    #expect(store.decision(for: "VCENTER.LOCAL", fingerprint: fp) == .trusted) // host lookup is case-insensitive
}

@Test func decisionIsMismatchWhenFingerprintChanges() throws {
    let store = makeStore()
    let original = CertificateFingerprint(sha256Hex: "aabb")
    let changed = CertificateFingerprint(sha256Hex: "ccdd")
    try store.trust(host: "vcenter.local", fingerprint: original, subject: "s", issuer: "i")

    let decision = store.decision(for: "vcenter.local", fingerprint: changed)
    #expect(decision == .mismatch(expected: original))
}

@Test func removeTrustClearsTheRecord() throws {
    let store = makeStore()
    let fp = CertificateFingerprint(sha256Hex: "aabb")
    try store.trust(host: "vcenter.local", fingerprint: fp, subject: "s", issuer: "i")
    #expect(store.decision(for: "vcenter.local", fingerprint: fp) == .trusted)

    try store.removeTrust(for: "vcenter.local")
    #expect(store.decision(for: "vcenter.local", fingerprint: fp) == .unknown)
}

@Test func trustingSameHostTwiceReplacesRatherThanDuplicates() throws {
    let store = makeStore()
    try store.trust(host: "vcenter.local", fingerprint: CertificateFingerprint(sha256Hex: "aabb"), subject: "s1", issuer: "i1")
    try store.trust(host: "vcenter.local", fingerprint: CertificateFingerprint(sha256Hex: "ccdd"), subject: "s2", issuer: "i2")

    let stored = try store.trustedCertificate(for: "vcenter.local")
    #expect(stored?.subject == "s2")
    #expect(stored?.fingerprint.sha256Hex == "ccdd")
}
