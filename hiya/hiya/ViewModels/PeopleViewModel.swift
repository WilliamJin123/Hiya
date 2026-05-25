import Foundation
import Observation

/// One day in a person's consistency strip. Hue marks the era — amber for the
/// cold first meeting (and the empty days before it), lavender for the warm
/// catch-ups that follow — while the active/idle split marks whether a
/// conversation actually happened that day.
enum StripDay: Equatable {
    case coldActive   // the first (cold) meeting
    case coldIdle     // a day before the first meeting — no contact
    case warmActive   // a catch-up after the first meeting
    case warmIdle     // a quiet day after the first meeting — no contact
}

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
    /// oldest → newest. Hue marks the era (amber = the cold first meeting and
    /// the days leading up to it, lavender = every warm catch-up after);
    /// brightness marks whether a conversation actually happened that day.
    func activityStrip(for person: Person, now: Date = .now, calendar: Calendar = .current) -> [StripDay] {
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
    ) -> [StripDay] {
        let today = calendar.startOfDay(for: now)
        let mine = conversations.filter { $0.personId == personId }
        let loggedDays = Set(mine.map { calendar.startOfDay(for: $0.occurredAt) })
        // The cold first meeting visible in this window, if any: the earliest
        // day the person was still cold. Everything on/before it is the amber
        // era; everything after is the warm (lavender) catch-up era. With no
        // cold day in view, the whole window is the warm era.
        let firstMeetingDay = mine
            .filter { $0.wasColdAtTime }
            .map { calendar.startOfDay(for: $0.occurredAt) }
            .min()

        return (0..<days).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let active = loggedDays.contains(day)
            let coldEra = firstMeetingDay.map { day <= $0 } ?? false
            switch (coldEra, active) {
            case (true, true):   return .coldActive
            case (true, false):  return .coldIdle
            case (false, true):  return .warmActive
            case (false, false): return .warmIdle
            }
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
        await mutate { _ = try await self.repo.createPerson(name: trimmed, status: .warm, notes: notes, metCold: false, anonymous: false) }
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
