# Insights Screen — Implementation Plan

> Execution checklist (inline, autonomous). Spec: `docs/superpowers/specs/2026-05-24-insights-screen-design.md`. Depends on the tab nav from the Settings plan.

**Goal:** A read-only Insights tab with four cards (activity over time, cold→warm conversions, valence breakdown, lessons feed), computed client-side via pure statics.

## File map
- Create `hiya/hiya/ViewModels/InsightsViewModel.swift` — pure statics + async `load()`.
- Create `hiya/hiya/Views/InsightsView.swift` — Swift Charts + themed cards.
- Modify `hiya/hiya/Views/RootView.swift` — add Insights tab.
- Create `hiya/hiyaTests/InsightsViewModelTests.swift`.

No model/migration/repo changes (reuses `conversations(start:end:)` + `listPeople()`).

## InsightsViewModel
```swift
struct WeekBucket: Identifiable, Equatable { let weekStart: Date; var cold: Int; var warm: Int; var id: Date { weekStart } }

@MainActor @Observable
final class InsightsViewModel {
    private let repo: HiyaRepository
    var weeks: [WeekBucket] = []
    var strangers = 0
    var becameRegulars = 0
    var valence: (positive: Int, neutral: Int, negative: Int) = (0,0,0)
    var lessons: [LoggedConversation] = []
    var isLoading = false
    var errorMessage: String?
    init(repo: HiyaRepository) { self.repo = repo }

    func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
            async let convResult = repo.conversations(start: .distantPast, end: end)
            async let peopleResult = repo.listPeople()
            let conv = try await convResult
            let people = try await peopleResult
            weeks = Self.weeklyActivity(from: conv, now: .now)
            let c = Self.conversions(people: people, conversations: conv)
            strangers = c.strangers; becameRegulars = c.became
            valence = Self.valenceBreakdown(conv)
            lessons = Self.lessons(from: conv)
        } catch { errorMessage = error.localizedDescription }
    }

    var conversionRate: Double { strangers == 0 ? 0 : Double(becameRegulars) / Double(strangers) }

    static func weeklyActivity(from conv: [LoggedConversation], now: Date, weeks weekCount: Int = 8, calendar: Calendar = .current) -> [WeekBucket] {
        // anchor = start of the ISO week containing `now`; build weekCount buckets oldest→newest.
        let cal = calendar
        let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: now)!.start
        var buckets: [WeekBucket] = (0..<weekCount).reversed().map { i in
            WeekBucket(weekStart: cal.date(byAdding: .weekOfYear, value: -i, to: thisWeekStart)!, cold: 0, warm: 0)
        }
        let earliest = buckets.first!.weekStart
        for c in conv where c.occurredAt >= earliest {
            let ws = cal.dateInterval(of: .weekOfYear, for: c.occurredAt)!.start
            guard let idx = buckets.firstIndex(where: { $0.weekStart == ws }) else { continue }
            if c.wasColdAtTime { buckets[idx].cold += 1 } else { buckets[idx].warm += 1 }
        }
        return buckets
    }

    static func conversions(people: [Person], conversations conv: [LoggedConversation]) -> (strangers: Int, became: Int) {
        let coldPersonIds = Set(conv.filter { $0.wasColdAtTime }.map(\.personId))   // people met as a stranger
        let warmIds = Set(people.filter { $0.status == .warm }.map(\.id))
        let became = coldPersonIds.filter { warmIds.contains($0) }.count
        return (coldPersonIds.count, became)
    }

    static func valenceBreakdown(_ conv: [LoggedConversation]) -> (positive: Int, neutral: Int, negative: Int) {
        var p = 0, n = 0, neg = 0
        for c in conv { switch c.valence { case .positive: p += 1; case .neutral: n += 1; case .negative: neg += 1; case .none: break } }
        return (p, n, neg)
    }

    static func lessons(from conv: [LoggedConversation]) -> [LoggedConversation] {
        conv.filter { ($0.improvementNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) }
            .sorted { $0.occurredAt > $1.occurredAt }
    }
}
```
Note: `conversations(start:end:)` already returns descending by occurredAt; statics don't rely on input order.

## InsightsViewModelTests
- `weeklyActivity_bucketsByWeekAndTrack`: two convs this week (1 cold, 1 warm) + one ~3 weeks ago cold → correct buckets; `.count == 8`; first bucket oldest.
- `conversions_countsStrangersAndGraduates`: build people (one warm w/ cold conv, one warm w/o, one still cold w/ cold conv) + matching convs → strangers==2, became==1.
- `valenceBreakdown_talliesAndIgnoresNil`.
- `lessons_onlyNonEmptyNewestFirst`.
(Construct `LoggedConversation` directly with explicit `personId`, `occurredAt`, `valence`, `improvementNote`, `wasColdAtTime`.)

## InsightsView
`NavigationStack`-free (RootView wraps it) — actually give it `.navigationTitle("Insights")`; RootView wraps in NavigationStack. ScrollView over `Theme.bgGradient`, four cards in `Theme.surface` rounded containers with `bodyHeading` titles:
1. **Activity** — `import Charts`; `Chart { ForEach(vm.weeks) { w in BarMark(x:.value("Week", w.weekStart, unit:.weekOfYear), y:.value("Count", w.cold)).foregroundStyle(by:.value("Track","Approaches")); BarMark(... w.warm ...).foregroundStyle(by:.value("Track","Catch-ups")) } }` with `.chartForegroundStyleScale(["Approaches": Theme.accentAmber, "Catch-ups": Theme.accentLavender])`, frame height ~180.
2. **Conversions** — big number `becameRegulars`, subtitle "of \(strangers) strangers became regulars", rate as percent.
3. **Valence** — three labeled rows / simple proportion bars using valence colors.
4. **Lessons** — list of `vm.lessons` (note, personName, date) or empty state.
Each card empty-state guarded. `.task { await vm.load() }`, `.refreshable`.

## RootView
Add as 4th tab: `NavigationStack { InsightsView(repo: repo) }.tabItem { Label("Insights", systemImage: "chart.bar.fill") }`.

## Self-review
- Pure statics → unit-testable without async. ✓
- Reuses existing repo methods; `.distantPast` start returns all. ✓
- Charts gated to iOS18 target (fine). ✓
