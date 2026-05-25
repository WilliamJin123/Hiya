import Foundation

/// One week's worth of conversation volume, split by track.
struct WeekBucket: Identifiable, Equatable, Sendable {
    let weekStart: Date
    var cold: Int
    var warm: Int
    var id: Date { weekStart }
}

@MainActor
@Observable
final class InsightsViewModel {
    private let repo: HiyaRepository

    var weeks: [WeekBucket] = []
    var strangers = 0
    var becameRegulars = 0
    var valence: (positive: Int, neutral: Int, negative: Int) = (0, 0, 0)
    var lessons: [LoggedConversation] = []
    var isLoading = false
    var errorMessage: String?

    init(repo: HiyaRepository) {
        self.repo = repo
    }

    var conversionRate: Double {
        strangers == 0 ? 0 : Double(becameRegulars) / Double(strangers)
    }

    var hasAnyData: Bool {
        !lessons.isEmpty || strangers > 0 || valence != (0, 0, 0) ||
            weeks.contains { $0.cold > 0 || $0.warm > 0 }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let todayStart = Calendar.current.startOfDay(for: .now)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? .now
            async let convResult = repo.conversations(start: .distantPast, end: end)
            async let peopleResult = repo.listPeople()
            let conv = try await convResult
            let people = try await peopleResult

            weeks = Self.weeklyActivity(from: conv, now: .now)
            let c = Self.conversions(people: people, conversations: conv)
            strangers = c.strangers
            becameRegulars = c.became
            valence = Self.valenceBreakdown(conv)
            lessons = Self.lessons(from: conv)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Pure computation (unit-tested)

    /// `weekCount` buckets ending with the week containing `now`, oldest→newest,
    /// zero-filled, each split into cold/warm conversation counts.
    static func weeklyActivity(
        from conv: [LoggedConversation],
        now: Date,
        weekCount: Int = 8,
        calendar: Calendar = .current
    ) -> [WeekBucket] {
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        var buckets: [WeekBucket] = (0..<weekCount).reversed().compactMap { i in
            calendar.date(byAdding: .weekOfYear, value: -i, to: thisWeekStart)
                .map { WeekBucket(weekStart: $0, cold: 0, warm: 0) }
        }
        guard let earliest = buckets.first?.weekStart else { return buckets }
        for c in conv where c.occurredAt >= earliest {
            guard let ws = calendar.dateInterval(of: .weekOfYear, for: c.occurredAt)?.start,
                  let idx = buckets.firstIndex(where: { $0.weekStart == ws }) else { continue }
            if c.wasColdAtTime { buckets[idx].cold += 1 } else { buckets[idx].warm += 1 }
        }
        return buckets
    }

    /// strangers = distinct people met cold (≥1 cold-snapshot conversation);
    /// became = those who are now warm.
    static func conversions(
        people: [Person],
        conversations conv: [LoggedConversation]
    ) -> (strangers: Int, became: Int) {
        // Only real, named people count as "strangers" in the conversion funnel —
        // nameless quick approaches (excluded from `people`) are cold attempts, not
        // relationship prospects, so they must not inflate the denominator.
        let realIds = Set(people.map(\.id))
        let coldPersonIds = Set(conv.filter { $0.wasColdAtTime }.map(\.personId)).intersection(realIds)
        let warmIds = Set(people.filter { $0.status == .warm }.map(\.id))
        let became = coldPersonIds.filter { warmIds.contains($0) }.count
        return (coldPersonIds.count, became)
    }

    static func valenceBreakdown(
        _ conv: [LoggedConversation]
    ) -> (positive: Int, neutral: Int, negative: Int) {
        var positive = 0, neutral = 0, negative = 0
        for c in conv {
            switch c.valence {
            case .positive: positive += 1
            case .neutral:  neutral += 1
            case .negative: negative += 1
            case .none:     break
            }
        }
        return (positive, neutral, negative)
    }

    static func lessons(from conv: [LoggedConversation]) -> [LoggedConversation] {
        conv.filter { ($0.improvementNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) }
            .sorted { $0.occurredAt > $1.occurredAt }
    }
}
