import Foundation
import Security

/// Token / secret storage backed by the iOS Keychain. The SDK persists
/// short-lived JWTs, the device-binding token, and the per-org client
/// secret here — never in UserDefaults or files.
///
/// Items are tagged with `kSecAttrService = bundleId.addressiq` so partner
/// apps don't collide with us.
public final class AddressIQKeychain {
    public static let shared = AddressIQKeychain()

    private let service: String

    public init(serviceSuffix: String = ".addressiq") {
        let bundle = Bundle.main.bundleIdentifier ?? "com.addressiq.sdk"
        self.service = bundle + serviceSuffix
    }

    @discardableResult
    public func set(_ value: String, for key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return setData(data, for: key)
    }

    public func get(_ key: String) -> String? {
        guard let data = getData(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func setData(_ data: Data, for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    public func getData(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    public func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Removes EVERY Keychain item the SDK has written for this app. Called
    /// from `AddressIQ.shared.logout()` and `reset()`.
    public func wipeAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
