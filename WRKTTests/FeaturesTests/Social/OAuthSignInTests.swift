import XCTest
import CryptoKit
@testable import WRKT

final class OAuthSignInTests: WRKTTestCase {

    // MARK: - Nonce tests

    func testNonceIsCorrectLength() {
        let (raw, _) = CryptoNonce.generate()
        XCTAssertEqual(raw.count, 32)
    }

    func testNonceContainsOnlyURLSafeCharacters() {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        for _ in 0..<20 {
            let (raw, _) = CryptoNonce.generate()
            XCTAssertTrue(raw.unicodeScalars.allSatisfy { allowed.contains($0) },
                          "Nonce contains non-URL-safe character: \(raw)")
        }
    }

    func testHashedNonceIsConsistent() {
        let (raw, hashed) = CryptoNonce.generate()
        let expectedHash = SHA256.hash(data: Data(raw.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
        XCTAssertEqual(hashed, expectedHash)
    }

    func testTwoNoncesAreUnique() {
        let (raw1, _) = CryptoNonce.generate()
        let (raw2, _) = CryptoNonce.generate()
        XCTAssertNotEqual(raw1, raw2)
    }

    // MARK: - New-user detection tests

    func testProfileWithEmptyUsernameNeedsSetup() {
        XCTAssertTrue(OAuthProfileState.needsSetup(username: ""))
    }

    func testProfileWithShortUsernameNeedsSetup() {
        XCTAssertTrue(OAuthProfileState.needsSetup(username: "ab"))
    }

    func testProfileWithValidUsernameDoesNotNeedSetup() {
        XCTAssertFalse(OAuthProfileState.needsSetup(username: "john_doe"))
    }

    func testProfileWithUUIDLikeUsernameNeedsSetup() {
        XCTAssertTrue(OAuthProfileState.needsSetup(username: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"))
    }
}
