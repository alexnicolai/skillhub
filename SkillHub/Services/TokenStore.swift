import Foundation
import Security

/// GitHub token storage in the login Keychain (a plaintext UserDefaults plist
/// is no place for a credential). Migrates any legacy UserDefaults value once.
enum TokenStore {
    private static let service = "com.alexnicolai.skillhub.github-token"
    private static let legacyDefaultsKey = "githubToken"

    static func get() -> String? {
        migrateIfNeeded()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else { return nil }
        return token
    }

    static func set(_ token: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(base as CFDictionary)
        guard !token.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        SecItemAdd(add as CFDictionary, nil)
    }

    /// One-time move of any token previously kept in UserDefaults.
    private static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: legacyDefaultsKey), !legacy.isEmpty else { return }
        set(legacy)
        defaults.removeObject(forKey: legacyDefaultsKey)
    }
}
