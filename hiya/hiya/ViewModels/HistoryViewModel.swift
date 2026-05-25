import Foundation
import Observation

@MainActor
@Observable
final class HistoryViewModel {
    private let repo: HiyaRepository
    private(set) var sections: [DaySection] = []
    private(set) var isLoading: Bool = false
    var errorMessage: String?

    /// How far back history loads. A year covers monthly review patterns;
    /// calendar nav past this point will show empty months.
    private let lookbackDays = 365

    init(repo: HiyaRepository) {
        self.repo = repo
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let todayStart = Calendar.current.startOfDay(for: .now)
            // Include today: window runs through the end of today (start of tomorrow).
            let windowEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
            let windowStart = Calendar.current.date(
                byAdding: .day,
                value: -lookbackDays,
                to: todayStart
            ) ?? todayStart
            let convs = try await repo.conversations(start: windowStart, end: windowEnd)
            sections = Self.groupByDay(convs)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var allEntries: [LoggedConversation] { sections.flatMap(\.entries) }

    func searchResults(query: String) -> [LoggedConversation] {
        Self.search(allEntries, query: query)
    }

    static func search(_ logs: [LoggedConversation], query: String) -> [LoggedConversation] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return logs
            .filter {
                ($0.location?.lowercased().contains(q) ?? false) ||
                ($0.note?.lowercased().contains(q) ?? false) ||
                $0.personName.lowercased().contains(q)
            }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    static func groupByDay(
        _ logs: [LoggedConversation],
        calendar: Calendar = .current
    ) -> [DaySection] {
        let grouped = Dictionary(grouping: logs) { calendar.startOfDay(for: $0.occurredAt) }
        return grouped
            .map { day, entries in
                DaySection(
                    date: day,
                    entries: entries.sorted { $0.occurredAt > $1.occurredAt }
                )
            }
            .sorted { $0.date > $1.date }
    }
}

struct DaySection: Identifiable, Sendable, Equatable {
    let date: Date
    let entries: [LoggedConversation]

    var id: Date { date }
    var totalCount: Int { entries.count }
    var uniquePeopleCount: Int { Set(entries.map(\.personId)).count }
    var coldCount: Int { entries.filter(\.wasColdAtTime).count }
    var hadCold: Bool { coldCount > 0 }
}
