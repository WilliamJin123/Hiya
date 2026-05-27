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

    @Test func dailyActivity_bucketsByDayAndTrack() async throws {
        let now = Date.now
        let convs = [
            conv(daysAgo: 0, wasCold: true),    // today, cold
            conv(daysAgo: 0, wasCold: true),    // today, another cold
            conv(daysAgo: 7, wasCold: false),   // a week ago, warm
            conv(daysAgo: 21, wasCold: true),   // three weeks ago, cold
            conv(daysAgo: 200, wasCold: true),  // outside the 8-week window
        ]

        let days = InsightsViewModel.dailyActivity(from: convs, now: now)

        #expect(days.count == 56, "8 weeks of daily buckets")
        #expect(days.first!.day < days.last!.day, "oldest first")
        #expect(days.last?.cold == 2, "today has both cold logs")
        #expect(days.last?.warm == 0)
        #expect(days[days.count - 8].warm == 1, "seven days ago has the warm log")
        // Totals: the 200-days-ago log is excluded.
        #expect(days.reduce(0) { $0 + $1.cold } == 3)
        #expect(days.reduce(0) { $0 + $1.warm } == 1)
    }

    @Test func conversions_countsStrangersAndRepeatMeetings() async throws {
        let metAgain = UUID()    // met cold, then met again → no longer a stranger
        let oneAndDone = UUID()  // met cold once, never again → still a stranger
        let bornWarm = UUID()    // never a cold conv → not a stranger

        // Statuses are deliberately "wrong" relative to the answer: metAgain is
        // still .cold and oneAndDone auto-graduated to .warm. The result must
        // ignore the status flag and key off repeat contact alone.
        let people = [
            Person(id: metAgain, ownerId: UUID(), name: "A", status: .cold, statusChangedAt: nil, createdAt: .now, lastLoggedAt: .now),
            Person(id: oneAndDone, ownerId: UUID(), name: "B", status: .warm, statusChangedAt: .now, createdAt: .now, lastLoggedAt: .now),
            Person(id: bornWarm, ownerId: UUID(), name: "C", status: .warm, statusChangedAt: .now, createdAt: .now, lastLoggedAt: .now),
        ]
        let convs = [
            conv(personId: metAgain, daysAgo: 10, wasCold: true),
            conv(personId: metAgain, daysAgo: 3, wasCold: true),   // met again
            conv(personId: oneAndDone, daysAgo: 5, wasCold: true),
            conv(personId: bornWarm, daysAgo: 1, wasCold: false),
        ]

        let result = InsightsViewModel.conversions(people: people, conversations: convs)

        #expect(result.strangers == 2, "metAgain + oneAndDone were met cold")
        #expect(result.became == 1, "only metAgain has a repeat meeting; status flag is ignored")
    }

    @Test func conversions_excludeNamelessQuickApproaches() {
        let real = UUID()
        let anonA = UUID()
        let anonB = UUID()
        // Anonymous quick-approach people are excluded from listPeople, so they
        // never appear in `people` — only the real named person does.
        let people = [
            Person(id: real, ownerId: UUID(), name: "Real", status: .warm, statusChangedAt: .now, createdAt: .now, lastLoggedAt: .now),
        ]
        let convs = [
            conv(personId: real, daysAgo: 9, wasCold: true),
            conv(personId: real, daysAgo: 2, wasCold: false),  // met again
            conv(personId: anonA, wasCold: true),
            conv(personId: anonB, wasCold: true),
        ]

        let result = InsightsViewModel.conversions(people: people, conversations: convs)

        #expect(result.strangers == 1, "nameless quick approaches don't count as strangers")
        #expect(result.became == 1, "the real person was met again")
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
