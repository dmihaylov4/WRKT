import Foundation
import GoogleSignIn
import UIKit

struct GoogleSignInResult {
    let idToken: String
    let accessToken: String
}

@MainActor
final class SignInWithGoogleService {

    static let shared = SignInWithGoogleService()

    private init() {}

    func configure() {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String,
              !clientID.isEmpty else {
            preconditionFailure("GOOGLE_CLIENT_ID is missing from Info.plist. Add GOOGLE_CLIENT_ID to the WRKT target build settings.")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    func requestSignIn(presenting viewController: UIViewController) async throws -> GoogleSignInResult {
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
        guard let idToken = result.user.idToken?.tokenString else {
            throw SupabaseError.custom(message: "Google Sign-In did not return an ID token")
        }
        return GoogleSignInResult(
            idToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
    }

    func handleURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}
