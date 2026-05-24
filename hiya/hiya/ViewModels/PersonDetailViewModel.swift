import Foundation

@MainActor
@Observable
final class PersonDetailViewModel {
    let repo: HiyaRepository
    let person: Person

    var notes: [PersonNote] = []
    var errorMessage: String?
    var isWorking = false

    init(repo: HiyaRepository, person: Person) {
        self.repo = repo
        self.person = person
    }

    func load() async {
        do {
            notes = try await repo.personNotes(personId: person.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func add(_ rawBody: String) async {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await repo.addPersonNote(personId: person.id, body: body)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func edit(_ note: PersonNote, to rawBody: String) async {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repo.updatePersonNote(id: note.id, body: body)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ note: PersonNote) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await repo.deletePersonNote(id: note.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
