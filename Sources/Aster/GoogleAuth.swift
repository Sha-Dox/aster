import Foundation
import AppKit
import AppAuth
import AsterCore

@MainActor protocol AccountSession: TokenProvider {
    var identity: String? { get }
    var username: String? { get }
    func signIn() async throws
    func signOut() throws
}

/// Google's installed-app OAuth flow with PKCE, state validation and a loopback listener supplied by AppAuth.
@MainActor final class GoogleAuth: AccountSession, @unchecked Sendable {
    private let clientID: String
    private let accountKey: String
    private var emailKey: String { "googleEmail:" + clientID + accountKey }
    private var credentialKey: String { "google-oauth:" + clientID + accountKey }
    private var authState: OIDAuthState?
    private var redirectHandler: OIDRedirectHTTPHandler?
    private var timeout: Task<Void, Never>?
    var username: String? { UserDefaults.standard.string(forKey: emailKey) }
    var identity: String? { authState?.isAuthorized == true ? username.map { "google:" + $0.lowercased() } : nil }
    init(clientID: String, accountKey: String = "") throws {
        guard clientID.hasSuffix(".apps.googleusercontent.com"), !clientID.contains(where: \.isWhitespace) else { throw MailError.message("Add a Google Desktop OAuth client ID in Settings.") }
        self.clientID = clientID; self.accountKey = accountKey
        if let data = Keychain.readData(credentialKey) { authState = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data) }
    }
    func signIn() async throws {
        guard let window = NSApp.keyWindow else { throw MailError.message("Open the Aster window to connect Gmail.") }
        let handler = OIDRedirectHTTPHandler(successURL: nil)
        redirectHandler = handler
        var listenerError: NSError?
        let redirect = handler.startHTTPListener(&listenerError)
        if let listenerError { throw listenerError }
        let configuration = OIDServiceConfiguration(authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!, tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!)
        let secret = Keychain.read("google-client-secret")
        let request = OIDAuthorizationRequest(configuration: configuration, clientId: clientID, clientSecret: secret.isEmpty ? nil : secret, scopes: ["https://www.googleapis.com/auth/gmail.modify"], redirectURL: redirect, responseType: OIDResponseTypeCode, additionalParameters: ["access_type": "offline", "prompt": "consent select_account"])
        timeout = Task { try? await Task.sleep(for: .seconds(180)); if !Task.isCancelled { handler.cancelHTTPListener() } }
        defer { timeout?.cancel(); timeout = nil; redirectHandler = nil }
        let result: OIDAuthState = try await withCheckedThrowingContinuation { continuation in
            handler.currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request, presenting: window) { state, error in
                if let state { continuation.resume(returning: state) }
                else { continuation.resume(throwing: error ?? MailError.message("Google sign-in did not complete.")) }
            }
        }
        authState = result
        try persist()
        let profile = try await GmailClient(tokens: self).profile()
        UserDefaults.standard.set(profile.emailAddress, forKey: emailKey)
    }
    func freshToken() async throws -> String { authState?.setNeedsTokenRefresh(); return try await token() }
    func token() async throws -> String {
        guard let authState, authState.isAuthorized else { throw MailError.message("Reconnect Google in Settings.") }
        let token: String = try await withCheckedThrowingContinuation { continuation in
            authState.performAction { accessToken, _, error in
                if let accessToken { continuation.resume(returning: accessToken) }
                else { continuation.resume(throwing: error ?? MailError.message("Google session expired. Reconnect in Settings.")) }
            }
        }
        try persist() // refreshed credentials remain in Keychain across launches
        return token
    }
    private func persist() throws {
        guard let authState else { return }
        try Keychain.saveData(NSKeyedArchiver.archivedData(withRootObject: authState, requiringSecureCoding: true), account: credentialKey)
    }
    func signOut() throws {
        redirectHandler?.cancelHTTPListener(); timeout?.cancel()
        try Keychain.delete(credentialKey); authState = nil; UserDefaults.standard.removeObject(forKey: emailKey)
    }
}
