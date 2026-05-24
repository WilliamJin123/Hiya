# Log a meeting: multiple people + chosen time — Design

**Date:** 2026-05-24
**Status:** Approved (pending spec review)

## Goal

Let the user log a single meeting that involves **one or more people**, at a **time they choose** (defaults to now; past and future allowed), and let them **edit the time** of an existing log. Today every log is stamped with `now` and covers exactly one person.

Motivating example: "Today at 2 pm I'm meeting two people — I want to log that now, at 2 pm, instead of it always being the current time."

## Non-goals

- Per-person valence/notes within one meeting (fields are shared across the meeting).
- Recurring schedules, cadence tracking, reminders, or notifications.
- Multi-person editing — editing remains a single-row operation.
- Batch editing of time across many existing logs.

## Constraint carried in

Cold (Approaches) and warm (Catch-ups) remain fully separate tracks. A multi-person meeting naturally respects this: each person's log row snapshots that person's own `wasColdAtTime`, so one meeting can contribute to the cold track, the warm track, or both — without ever merging the counters.

## Data layer

### Repository protocol (`HiyaRepository`)

- `logConversation(personId:occurredAt:valence:note:improvementNote:)` — add `occurredAt: Date`.
- `updateConversation(id:occurredAt:valence:note:improvementNote:)` — add `occurredAt: Date`.

The concrete implementations give `occurredAt` a default of `.now`. This keeps the ~27 existing `logConversation` call sites (almost all tests calling on the concrete `MockHiyaRepository`) compiling unchanged. Production code calls through the `HiyaRepository` protocol type, where defaults don't apply, so it must pass `occurredAt` explicitly — which is what we want.

### LiveHiyaRepository

- `logConversation` insert includes `occurred_at` as an ISO8601 string (via the existing `Date.iso8601String` helper), overriding the column's `default now()`.
- `updateConversation` sets `occurred_at`.
- Note: the DB trigger `update_person_last_logged` is `AFTER INSERT` only. So editing a log's time does **not** recompute `people.last_logged_at`. Accepted — rare, and the next insert re-establishes it.

### MockHiyaRepository

- `logConversation` uses the passed `occurredAt` instead of hardcoded `.now`.
- Mirror the DB trigger's forward-only behavior: advance `lastLoggedAt` only when `occurredAt` is newer than the current value. This makes back-dating a log never regress a person's "last seen" (today the mock overwrites it unconditionally — a latent bug this fixes).
- `updateConversation` sets the stored `occurredAt`; does not recompute `lastLoggedAt` (matches the DB trigger).

## Multi-person model (create mode only)

`LogSheetViewModel` replaces the single `selectedPerson` with an ordered list of targets:

```swift
enum LogTarget: Identifiable, Equatable {
    case existing(Person)
    case new(String)   // typed name with no match; created on save
}
private(set) var targets: [LogTarget]
```

- **Save (create):** resolve each target to a person id — `.existing` uses its id; `.new(name)` calls `createPerson(name:)` — then write one `logConversation` per id, all sharing the same `occurredAt`, `valence`, `note`, `improvementNote`.
- **Duplicate guard:** the same person can't be added twice; typing a name that matches an existing person resolves to that person rather than creating a duplicate.
- **canSave (create):** at least one target present.
- **Partial failure:** rows are written sequentially; if one fails mid-way, earlier rows persist and an error surfaces. Accepted for v1 — there's no cross-row transaction over the REST API, and the blast radius is small.
- **Edit mode is unchanged:** it operates on one existing conversation row; `targets` is not used.
- **preselectedPerson** (from a CHECK IN tap) seeds `targets = [.existing(person)]`.

## Timestamp

- `LogSheetViewModel` adds `var occurredAt: Date`, default `.now`; initialized from the entry's `occurredAt` in edit mode. Passed to `logConversation`/`updateConversation`.
- Any date/time is allowed, including future, so "log a 2 pm meeting this morning" works. The only quirk: a future time briefly shows "last seen in N hours" until it passes. Accepted.

## UI (`LogSheetView`)

- **PERSON section (create):** selected people render as removable chips. A text field below adds more — typing filters existing people (excluding already-selected); tapping a suggestion appends an `.existing` chip, and a "Add \"Name\"" row appends a `.new` chip. The field clears after each add so several people can be added in a row.
- **PERSON section (edit):** unchanged — read-only single name.
- **WHEN section (new):** a `DatePicker` with date + time, defaulting to now. Shown in both create and edit.
- Styling matches the existing sheet (surface chips, `Theme` tokens).

## Testing

Existing `logConversation`/streak/count tests are unaffected (default `.now`).

New tests:
- View model resolves multiple targets (mix of existing + new) into N logs that share one `occurredAt`.
- A custom `occurredAt` places the log in the correct day: a back-dated log does not count toward today's cold/warm count and appears in the right history day section.
- Mock advances `lastLoggedAt` forward-only — back-dating doesn't regress it.
- Duplicate-target guard prevents adding the same person twice.
