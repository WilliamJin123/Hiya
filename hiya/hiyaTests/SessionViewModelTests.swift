import Testing
import Foundation
@testable import hiya

@MainActor
struct SessionViewModelTests {
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

    @Test func start_anonymousSession_entersApp() async {
        let repo = MockHiyaRepository()          // default: anonymous session present
        let vm = SessionViewModel(repo: repo)
        await vm.start()
        #expect(vm.state == .app)
        #expect(vm.account?.isAnonymous == true)
    }

    @Test func claim_makesPermanentStaysInApp() async {
        let repo = MockHiyaRepository()
        let vm = SessionViewModel(repo: repo)
        await vm.start()
        let ok = await vm.claim(email: "w@x.com", password: "secret1", displayName: "William Jin")
        #expect(ok)
        #expect(vm.state == .app)
        #expect(vm.account?.isAnonymous == false)
        #expect(vm.profile?.displayName == "William Jin")
    }

    @Test func signOut_routesToAuth() async {
        let repo = MockHiyaRepository()
        let vm = SessionViewModel(repo: repo)
        await vm.start()
        await vm.signOut()
        #expect(vm.state == .auth)
        #expect(vm.account == nil)
    }

    @Test func signIn_routesToApp() async {
        let repo = MockHiyaRepository()
        let vm = SessionViewModel(repo: repo)
        await vm.signOut()                        // start signed out
        let ok = await vm.signIn(email: "w@x.com", password: "secret1")
        #expect(ok)
        #expect(vm.state == .app)
        #expect(vm.account?.isAnonymous == false)
    }
}
