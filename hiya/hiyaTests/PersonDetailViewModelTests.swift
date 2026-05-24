import Testing
import Foundation
@testable import hiya

@MainActor
struct PersonDetailViewModelTests {

    @Test func add_appendsAndReloads() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let vm = PersonDetailViewModel(repo: repo, person: p)

        await vm.add("climbing gym")

        #expect(vm.notes.count == 1)
        #expect(vm.notes.first?.body == "climbing gym")
    }

    @Test func add_ignoresBlank() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let vm = PersonDetailViewModel(repo: repo, person: p)

        await vm.add("   ")

        #expect(vm.notes.isEmpty)
    }

    @Test func edit_updatesBodyAndMarksEdited() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let vm = PersonDetailViewModel(repo: repo, person: p)
        await vm.add("first")
        let note = vm.notes.first!

        await vm.edit(note, to: "first edited")

        #expect(vm.notes.first?.body == "first edited")
        #expect(vm.notes.first?.wasEdited == true)
    }

    @Test func delete_removes() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let vm = PersonDetailViewModel(repo: repo, person: p)
        await vm.add("x")
        let note = vm.notes.first!

        await vm.delete(note)

        #expect(vm.notes.isEmpty)
    }

    @Test func load_showsSeededNote() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex", notes: "seed")
        let vm = PersonDetailViewModel(repo: repo, person: p)

        await vm.load()

        #expect(vm.notes.map(\.body) == ["seed"])
    }
}
