import Foundation
import Security

protocol APICredentialStore {
    func read() throws -> String?
    func save(_ value: String) throws
    func remove() throws
}

struct KeychainAPICredentialStore: APICredentialStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.sergegalmak.tradeview.twelvedata",
         kSecAttrAccount as String: "personal-api-key"]
    }

    func read() throws -> String? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let code = SecItemCopyMatching(attributes as CFDictionary, &result)
        if code == errSecItemNotFound { return nil }
        guard code == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw CredentialError.access(code) }
        return value
    }

    func save(_ value: String) throws {
        let data = Data(value.utf8)
        let code = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if code == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let insertCode = SecItemAdd(attributes as CFDictionary, nil)
            guard insertCode == errSecSuccess else { throw CredentialError.access(insertCode) }
        } else if code != errSecSuccess { throw CredentialError.access(code) }
    }

    func remove() throws {
        let code = SecItemDelete(query as CFDictionary)
        guard code == errSecSuccess || code == errSecItemNotFound else { throw CredentialError.access(code) }
    }
}

enum CredentialError: LocalizedError {
    case access(OSStatus)
    var errorDescription: String? {
        switch self {
        case .access(let code): return "Не удалось получить доступ к Связке ключей macOS (\(code))."
        }
    }
}

protocol AppPreferenceStore {
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
}

struct UserDefaultsPreferenceStore: AppPreferenceStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func set(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}
