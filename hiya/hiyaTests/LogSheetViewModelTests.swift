import Testing
import Foundation
@testable import hiya

@MainActor
struct LogSheetViewModelTests {

    @Test func save_createsOneLogPerTarget_sharingOccurredAt() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        let vm = LogSheetViewModel(repo: repo)
        await vm.load()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        vm.occurredAt = when
        vm.addExisting(alex)
        vm.addNew("Bea")

        let ok = await vm.save()

        #expect(ok)
        #expect(repo.conversations.count == 2, "one log per target")
        #expect(repo.conversations.allSatisfy { abs($0.occurredAt.timeIntervalSince(when)) < 0.001 })
        #expect(repo.people.contains { $0.name == "Bea" }, "a new target is created as a person")
    }

    @Test func addExisting_ignoresDuplicates() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        let vm = LogSheetViewModel(repo: repo)
        await vm.load()
        vm.addExisting(alex)
        vm.addExisting(alex)
        #expect(vm.targets.count == 1)
    }

    @Test func save_seedsNewPersonNoteFromConversationNote() async throws {
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo)
        await vm.load()
        vm.addNew("Bea")
        vm.note = "from work"

        let ok = await vm.save()

        #expect(ok)
        let bea = repo.people.first { $0.name == "Bea" }!
        #expect(bea.notes == "from work", "the first note seeds the new person's profile note")
    }

    @Test func canAddTypedName_trueEvenWhenNameExists() async throws {
        let repo = MockHiyaRepository()
        _ = try await repo.createPerson(name: "Alex")
        let vm = LogSheetViewModel(repo: repo, creationMode: .warm)
        await vm.load()
        vm.searchText = "Alex"
        #expect(vm.canAddTypedName, "can still add a distinct same-named person")
        #expect(vm.filteredPeople.contains { $0.name == "Alex" }, "existing match is shown to pick in warm mode")
    }

    @Test func coldMode_hidesExistingPeopleSuggestions() async throws {
        let repo = MockHiyaRepository()
        _ = try await repo.createPerson(name: "Alex")
        let vm = LogSheetViewModel(repo: repo, creationMode: .cold)
        await vm.load()
        vm.searchText = "Al"
        #expect(vm.filteredPeople.isEmpty, "cold approaches never suggest existing people")
    }

    @Test func warmMode_createsNewPersonAsWarm() async throws {
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo, creationMode: .warm)
        await vm.load()
        vm.addNew("Old Friend")
        _ = await vm.save()
        let p = repo.people.first { $0.name == "Old Friend" }!
        #expect(p.status == .warm, "new people logged from Catch-ups are known → warm")
    }

    @Test func coldMode_createsNewPersonAsCold() async throws {
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo, creationMode: .cold)
        await vm.load()
        vm.addNew("Stranger")
        _ = await vm.save()
        let p = repo.people.first { $0.name == "Stranger" }!
        #expect(p.status == .cold)
    }

    @Test func save_foldsTypedNameIntoTarget() async throws {
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo)
        await vm.load()
        vm.searchText = "Cara"   // typed but not explicitly added
        let ok = await vm.save()
        #expect(ok)
        #expect(repo.conversations.count == 1)
        #expect(repo.people.contains { $0.name == "Cara" })
    }

    @Test func editing_initializesOccurredAtFromEntry() async {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = LoggedConversation(
            id: UUID(), personId: UUID(), personName: "Alex",
            occurredAt: when, valence: nil, note: nil, improvementNote: nil
        )
        let vm = LogSheetViewModel(repo: MockHiyaRepository(), editing: entry)
        #expect(abs(vm.occurredAt.timeIntervalSince(when)) < 0.001)
    }

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
        let vm = LogSheetViewModel(repo: repo, creationMode: .warm)
        await vm.load()

        vm.searchText = "Al"
        #expect(vm.filteredPeople.map(\.name).sorted() == ["Alex", "Alice"])
    }

    @Test func filteredPeopleIsCaseInsensitive() async throws {
        let repo = MockHiyaRepository()
        _ = try await repo.createPerson(name: "Alex")
        let vm = LogSheetViewModel(repo: repo, creationMode: .warm)
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
        vm.addExisting(alex)
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
        vm.addExisting(alex)
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
        vm.addExisting(alex)
        repo.errorToThrow = NSError(domain: "test", code: 1)

        let success = await vm.save()

        #expect(success == false)
        #expect(vm.errorMessage != nil)
    }

    @Test func init_withPreselectedPerson_seedsTarget() async {
        let person = Person(
            id: UUID(),
            ownerId: UUID(),
            name: "Alex",
            status: .warm,
            statusChangedAt: .now,
            createdAt: .now,
            lastLoggedAt: .now
        )
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo, preselectedPerson: person)

        #expect(vm.targets.count == 1)
        #expect(vm.targets.first?.id == LogTarget.existing(person).id)
        #expect(vm.canSave == true)
        #expect(vm.editing == nil)
    }

    @Test func init_withEditing_prefillsFields() async {
        let logged = LoggedConversation(
            id: UUID(),
            personId: UUID(),
            personName: "Alex",
            occurredAt: .now,
            valence: .positive,
            note: "lunch",
            improvementNote: "rushed"
        )
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo, editing: logged)

        #expect(vm.searchText == "Alex")
        #expect(vm.valence == .positive)
        #expect(vm.note == "lunch")
        #expect(vm.improvementNote == "rushed")
        #expect(vm.editing != nil)
    }

    @Test func canSave_isTrueWhenEditing_evenWithoutChanges() async {
        let logged = LoggedConversation(
            id: UUID(), personId: UUID(), personName: "Alex",
            occurredAt: .now, valence: nil, note: nil, improvementNote: nil
        )
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo, editing: logged)
        #expect(vm.canSave == true)
    }

    @Test func save_inEditMode_callsUpdateConversationNotInsert() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        try await repo.logConversation(personId: alex.id, valence: .neutral, note: "first", improvementNote: nil)
        let original = repo.conversations[0]
        let logged = LoggedConversation(
            id: original.id, personId: alex.id, personName: "Alex",
            occurredAt: original.occurredAt, valence: .neutral, note: "first", improvementNote: nil
        )
        let vm = LogSheetViewModel(repo: repo, editing: logged)
        vm.note = "updated"

        let success = await vm.save()

        #expect(success)
        #expect(repo.conversations.count == 1)
        #expect(repo.conversations[0].note == "updated")
    }

    @Test func save_inCreateMode_passesImprovementNote() async {
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo)
        vm.searchText = "Bea"
        vm.improvementNote = "be earlier"

        _ = await vm.save()

        #expect(repo.conversations.count == 1)
        #expect(repo.conversations[0].improvementNote == "be earlier")
    }

    @Test func save_inEditMode_persistsImprovementNote() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)
        let original = repo.conversations[0]
        let logged = LoggedConversation(
            id: original.id, personId: alex.id, personName: "Alex",
            occurredAt: original.occurredAt, valence: nil, note: nil, improvementNote: nil
        )
        let vm = LogSheetViewModel(repo: repo, editing: logged)
        vm.improvementNote = "more present"

        _ = await vm.save()

        #expect(repo.conversations[0].improvementNote == "more present")
    }

    @Test func delete_returnsTrue_andRemovesConversation() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)
        let original = repo.conversations[0]
        let logged = LoggedConversation(
            id: original.id, personId: alex.id, personName: "Alex",
            occurredAt: original.occurredAt, valence: nil, note: nil, improvementNote: nil
        )
        let vm = LogSheetViewModel(repo: repo, editing: logged)

        let success = await vm.delete()

        #expect(success)
        #expect(repo.conversations.isEmpty)
    }

    @Test func delete_setsErrorOnFailure_returnsFalse() async throws {
        let repo = MockHiyaRepository()
        let alex = try await repo.createPerson(name: "Alex")
        try await repo.logConversation(personId: alex.id, valence: nil, note: nil, improvementNote: nil)
        let original = repo.conversations[0]
        let logged = LoggedConversation(
            id: original.id, personId: alex.id, personName: "Alex",
            occurredAt: original.occurredAt, valence: nil, note: nil, improvementNote: nil
        )
        let vm = LogSheetViewModel(repo: repo, editing: logged)
        repo.errorToThrow = NSError(domain: "test", code: 1)

        let success = await vm.delete()

        #expect(success == false)
        #expect(vm.errorMessage != nil)
    }

    // MARK: - Choosable origin (met_cold) + backdating

    @Test func newColdApproach_createsMetColdPerson() async throws {
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo, creationMode: .cold)
        await vm.load()
        vm.searchText = "Angie"
        #expect(vm.origin == .cold)

        let ok = await vm.save()
        #expect(ok)
        let angie = repo.people.first { $0.name == "Angie" }
        #expect(angie?.metCold == true)
        #expect(angie?.status == .cold)
    }

    @Test func alreadyKnew_createsWarmNotMetCold() async throws {
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo, creationMode: .cold)
        await vm.load()
        vm.searchText = "Old Friend"
        vm.origin = .warm

        let ok = await vm.save()
        #expect(ok)
        let friend = repo.people.first { $0.name == "Old Friend" }
        #expect(friend?.metCold == false)
        #expect(friend?.status == .warm)
    }

    @Test func backdatedFirstMeeting_isCold() async throws {
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo, creationMode: .cold)
        await vm.load()
        vm.searchText = "Angie"
        vm.occurredAt = Calendar.current.date(byAdding: .day, value: -7, to: .now)!

        _ = await vm.save()
        #expect(repo.conversations.first?.wasColdAtTime == true)
    }
}
