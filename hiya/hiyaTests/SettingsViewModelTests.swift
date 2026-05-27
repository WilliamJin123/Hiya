import Testing
import Foundation
@testable import hiya

@MainActor
struct SettingsViewModelTests {

    @Test func load_seedsGoalsFromProfile() async throws {
        let repo = MockHiyaRepository(profile: Profile(
            id: UUID(), displayName: nil,
            coldDailyGoal: 3, warmDailyGoal: 8,
            streakMode: .hard, timezone: TimeZone.current.identifier, createdAt: .now
        ))
        let vm = SettingsViewModel(repo: repo)

        await vm.load()

        #expect(vm.coldGoal == 3)
        #expect(vm.warmGoal == 8)
    }

    @Test func save_persistsBothGoals() async throws {
        let repo = MockHiyaRepository()
        let vm = SettingsViewModel(repo: repo)
        vm.coldGoal = 4
        vm.warmGoal = 9

        await vm.save()

        #expect(vm.didSave == true)
        #expect(repo.profile.coldDailyGoal == 4)
        #expect(repo.profile.warmDailyGoal == 9)
    }

    @Test func save_setsErrorOnFailure() async throws {
        let repo = MockHiyaRepository()
        repo.errorToThrow = NSError(domain: "test", code: 1)
        let vm = SettingsViewModel(repo: repo)

        await vm.save()

        #expect(vm.errorMessage != nil)
        #expect(vm.didSave == false)
    }
}
