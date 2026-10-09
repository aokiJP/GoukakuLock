import Foundation
import Security

/// 預け金のサーバーの合い言葉をキーチェーンにしまう。
/// iCloud キーチェーンで同期する(iPhone を替えても、同じ Apple アカウントなら合い言葉が残り、預け金を見失わない)
enum Keychain {
    private static let service = "com.aokijp.goukakulock.deposit"

    private static func base(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read(account: String) -> String? {
        var query = base(account)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        delete(account: account)
        var query = base(account)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrSynchronizable as String] = true
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(query as CFDictionary, nil) == errSecSuccess { return true }
        // iCloud キーチェーンが使えないときは、この iPhone だけに
        query[kSecAttrSynchronizable as String] = false
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete(account: String) {
        var query = base(account)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(query as CFDictionary)
    }
}
