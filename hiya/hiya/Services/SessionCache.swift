import Foundation

/// Persists the last-known profile + account JSON to UserDefaults so the
/// gate can flip from `.loading` to `.app` instantly on cold-start, instead
/// of waiting for the `ensureSignedIn` round-trip. The network call still
/// runs (silently) and overwrites the cache on success; if the session has
/// gone away server-side, the gate falls back to `.auth` and the cache is
/// cleared.
///
/// Intentionally a value type. Only touched from `SessionViewModel`
/// (`@MainActor`), so we don't need to make it `Sendable`.
struct SessionCache {
    private let defaults: UserDefaults
    private let profileKey = "hiya.cache.profile.v1"
    private let accountKey = "hiya.cache.account.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(profile: Profile?, account: AuthAccount?) {
        let enc = JSONEncoder()
        if let profile, let data = try? enc.encode(profile) {
            defaults.set(data, forKey: profileKey)
        } else {
            defaults.removeObject(forKey: profileKey)
        }
        if let account, let data = try? enc.encode(account) {
            defaults.set(data, forKey: accountKey)
        } else {
            defaults.removeObject(forKey: accountKey)
        }
    }

    func load() -> (profile: Profile?, account: AuthAccount?) {
        let dec = JSONDecoder()
        let profile: Profile? = defaults.data(forKey: profileKey)
            .flatMap { try? dec.decode(Profile.self, from: $0) }
        let account: AuthAccount? = defaults.data(forKey: accountKey)
            .flatMap { try? dec.decode(AuthAccount.self, from: $0) }
        return (profile, account)
    }

    func clear() {
        defaults.removeObject(forKey: profileKey)
        defaults.removeObject(forKey: accountKey)
    }
}
