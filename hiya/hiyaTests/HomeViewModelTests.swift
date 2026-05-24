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
        #expect(vm.goal == 10)
        #expect(vm.todaysLog.count == 2)
        #expect(vm.errorMessage == nil)
    }

    @Test func counts_areSeparateByValence() async throws {
        let repo = MockHiyaRepository()
        // One cold log (fresh person stays cold)...
        let cold = try await repo.createPerson(name: "Cold")
        try await repo.logConversation(personId: cold.id, valence: nil, note: nil, improvementNote: nil)
        // ...and one warm log (flip status before logging so it snapshots warm).
        let warm = try await repo.createPerson(name: "Warm")
        if let idx = repo.people.firstIndex(where: { $0.id == warm.id }) {
            repo.people[idx].status = .warm
            repo.people[idx].statusChangedAt = .now
        }
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
        let alex = try await repo.createPerson(name: "Alex")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        repo.conversations.append(Conversation(
            id: UUID(),
            ownerId: repo.profile.id,
            personId: alex.id,
            occurredAt: yesterday,
            valence: nil,
            note: nil,
            createdAt: yesterday
        ))
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)

        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        #expect(vm.count(for: .cold) == 1, "yesterday's conversation should not count")
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
            id: UUID(), displayName: nil, dailyGoal: 2,
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
            id: UUID(), displayName: nil, dailyGoal: 5,
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
            id: UUID(), displayName: nil, dailyGoal: 3,
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
