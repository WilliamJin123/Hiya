import Testing
import Foundation
@testable import hiya

@MainActor
struct MockHiyaRepositoryTests {

    @Test func createPerson_defaultsToCold() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        #expect(alex.status == .cold)
        #expect(alex.statusChangedAt == nil)
    }

    @Test func logConversation_onColdPerson_snapshotsColdAndGraduates() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")

        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)

        #expect(repo.conversations.count == 1)
        #expect(repo.conversations[0].wasColdAtTime == true)
        let updated = repo.people.first(where: { $0.id == alex.id })!
        #expect(updated.status == .warm)
        #expect(updated.statusChangedAt != nil)
    }

    @Test func logConversation_onWarmPerson_snapshotsWarmAndStaysWarm() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)
        let graduationTime = repo.people.first(where: { $0.id == alex.id })!.statusChangedAt

        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)

        #expect(repo.conversations.count == 2)
        #expect(repo.conversations[1].wasColdAtTime == false)
        let updated = repo.people.first(where: { $0.id == alex.id })!
        #expect(updated.status == .warm)
        #expect(updated.statusChangedAt == graduationTime, "warm→warm log should not bump statusChangedAt")
    }

    @Test func promotePerson_setsWarm() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")

        try await repo.promotePerson(id: alex.id)

        let updated = repo.people.first(where: { $0.id == alex.id })!
        #expect(updated.status == .warm)
        #expect(updated.statusChangedAt != nil)
    }

    @Test func demotePerson_setsCold() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)
        // alex is now warm; demote back to cold
        try await repo.demotePerson(id: alex.id)

        let updated = repo.people.first(where: { $0.id == alex.id })!
        #expect(updated.status == .cold)
    }

    @Test func todaysLog_propagatesWasColdAtTime() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil) // cold
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil) // warm

        let (start, end) = HomeViewModel.todayWindow()
        let log = try await repo.todaysLog(start: start, end: end)

        // log is sorted descending by occurredAt — most recent first
        #expect(log.count == 2)
        #expect(log[0].wasColdAtTime == false, "most recent log should be warm")
        #expect(log[1].wasColdAtTime == true, "earlier log should be cold")
    }
}
