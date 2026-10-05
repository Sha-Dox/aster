import Foundation
import AppKit
import Security
import MSAL
import AsterCore

@MainActor final class MicrosoftAuth: AccountSession, @unchecked Sendable {
    private let app: MSALPublicClientApplication
    private(set) var account: MSALAccount?
    private let scopes = ["https://graph.microsoft.com/Mail.ReadWrite", "https://graph.microsoft.com/Mail.Send", "https://graph.microsoft.com/User.Read"]
    init(clientID: String, accountID: String? = nil) throws {
        guard UUID(uuidString: clientID) != nil else { throw MailError.message("Add your Microsoft Entra application ID in Settings.") }
        let authority = try MSALAADAuthority(url: URL(string: "https://login.microsoftonline.com/common")!)
        let config = MSALPublicClientApplicationConfig(clientId: clientID, redirectUri: "msauth.app.aster.mail://auth", authority: authority)
        config.cacheConfig.keychainSharingGroup = "app.aster.mail"
        app = try MSALPublicClientApplication(configuration: config)
        let saved = accountID ?? UserDefaults.standard.string(forKey: "accountID")
        account = try app.allAccounts().first { $0.identifier == saved }
    }
    var identity: String? { account?.identifier }
    var username: String? { account?.username }
    func signIn() async throws {
        guard let controller = NSApp.keyWindow?.contentViewController else { throw MailError.message("Open the Aster window to sign in.") }
        let web = MSALWebviewParameters(authPresentationViewController: controller)
        let parameters = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: web)
        parameters.promptType = .selectAccount
        let result: MSALResult = try await withCheckedThrowingContinuation { continuation in
            app.acquireToken(with: parameters) { result, error in
                if let result { continuation.resume(returning: result) }
                else { continuation.resume(throwing: error ?? MailError.message("Sign-in did not finish.")) }
            }
        }
        account = result.account
        UserDefaults.standard.set(result.account.identifier, forKey: "accountID")
    }
    func token() async throws -> String { try await acquire(forceRefresh: false) }
    func freshToken() async throws -> String { try await acquire(forceRefresh: true) }
    private func acquire(forceRefresh: Bool) async throws -> String {
        guard let account else { throw MailError.message("Sign in to Microsoft to synchronize your inbox.") }
        let parameters = MSALSilentTokenParameters(scopes: scopes, account: account)
        parameters.forceRefresh = forceRefresh
        let result: MSALResult = try await withCheckedThrowingContinuation { continuation in
            app.acquireTokenSilent(with: parameters) { result, error in
                if let result { continuation.resume(returning: result) }
                else { continuation.resume(throwing: error ?? MailError.message("Your session needs attention. Reconnect in Settings.")) }
            }
        }
        return result.accessToken
    }
    func signOut() throws {
        if let account { try app.remove(account) }
        if UserDefaults.standard.string(forKey: "accountID") == account?.identifier { UserDefaults.standard.removeObject(forKey: "accountID") }; account = nil
    }
}
enum Keychain {
    static func readData(_ account: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.aster.mail.ai", kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }
    static func read(_ account: String) -> String { readData(account).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    static func save(_ value: String, account: String) throws { try saveData(Data(value.utf8), account: account) }
    static func delete(_ account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.aster.mail.ai", kSecAttrAccount as String: account]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw MailError.message("Could not remove credentials from Keychain.") }
    }
    static func saveData(_ data: Data, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.aster.mail.ai", kSecAttrAccount as String: account]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = data; insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw MailError.message("Could not save the credential to Keychain.") }
        } else if update != errSecSuccess { throw MailError.message("Could not update the credential in Keychain.") }
    }
}
