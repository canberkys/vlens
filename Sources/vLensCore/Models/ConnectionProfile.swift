import Foundation

/// A saved connection target (vCenter or standalone ESXi host). The password
/// is never held here — it's resolved from a CredentialStore by `id` at
/// connect time. Certificate trust isn't here either: it's tracked per
/// hostname in `CertificateTrustStoreProtocol`/`LocalJSONCertificateTrustStore`
/// (see CertificateTrust.swift), independent of whether the user chose to
/// save this profile — trust-on-first-use protects ephemeral connections
/// too, not just saved ones.
public struct ConnectionProfile: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var host: String
    public var username: String

    public init(id: UUID = UUID(), name: String, host: String, username: String) {
        self.id = id
        self.name = name
        self.host = host
        self.username = username
    }

    /// `CredentialStoreProtocol.saveSecret`/`readSecret` reference ID for
    /// this profile's saved password. Shared between the GUI app
    /// (`ConnectionViewModel`) and `vlens-cli` so both resolve the exact
    /// same Keychain entry — kept here, not duplicated, so the format can't
    /// drift between the two call sites.
    public static func keychainReferenceID(for profileID: UUID) -> String {
        "profile.\(profileID.uuidString).password"
    }
}
