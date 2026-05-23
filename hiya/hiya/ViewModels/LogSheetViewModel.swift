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
    var improvementNote: String = ""
    private(set) var editing: LoggedConversation?

    private(set) var isLoading: Bool = false
    private(set) var isSaving: Bool = false
    private(set) var isDeleting: Bool = false
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
        if editing != nil { return true }
        if selectedPerson != nil { return true }
        return !trimmedSearch.isEmpty
    }

    init(
        repo: HiyaRepository,
        editing: LoggedConversation? = nil,
        preselectedPerson: Person? = nil
    ) {
        self.repo = repo
        self.editing = editing
        if let editing {
            searchText = editing.personName
            valence = editing.valence
            note = editing.note ?? ""
            improvementNote = editing.improvementNote ?? ""
        } else if let preselected = preselectedPerson {
            selectedPerson = preselected
            searchText = preselected.name
        }
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
            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedImprovement = improvementNote.trimmingCharacters(in: .whitespacesAndNewlines)
            let noteToSend = trimmedNote.isEmpty ? nil : trimmedNote
            let improvementToSend = trimmedImprovement.isEmpty ? nil : trimmedImprovement

            if let editing {
                try await repo.updateConversation(
                    id: editing.id,
                    valence: valence,
                    note: noteToSend,
                    improvementNote: improvementToSend
                )
            } else {
                let personId: UUID
                if let selected = selectedPerson {
                    personId = selected.id
                } else {
                    let new = try await repo.createPerson(name: trimmedSearch)
                    personId = new.id
                }
                try await repo.logConversation(
                    personId: personId,
                    valence: valence,
                    note: noteToSend,
                    improvementNote: improvementToSend
                )
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Returns true if delete succeeded. Only valid when editing.
    func delete() async -> Bool {
        guard let editing else { return false }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await repo.deleteConversation(id: editing.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
