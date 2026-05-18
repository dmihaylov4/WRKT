import Foundation
import CryptoKit
import Security

enum CryptoNonce {
    /// Returns (rawNonce, sha256HashedNonce).
    /// Pass rawNonce to Supabase signInWithIdToken.
    /// Pass sha256HashedNonce to ASAuthorizationAppleIDRequest.nonce.
    static func generate() -> (raw: String, hashed: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let raw = String(
            Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
                .prefix(32)
        )
        let hashed = SHA256.hash(data: Data(raw.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
        return (raw, hashed)
    }
}

enum OAuthProfileState {
    /// Returns true if the username indicates the profile was never properly set up.
    /// Catches: empty string, too short (< 3 chars), UUID-formatted strings.
    static func needsSetup(username: String) -> Bool {
        if username.count < 3 { return true }
        let uuidPattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", uuidPattern)
        return predicate.evaluate(with: username.lowercased())
    }
}
