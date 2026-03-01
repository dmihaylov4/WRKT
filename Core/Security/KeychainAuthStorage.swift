//
//  KeychainAuthStorage.swift
//  WRKT
//
//  Keychain-backed AuthLocalStorage for the Supabase Auth SDK.
//  Replaces UserDefaultsStorage so that session JWTs are stored in the
//  hardware-encrypted Keychain instead of a plain-text plist.
//
//  Migration: on the first retrieve() call after upgrading, any token found
//  in UserDefaults is silently moved to the Keychain. The user stays logged in.
//

import Foundation
import Security
import Auth

// MARK: - Keychain Auth Storage

/// Implements `AuthLocalStorage` using the Keychain.
///
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` means:
/// - Tokens are only readable when the device is unlocked.
/// - Tokens are NOT included in iCloud or iTunes backups.
/// - Tokens are NOT transferred to a new device via backup/restore.
final class KeychainAuthStorage: @unchecked Sendable, AuthLocalStorage {

    func store(key: String, value: Data) throws {
        try Keychain.store(value, forKey: key)
    }

    /// Returns the stored token for `key`.
    ///
    /// Migration path: if the Keychain has no entry but UserDefaults does
    /// (i.e. the user has upgraded from an older build), the data is copied
    /// to the Keychain and removed from UserDefaults automatically.
    func retrieve(key: String) throws -> Data? {
        if let data = try Keychain.retrieve(forKey: key) {
            return data
        }

        // Legacy migration: move UserDefaults token to Keychain
        if let legacy = UserDefaults.standard.data(forKey: key) {
            try Keychain.store(legacy, forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
            return legacy
        }

        return nil
    }

    func remove(key: String) throws {
        try Keychain.delete(forKey: key)
        // Belt-and-suspenders: also clear UserDefaults in case the token
        // was never migrated (e.g. sign-out before first retrieve)
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Keychain

private enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "com.dmihaylov.trak"

    static func store(_ data: Data, forKey key: String) throws {
        // Delete any existing item first — Keychain add fails if the item exists
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            // Only readable when device is unlocked; excluded from backups
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func retrieve(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.retrieveFailed(status)
        }
        return result as? Data
    }

    static func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - Errors

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let s):    return "Keychain save failed (OSStatus \(s))"
        case .retrieveFailed(let s): return "Keychain read failed (OSStatus \(s))"
        case .deleteFailed(let s):  return "Keychain delete failed (OSStatus \(s))"
        }
    }
}
