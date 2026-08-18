import Cocoa

/// the API key lives in the keychain rather than in the preferences: GeneralTab's settings export writes the whole
/// preferences domain to a file the user picks, which would carry the key in plaintext
class LLMKeychain {
    private static let service = App.bundleIdentifier + ".llm"
    private static let account = "api-key"

    /// reading the secret is what makes the keychain ask for authorization, so the result is kept for the lifetime
    /// of the process: at most one prompt per launch, even if the answer to it was "Allow" rather than "Always Allow"
    private static var cachedKey: String?

    /// only called when a question is actually being sent, which is a moment the prompt can be explained by
    static func apiKey() -> String? {
        if let cachedKey { return cachedKey }
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            // errSecAuthFailed / errSecUserCanceled land here: the key is stored, we were just not allowed to read it
            if status != errSecItemNotFound {
                Logger.error { "couldn't read the API key: \(status)" }
            }
            return nil
        }
        cachedKey = key
        return key
    }

    /// tells whether a key is stored without decrypting it, which no prompt is needed for
    static func hasApiKey() -> Bool {
        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    @discardableResult
    static func setApiKey(_ key: String) -> Bool {
        cachedKey = key.isEmpty ? nil : key
        guard !key.isEmpty else {
            SecItemDelete(baseQuery() as CFDictionary)
            return true
        }
        let value = [kSecValueData as String: Data(key.utf8)] as CFDictionary
        // updating in place rather than delete-and-add: this runs per keystroke, and there is never a moment
        // where a previously working key is gone
        if SecItemUpdate(baseQuery() as CFDictionary, value) == errSecSuccess { return true }
        var attributes = baseQuery()
        attributes[kSecValueData as String] = Data(key.utf8)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status != errSecSuccess else { return true }
        Logger.error { "couldn't store the API key: \(status)" }
        return false
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
