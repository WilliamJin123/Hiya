import Foundation
import Observation

@MainActor
@Observable
final class PeopleViewModel {
    private let repo: HiyaRepository
    private(set) var people: [Person] = []
    private(set) var recentConversations: [LoggedConversation] = []
    private(set) var isLoading: Bool = false
    var errorMessage: String?

    /// Number of days shown in a person's consistency strip.
    static let stripDays = 14

    init(repo: HiyaRepository) {
        self.repo = repo
    }

    var justMet: [Person] {
        people.filter { $0.status == .cold }
            .sorted { $0.lastLoggedAt > $1.lastLoggedAt }
    }

    var recurring: [Person] {
        people.filter { $0.status == .warm }
            .sorted { $0.lastLoggedAt > $1.lastLoggedAt }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let (start, end) = Self.stripWindow()
            async let peopleResult = repo.listPeople()
            async let convResult = repo.conversations(start: start, end: end)
            people = try await peopleResult
            recentConversations = try await convResult
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Per-day contact history for a person over the last `stripDays`, ordered
    /// oldest → newest. `true` means at least one logged conversation that day.
    func activityStrip(for person: Person, now: Date = .now, calendar: Calendar = .current) -> [Bool] {
        Self.activityStrip(
            personId: person.id,
            conversations: recentConversations,
            days: Self.stripDays,
            now: now,
            calendar: calendar
        )
    }

    static func activityStrip(
        personId: UUID,
        conversations: [LoggedConversation],
        days: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Bool] {
        let today = calendar.startOfDay(for: now)
        let loggedDays = Set(
            conversations
                .filter { $0.personId == personId }
                .map { calendar.startOfDay(for: $0.occurredAt) }
        )
        return (0..<days).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return loggedDays.contains(day)
        }
    }

    static func stripWindow(now: Date = .now, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let todayStart = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(stripDays - 1), to: todayStart) ?? todayStart
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        return (start, end)
    }

    func delete(_ id: UUID) async {
        await mutate { try await self.repo.deletePerson(id: id) }
    }

    /// Add someone you already know, directly as a Catch-up (warm) — no logged
    /// conversation required. An optional note differentiates same-named people.
    func addPerson(name: String, notes: String? = nil) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await mutate { _ = try await self.repo.createPerson(name: trimmed, status: .warm, notes: notes) }
    }

    func updateNotes(id: UUID, notes: String?) async {
        await mutate { try await self.repo.updatePersonNotes(id: id, notes: notes) }
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
