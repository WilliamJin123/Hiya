import Testing
import Foundation
@testable import hiya

@MainActor
struct ChallengesViewModelTests {
    private func conv(_ pid: UUID, cold: Bool, daysAgo: Int, now: Date) -> LoggedConversation {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        return LoggedConversation(id: UUID(), personId: pid, personName: "X",
                                  occurredAt: d, valence: nil, note: nil,
                                  improvementNote: nil, wasColdAtTime: cold)
    }

    @Test func progress_countsUniquePeopleOnTrackInWindow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let ch = Challenge(id: UUID(), ownerId: UUID(), title: "t", prompt: "p",
                           track: .cold, targetCount: 3, durationDays: 7,
                           source: .custom, templateSlug: nil, startedAt: start, completedAt: nil)
        let a = UUID(); let b = UUID()
        let convs = [
            conv(a, cold: true, daysAgo: 1, now: now),
            conv(a, cold: true, daysAgo: 0, now: now),       // same person → still 1 unique
            conv(b, cold: true, daysAgo: 1, now: now),
            conv(UUID(), cold: false, daysAgo: 1, now: now), // warm → ignored
            conv(UUID(), cold: true, daysAgo: 10, now: now), // before window start
        ]
        #expect(ChallengesViewModel.progress(for: ch, in: convs, now: now) == 2)
    }

    @Test func load_autoCompletesMetTargetedChallenge() async throws {
        let repo = MockHiyaRepository()
        // Challenge starts first; the qualifying log happens after (only logs
        // within [startedAt, endDate] count toward it).
        _ = try await repo.startChallenge(ChallengeDraft(title: "One", prompt: "p", track: .cold, targetCount: 1, durationDays: 1))
        let person = try await repo.createPerson(name: "Alex")
        try await repo.logConversation(personId: person.id, valence: nil, note: nil, improvementNote: nil)

        let vm = ChallengesViewModel(repo: repo)
        await vm.load()

        #expect(vm.active.isEmpty)
        #expect(vm.completed.count == 1)
    }

    @Test func activeChallenges_forTrack_includesAny() async throws {
        let repo = MockHiyaRepository()
        _ = try await repo.startChallenge(ChallengeDraft(title: "cold", prompt: "p", track: .cold, targetCount: nil, durationDays: nil))
        _ = try await repo.startChallenge(ChallengeDraft(title: "warm", prompt: "p", track: .warm, targetCount: nil, durationDays: nil))
        _ = try await repo.startChallenge(ChallengeDraft(title: "any", prompt: "p", track: .any, targetCount: nil, durationDays: nil))

        let vm = ChallengesViewModel(repo: repo)
        await vm.load()

        #expect(Set(vm.activeChallenges(for: .cold).map(\.title)) == ["cold", "any"])
        #expect(Set(vm.activeChallenges(for: .warm).map(\.title)) == ["warm", "any"])
    }
}
