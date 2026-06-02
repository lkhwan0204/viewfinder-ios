import AuthenticationServices
import Combine
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import GoogleSignIn
import Security
import UIKit

struct AuthUser: Codable, Equatable {
    let id: String
    let displayName: String
    let email: String?
    let provider: String

    static let fallback = AuthUser(id: "local-user", displayName: "나", email: nil, provider: "local")

    init(id: String, displayName: String, email: String?, provider: String) {
        self.id = id
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "나" : displayName
        self.email = email
        self.provider = provider
    }

    init(firebaseUser: FirebaseAuth.User, provider: AuthProviderKind? = nil) {
        let providerID = provider?.rawValue ?? firebaseUser.providerData.first?.providerID ?? "firebase"
        self.init(
            id: firebaseUser.uid,
            displayName: firebaseUser.displayName ?? firebaseUser.email ?? "나",
            email: firebaseUser.email,
            provider: providerID
        )
    }
}

enum AuthProviderKind: String {
    case apple = "apple.com"
    case google = "google.com"

    var userDocumentValue: String {
        switch self {
        case .apple:
            return "apple"
        case .google:
            return "google"
        }
    }

    var title: String {
        switch self {
        case .apple:
            return "Apple"
        case .google:
            return "Google"
        }
    }
}

protocol AuthService {
    func restoreCurrentUser() -> AuthUser?
    func addAuthStateListener(_ listener: @escaping (AuthUser?) -> Void) -> AuthStateDidChangeListenerHandle
    func removeAuthStateListener(_ handle: AuthStateDidChangeListenerHandle)
    func signInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String) async throws -> AuthUser
    @MainActor func signInWithGoogle() async throws -> AuthUser
    func signOut() throws
}

enum AuthSignInError: LocalizedError {
    case cancelled(AuthProviderKind)
    case missingCredential(AuthProviderKind)
    case missingClientID
    case missingPresenter
    case appleCapabilityMissing
    case failed(AuthProviderKind, String)

    var errorDescription: String? {
        switch self {
        case .cancelled(let provider):
            return "\(provider.title) 로그인을 취소했어요."
        case .missingCredential(let provider):
            return "\(provider.title) 로그인 정보를 확인하지 못했어요."
        case .missingClientID:
            return "Google 로그인 CLIENT_ID를 찾지 못했어요."
        case .missingPresenter:
            return "로그인 화면을 열 수 없어요."
        case .appleCapabilityMissing:
            return "Personal Team에서는 Apple 로그인을 사용할 수 없어요. 지금은 Google로 로그인해줘."
        case .failed(let provider, let message):
            return "\(provider.title) 로그인에 실패했어요. \(message)"
        }
    }
}

final class FirebaseAuthService: AuthService {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func restoreCurrentUser() -> AuthUser? {
        Auth.auth().currentUser.map { AuthUser(firebaseUser: $0) }
    }

    func addAuthStateListener(_ listener: @escaping (AuthUser?) -> Void) -> AuthStateDidChangeListenerHandle {
        Auth.auth().addStateDidChangeListener { _, user in
            listener(user.map { AuthUser(firebaseUser: $0) })
        }
    }

    func removeAuthStateListener(_ handle: AuthStateDidChangeListenerHandle) {
        Auth.auth().removeStateDidChangeListener(handle)
    }

    func signInWithApple(credential appleCredential: ASAuthorizationAppleIDCredential, rawNonce: String) async throws -> AuthUser {
        guard let identityToken = appleCredential.identityToken,
              let idTokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthSignInError.missingCredential(.apple)
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: rawNonce,
            fullName: appleCredential.fullName
        )

        let result = try await signIn(with: credential)
        let displayName = appleDisplayName(from: appleCredential) ?? result.user.displayName ?? result.user.email ?? "나"
        let email = appleCredential.email ?? result.user.email

        await updateFirebaseProfileIfNeeded(user: result.user, displayName: displayName)
        await upsertUserDocument(
            uid: result.user.uid,
            provider: .apple,
            displayName: displayName,
            email: email
        )

