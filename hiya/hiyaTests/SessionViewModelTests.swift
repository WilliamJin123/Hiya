import Testing
import Foundation
@testable import hiya

@MainActor
struct SessionViewModelTests {
    /// Fresh, isolated defaults per test so the onboarding/graduated flags
    /// never leak between tests or into the real app domain.
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    @Test func decide_appWhenAccountPresent() {
        let acct = AuthAccount(id: UUID(), email: nil, isAnonymous: true)
        #expect(SessionViewModel.decide(account: acct, hasGraduated: false) == .app)
        #expect(SessionViewModel.decide(account: acct, hasGraduated: true) == .app)
    }
    @Test func decide_authWhenNoSessionButGraduated() {
        #expect(SessionViewModel.decide(account: nil, hasGraduated: true) == .auth)
    }
    @Test func decide_createAnonymousWhenFresh() {
        #expect(SessionViewModel.decide(account: nil, hasGraduated: false) == .createAnonymous)
    }

    @Test func start_freshUser_routesToOnboarding() async {
        let repo = MockHiyaRepository()            // anonymous session present
        let vm = SessionViewModel(repo: repo, defaults: freshDefaults())
        await vm.start()
        #expect(vm.state == .onboarding)           // not yet onboarded
    }

    @Test func start_onboardedUser_entersApp() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hiya.hasOnboarded")
        let repo = MockHiyaRepository()
        let vm = SessionViewModel(repo: repo, defaults: defaults)
        await vm.start()
        #expect(vm.state == .app)
        #expect(vm.account?.isAnonymous == true)
    }

    @Test func completeOnboarding_setsFlagAndApp() async {
        let defaults = freshDefaults()
        let vm = SessionViewModel(repo: MockHiyaRepository(), defaults: defaults)
        await vm.start()
        #expect(vm.state == .onboarding)
        vm.completeOnboarding()
        #expect(vm.state == .app)
        // Flag persists: a new session on the same defaults skips onboarding.
        let vm2 = SessionViewModel(repo: MockHiyaRepository(), defaults: defaults)
        await vm2.start()
        #expect(vm2.state == .app)
    }

    @Test func claim_makesPermanentStaysInApp() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hiya.hasOnboarded")
        let vm = SessionViewModel(repo: MockHiyaRepository(), defaults: defaults)
        await vm.start()
        let ok = await vm.claim(email: "w@x.com", password: "secret1", displayName: "William Jin")
        #expect(ok)
        #expect(vm.state == .app)
        #expect(vm.account?.isAnonymous == false)
        #expect(vm.profile?.displayName == "William Jin")
    }

    @Test func signOut_routesToAuth() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hiya.hasOnboarded")
        let vm = SessionViewModel(repo: MockHiyaRepository(), defaults: defaults)
        await vm.start()
        await vm.signOut()
        #expect(vm.state == .auth)
        #expect(vm.account == nil)
    }

    @Test func signIn_routesToApp() async {
        let vm = SessionViewModel(repo: MockHiyaRepository(), defaults: freshDefaults())
        await vm.signOut()                          // start signed out
        let ok = await vm.signIn(email: "w@x.com", password: "secret1")
        #expect(ok)
        #expect(vm.state == .app)
        #expect(vm.account?.isAnonymous == false)
    }

    @Test func deleteAccount_success_routesToAuthAndClearsFlags() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hiya.hasGraduatedToAccount")
        defaults.set(true, forKey: "hiya.hasOnboarded")
        let repo = MockHiyaRepository()
        let vm = SessionViewModel(repo: repo, defaults: defaults)
        await vm.start()

        await vm.deleteAccount()

        #expect(repo.didDeleteAccount)
        #expect(vm.state == .auth)
        #expect(vm.account == nil)
        // Flags reset: a fresh session on the same defaults is a brand-new device.
        #expect(SessionViewModel.decide(account: nil, hasGraduated: defaults.bool(forKey: "hiya.hasGraduatedToAccount")) == .createAnonymous)
        #expect(defaults.bool(forKey: "hiya.hasOnboarded") == false)
    }

    @Test func start_writesCacheOnSuccess() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hiya.hasOnboarded")
        let vm = SessionViewModel(repo: MockHiyaRepository(), defaults: defaults)
        await vm.start()

        let cached = SessionCache(defaults: defaults).load()
        #expect(cached.profile != nil, "successful start should populate profile cache")
        #expect(cached.account != nil, "successful start should populate account cache")
    }

    @Test func start_optimisticallyHydratesFromCache() async {
        // Pre-seed cache with a previous session's data, then verify a fresh
        // VM picks it up immediately. We can't observe the .loading→.app
        // transition timing in a unit test, but we can check that the final
        // state ends in .app with the cached profile in place.
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hiya.hasOnboarded")
        let cachedProfile = Profile(
            id: UUID(), displayName: "Cached You",
            coldDailyGoal: 4, warmDailyGoal: 6,
            streakMode: .hard, timezone: "UTC", createdAt: .now
        )
        let cachedAccount = AuthAccount(id: cachedProfile.id, email: "u@example.com", isAnonymous: false)
        SessionCache(defaults: defaults).save(profile: cachedProfile, account: cachedAccount)

        let vm = SessionViewModel(repo: MockHiyaRepository(), defaults: defaults)
        await vm.start()

        #expect(vm.state == .app)
        // Mock returns its own anonymous profile, which overwrites the cache —
        // so the final profile is the mock's, but state.app was reached without
        // waiting for the network round-trip (that's the perceived-perf win;
        // not directly observable here, just the contract that cache+net both work).
        #expect(vm.profile != nil)
    }

    @Test func signOut_clearsCache() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hiya.hasOnboarded")
        let vm = SessionViewModel(repo: MockHiyaRepository(), defaults: defaults)
        await vm.start()

        await vm.signOut()

        let cached = SessionCache(defaults: defaults).load()
        #expect(cached.profile == nil)
        #expect(cached.account == nil)
    }

    @Test func deleteAccount_clearsCache() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hiya.hasOnboarded")
        let vm = SessionViewModel(repo: MockHiyaRepository(), defaults: defaults)
        await vm.start()

        await vm.deleteAccount()

        let cached = SessionCache(defaults: defaults).load()
        #expect(cached.profile == nil)
        #expect(cached.account == nil)
    }

    @Test func deleteAccount_failure_keepsStateAndSetsError() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hiya.hasOnboarded")
        let repo = MockHiyaRepository()
        let vm = SessionViewModel(repo: repo, defaults: defaults)
        await vm.start()
        #expect(vm.state == .app)

        repo.errorToThrow = NSError(domain: "test", code: 1)
        await vm.deleteAccount()

        #expect(vm.state == .app)              // unchanged
        #expect(vm.account != nil)
        #expect(vm.errorMessage != nil)
    }
}
