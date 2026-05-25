import Testing
import Foundation
@testable import hiya

@MainActor
struct PeopleViewModelTests {

    @Test func load_populatesPeople() async throws {
        let repo = MockHiyaRepository()
        _ = try await repo.createPerson(name: "Alex")
        _ = try await repo.createPerson(name: "Bea")

        let vm = PeopleViewModel(repo: repo)
        await vm.load()

        #expect(vm.people.count == 2)
    }

    @Test func slices_separateJustMetFromRecurring() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        _ = try await repo.createPerson(name: "Bea")
        if let idx = repo.people.firstIndex(where: { $0.id == alex.id }) {
            repo.people[idx].status = .warm
            repo.people[idx].statusChangedAt = .now
        }

        let vm = PeopleViewModel(repo: repo)
        await vm.load()

        #expect(vm.justMet.map(\.name) == ["Bea"])
        #expect(vm.recurring.map(\.name) == ["Alex"])
    }

    @Test func activityStrip_marksLoggedDaysOldestToNewest() {
        let cal = Calendar.current
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let pid = UUID()
        let other = UUID()
        func conv(_ personId: UUID, daysAgo: Int, wasCold: Bool = false) -> LoggedConversation {
            let d = cal.date(byAdding: .day, value: -daysAgo, to: now)!
            return LoggedConversation(
                id: UUID(), personId: personId, personName: "X",
                occurredAt: d, valence: nil, note: nil, improvementNote: nil,
                wasColdAtTime: wasCold
            )
        }

        let strip = PeopleViewModel.activityStrip(
            personId: pid,
            conversations: [conv(pid, daysAgo: 0), conv(pid, daysAgo: 3), conv(other, daysAgo: 1)],
            days: 7,
            now: now,
            calendar: cal
        )

        // No cold conversation in view, so the whole strip is the warm era.
        #expect(strip.count == 7)
        #expect(strip[6] == .warmActive)  // today
        #expect(strip[3] == .warmActive)  // 3 days ago
        #expect(strip[5] == .warmIdle)    // 1 day ago belongs to a different person
        #expect(strip[0] == .warmIdle)    // 6 days ago, no log
    }

    @Test func activityStrip_amberEraEndsAtColdFirstMeeting() {
        let cal = Calendar.current
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let pid = UUID()
        func conv(_ daysAgo: Int, wasCold: Bool) -> LoggedConversation {
            let d = cal.date(byAdding: .day, value: -daysAgo, to: now)!
            return LoggedConversation(
                id: UUID(), personId: pid, personName: "X",
                occurredAt: d, valence: nil, note: nil, improvementNote: nil,
                wasColdAtTime: wasCold
            )
        }

        // Met cold 4 days ago (index 2), warm catch-up today (index 6).
        let strip = PeopleViewModel.activityStrip(
            personId: pid,
            conversations: [conv(4, wasCold: true), conv(0, wasCold: false)],
            days: 7,
            now: now,
            calendar: cal
        )

        #expect(strip.count == 7)
        #expect(strip[0] == .coldIdle)    // 6 days ago — before the meeting
        #expect(strip[1] == .coldIdle)    // 5 days ago — before the meeting
        #expect(strip[2] == .coldActive)  // 4 days ago — the cold first meeting
        #expect(strip[3] == .warmIdle)    // after the meeting, no contact
        #expect(strip[5] == .warmIdle)    // after the meeting, no contact
        #expect(strip[6] == .warmActive)  // today — warm catch-up
    }

    @Test func addPerson_createsWarmPerson_inRecurring() async throws {
        let repo = MockHiyaRepository()
        let vm = PeopleViewModel(repo: repo)
        await vm.load()

        await vm.addPerson(name: "Old Friend")

        #expect(vm.recurring.map(\.name) == ["Old Friend"])
        #expect(vm.justMet.isEmpty)
    }

    @Test func addPerson_withNote_storesNoteAsWarm() async throws {
        let repo = MockHiyaRepository()
        let vm = PeopleViewModel(repo: repo)
        await vm.load()

        await vm.addPerson(name: "Sam", notes: "from work")

        let sam = vm.people.first { $0.name == "Sam" }!
        #expect(sam.notes == "from work")
        #expect(sam.status == .warm)
    }

    @Test func updateNotes_persistsAndReloads() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")

        let vm = PeopleViewModel(repo: repo)
        await vm.load()
        await vm.updateNotes(id: alex.id, notes: "Met at climbing gym")

        let updated = vm.people.first(where: { $0.id == alex.id })!
        #expect(updated.notes == "Met at climbing gym")
    }

    @Test func updateNotes_withNil_clearsNotes() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        try await repo.updatePersonNotes(id: alex.id, notes: "something")

        let vm = PeopleViewModel(repo: repo)
        await vm.load()
        await vm.updateNotes(id: alex.id, notes: nil)

        let updated = vm.people.first(where: { $0.id == alex.id })!
        #expect(updated.notes == nil)
    }

    @Test func delete_removesPersonAndConversations() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)
        #expect(repo.conversations.count == 2)

        let vm = PeopleViewModel(repo: repo)
        await vm.load()
        await vm.delete(alex.id)

        #expect(vm.people.isEmpty)
        #expect(repo.conversations.isEmpty, "deleting a person should cascade-delete their conversations")
    }

    @Test func load_setsErrorOnFailure() async {
        let repo = MockHiyaRepository()
        repo.errorToThrow = NSError(domain: "test", code: 1)

        let vm = PeopleViewModel(repo: repo)
        await vm.load()

        #expect(vm.errorMessage != nil)
    }
}
