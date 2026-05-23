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
