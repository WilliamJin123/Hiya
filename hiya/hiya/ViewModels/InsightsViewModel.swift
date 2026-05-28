import Foundation

/// One day's worth of conversation volume, split by track.
struct DayBucket: Identifiable, Equatable, Sendable {
    let day: Date
    var cold: Int
    var warm: Int
    var id: Date { day }
}

@MainActor
@Observable
final class InsightsViewModel {
    private let repo: HiyaRepository

    var days: [DayBucket] = []
    var strangers = 0
    var becameRegulars = 0
    var valence: (positive: Int, neutral: Int, negative: Int) = (0, 0, 0)
    var lessons: [LoggedConversation] = []
    var isLoading = false
    /// First successful load landed — drives the SWR seam in the view.
    private(set) var hasLoaded = false
    var errorMessage: String?

    init(repo: HiyaRepository) {
        self.repo = repo
    }

    var conversionRate: Double {
        strangers == 0 ? 0 : Double(becameRegulars) / Double(strangers)
    }

    var hasAnyData: Bool {
        !lessons.isEmpty || strangers > 0 || valence != (0, 0, 0) ||
            days.contains { $0.cold > 0 || $0.warm > 0 }
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

            days = Self.dailyActivity(from: conv, now: .now)
            let c = Self.conversions(people: people, conversations: conv)
            strangers = c.strangers
            becameRegulars = c.became
            valence = Self.valenceBreakdown(conv)
            lessons = Self.lessons(from: conv)
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Pure computation (unit-tested)

    /// `dayCount` daily buckets ending today, oldest→newest, zero-filled, each
    /// split into cold/warm conversation counts. Default 56 days = the last 8 weeks.
    static func dailyActivity(
        from conv: [LoggedConversation],
        now: Date,
        dayCount: Int = 56,
        calendar: Calendar = .current
    ) -> [DayBucket] {
        let today = calendar.startOfDay(for: now)
        var buckets: [DayBucket] = (0..<dayCount).reversed().compactMap { i in
            calendar.date(byAdding: .day, value: -i, to: today)
                .map { DayBucket(day: $0, cold: 0, warm: 0) }
        }
        guard let earliest = buckets.first?.day else { return buckets }
        var indexByDay: [Date: Int] = [:]
        for (i, b) in buckets.enumerated() { indexByDay[b.day] = i }
        for c in conv where c.occurredAt >= earliest {
            let day = calendar.startOfDay(for: c.occurredAt)
            guard let idx = indexByDay[day] else { continue }
            if c.wasColdAtTime { buckets[idx].cold += 1 } else { buckets[idx].warm += 1 }
        }
        return buckets
    }

    /// strangers = distinct people met cold (≥1 cold-snapshot conversation);
    /// became = those I met *again* at least once (≥2 logged conversations).
    static func conversions(
        people: [Person],
        conversations conv: [LoggedConversation]
    ) -> (strangers: Int, became: Int) {
        // Only real, named people count as "strangers" in the conversion funnel —
        // nameless quick approaches (excluded from `people`) are cold attempts, not
        // relationship prospects, so they must not inflate the denominator.
        let realIds = Set(people.map(\.id))
        let coldPersonIds = Set(conv.filter { $0.wasColdAtTime }.map(\.personId)).intersection(realIds)
        // A stranger is "no longer a stranger" only once I've met them again —
        // not because their status auto-graduated to warm over time. So count it
        // by repeat contact: ≥2 logged conversations with that person.
        var convCounts: [UUID: Int] = [:]
        for c in conv where coldPersonIds.contains(c.personId) {
            convCounts[c.personId, default: 0] += 1
        }
        let became = coldPersonIds.filter { (convCounts[$0] ?? 0) >= 2 }.count
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
