# Insights Screen — Design

**Date:** 2026-05-24

## Goal

A read-only Insights tab that reflects progress back to the user — biased toward the cold-approach behavior the app exists to build — using data already logged.

## Dependencies

Builds on the Settings/tab-nav spec (`2026-05-24-settings-per-mode-goals-design.md`): the **Insights tab** slots into the `TabView` created there. No data-model or migration changes — Insights is pure read-side.

## Data sources

`InsightsViewModel.load()` fetches:
- `conversations(start: .distantPast, end: now + 1 day)` → `[LoggedConversation]` (has `occurredAt`, `valence`, `wasColdAtTime`, `improvementNote`, `personName`). The existing method filters `>= start && < end`, so a distant-past start returns everything.
- `listPeople()` → `[Person]` (for conversion status).

All computation is client-side via **pure static functions** (so they unit-test without async).

## The four cards

1. **Activity over time** — `Swift Charts` `BarMark`, last 8 ISO weeks, two series (Approaches vs Catch-ups) by `wasColdAtTime`. Counts conversations (volume), not unique people.
   - `static func weeklyActivity(from:now:) -> [WeekBucket]` where `WeekBucket { weekStart: Date, cold: Int, warm: Int }`, 8 buckets oldest→newest, zero-filled.

2. **Cold→Warm conversions** — headline "N strangers became regulars," plus a rate.
   - *strangers met* = distinct people with ≥1 conversation where `wasColdAtTime == true`.
   - *became regulars* = of those, the people whose current `status == .warm`.
   - rate = became / max(1, strangers).
   - **Heuristic note:** people manually moved cold→warm have their conversations reclassified (`wasColdAtTime = false`), so they don't count as "strangers met." This card therefore reflects **natural graduations / genuinely-cold-first relationships**, which is the intended signal. Documented so the number isn't mistaken for "all warm people."
   - `static func conversions(people:conversations:) -> (strangers: Int, became: Int)`.

3. **How it felt (valence)** — counts of positive / neutral / negative across conversations with a non-nil valence, shown as a labeled breakdown with the existing valence colors. `static func valenceBreakdown(_:) -> (positive: Int, neutral: Int, negative: Int)`.

4. **Lessons feed** — conversations with a non-empty `improvementNote`, newest-first, each row showing the note, person name, and date. `static func lessons(from:) -> [LoggedConversation]`.

## UI

`InsightsView` — `ScrollView` over `Theme.bgGradient`, one themed card per section (rounded `Theme.surface` containers, section headings like the rest of the app). Empty states per card ("Log a few conversations to see this"). Its own `NavigationStack` with title "Insights". `.task { await vm.load() }` + `.refreshable`.

The activity chart uses `Chart { ForEach … BarMark(...).foregroundStyle(by: .value("Track", …)) }` with `Theme.accentAmber` (Approaches) and `Theme.accentLavender` (Catch-ups) via `.chartForegroundStyleScale`.

## Testing

`InsightsViewModelTests` against the pure statics:
- `weeklyActivity` buckets conversations into the right weeks and splits cold/warm; produces 8 zero-filled buckets.
- `conversions` counts strangers and graduates correctly (warm-with-cold-convo counts; warm-without doesn't; currently-cold-with-cold-convo is a stranger not yet converted).
- `valenceBreakdown` tallies the three buckets and ignores nil.
- `lessons` returns only non-empty improvement notes, newest-first.

## Out of scope

- Date-range pickers / drill-downs (fixed windows: 8 weeks for activity, all-time for the rest).
- Exporting or sharing insights.
