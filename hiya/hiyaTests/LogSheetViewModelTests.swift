import Testing
import Foundation
@testable import hiya

@MainActor
struct LogSheetViewModelTests {

    @Test func loadPopulatesExistingPeople() async throws {
        let repo = MockHiyaRepository()
        _ = try await repo.createPerson(name: "Alex")
        _ = try await repo.createPerson(name: "Bea")

        let vm = LogSheetViewModel(repo: repo)
        await vm.load()

        #expect(vm.allPeople.map(\.name).sorted() == ["Alex", "Bea"])
    }

    @Test func filteredPeopleMatchesSearchSubstring() async throws {
        let repo = MockHiyaRepository()
        _ = try await repo.createPerson(name: "Alex")
        _ = try await repo.createPerson(name: "Alice")
        _ = try await repo.createPerson(name: "Bob")
        let vm = LogSheetViewModel(repo: repo)
        await vm.load()

        vm.searchText = "Al"
        #expect(vm.filteredPeople.map(\.name).sorted() == ["Alex", "Alice"])
    }

    @Test func filteredPeopleIsCaseInsensitive() async throws {
        let repo = MockHiyaRepository()
        _ = try await repo.createPerson(name: "Alex")
        let vm = LogSheetViewModel(repo: repo)
        await vm.load()

        vm.searchText = "ale"
        #expect(vm.filteredPeople.map(\.name) == ["Alex"])
    }

    @Test func canSaveFalseWhenNoSelectionAndEmptySearch() async {
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo)
        await vm.load()
        #expect(vm.canSave == false)
    }

    @Test func canSaveTrueWhenPersonSelected() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        let vm = LogSheetViewModel(repo: repo)
        await vm.load()
        vm.select(alex)
        #expect(vm.canSave == true)
    }

    @Test func canSaveTrueWhenSearchHasNewName() async {
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo)
        await vm.load()
        vm.searchText = "  Charlie  "
        #expect(vm.canSave == true)
    }

    @Test func saveExistingPersonLogsConversation() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        let vm = LogSheetViewModel(repo: repo)
        await vm.load()
        vm.select(alex)
        vm.valence = .positive
        vm.note = "lunch"

        let success = await vm.save()

        #expect(success)
        #expect(repo.conversations.count == 1)
        #expect(repo.conversations[0].personId == alex.id)
        #expect(repo.conversations[0].valence == .positive)
        #expect(repo.conversations[0].note == "lunch")
    }

    @Test func saveNewPersonCreatesThenLogs() async {
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo)
        await vm.load()
        vm.searchText = "Charlie"

        let success = await vm.save()

        #expect(success)
        #expect(repo.people.count == 1)
        #expect(repo.people[0].name == "Charlie")
        #expect(repo.conversations.count == 1)
        #expect(repo.conversations[0].personId == repo.people[0].id)
    }

    @Test func saveTrimsWhitespaceFromNewName() async {
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo)
        await vm.load()
        vm.searchText = "  Charlie  "

        _ = await vm.save()

        #expect(repo.people.first?.name == "Charlie")
    }

    @Test func saveSetsErrorOnFailure() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        let vm = LogSheetViewModel(repo: repo)
        await vm.load()
        vm.select(alex)
        repo.errorToThrow = NSError(domain: "test", code: 1)

        let success = await vm.save()

        #expect(success == false)
        #expect(vm.errorMessage != nil)
    }
}
