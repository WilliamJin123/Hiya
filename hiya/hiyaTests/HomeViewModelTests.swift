import Testing
import Foundation
@testable import hiya

@MainActor
struct HomeViewModelTests {

    private func logUniquePeople(_ count: Int, into repo: MockHiyaRepository) async throws {
        for i in 0..<count {
            let p = try await repo.createPerson(name: "Person\(i)")
            try await repo.logConversation(personId: p.id, valence: nil, note: nil, improvementNote: nil)
        }
    }

    @Test func goalReachedTick_increments_onInProgressToAtGoalTransition() async throws {
        let repo = MockHiyaRepository()
        try await logUniquePeople(9, into: repo)
        let vm = HomeViewModel(repo: repo)
        await vm.refresh()                    // hasLoaded → true, count = 9, ring .inProgress
        #expect(vm.goalReachedTick == 0)

        try await logUniquePeople(1, into: repo)
        await vm.refresh()                    // 9 → 10: .inProgress → .atGoal
        #expect(vm.goalReachedTick == 1)
    }

    @Test func goalReachedTick_doesNotFire_onColdLoadAlreadyAtGoal() async throws {
        // Opening the app fresh with the goal already met (e.g. from earlier
        // today) must not celebrate — the wasLoaded gate guards this.
        let repo = MockHiyaRepository()
        try await logUniquePeople(10, into: repo)
        let vm = HomeViewModel(repo: repo)
        await vm.refresh()
        #expect(vm.goalReachedTick == 0)
    }

    @Test func goalReachedTick_doesNotFire_onAtGoalToOverloadTransition() async throws {
        let repo = MockHiyaRepository()
        try await logUniquePeople(10, into: repo)
        let vm = HomeViewModel(repo: repo)
        await vm.refresh()                    // already-at-goal cold load → no fire
        #expect(vm.goalReachedTick == 0)

        try await logUniquePeople(1, into: repo)
        await vm.refresh()                    // 10 → 11: .atGoal → .overload, silent
        #expect(vm.goalReachedTick == 0)
    }

