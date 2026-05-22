import Testing
import Foundation
@testable import hiya

@MainActor
struct HomeViewModelTests {

    @Test func refreshLoadsCountAndLog() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        try await repo.logConversation(personId: alex.id, valence: .positive, note: nil, improvementNote: nil)
        try await repo.logConversation(personId: alex.id, valence: nil, note: "good chat", improvementNote: nil)

        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        #expect(vm.count == 2)
        #expect(vm.goal == 10)
        #expect(vm.todaysLog.count == 2)
        #expect(vm.errorMessage == nil)
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

        #expect(vm.count == 1, "yesterday's conversation should not count")
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
        let alex = try await repo.createPerson(name: "Alex")
        for _ in 0..<3 {
            try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)
        }
        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        #expect(abs(vm.progress - 0.3) < 0.001)
    }

    @Test func progressCapsAt1WhenOverGoal() async throws {
        let repo = MockHiyaRepository(profile: Profile(
            id: UUID(), displayName: nil, dailyGoal: 2,
            streakMode: .hard, timezone: TimeZone.current.identifier, createdAt: .now
        ))
        let alex = try await repo.createPerson(name: "Alex")
        for _ in 0..<5 {
            try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)
        }
        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        #expect(abs(vm.progress - 1.0) < 0.001)
    }

    @Test func ringState_isInProgress_whenBelowGoal() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        for _ in 0..<3 {
            try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)
        }
        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        if case let .inProgress(count, goal, progress) = vm.ringState {
            #expect(count == 3)
            #expect(goal == 10)
            #expect(abs(progress - 0.3) < 0.001)
        } else {
            Issue.record("expected .inProgress, got \(vm.ringState)")
        }
    }

    @Test func ringState_isAtGoal_whenExactlyGoal() async throws {
        let repo = MockHiyaRepository(profile: Profile(
            id: UUID(), displayName: nil, dailyGoal: 5,
            streakMode: .hard, timezone: TimeZone.current.identifier, createdAt: .now
        ))
        let alex = try await repo.createPerson(name: "Alex")
        for _ in 0..<5 {
            try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)
        }
        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        if case let .atGoal(goal) = vm.ringState {
            #expect(goal == 5)
        } else {
            Issue.record("expected .atGoal, got \(vm.ringState)")
        }
    }

    @Test func ringState_isOverload_withCorrectExtra_whenAboveGoal() async throws {
        let repo = MockHiyaRepository(profile: Profile(
            id: UUID(), displayName: nil, dailyGoal: 3,
            streakMode: .hard, timezone: TimeZone.current.identifier, createdAt: .now
        ))
        let alex = try await repo.createPerson(name: "Alex")
        for _ in 0..<5 {
            try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)
        }
        let vm = HomeViewModel(repo: repo)
        await vm.refresh()

        if case let .overload(count, goal, extra) = vm.ringState {
            #expect(count == 5)
            #expect(goal == 3)
            #expect(extra == 2)
        } else {
            Issue.record("expected .overload, got \(vm.ringState)")
        }
    }
}
