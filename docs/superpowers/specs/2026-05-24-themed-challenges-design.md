# Themed Challenges — Design

**Date:** 2026-05-24
**Status:** Draft (pending user review)

## Goal

Give the user themed challenges that vary *how* they socialize, drawn from a built-in catalog and/or created custom. A challenge is a **hybrid**: a qualitative prompt that may also carry a numeric target and/or a duration. Multiple challenges can run at once. Everything is stored in Supabase and surfaced both on a dedicated screen and on the Home page so it actually nudges.

## Decisions (locked during brainstorming)

- **Mechanic:** hybrid — prompt + optional `targetCount` + optional `durationDays`.
- **Track:** per-challenge — `cold` (Approaches), `warm` (Catch-ups), or `any`. Respects the cold/warm separation.
- **Storage:** Supabase (new `challenges` table, RLS, repo methods).
- **Concurrency:** multiple active at once.
- **Scope:** screen + Home surfacing together.
- **Auto-progress unit:** unique people on the challenge's track within its window.

## Non-goals (v1)

- Reusable custom-template library — creating a custom challenge **starts** it (a `challenges` row). "Save as reusable" is a later add.
- Reminders / notifications.
- Editing a challenge after starting (you abandon + restart).
- Rich challenge history/analytics beyond a simple "recently completed" list.

## Data model

### Bundled catalog (no DB)

`hiya/Models/ChallengeTemplate.swift`:

```swift
enum ChallengeTrack: String, Codable, Sendable, Equatable, CaseIterable {
    case cold, warm, any
}

struct ChallengeTemplate: Identifiable, Sendable, Equatable {
    let slug: String        // stable id, used as template_slug
    let title: String
    let prompt: String
    let track: ChallengeTrack
    let targetCount: Int?   // nil = pure prompt, no numeric target
    let durationDays: Int?  // nil = open-ended

    var id: String { slug }

    static let catalog: [ChallengeTemplate] = [ /* ~8 entries, see below */ ]
}
```

Initial catalog (titles/prompts final, tune later):
- `cold`, no target: **Open with a question** — "Start a conversation with an open-ended question."
- `cold`, no target: **Genuine compliment** — "Give someone you don't know a sincere compliment."
- `cold`, target 3 / 7d: **Three new faces** — "Approach three new people this week."
- `cold`, target 1 / 1d: **One today** — "Approach one new person today."
- `warm`, no target: **Go deeper** — "Ask a catch-up about something beyond small talk."
- `warm`, target 2 / 7d: **Reconnect ×2** — "Catch up with two people you've lost touch with this week."
- `any`, no target: **Phone away** — "Have a full conversation without checking your phone."
- `any`, no target: **Listen more** — "Spend a conversation mostly listening."

### `Challenge` (a started instance)

`hiya/Models/Challenge.swift`:

```swift
enum ChallengeSource: String, Codable, Sendable, Equatable { case catalog, custom }

struct Challenge: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let ownerId: UUID
    var title: String
    var prompt: String
    var track: ChallengeTrack
    var targetCount: Int?
    var durationDays: Int?
    var source: ChallengeSource
    var templateSlug: String?
    var startedAt: Date
    var completedAt: Date?
    // CodingKeys map camelCase ⇄ snake_case (owner_id, target_count, etc.)
}
```

Computed helpers: `isComplete` (`completedAt != nil`), `endDate` (`startedAt + durationDays`).

### Supabase migration

`supabase/migrations/<ts>_add_challenges.sql` — mirror the existing RLS style (per-operation policies keyed on `auth.uid() = owner_id`):

```sql
create table public.challenges (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references public.profiles(id) on delete cascade,
  title         text not null,
  prompt        text not null,
  track         text not null default 'any' check (track in ('cold','warm','any')),
  target_count  int,
  duration_days int,
  source        text not null default 'custom' check (source in ('catalog','custom')),
  template_slug text,
  started_at    timestamptz not null default now(),
  completed_at  timestamptz,
  created_at    timestamptz not null default now()
);
create index challenges_owner_started_idx on public.challenges(owner_id, started_at desc);
alter table public.challenges enable row level security;
create policy "challenges_select_own" on public.challenges for select using (auth.uid() = owner_id);
create policy "challenges_insert_own" on public.challenges for insert with check (auth.uid() = owner_id);
create policy "challenges_update_own" on public.challenges for update using (auth.uid() = owner_id);
create policy "challenges_delete_own" on public.challenges for delete using (auth.uid() = owner_id);
```

