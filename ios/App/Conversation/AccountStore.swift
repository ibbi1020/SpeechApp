import Foundation
import Security

/// Prototype account flags. UUID prefers Keychain; UserDefaults if Keychain write fails.
final class AccountStore {
    private enum Keys {
        static let possibleMinorFlag = "account.possibleMinorFlag"
        static let uuidFallback = "account.uuid"
    }

    private static let keychainService = "com.speechapp.prototype.format1"
    private static let keychainAccount = "accountUUID"

    private let defaults: UserDefaults

    var accountUUID: UUID
    var possibleMinorFlag: Bool {
        didSet { defaults.set(possibleMinorFlag, forKey: Keys.possibleMinorFlag) }
    }

    /// False when UUID was stored in UserDefaults because Keychain add failed.
    private(set) var uuidInKeychain: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        possibleMinorFlag = defaults.bool(forKey: Keys.possibleMinorFlag)
        let resolved = Self.loadOrCreateUUID(defaults: defaults)
        accountUUID = resolved.uuid
        uuidInKeychain = resolved.inKeychain
    }

    private static func loadOrCreateUUID(defaults: UserDefaults) -> (uuid: UUID, inKeychain: Bool) {
        if let stored = readKeychain(), let uuid = UUID(uuidString: stored) {
            return (uuid, true)
        }
        if let stored = defaults.string(forKey: Keys.uuidFallback), let uuid = UUID(uuidString: stored) {
            if writeKeychain(uuid.uuidString) {
                defaults.removeObject(forKey: Keys.uuidFallback)
                return (uuid, true)
            }
            return (uuid, false)
        }
        let uuid = UUID()
        if writeKeychain(uuid.uuidString) {
            return (uuid, true)
        }
        defaults.set(uuid.uuidString, forKey: Keys.uuidFallback)
        return (uuid, false)
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