    @Test func refreshLoadsCountAndLog() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        let bea = try await repo.createPerson(name: "Bea")
        try await repo.logConversation(personId: alex.id, valence: .positive, note: nil, improvementNote: nil)
        try await repo.logConversation(personId: bea.id, valence: nil, note: "good chat", improvementNote: nil)

        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        #expect(vm.count(for: .cold) == 2)
        #expect(vm.count(for: .warm) == 0)
        #expect(vm.goal(for: .cold) == 10)
        #expect(vm.todaysLog.count == 2)
        #expect(vm.errorMessage == nil)
    }

    @Test func counts_areSeparateByValence() async throws {
        let repo = MockHiyaRepository()
        // One cold approach (cold origin)...
        let cold = try await repo.createPerson(name: "Cold")
        try await repo.logConversation(personId: cold.id, valence: nil, note: nil, improvementNote: nil)
        // ...and one catch-up with someone you already knew (warm origin).
        let warm = try await repo.createPerson(name: "Warm", status: .warm)
        try await repo.logConversation(personId: warm.id, valence: nil, note: nil, improvementNote: nil)

        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        #expect(vm.count(for: .cold) == 1)
        #expect(vm.count(for: .warm) == 1)
    }

    @Test func count_dedupesByPersonId() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        for _ in 0..<5 {
            try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)
        }
        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        #expect(vm.count(for: .cold) == 1, "5 logs with the same person should count as 1 unique person")
        #expect(vm.todaysLog.count == 5, "but every log row should still appear in todaysLog")
    }

    @Test func refreshExcludesConversationsOutsideToday() async throws {
        let repo = MockHiyaRepository()
        // A cold approach logged today — counts.
        let today = try await repo.createPerson(name: "Today")
        try await repo.logConversation(personId: today.id, valence: nil, note: nil, improvementNote: nil)
        // A different person whose only meeting was yesterday — outside today's window.
        let past = try await repo.createPerson(name: "Past")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        try await repo.logConversation(personId: past.id, occurredAt: yesterday, valence: nil, note: nil, improvementNote: nil)

        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        #expect(vm.count(for: .cold) == 1, "yesterday's conversation should not count toward today")
    }

    @Test func backDatedLog_doesNotCountToday() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        try await repo.logConversation(personId: p.id, occurredAt: yesterday, valence: nil, note: nil, improvementNote: nil)

        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        #expect(vm.count(for: .cold) == 0, "a back-dated log should not count toward today")
    }

    @Test func refreshSetsErrorOnFailure() async {
        let repo = MockHiyaRepository()
        repo.errorToThrow = NSError(domain: "test", code: 1)
        let vm = HomeViewModel(repo: repo)

        await vm.refresh()

        #expect(vm.errorMessage != nil)
    }

    @Test func progressIsFractionOfGoal() async throws {
        let repo = MockHiyaRepository()
        try await logUniquePeople(3, into: repo)
        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        #expect(abs(vm.progress(for: .cold) - 0.3) < 0.001)
    }

    @Test func progressCapsAt1WhenOverGoal() async throws {
        let repo = MockHiyaRepository(profile: Profile(
            id: UUID(), displayName: nil, coldDailyGoal: 2,
            streakMode: .hard, timezone: TimeZone.current.identifier, createdAt: .now
        ))
        try await logUniquePeople(5, into: repo)
        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        #expect(abs(vm.progress(for: .cold) - 1.0) < 0.001)
    }

    @Test func ringState_isInProgress_whenBelowGoal() async throws {
        let repo = MockHiyaRepository()
        try await logUniquePeople(3, into: repo)
        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        if case let .inProgress(count, goal, progress) = vm.ringState(for: .cold) {
            #expect(count == 3)
            #expect(goal == 10)
            #expect(abs(progress - 0.3) < 0.001)
        } else {
            Issue.record("expected .inProgress, got \(vm.ringState(for: .cold))")
        }
    }

    @Test func ringState_isAtGoal_whenExactlyGoal() async throws {
        let repo = MockHiyaRepository(profile: Profile(
            id: UUID(), displayName: nil, coldDailyGoal: 5,
            streakMode: .hard, timezone: TimeZone.current.identifier, createdAt: .now
        ))
        try await logUniquePeople(5, into: repo)
        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        if case let .atGoal(goal) = vm.ringState(for: .cold) {
            #expect(goal == 5)
        } else {
            Issue.record("expected .atGoal, got \(vm.ringState(for: .cold))")
        }
    }

    @Test func ringState_isOverload_withCorrectExtra_whenAboveGoal() async throws {
        let repo = MockHiyaRepository(profile: Profile(
            id: UUID(), displayName: nil, coldDailyGoal: 3,
            streakMode: .hard, timezone: TimeZone.current.identifier, createdAt: .now
        ))
        try await logUniquePeople(5, into: repo)
        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        if case let .overload(count, goal, extra) = vm.ringState(for: .cold) {
            #expect(count == 5)
            #expect(goal == 3)
            #expect(extra == 2)
        } else {
            Issue.record("expected .overload, got \(vm.ringState(for: .cold))")
        }
    }

    @Test func refresh_loadsStreaksFromActivity() async throws {
        let repo = MockHiyaRepository()
        // Two unique people today: first log is cold (graduates them to warm),
        // second log is also cold (new person, graduates to warm).
        let alex = try await repo.createPerson(name: "Alex")
        let bea = try await repo.createPerson(name: "Bea")
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)
        try await repo.logConversation(personId: bea.id, valence: nil, note: nil, improvementNote: nil)

        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        // Both logs were cold (first time meeting both people), so cold streak = 1
        // Warm streak = 0 (no warm logs)
        #expect(vm.streaks.cold == 1)
        #expect(vm.streaks.warm == 0)
    }

    @Test func refresh_loadsFollowUpSuggestions() async throws {
        let repo = MockHiyaRepository()
        // Seed a warm person 10 days stale and a fresh warm person.
        let now = Date.now
        let stale = Person(
            id: UUID(),
            ownerId: repo.profile.id,
            name: "Stale",
            status: .warm,
            statusChangedAt: now,
            createdAt: now,
            lastLoggedAt: Calendar.current.date(byAdding: .day, value: -10, to: now)!
        )
        let fresh = Person(
            id: UUID(),
            ownerId: repo.profile.id,
            name: "Fresh",
            status: .warm,
            statusChangedAt: now,
            createdAt: now,
            lastLoggedAt: now
        )
        repo.people.append(stale)
        repo.people.append(fresh)

        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        #expect(vm.followUpSuggestions.map(\.name) == ["Stale"])
    }

    @Test func refresh_success_flipsHasLoaded() async throws {
        let repo = MockHiyaRepository()
        let vm = HomeViewModel(repo: repo)
        #expect(vm.hasLoaded == false)

        await vm.refresh()

        #expect(vm.hasLoaded == true)
    }

    @Test func refresh_failure_leavesHasLoadedFalse() async {
        let repo = MockHiyaRepository()
        repo.errorToThrow = NSError(domain: "test", code: 1)
        let vm = HomeViewModel(repo: repo)

        await vm.refresh()

        #expect(vm.errorMessage != nil)
        #expect(vm.hasLoaded == false, "first-load failure should keep skeleton showing")
    }

    @Test func refresh_warmStreakReflectsRepeatLogs() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil) // cold
        // Simulate cycle reset — graduate alex to warm so the next log is warm.
        if let idx = repo.people.firstIndex(where: { $0.id == alex.id }) {
            repo.people[idx].status = .warm
            repo.people[idx].statusChangedAt = .now
        }
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil) // warm

        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        #expect(vm.streaks.cold == 1)
        #expect(vm.streaks.warm == 1)
    }
}