## Progress & completion

Progress only applies when `targetCount != nil`. It's computed client-side from conversations:

> **progress** = count of *unique* `personId` among conversations whose `occurredAt` is within `[startedAt, min(now, endDate ?? now)]` and whose track matches (`cold` → `wasColdAtTime`; `warm` → `!wasColdAtTime`; `any` → either).

Completion:
- **Manual:** "Mark done" sets `completedAt`.
- **Auto:** on load, any active targeted challenge whose progress ≥ `targetCount` is marked complete (persisted). Pure-prompt challenges (no target) are manual-only.

A pure helper makes this testable:

```swift
static func progress(for challenge: Challenge, in conversations: [LoggedConversation], now: Date) -> Int
```

## Repository

Protocol additions (concrete impls; Mock gets in-memory `var challenges: [Challenge]`):

```swift
func challenges() async throws -> [Challenge]                 // all for owner, started_at desc
func startChallenge(_ draft: ChallengeDraft) async throws -> Challenge
func completeChallenge(id: UUID) async throws                 // sets completed_at = now
func abandonChallenge(id: UUID) async throws                  // deletes the row
```

`ChallengeDraft` is a small struct carrying the insert fields (title, prompt, track, targetCount, durationDays, source, templateSlug) to avoid a long parameter list. Live builds it from a catalog template or the custom form.

## View model

`hiya/ViewModels/ChallengesViewModel.swift` (`@MainActor @Observable`):
- State: `challenges: [Challenge]`, `recentConversations: [LoggedConversation]`, `errorMessage`.
- Derived: `active` (`!isComplete`), `completed` (`isComplete`, most-recent first).
- `load()`: fetch `challenges()` + `conversations(start:end:)` over a window covering the earliest active `startedAt` (fallback 30 days); then auto-complete met targeted challenges.
- `progress(for:) -> Int` (wraps the pure helper with `recentConversations`).
- `start(template:)`, `startCustom(...)`, `complete(id:)`, `abandon(id:)` — each mutates then reloads.
- `activeChallenges(for track: PersonStatus) -> [Challenge]` — active challenges whose `track` is that side or `any`; used by Home surfacing.

## UI

### Entry point
A challenges button in the Home toolbar (leading, beside the calendar). Icon `target`, tinted `accentLavender`.

### `ChallengesView` (new screen)
- **ACTIVE** section — one card per active challenge: title, prompt, a track chip (amber = Approaches, lavender = Catch-ups, neutral = Either), a progress bar `2 / 3` when targeted, a "Mark done" button, and `.swipeActions` → Abandon (destructive, confirmed).
- **COMPLETED** section — completed challenges, muted with a checkmark (most recent first). Keeps the reward visible without analytics.
- **+ New challenge** toolbar button → a chooser: **Browse catalog** or **Create custom**.

### Catalog browse (sheet)
List `ChallengeTemplate.catalog` grouped by track; tap a row → `start(template:)` → dismiss.

### Create custom (sheet)
Form: title, prompt, track (segmented Approaches/Catch-ups/Either), optional target (stepper, 0 = none), optional duration (None / 3 / 7 / 14 / 30 days). Save → `startCustom(...)` → dismiss.

### Home surfacing
On each Home page, a compact **CHALLENGE** section (below the log button) listing `vm.activeChallenges(for: pageMode)` — title, prompt, and progress if targeted. Read-only nudge; tapping opens `ChallengesView`. Hidden when none active for that track. The cold page shows `cold` + `any`; the warm page shows `warm` + `any`.

## Testing

- `ChallengesViewModel.progress`: targeted `cold` challenge counts unique cold people in window; `warm` likewise; `any` counts both; logs outside `[startedAt, endDate]` are excluded.
- Auto-complete: `load()` marks a targeted challenge complete once progress ≥ target.
- `start` / `complete` / `abandon` round-trip via the mock; `activeChallenges(for:)` filters by track + `any`.
- Mock repo challenge CRUD.
- Catalog sanity: non-empty, slugs unique.
