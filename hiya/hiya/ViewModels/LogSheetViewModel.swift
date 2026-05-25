import Foundation
import Observation

@MainActor
@Observable
final class LogSheetViewModel {
    private let repo: HiyaRepository

    private(set) var allPeople: [Person] = []
    var searchText: String = ""
    private(set) var targets: [LogTarget] = []
    var valence: Conversation.Valence?
    var note: String = ""
    var improvementNote: String = ""
    var location: String = ""
    var occurredAt: Date = .now
    /// How many nameless quick approaches to log in one save (e.g. a session of
    /// similar attempts). Only used on the quick-approach path.
    var quickApproachCount: Int = 1
    private(set) var editing: LoggedConversation?

    /// How a *new* person is created: `.cold` = a cold approach (a brand-new
    /// stranger; no existing-people suggestions; saved cold + `met_cold`), `.warm`
    /// = someone you already knew (suggestions shown; saved warm, not met_cold).
    /// Editable in the sheet when a new person is about to be created.
    var origin: PersonStatus

    private(set) var isLoading: Bool = false
    private(set) var isSaving: Bool = false
    private(set) var isDeleting: Bool = false
    var errorMessage: String?

    var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var filteredPeople: [Person] {
        // Cold approaches are always new strangers — never suggest existing people.
        guard origin == .warm else { return [] }
        let chosen = Set(targets.compactMap { target -> UUID? in
            if case .existing(let p) = target { return p.id }
            return nil
        })
        let available = allPeople.filter { !chosen.contains($0.id) }
        let q = trimmedSearch.lowercased()
        guard !q.isEmpty else { return available }
        return available.filter { $0.name.lowercased().contains(q) }
    }

    /// Whether to offer a "create new person" row. Available whenever there's
    /// typed text — even if the name matches an existing person, so you can add
    /// a *distinct* same-named person (differentiated by note). Existing matches
    /// are listed above the row so you can pick one instead of duplicating.
    var canAddTypedName: Bool {
        !trimmedSearch.isEmpty
    }

    /// A nameless cold approach: Approaches mode with nobody named or selected.
    /// Saving logs `quickApproachCount` anonymous quick approaches.
    var isQuickApproach: Bool {
        editing == nil && origin == .cold && targets.isEmpty && trimmedSearch.isEmpty
    }

    var canSave: Bool {
        if editing != nil { return true }
        return isQuickApproach || !targets.isEmpty || !trimmedSearch.isEmpty
    }

    init(
        repo: HiyaRepository,
        editing: LoggedConversation? = nil,
        preselectedPerson: Person? = nil,
        creationMode: PersonStatus = .cold
    ) {
        self.repo = repo
        self.editing = editing
        self.origin = creationMode
        if let editing {
            searchText = editing.personName
            valence = editing.valence
            note = editing.note ?? ""
            improvementNote = editing.improvementNote ?? ""
            location = editing.location ?? ""
            occurredAt = editing.occurredAt
        } else if let preselected = preselectedPerson {
            targets = [.existing(preselected)]
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

    func addExisting(_ person: Person) {
        let target = LogTarget.existing(person)
        guard !targets.contains(where: { $0.id == target.id }) else { return }
        targets.append(target)
        searchText = ""
    }

    func addNew(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let target = LogTarget.new(name)
        guard !targets.contains(where: { $0.id == target.id }) else { return }
        targets.append(target)
        searchText = ""
    }

    func removeTarget(_ target: LogTarget) {
        targets.removeAll { $0.id == target.id }
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
            let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
            let locationToSend = trimmedLocation.isEmpty ? nil : trimmedLocation

            if let editing {
                try await repo.updateConversation(
                    id: editing.id,
                    occurredAt: occurredAt,
                    valence: valence,
                    note: noteToSend,
                    improvementNote: improvementToSend,
                    location: locationToSend
                )
            } else {
                // Fold any leftover typed text into a target so the fast
                // "type one name and save" path still works.
                var finalTargets = targets
                let pending = trimmedSearch
                if !pending.isEmpty {
                    // In warm mode, fold a typed name onto an existing match; in
                    // cold mode it's always a brand-new stranger.
                    if origin == .warm,
                       let match = allPeople.first(where: { $0.name.lowercased() == pending.lowercased() }) {
                        let t = LogTarget.existing(match)
                        if !finalTargets.contains(where: { $0.id == t.id }) { finalTargets.append(t) }
                    } else {
                        let t = LogTarget.new(pending)
                        if !finalTargets.contains(where: { $0.id == t.id }) { finalTargets.append(t) }
                    }
                }
                if finalTargets.isEmpty {
                    // No one named or selected in Approaches mode → log nameless
                    // quick approaches that still count toward the cold tally.
                    guard origin == .cold else { return false }
                    try await repo.logQuickApproach(
                        count: quickApproachCount,
                        occurredAt: occurredAt,
                        valence: valence,
                        note: noteToSend,
                        location: locationToSend
                    )
                    return true
                }

                // Resolve each target to a person id (creating new people).
                var personIds: [UUID] = []
                for target in finalTargets {
                    switch target {
                    case .existing(let person):
                        personIds.append(person.id)
                    case .new(let name):
                        // The first note about a person seeds their profile note,
                        // which differentiates same-named people later. New people
                        // take the log's track: cold = just-met stranger, warm =
                        // someone you already knew.
                        let created = try await repo.createPerson(name: name, status: origin, notes: noteToSend, metCold: origin == .cold, anonymous: false)
                        personIds.append(created.id)
                    }
                }

                // One log per person, all sharing the same time/valence/notes.
                for personId in personIds {
                    try await repo.logConversation(
                        personId: personId,
                        occurredAt: occurredAt,
                        valence: valence,
                        note: noteToSend,
                        improvementNote: improvementToSend,
                        location: locationToSend
                    )
                }
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

enum LogTarget: Identifiable, Equatable {
    case existing(Person)
    case new(String)

    var id: String {
        switch self {
        case .existing(let p): "existing-\(p.id.uuidString)"
        case .new(let name):   "new-\(name.lowercased())"
        }
    }

    var displayName: String {
        switch self {
        case .existing(let p): p.name
        case .new(let name):   name
        }
    }

    /// Short differentiator shown on the chip (e.g. "climbing gym"). New
    /// people don't have one yet — their note is seeded on save.
    var note: String? {
        switch self {
        case .existing(let p): (p.notes?.isEmpty == false) ? p.notes : nil
        case .new:             nil
        }
    }
}
