import Foundation
import Observation

@MainActor
@Observable
final class HistoryViewModel {
    private let repo: HiyaRepository
    private(set) var sections: [DaySection] = []
    private(set) var isLoading: Bool = false
    var errorMessage: String?

    /// How far back history loads. 90 days is plenty for personal use without
    /// fetching a huge payload.
    private let lookbackDays = 90

    init(repo: HiyaRepository) {
        self.repo = repo
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let todayStart = Calendar.current.startOfDay(for: .now)
            let windowStart = Calendar.current.date(
                byAdding: .day,
                value: -lookbackDays,
                to: todayStart
            ) ?? todayStart
            let convs = try await repo.conversations(start: windowStart, end: todayStart)
            sections = Self.groupByDay(convs)
        } catch {
            errorMessage = error.localizedDescription
        }
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
