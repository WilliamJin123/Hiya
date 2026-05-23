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

    @Test func filter_byMode_returnsOnlyMatchingStatus() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        let bea = try await repo.createPerson(name: "Bea")
        // Alex logged once → auto-graduates to warm
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)
        _ = bea // bea stays cold

        let vm = PeopleViewModel(repo: repo)
        await vm.load()

        let coldNames = vm.people(in: .cold).map(\.name).sorted()
        let warmNames = vm.people(in: .warm).map(\.name).sorted()
        #expect(coldNames == ["Bea"])
        #expect(warmNames == ["Alex"])
    }

    @Test func promote_movesPersonToWarm() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")

        let vm = PeopleViewModel(repo: repo)
        await vm.load()
        await vm.promote(alex.id)

        let updated = vm.people.first(where: { $0.id == alex.id })!
        #expect(updated.status == .warm)
        #expect(vm.people(in: .cold).isEmpty)
        #expect(vm.people(in: .warm).count == 1)
    }

    @Test func demote_movesPersonToCold() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)

        let vm = PeopleViewModel(repo: repo)
        await vm.load()
        await vm.demote(alex.id)

        let updated = vm.people.first(where: { $0.id == alex.id })!
        #expect(updated.status == .cold)
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
