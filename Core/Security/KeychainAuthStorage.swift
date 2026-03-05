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
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` means:
/// - Tokens are readable after the device has been unlocked at least once since boot.
/// - Tokens remain readable when the screen is locked (required for background network calls).
/// - Tokens are NOT included in iCloud or iTunes backups.
/// - Tokens are NOT transferred to a new device via backup/restore.
final class KeychainAuthStorage: @unchecked Sendable, AuthLocalStorage {

    func store(key: String, value: Data) throws {
        try Keychain.store(value, forKey: key)
    }

    /// Returns the stored token for `key`.
    ///
    /// Migration path 1 (accessibility): upgrades any WhenUnlocked Keychain items to
    /// AfterFirstUnlock so the auth token is readable while the screen is locked (needed
    /// for background virtual run snapshot publishing). Runs once while device is unlocked.
    ///
    /// Migration path 2 (legacy): if the Keychain has no entry but UserDefaults does
    /// (i.e. the user has upgraded from an older build), the data is copied
    /// to the Keychain and removed from UserDefaults automatically.
    func retrieve(key: String) throws -> Data? {
        // One-time accessibility migration: must succeed while device is unlocked.
        let migrationKey = "KeychainAfterFirstUnlockMigrated_v1"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            if Keychain.migrateToAfterFirstUnlock() {
                UserDefaults.standard.set(true, forKey: migrationKey)
            }
            // If migration returned false, device is locked — will retry on next retrieve()
        }

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
            // AfterFirstUnlock: readable in background (e.g. while screen is locked during
            // active virtual run). Still excluded from iCloud/iTunes backups.
            // Previously WhenUnlockedThisDeviceOnly — that blocked Keychain access when the
            // screen was locked, causing the Supabase auth token to be unreadable and every
            // REST call to fail with an RLS policy violation.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Migrate any existing WhenUnlocked items to AfterFirstUnlock so they remain readable
    /// when the screen is locked (needed for background network calls). Returns true on success
    /// or if there was nothing to migrate; false if the device is currently locked.
    @discardableResult
    static func migrateToAfterFirstUnlock() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updates: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
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
