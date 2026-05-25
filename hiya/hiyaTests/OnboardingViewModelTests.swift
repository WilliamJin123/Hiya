import Testing
import Foundation
@testable import hiya

@MainActor
struct OnboardingViewModelTests {
    @Test func seedsGoalsFromProfile() {
        var p = Profile.preview
        p.coldDailyGoal = 5
        p.warmDailyGoal = 8
        let vm = OnboardingViewModel(repo: MockHiyaRepository(), profile: p)
        #expect(vm.coldGoal == 5)
        #expect(vm.warmGoal == 8)
    }

    @Test func seedsDefaultsWhenNoProfile() {
        let vm = OnboardingViewModel(repo: MockHiyaRepository(), profile: nil)
        #expect(vm.coldGoal == 10)
        #expect(vm.warmGoal == 10)
    }

    @Test func nextAdvancesAndClamps() {
        let vm = OnboardingViewModel(repo: MockHiyaRepository(), profile: .preview)
        #expect(vm.page == 0)
        vm.next(); vm.next(); vm.next()
        #expect(vm.page == 3)
        #expect(vm.isLastPage)
        vm.next()                       // already last — stays
        #expect(vm.page == 3)
    }

    @Test func finishSavesGoals() async {
        let repo = MockHiyaRepository()
        let vm = OnboardingViewModel(repo: repo, profile: .preview)
        vm.coldGoal = 7
        vm.warmGoal = 12
        let ok = await vm.finish()
        #expect(ok)
        let saved = try? await repo.ensureSignedIn()
        #expect(saved?.coldDailyGoal == 7)
        #expect(saved?.warmDailyGoal == 12)
    }
}
