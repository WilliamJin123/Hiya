import Foundation

@MainActor
@Observable
final class PersonDetailViewModel {
    let repo: HiyaRepository
    let person: Person

    var notes: [PersonNote] = []
    var interactions: [LoggedConversation] = []
    var errorMessage: String?
    var isWorking = false

    init(repo: HiyaRepository, person: Person) {
        self.repo = repo
        self.person = person
    }

    func load() async {
        do {
            async let notesResult = repo.personNotes(personId: person.id)
            async let interactionsResult = repo.personConversations(personId: person.id)
            notes = try await notesResult
            interactions = try await interactionsResult
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Add a note. Optimistic: the repo returns the created row, which we
    /// splice in locally — no need for a full `load()` round-trip after.
    /// Interactions don't change on note mutations, so they don't reload either.
    func add(_ rawBody: String) async {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let created = try await repo.addPersonNote(personId: person.id, body: body)
            notes.insert(created, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Edit a note. Optimistic: we mutate the local copy on success.
    func edit(_ note: PersonNote, to rawBody: String) async {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repo.updatePersonNote(id: note.id, body: body)
            if let idx = notes.firstIndex(where: { $0.id == note.id }) {
                notes[idx].body = body
                notes[idx].updatedAt = .now
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete a note. Optimistic: drop locally after the server confirms.
    func delete(_ note: PersonNote) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await repo.deletePersonNote(id: note.id)
            notes.removeAll { $0.id == note.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
