import AuthenticationServices
import Foundation

struct AppleSignInResult {
    let idToken: String
    let nonce: String
    let fullName: PersonNameComponents?
    let email: String?
}

@MainActor
final class SignInWithAppleService: NSObject {

    private var continuation: CheckedContinuation<AppleSignInResult, Error>?
    private var pendingNonce: String?
    private var presentationAnchor: ASPresentationAnchor?

    func requestSignIn(presenting window: ASPresentationAnchor) async throws -> AppleSignInResult {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let (raw, hashed) = CryptoNonce.generate()
            self.pendingNonce = raw

            // Store anchor before performRequests(); the context provider can be
            // called synchronously during that call.
            self.presentationAnchor = window

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashed

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

extension SignInWithAppleService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard
                let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let idTokenData = appleCredential.identityToken,
                let idToken = String(data: idTokenData, encoding: .utf8),
                let nonce = pendingNonce
            else {
                continuation?.resume(throwing: SupabaseError.custom(message: "Invalid Apple credential"))
                continuation = nil
                pendingNonce = nil
                return
            }

            let result = AppleSignInResult(
                idToken: idToken,
                nonce: nonce,
                fullName: appleCredential.fullName,
                email: appleCredential.email
            )
            continuation?.resume(returning: result)
            continuation = nil
            pendingNonce = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
            pendingNonce = nil
        }
    }
}

extension SignInWithAppleService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            guard let anchor = presentationAnchor else {
                preconditionFailure("presentationAnchor was nil when presentation context was requested")
            }
            return anchor
        }
    }
}
