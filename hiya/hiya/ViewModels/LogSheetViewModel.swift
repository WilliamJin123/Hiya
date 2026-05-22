import Foundation
import Observation

@MainActor
@Observable
final class LogSheetViewModel {
    private let repo: HiyaRepository

    private(set) var allPeople: [Person] = []
    var searchText: String = ""
    private(set) var selectedPerson: Person?
    var valence: Conversation.Valence?
    var note: String = ""

    private(set) var isLoading: Bool = false
    private(set) var isSaving: Bool = false
    var errorMessage: String?

    var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var filteredPeople: [Person] {
        let q = trimmedSearch.lowercased()
        guard !q.isEmpty else { return allPeople }
        return allPeople.filter { $0.name.lowercased().contains(q) }
    }

    var canSave: Bool {
        if selectedPerson != nil { return true }
        return !trimmedSearch.isEmpty
    }

    init(repo: HiyaRepository) {
        self.repo = repo
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            allPeople = try await repo.listPeople()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ person: Person) {
        selectedPerson = person
        searchText = person.name
    }

    func clearSelection() {
        selectedPerson = nil
    }

    /// Returns true if save succeeded.
    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let personId: UUID
            if let selected = selectedPerson {
                personId = selected.id
            } else {
                let new = try await repo.createPerson(name: trimmedSearch)
                personId = new.id
            }
            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            try await repo.logConversation(
                personId: personId,
                valence: valence,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                improvementNote: nil
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
