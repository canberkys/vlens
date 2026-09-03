import Foundation
import Security

// Shape mirrors Docky's Core/Keychain/CredentialStoreProtocol.swift —
// proven pattern, reused deliberately rather than re-derived.

public protocol CredentialStoreProtocol: Sendable {
    func saveSecret(_ secret: String, for referenceID: String) throws
    func readSecret(for referenceID: String) throws -> String?
    func deleteSecret(for referenceID: String) throws
}

public enum KeychainError: Error, Sendable, Equatable {
    case unexpectedDataFormat
    case encodingFailed
    case unhandled(status: OSStatus, operation: String)

    public var localizedDescription: String {
        switch self {
        case .unexpectedDataFormat:
            return "Keychain returned data in an unexpected format."
        case .encodingFailed:
            return "Failed to encode secret as UTF-8 data."
        case .unhandled(let status, let operation):
            return "Keychain \(operation) failed with OSStatus \(status)."
        }
    }
}

public struct KeychainCredentialStore: CredentialStoreProtocol, Sendable {
    public static let defaultService = "com.vlens.credentials"

    private let service: String

    public init(service: String = KeychainCredentialStore.defaultService) {
        self.service = service
    }

    public func saveSecret(_ secret: String, for referenceID: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: referenceID
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandled(status: addStatus, operation: "add")
            }
        default:
            throw KeychainError.unhandled(status: updateStatus, operation: "update")
        }
    }

    public func readSecret(for referenceID: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: referenceID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.unexpectedDataFormat
            }
            guard let secret = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedDataFormat
            }
            return secret
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status: status, operation: "read")
        }
    }

    public func deleteSecret(for referenceID: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: referenceID
        ]

        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unhandled(status: status, operation: "delete")
        }
    }
}

/// Process-scoped, in-memory credential store — used when the user connects
/// without saving the password. Dies with the process, never touches disk
/// or Keychain. Mirrors Docky's EphemeralCredentialStore.
public final class EphemeralCredentialStore: CredentialStoreProtocol, @unchecked Sendable {
    public static let shared = EphemeralCredentialStore()
    public static let referenceIDPrefix = "ephemeral."

    private let lock = NSLock()
    private var secrets: [String: String] = [:]

    public init() {}

    public static func makeReferenceID(profileID: UUID) -> String {
        "\(referenceIDPrefix)profile.\(profileID.uuidString).password"
    }

    public static func owns(referenceID: String) -> Bool {
        referenceID.hasPrefix(referenceIDPrefix)
    }

    public func saveSecret(_ secret: String, for referenceID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        secrets[referenceID] = secret
    }

    public func readSecret(for referenceID: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return secrets[referenceID]
    }

    public func deleteSecret(for referenceID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        secrets.removeValue(forKey: referenceID)
    }
}
