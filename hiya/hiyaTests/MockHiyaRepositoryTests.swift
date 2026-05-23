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

    @Test func updatePersonNotes_setsAndClearsNotes() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")

        try await repo.updatePersonNotes(id: alex.id, notes: "Met at climbing gym")
        #expect(repo.people.first(where: { $0.id == alex.id })?.notes == "Met at climbing gym")

        try await repo.updatePersonNotes(id: alex.id, notes: nil)
        #expect(repo.people.first(where: { $0.id == alex.id })?.notes == nil)
    }

    @Test func followUpSuggestions_returnsOnlyWarmPeopleNotSeenInWindow() async throws {
        let repo = MockHiyaRepository()
        // Seed three warm people with varying last-seen dates and one cold person.
        let now = Date.now
        func mk(_ name: String, status: PersonStatus, daysAgo: Int) -> Person {
            Person(
                id: UUID(),
                ownerId: repo.profile.id,
                name: name,
                status: status,
                statusChangedAt: status == .warm ? now : nil,
                createdAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!,
                lastLoggedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
            )
        }
        repo.people.append(mk("RecentWarm",    status: .warm, daysAgo: 3))   // inside window
        repo.people.append(mk("OldWarm",       status: .warm, daysAgo: 14))  // outside, oldest
        repo.people.append(mk("MidWarm",       status: .warm, daysAgo: 9))   // outside, newer
        repo.people.append(mk("StaleCold",     status: .cold, daysAgo: 30))  // wrong status

        let suggestions = try await repo.followUpSuggestions(thresholdDays: 7, limit: 3)

        #expect(suggestions.map(\.name) == ["OldWarm", "MidWarm"], "expect warm people not-seen-in-7-days, oldest first")
    }

    @Test func followUpSuggestions_respectsLimit() async throws {
        let repo = MockHiyaRepository()
        let now = Date.now
        for i in 0..<5 {
            repo.people.append(Person(
                id: UUID(),
                ownerId: repo.profile.id,
                name: "Warm\(i)",
                status: .warm,
                statusChangedAt: now,
                createdAt: now,
                lastLoggedAt: Calendar.current.date(byAdding: .day, value: -(10 + i), to: now)!
            ))
        }

        let suggestions = try await repo.followUpSuggestions(thresholdDays: 7, limit: 3)

        #expect(suggestions.count == 3)
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
