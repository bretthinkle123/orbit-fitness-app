import Foundation
import Security

/// Errors from the Keychain Services C API, wrapped so callers never handle
/// a raw `OSStatus` directly.
enum KeychainError: Error, Equatable, Sendable {
    case unhandledStatus(OSStatus)
}

/// The narrow contract `AuthService`/`APIClient` depend on — never the
/// concrete Keychain type directly (`code-standards` facade rule: depend on
/// an abstraction, inject the dependency). A mock conforming to this is what
/// `CoreTests.swift` uses to test `AuthService`'s sign-out sequencing without
/// touching the real Keychain.
protocol TokenStoring: Sendable {
    /// Persists `token`, replacing any previously stored value.
    func save(token: String) throws
    /// Returns the stored token, or `nil` if none has been saved (or it was
    /// cleared) — never throws for "not found," only for a genuine Keychain
    /// failure.
    func loadToken() throws -> String?
    /// Removes the stored token. Idempotent: clearing an already-empty store
    /// is a no-op, not an error (mirrors the backend's own idempotent-erase
    /// discipline, `lifecycle/erase.py`).
    func clear() throws
}

/// The ONE place the app touches Keychain Services (`code-standards`: no
/// hardcoded secrets, and CLAUDE.md/plan.md: "never `UserDefaults` for the
/// token"). Stores a single string value (the cached Firebase ID token
/// `APIClient` attaches as a bearer credential) under one fixed
/// service/account pair scoped to `kSecAttrAccessibleAfterFirstUnlock` — the
/// token is app-launch-usable in the background (e.g. a background refresh)
/// but never syncs to iCloud Keychain and never survives a full device wipe,
/// matching a bearer credential's expected lifetime.
struct KeychainTokenStore: TokenStoring {
    private let service: String
    private let account: String

    init(service: String = "com.orbitfitness.orbit", account: String = "firebaseIDToken") {
        self.service = service
        self.account = account
    }

    func save(token: String) throws {
        let data = Data(token.utf8)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // Already present — update in place rather than delete+add, so a
            // failed update can never leave the store transiently empty.
            let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError.unhandledStatus(updateStatus) }
            return
        }
        guard addStatus == errSecSuccess else { throw KeychainError.unhandledStatus(addStatus) }
    }

    func loadToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else { throw KeychainError.unhandledStatus(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        // Deleting an absent item reports `errSecItemNotFound` — that's the
        // idempotent "already clear" case, not a failure.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    /// The fixed class/service/account triple every operation above scopes
    /// to — kept in one place so `save`/`loadToken`/`clear` can never drift
    /// out of sync with each other about which Keychain item they mean.
    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
