# Dated Person Notes — Design

**Date:** 2026-05-24

## Goal

Turn a person's single `notes` field into a **timeline of dated note entries**. Every note you add is stamped with when you learned it; editing an entry preserves that original "learned on" date while recording that it was edited. The result is a journal of what you learn about a person over time.

## Scope decisions (locked with user)

1. **Standalone notes only.** The timeline holds notes you explicitly add about a person. Conversation notes (`conversation.note`) are unrelated and stay in History, untouched. The detail screen is **not** a merged conversation+note feed.
2. **Keep original date AND track edits.** Each entry keeps an immutable `created_at` ("learned on") plus an `updated_at` that's null until the first edit. The UI shows both when an entry has been edited.
3. **First/oldest note is the differentiator.** The oldest entry's body remains the duplicate-name disambiguator shown in the People list — a stable identity anchor, matching today's behavior.

## Data model

New table `person_notes` — one row per timeline entry:

| column | type | meaning |
|---|---|---|
| `id` | uuid PK (`gen_random_uuid()`) | |
| `owner_id` | uuid not null → `profiles(id)` on delete cascade | RLS scope |
| `person_id` | uuid not null → `people(id)` on delete cascade | |
| `body` | text not null | the note text |
| `created_at` | timestamptz not null default now() | **"learned on"** — never changes |
| `updated_at` | timestamptz null | null until first edit; set to now() on every edit |

Index: `person_notes(person_id, created_at desc)`.

RLS (mirror `challenges`/`people`): enable RLS; `select`/`insert`/`update`/`delete` policies all gated on `auth.uid() = owner_id`.

Swift model `PersonNote: Codable, Sendable, Identifiable, Equatable, Hashable` with snake_case `CodingKeys`, fields `id, ownerId, personId, body, createdAt, updatedAt`, and a computed `var wasEdited: Bool { updatedAt != nil }`.

### `Person.notes` is retained as a denormalized cache

`Person.notes` continues to hold the **oldest entry's body** (or `nil` if no entries). This keeps every existing read path working unchanged:
- People-list row subtitle (`PeopleView` `PersonRow.subtitleText` + the `note.text` icon).
- Log-sheet differentiator (`LogSheetViewModel`, person chips/subtitles).
- Duplicate-name handling.

It is recomputed by the app on every note mutation (not via a DB trigger — keeps logic testable in `MockHiyaRepository`).

## Differentiator sync rules

After any note mutation, set `Person.notes` to the body of the **oldest remaining entry**, or `nil` if none:

| Action | Effect on differentiator |
|---|---|
| Add a note to a person with none | New note is oldest → becomes differentiator |
| Add a newer note | Oldest unchanged → differentiator unchanged |
| Edit the oldest entry | Differentiator updates to new body |
| Edit a newer entry | Differentiator unchanged |
| Delete the oldest entry | Next-oldest becomes differentiator |
| Delete the last entry | Differentiator → `nil` |

## Repository surface

Added to the `HiyaRepository` protocol, with concrete implementations in `LiveHiyaRepository` (Supabase) and `MockHiyaRepository` (in-memory). Follow the established protocol-requirement-with-concrete-default pattern only where needed to avoid breaking existing call sites.

- `personNotes(personId: UUID) async throws -> [PersonNote]` — all entries for a person, newest-first.
- `addPersonNote(personId: UUID, body: String) async throws -> PersonNote` — stamped `now()`; no back-dating in v1. Recomputes differentiator.
- `updatePersonNote(id: UUID, body: String) async throws` — updates body, sets `updated_at = now()`, preserves `created_at`. Recomputes differentiator.
- `deletePersonNote(id: UUID) async throws` — removes the entry. Recomputes differentiator.
- `createPerson(name:status:notes:)` — **additionally** seeds a first `person_notes` entry when a non-empty `notes` is supplied. This preserves today's "first note at creation becomes the person's note" behavior (the new entry's body == the seeded `Person.notes`). This is the **only** automatic timeline entry. Logging a conversation note on an *existing* person does **not** add a timeline entry (standalone-only).

`updatePersonNotes(id:notes:)` (the existing whole-blob setter) is retained as the low-level differentiator writer used by the recompute logic and by `moveToWarm`. `moveToWarm` no longer persists a notes-field edit (the detail sheet no longer has a single notes TextField); it just changes status and reclassifies conversations as before.

## UI — `PersonDetailSheet` + new `PersonDetailViewModel`

Introduce `PersonDetailViewModel` (`@MainActor @Observable`) to hold the timeline and the add/edit/delete logic — the inline logic now warrants a view model and makes the behavior unit-testable.

`PersonDetailSheet` replaces the single notes TextField with a **NOTES** timeline section:
- An "Add a note…" `TextField` + **Add** button at the top of the section. Adding clears the field and prepends the new entry.
- Entries listed **newest-first** below. Each entry shows:
  - the date line: `Learned <date>` and, if edited, `· edited <date>`.
  - the body text.
- Tap an entry → edit via an `.alert` with a prefilled `TextField` (mirrors the add-person alert pattern) → Save calls `updatePersonNote`.
- Swipe / delete affordance on an entry → `deletePersonNote`.
- The `moveToWarm` button (shown when `person.status == .cold`) stays; the standalone notes Save button is removed.

Header (JUST MET badge, "Last seen …") is unchanged.

## Migration / backfill

`supabase/migrations/<ts>_add_person_notes_timeline.sql`:
1. Create `person_notes` table, index, enable RLS, four owner-gated policies.
2. Backfill one entry per person who currently has a non-empty `notes`:
   - `body = people.notes`
   - `created_at = COALESCE(earliest conversation occurred_at for that person, people.created_at)` — best-available "learned on" date.
   - `updated_at = null`, `owner_id = people.owner_id`.

Applied to remote with `supabase db push --yes` (user has authorized running migrations).

## Testing

`MockHiyaRepository`: add `var personNoteRows: [PersonNote] = []`; implement the four note methods + differentiator recompute; have `createPerson(notes:)` seed an entry.

Unit tests (Swift Testing, mirror `MockHiyaRepositoryTests` style):
- `addPersonNote` on a person with none seeds the timeline **and** sets `Person.notes`.
- A second (newer) note leaves `Person.notes` unchanged.
- Editing the oldest entry updates `Person.notes`, sets `updatedAt`, and preserves `createdAt`.
- Editing a newer entry leaves `Person.notes` unchanged.
- Deleting the oldest entry promotes the next-oldest to differentiator.
- Deleting the last entry clears `Person.notes` to `nil`.
- `createPerson(name:notes:)` with a note creates exactly one entry whose body matches.
- `personNotes` returns entries newest-first.

Plus `PersonDetailViewModel` tests for add/edit/delete wiring against the mock.

## Out of scope (v1)

- Back-dating new notes (notes are stamped `now()`).
- Merging conversation notes into the timeline.
- A full edit-history log per entry (we track only `created_at` + last `updated_at`, which satisfies "show both original and edited").
