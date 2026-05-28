import Testing
import Foundation
@testable import hiya

struct SessionCacheTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "hiya.test.cache.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func makeProfile() -> Profile {
        Profile(
            id: UUID(),
            displayName: "Cached User",
            coldDailyGoal: 7,
            warmDailyGoal: 12,
            streakMode: .hard,
            timezone: "UTC",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeAccount() -> AuthAccount {
        AuthAccount(id: UUID(), email: "u@example.com", isAnonymous: false)
    }

    @Test func emptyCache_returnsNils() {
        let cache = SessionCache(defaults: makeDefaults())
        let loaded = cache.load()
        #expect(loaded.profile == nil)
        #expect(loaded.account == nil)
    }

    @Test func savedProfileAndAccount_roundTrip() {
        let defaults = makeDefaults()
        let cache = SessionCache(defaults: defaults)
        let p = makeProfile()
        let a = makeAccount()

        cache.save(profile: p, account: a)

        let loaded = cache.load()
        #expect(loaded.profile == p)
        #expect(loaded.account == a)
    }

    @Test func savedNils_clearsBoth() {
        let cache = SessionCache(defaults: makeDefaults())
        cache.save(profile: makeProfile(), account: makeAccount())

        cache.save(profile: nil, account: nil)

        let loaded = cache.load()
        #expect(loaded.profile == nil)
        #expect(loaded.account == nil)
    }

    @Test func clear_removesEntries() {
        let cache = SessionCache(defaults: makeDefaults())
        cache.save(profile: makeProfile(), account: makeAccount())

        cache.clear()

        let loaded = cache.load()
        #expect(loaded.profile == nil)
        #expect(loaded.account == nil)
    }
}
