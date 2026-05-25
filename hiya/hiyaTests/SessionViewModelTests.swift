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
}