        return AuthUser(id: result.user.uid, displayName: displayName, email: email, provider: AuthProviderKind.apple.rawValue)
    }

    @MainActor
    func signInWithGoogle() async throws -> AuthUser {
        guard let presentingViewController = UIApplication.shared.topMostViewController else {
            throw AuthSignInError.missingPresenter
        }

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthSignInError.missingClientID
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let googleResult = try await googleSignIn(withPresenting: presentingViewController)
        guard let idToken = googleResult.user.idToken?.tokenString else {
            throw AuthSignInError.missingCredential(.google)
        }

        let accessToken = googleResult.user.accessToken.tokenString
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        let authResult = try await signIn(with: credential)
        let displayName = googleResult.user.profile?.name ?? authResult.user.displayName ?? authResult.user.email ?? "나"
        let email = googleResult.user.profile?.email ?? authResult.user.email

        await upsertUserDocument(
            uid: authResult.user.uid,
            provider: .google,
            displayName: displayName,
            email: email
        )

        return AuthUser(id: authResult.user.uid, displayName: displayName, email: email, provider: AuthProviderKind.google.rawValue)
    }

    func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }

    private func signIn(with credential: AuthCredential) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signIn(with: credential) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result else {
                    continuation.resume(throwing: AuthSignInError.missingCredential(.apple))
                    return
                }

                continuation.resume(returning: result)
            }
        }
    }

    @MainActor
    private func googleSignIn(withPresenting presentingViewController: UIViewController) async throws -> GIDSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
                if let error {
                    if Self.isGoogleSignInCancelled(error) {
                        continuation.resume(throwing: AuthSignInError.cancelled(.google))
                    } else {
                        print("Google login failed: \(error.localizedDescription)")
                        continuation.resume(throwing: AuthSignInError.failed(.google, error.localizedDescription))
                    }
                    return
                }

                guard let result else {
                    continuation.resume(throwing: AuthSignInError.missingCredential(.google))
                    return
                }

                continuation.resume(returning: result)
            }
        }
    }

    private func upsertUserDocument(uid: String, provider: AuthProviderKind, displayName: String, email: String?) async {
        let reference = firestore.collection("users").document(uid)

        do {
            let exists = try await documentExists(reference)
            var data: [String: Any] = [
                "uid": uid,
                "provider": provider.userDocumentValue,
                "displayName": displayName,
                "email": email ?? NSNull(),
                "lastLoginAt": FieldValue.serverTimestamp()
            ]

            if !exists {
                data["createdAt"] = FieldValue.serverTimestamp()
            }

            try await setData(data, for: reference)
        } catch {
            print("Firestore user upsert failed: \(error.localizedDescription)")
        }
    }

    private func documentExists(_ reference: DocumentReference) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            reference.getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: snapshot?.exists == true)
            }
        }
    }

    private func setData(_ data: [String: Any], for reference: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.setData(data, merge: true) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func updateFirebaseProfileIfNeeded(user: FirebaseAuth.User, displayName: String) async {
        guard user.displayName?.isEmpty ?? true, !displayName.isEmpty, displayName != "나" else {
            return
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let request = user.createProfileChangeRequest()
                request.displayName = displayName
                request.commitChanges { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        } catch {
            print("Firebase profile update failed: \(error.localizedDescription)")
        }
    }

    private func appleDisplayName(from credential: ASAuthorizationAppleIDCredential) -> String? {
        let formatter = PersonNameComponentsFormatter()
        let name = formatter.string(from: credential.fullName ?? PersonNameComponents())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func isGoogleSignInCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "com.google.GIDSignIn" && nsError.code == -5
    }
}

final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let completion: (Result<(credential: ASAuthorizationAppleIDCredential, rawNonce: String), AuthSignInError>) -> Void
    private var rawNonce: String?

    init(completion: @escaping (Result<(credential: ASAuthorizationAppleIDCredential, rawNonce: String), AuthSignInError>) -> Void) {
        self.completion = completion
    }

    func start() {
        let nonce = Self.randomNonceString()
        rawNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let rawNonce else {
            print("Apple login failed: missing ASAuthorizationAppleIDCredential or raw nonce")
            completion(.failure(.missingCredential(.apple)))
            return
        }

        completion(.success((credential, rawNonce)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        let message = error.localizedDescription

        if nsError.domain == ASAuthorizationError.errorDomain,
           let code = ASAuthorizationError.Code(rawValue: nsError.code),
           code == .canceled {
            print("Apple login cancelled: \(message)")
            completion(.failure(.cancelled(.apple)))
            return
        }

        if nsError.domain == ASAuthorizationError.errorDomain,
           let code = ASAuthorizationError.Code(rawValue: nsError.code),
           code == .unknown {
            print("Apple login failed: \(message). Check Sign in with Apple capability and provisioning profile.")
            completion(.failure(.appleCapabilityMissing))
            return
        }

        print("Apple login failed: \(message)")
        completion(.failure(.failed(.apple, message)))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.keyWindow ?? ASPresentationAnchor()
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
            }

            for random in randoms {
                guard remainingLength > 0 else {
                    break
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var currentUser: AuthUser?
    @Published private(set) var isSigningIn = false
    @Published var errorMessage: String?

    private let service: AuthService
    private var appleSignInCoordinator: AppleSignInCoordinator?
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init(service: AuthService = FirebaseAuthService()) {
        self.service = service
        currentUser = service.restoreCurrentUser()
        authStateHandle = service.addAuthStateListener { [weak self] user in
            Task { @MainActor in
                self?.currentUser = user
            }
        }
    }

    deinit {
        if let authStateHandle {
            service.removeAuthStateListener(authStateHandle)
        }
    }

    var isAuthenticated: Bool {
        currentUser != nil
    }

    func startAppleSignIn() {
        errorMessage = nil

        let coordinator = AppleSignInCoordinator { [weak self] result in
            Task { @MainActor in
                guard let self else { return }

                self.isSigningIn = true
                defer {
                    self.isSigningIn = false
                    self.appleSignInCoordinator = nil
                }

                switch result {
                case .success(let payload):
                    do {
                        self.currentUser = try await self.service.signInWithApple(
                            credential: payload.credential,
                            rawNonce: payload.rawNonce
                        )
                        self.errorMessage = nil
                    } catch {
                        self.handle(error, provider: .apple)
                    }
                case .failure(let error):
                    self.handle(error, provider: .apple)
                }
            }
        }

        appleSignInCoordinator = coordinator
        coordinator.start()
    }

    func startGoogleSignIn() {
        errorMessage = nil
        isSigningIn = true

        Task { @MainActor in
            defer { self.isSigningIn = false }

            do {
                self.currentUser = try await service.signInWithGoogle()
                self.errorMessage = nil
            } catch {
                self.handle(error, provider: .google)
            }
        }
    }

    func signOut() {
        do {
            try service.signOut()
            currentUser = nil
            errorMessage = nil
        } catch {
            print("Sign out failed: \(error.localizedDescription)")
            errorMessage = "로그아웃에 실패했어요. \(error.localizedDescription)"
        }
    }

    private func handle(_ error: Error, provider: AuthProviderKind) {
        if let authError = error as? AuthSignInError {
            errorMessage = authError.localizedDescription
            return
        }

        let nsError = error as NSError
        if provider == .apple,
           nsError.domain == ASAuthorizationError.errorDomain,
           let code = ASAuthorizationError.Code(rawValue: nsError.code),
           code == .canceled {
            print("Apple login cancelled: \(error.localizedDescription)")
            errorMessage = AuthSignInError.cancelled(.apple).localizedDescription
            return
        }

        if provider == .apple,
           nsError.domain == ASAuthorizationError.errorDomain,
           let code = ASAuthorizationError.Code(rawValue: nsError.code),
           code == .unknown {
            print("Apple login failed: \(error.localizedDescription). Check Sign in with Apple capability and provisioning profile.")
            errorMessage = AuthSignInError.appleCapabilityMissing.localizedDescription
            return
        }

        print("\(provider.title) login failed: \(error.localizedDescription)")
        errorMessage = AuthSignInError.failed(provider, error.localizedDescription).localizedDescription
    }
}

private extension UIApplication {
    var keyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }
    }

    var topMostViewController: UIViewController? {
        var topController = keyWindow?.rootViewController

        while let presentedController = topController?.presentedViewController {
            topController = presentedController
        }

        if let navigationController = topController as? UINavigationController {
            return navigationController.visibleViewController
        }

        if let tabBarController = topController as? UITabBarController {
            return tabBarController.selectedViewController
        }

        return topController
    }
}
