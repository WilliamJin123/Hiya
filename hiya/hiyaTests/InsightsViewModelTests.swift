import Testing
import Foundation
@testable import hiya

@MainActor
struct InsightsViewModelTests {

    private func conv(
        personId: UUID = UUID(),
        daysAgo: Int = 0,
        valence: Conversation.Valence? = nil,
        improvementNote: String? = nil,
        wasCold: Bool = true
    ) -> LoggedConversation {
        LoggedConversation(
            id: UUID(),
            personId: personId,
            personName: "P",
            occurredAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
            valence: valence,
            note: nil,
            improvementNote: improvementNote,
            wasColdAtTime: wasCold
        )
    }

    @Test func weeklyActivity_bucketsByWeekAndTrack() async throws {
        let now = Date.now
        // Shift by whole weeks so bucket placement is independent of weekday.
        let convs = [
            conv(daysAgo: 0, wasCold: true),    // this week, cold
            conv(daysAgo: 7, wasCold: false),   // 1 week ago, warm
            conv(daysAgo: 21, wasCold: true),   // 3 weeks ago, cold
        ]

        let weeks = InsightsViewModel.weeklyActivity(from: convs, now: now)

        #expect(weeks.count == 8)
        #expect(weeks.first!.weekStart < weeks.last!.weekStart, "oldest first")
        #expect(weeks.last?.cold == 1, "this week has the cold log")
        #expect(weeks[weeks.count - 2].warm == 1, "one week ago has the warm log")
        // Totals across all buckets.
        #expect(weeks.reduce(0) { $0 + $1.cold } == 2)
        #expect(weeks.reduce(0) { $0 + $1.warm } == 1)
    }

    @Test func conversions_countsStrangersAndGraduates() async throws {
        let graduate = UUID()      // warm now, met cold
        let stillStranger = UUID() // cold now, met cold
        let bornWarm = UUID()      // warm now, never a cold conv

        let people = [
            Person(id: graduate, ownerId: UUID(), name: "G", status: .warm, statusChangedAt: .now, createdAt: .now, lastLoggedAt: .now),
            Person(id: stillStranger, ownerId: UUID(), name: "S", status: .cold, statusChangedAt: nil, createdAt: .now, lastLoggedAt: .now),
            Person(id: bornWarm, ownerId: UUID(), name: "B", status: .warm, statusChangedAt: .now, createdAt: .now, lastLoggedAt: .now),
        ]
        let convs = [
            conv(personId: graduate, wasCold: true),
            conv(personId: stillStranger, wasCold: true),
            conv(personId: bornWarm, wasCold: false),
        ]

        let result = InsightsViewModel.conversions(people: people, conversations: convs)

        #expect(result.strangers == 2, "graduate + stillStranger were met cold")
        #expect(result.became == 1, "only the graduate is now warm")
    }

    @Test func valenceBreakdown_talliesAndIgnoresNil() async throws {
        let convs = [
            conv(valence: .positive), conv(valence: .positive),
            conv(valence: .neutral),
            conv(valence: .negative),
            conv(valence: nil),
        ]

        let v = InsightsViewModel.valenceBreakdown(convs)

        #expect(v.positive == 2)
        #expect(v.neutral == 1)
        #expect(v.negative == 1)
    }

    @Test func lessons_onlyNonEmptyNewestFirst() async throws {
        let convs = [
            conv(daysAgo: 5, improvementNote: "older lesson"),
            conv(daysAgo: 1, improvementNote: "newer lesson"),
            conv(daysAgo: 2, improvementNote: "   "),  // blank → excluded
            conv(daysAgo: 3, improvementNote: nil),     // nil → excluded
        ]

        let lessons = InsightsViewModel.lessons(from: convs)

        #expect(lessons.map(\.improvementNote) == ["newer lesson", "older lesson"])
    }
}
