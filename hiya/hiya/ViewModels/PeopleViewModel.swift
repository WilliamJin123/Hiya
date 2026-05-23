import Foundation
import Observation

@MainActor
@Observable
final class PeopleViewModel {
    private let repo: HiyaRepository
    private(set) var people: [Person] = []
    private(set) var isLoading: Bool = false
    var errorMessage: String?

    init(repo: HiyaRepository) {
        self.repo = repo
    }

    func people(in mode: PersonStatus) -> [Person] {
        people.filter { $0.status == mode }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            people = try await repo.listPeople()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func promote(_ id: UUID) async {
        await mutate { try await repo.promotePerson(id: id) }
    }

    func demote(_ id: UUID) async {
        await mutate { try await repo.demotePerson(id: id) }
    }

    func delete(_ id: UUID) async {
        await mutate { try await repo.deletePerson(id: id) }
    }

    private func mutate(_ action: () async throws -> Void) async {
        errorMessage = nil
        do {
            try await action()
            people = try await repo.listPeople()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
