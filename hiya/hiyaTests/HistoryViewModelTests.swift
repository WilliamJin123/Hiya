import Testing
import Foundation
@testable import hiya

@MainActor
struct HistoryViewModelTests {

    @Test func load_excludesToday() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        // Today's log — should be excluded from history
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)

        let vm = HistoryViewModel(repo: repo)
        await vm.load()

        #expect(vm.sections.isEmpty, "today's logs do not appear in history (they're on Home)")
    }

    @Test func load_groupsConversationsByDay() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        let bea = try await repo.createPerson(name: "Bea")

        // Two convos two days ago, one yesterday — append directly to bypass
        // logConversation's now-stamping.
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: .now)!
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!

        repo.conversations.append(Conversation(
            id: UUID(), ownerId: repo.profile.id, personId: alex.id,
            occurredAt: twoDaysAgo, valence: .positive, note: "lunch",
            createdAt: twoDaysAgo
        ))
        repo.conversations.append(Conversation(
            id: UUID(), ownerId: repo.profile.id, personId: bea.id,
            occurredAt: twoDaysAgo, valence: nil, note: nil,
            createdAt: twoDaysAgo
        ))
        repo.conversations.append(Conversation(
            id: UUID(), ownerId: repo.profile.id, personId: alex.id,
            occurredAt: yesterday, valence: nil, note: nil,
            createdAt: yesterday
        ))

        let vm = HistoryViewModel(repo: repo)
        await vm.load()

        #expect(vm.sections.count == 2, "two distinct past days")
        let firstSection = vm.sections[0]
        #expect(firstSection.totalCount == 1, "yesterday's section has the most recent day, one log")
        #expect(vm.sections[1].totalCount == 2, "two days ago has two logs")
        #expect(vm.sections[0].date > vm.sections[1].date, "sections sorted newest first")
    }

    @Test func daySection_hadCold_reflectsAtLeastOneColdEntry() async throws {
        let convs = [
            LoggedConversation(id: UUID(), personId: UUID(), personName: "A",
                               occurredAt: .now, valence: nil, note: nil,
                               improvementNote: nil, wasColdAtTime: true),
            LoggedConversation(id: UUID(), personId: UUID(), personName: "B",
                               occurredAt: .now, valence: nil, note: nil,
                               improvementNote: nil, wasColdAtTime: false),
        ]
        let sections = HistoryViewModel.groupByDay(convs)
        #expect(sections.count == 1)
        #expect(sections[0].hadCold == true)
        #expect(sections[0].coldCount == 1)
    }

    @Test func load_setsErrorOnFailure() async {
        let repo = MockHiyaRepository()
        repo.errorToThrow = NSError(domain: "test", code: 1)

        let vm = HistoryViewModel(repo: repo)
        await vm.load()

        #expect(vm.errorMessage != nil)
    }
}
