# Dated Person Notes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace a person's single `notes` field with a dated timeline of note entries, where each note records when it was learned and tracks when it was edited.

**Architecture:** A new `person_notes` table holds one row per entry (immutable `created_at`, nullable `updated_at`). `Person.notes` is retained as an app-maintained denormalized cache of the *oldest* entry's body (the duplicate-name differentiator), recomputed on every note mutation so all existing read paths keep working. A new `PersonDetailViewModel` drives the timeline UI in `PersonDetailSheet`.

**Tech Stack:** SwiftUI, Swift 6, `@Observable` view models, protocol-backed `HiyaRepository` (Supabase Live + in-memory Mock), Swift Testing, Supabase Postgres + RLS.

**Spec:** `docs/superpowers/specs/2026-05-24-dated-person-notes-design.md`

---

## Conventions for every test run

Run the suite **once**, tee to a log, then grep the log (never double-run):

```bash
cd /Users/williamjin/Documents/Hiya
xcodebuild test \
  -project hiya/hiya.xcodeproj -scheme hiya \
  -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  2>&1 | tee /tmp/hiya_test.log | tail -40
```

When the run **adds new test functions**, use `clean test` instead of `test` (DerivedData caches Swift Testing discovery, so new tests can be silently skipped otherwise):

```bash
xcodebuild clean test \
  -project hiya/hiya.xcodeproj -scheme hiya \
  -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  2>&1 | tee /tmp/hiya_test.log | tail -40
```

Parse pass/fail from the log:

```bash
grep -E "Test run with .* tests passed|failed|error:" /tmp/hiya_test.log | tail -20
```

To run only the new tests during a task (faster, also forces discovery of a single test):

```bash
xcodebuild test \
  -project hiya/hiya.xcodeproj -scheme hiya \
  -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  -only-testing:hiyaTests/MockHiyaRepositoryTests \
  2>&1 | tee /tmp/hiya_test.log | tail -40
```

---

## File Structure

- **Create** `hiya/hiya/Models/PersonNote.swift` — the `PersonNote` model.
- **Modify** `hiya/hiya/Services/HiyaRepository.swift` — protocol methods + `LiveHiyaRepository` impls + `createPerson` seeding + a private differentiator recompute.
- **Modify** `hiya/hiya/Services/MockHiyaRepository.swift` — `personNoteRows` store, note methods, differentiator recompute, `createPerson` seeding, `deletePerson` cascade.
- **Create** `hiya/hiya/ViewModels/PersonDetailViewModel.swift` — timeline state + add/edit/delete.
- **Modify** `hiya/hiya/Views/PersonDetailSheet.swift` — replace single notes field with the timeline UI.
- **Modify** `hiya/hiyaTests/MockHiyaRepositoryTests.swift` — repository behavior tests.
- **Create** `hiya/hiyaTests/PersonDetailViewModelTests.swift` — view-model tests.
- **Create** `supabase/migrations/20260524170000_add_person_notes_timeline.sql` — table, RLS, backfill.

---

## Task 1: `PersonNote` model

**Files:**
- Create: `hiya/hiya/Models/PersonNote.swift`

- [ ] **Step 1: Create the model**

```swift
import Foundation

/// One dated entry in a person's note timeline. `createdAt` is the immutable
/// "learned on" date; `updatedAt` stays nil until the entry is first edited.
struct PersonNote: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: UUID
    let ownerId: UUID
    let personId: UUID
    var body: String
    let createdAt: Date
    var updatedAt: Date?

    var wasEdited: Bool { updatedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case personId = "person_id"
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: build only (fast feedback):
```bash
cd /Users/williamjin/Documents/Hiya
xcodebuild build -project hiya/hiya.xcodeproj -scheme hiya \
  -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Models/PersonNote.swift
git commit -m "feat(notes): add PersonNote model

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Repository protocol + Mock implementation (TDD)

This task adds the four note methods and the differentiator-recompute behavior to the protocol and the Mock, plus `createPerson` seeding and `deletePerson` cascade. Tests are written against the Mock first.

**Files:**
- Modify: `hiya/hiya/Services/HiyaRepository.swift` (protocol only in this task)
- Modify: `hiya/hiya/Services/MockHiyaRepository.swift`
- Test: `hiya/hiyaTests/MockHiyaRepositoryTests.swift`

- [ ] **Step 1: Write the failing tests**

Append these tests inside the `struct MockHiyaRepositoryTests { … }` body in `hiya/hiyaTests/MockHiyaRepositoryTests.swift` (before the closing brace):

```swift
    @Test func addPersonNote_seedsTimelineAndDifferentiator() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        #expect(repo.people.first { $0.id == p.id }?.notes == nil)

        _ = try await repo.addPersonNote(personId: p.id, body: "climbing gym")

        #expect(repo.people.first { $0.id == p.id }?.notes == "climbing gym")
        #expect(try await repo.personNotes(personId: p.id).count == 1)
    }

    @Test func addPersonNote_secondNoteLeavesDifferentiator() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let first = try await repo.addPersonNote(personId: p.id, body: "first")
        // Force `first` to be the oldest deterministically.
        if let i = repo.personNoteRows.firstIndex(where: { $0.id == first.id }) {
            repo.personNoteRows[i].createdAt = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        }

        _ = try await repo.addPersonNote(personId: p.id, body: "second")

        #expect(repo.people.first { $0.id == p.id }?.notes == "first")
    }

    @Test func updatePersonNote_onOldest_updatesDifferentiator_setsUpdatedAt_keepsCreatedAt() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let first = try await repo.addPersonNote(personId: p.id, body: "first")
        let originalCreated = first.createdAt

        try await repo.updatePersonNote(id: first.id, body: "first edited")

        let updated = repo.personNoteRows.first { $0.id == first.id }!
        #expect(updated.body == "first edited")
        #expect(updated.updatedAt != nil)
        #expect(updated.createdAt == originalCreated)
        #expect(repo.people.first { $0.id == p.id }?.notes == "first edited")
    }

    @Test func updatePersonNote_onNewer_leavesDifferentiator() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let first = try await repo.addPersonNote(personId: p.id, body: "first")
        if let i = repo.personNoteRows.firstIndex(where: { $0.id == first.id }) {
            repo.personNoteRows[i].createdAt = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        }
        let second = try await repo.addPersonNote(personId: p.id, body: "second")

        try await repo.updatePersonNote(id: second.id, body: "second edited")

        #expect(repo.people.first { $0.id == p.id }?.notes == "first")
    }

    @Test func deletePersonNote_oldest_promotesNext() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let first = try await repo.addPersonNote(personId: p.id, body: "first")
        if let i = repo.personNoteRows.firstIndex(where: { $0.id == first.id }) {
            repo.personNoteRows[i].createdAt = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        }
        _ = try await repo.addPersonNote(personId: p.id, body: "second")

        try await repo.deletePersonNote(id: first.id)

        #expect(repo.people.first { $0.id == p.id }?.notes == "second")
    }

    @Test func deletePersonNote_last_clearsDifferentiator() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let only = try await repo.addPersonNote(personId: p.id, body: "only")

        try await repo.deletePersonNote(id: only.id)

        #expect(repo.people.first { $0.id == p.id }?.notes == nil)
        #expect(try await repo.personNotes(personId: p.id).isEmpty)
    }

    @Test func createPerson_withNote_createsOneTimelineEntry() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex", status: .cold, notes: "met at gym")

        let notes = try await repo.personNotes(personId: p.id)
        #expect(notes.count == 1)
        #expect(notes.first?.body == "met at gym")
        #expect(repo.people.first { $0.id == p.id }?.notes == "met at gym")
    }

    @Test func personNotes_returnsNewestFirst() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let older = try await repo.addPersonNote(personId: p.id, body: "older")
        if let i = repo.personNoteRows.firstIndex(where: { $0.id == older.id }) {
            repo.personNoteRows[i].createdAt = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        }
        _ = try await repo.addPersonNote(personId: p.id, body: "newer")

        let notes = try await repo.personNotes(personId: p.id)
        #expect(notes.map(\.body) == ["newer", "older"])
    }

    @Test func deletePerson_cascadesNotes() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex", notes: "seed")
        #expect(repo.personNoteRows.contains { $0.personId == p.id })

        try await repo.deletePerson(id: p.id)

        #expect(!repo.personNoteRows.contains { $0.personId == p.id })
    }
```

- [ ] **Step 2: Run the tests to verify they fail (compile error)**

Run:
```bash
cd /Users/williamjin/Documents/Hiya
xcodebuild test -project hiya/hiya.xcodeproj -scheme hiya \
  -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  -only-testing:hiyaTests/MockHiyaRepositoryTests \
  2>&1 | tee /tmp/hiya_test.log | tail -25
```
Expected: build FAILS — `value of type 'MockHiyaRepository' has no member 'addPersonNote'` / `personNoteRows`.

- [ ] **Step 3: Add the protocol requirements**

In `hiya/hiya/Services/HiyaRepository.swift`, add these four lines to the `protocol HiyaRepository` body (place them right after `func updatePersonNotes(id: UUID, notes: String?) async throws`):

```swift
    func personNotes(personId: UUID) async throws -> [PersonNote]
    func addPersonNote(personId: UUID, body: String) async throws -> PersonNote
    func updatePersonNote(id: UUID, body: String) async throws
    func deletePersonNote(id: UUID) async throws
```

- [ ] **Step 4: Implement in the Mock**

In `hiya/hiya/Services/MockHiyaRepository.swift`:

(a) Add the store alongside the other stored vars (after `var challengeRows: [Challenge] = []`):

```swift
    var personNoteRows: [PersonNote] = []
```

(b) Replace the existing `createPerson(...)` method with this version (seeds a timeline entry when a note is supplied):

```swift
    func createPerson(name: String, status: PersonStatus = .cold, notes: String? = nil) async throws -> Person {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = (trimmedNotes?.isEmpty == false) ? trimmedNotes : nil
        let person = Person(
            id: UUID(),
            ownerId: profile.id,
            name: name,
            status: status,
            statusChangedAt: status == .warm ? .now : nil,
            notes: seed,
            createdAt: .now,
            lastLoggedAt: .now
        )
        people.append(person)
        if let seed {
            personNoteRows.append(PersonNote(
                id: UUID(),
                ownerId: profile.id,
                personId: person.id,
                body: seed,
                createdAt: person.createdAt,
                updatedAt: nil
            ))
        }
        return person
    }
```

(c) Replace the existing `deletePerson(...)` method with this version (cascades notes too):

```swift
    func deletePerson(id: UUID) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        // Mirror the DB cascade — removing a person also removes their logs and notes.
        people.removeAll { $0.id == id }
        conversations.removeAll { $0.personId == id }
        personNoteRows.removeAll { $0.personId == id }
    }
```

(d) Add the four note methods + recompute helper (place after `updatePersonNotes(...)`):

```swift
    func personNotes(personId: UUID) async throws -> [PersonNote] {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        return personNoteRows
            .filter { $0.personId == personId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func addPersonNote(personId: UUID, body: String) async throws -> PersonNote {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        let note = PersonNote(
            id: UUID(),
            ownerId: profile.id,
            personId: personId,
            body: body,
            createdAt: .now,
            updatedAt: nil
        )
        personNoteRows.append(note)
        recomputeDifferentiator(personId: personId)
        return note
    }

    func updatePersonNote(id: UUID, body: String) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        guard let idx = personNoteRows.firstIndex(where: { $0.id == id }) else { return }
        personNoteRows[idx].body = body
        personNoteRows[idx].updatedAt = .now
        recomputeDifferentiator(personId: personNoteRows[idx].personId)
    }

    func deletePersonNote(id: UUID) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        guard let note = personNoteRows.first(where: { $0.id == id }) else { return }
        let personId = note.personId
        personNoteRows.removeAll { $0.id == id }
        recomputeDifferentiator(personId: personId)
    }

    /// Keep `Person.notes` equal to the oldest remaining note's body (the
    /// duplicate-name differentiator), or nil when the person has no notes.
    private func recomputeDifferentiator(personId: UUID) {
        guard let pIdx = people.firstIndex(where: { $0.id == personId }) else { return }
        let oldest = personNoteRows
            .filter { $0.personId == personId }
            .min(by: { $0.createdAt < $1.createdAt })
        people[pIdx].notes = oldest?.body
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run (new tests added → clean):
```bash
cd /Users/williamjin/Documents/Hiya
xcodebuild clean test -project hiya/hiya.xcodeproj -scheme hiya \
  -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  -only-testing:hiyaTests/MockHiyaRepositoryTests \
  2>&1 | tee /tmp/hiya_test.log | tail -25
```
Expected: all `MockHiyaRepositoryTests` pass, including the 9 new ones.

Note: `LiveHiyaRepository` does NOT yet conform to the new protocol methods, so the **full app target won't build until Task 3**. That's expected — `-only-testing:hiyaTests/MockHiyaRepositoryTests` still compiles the test + app sources, so if Task 3 isn't done this run fails to build with `type 'LiveHiyaRepository' does not conform to protocol 'HiyaRepository'`. **Do Task 3 immediately after Step 4 here, then run Step 5.** (Reordering note: implement Task 3 Step 1 before running this step.)

- [ ] **Step 6: Commit** (after Task 3's Live impl also compiles — commit both together)

```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Services/HiyaRepository.swift hiya/hiya/Services/MockHiyaRepository.swift hiya/hiyaTests/MockHiyaRepositoryTests.swift
git commit -m "feat(notes): person-notes repo methods + differentiator recompute (mock + protocol)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Live (Supabase) implementation

Because the protocol gained methods in Task 2, `LiveHiyaRepository` must implement them for the app target to build. Implement this **immediately after Task 2 Step 4**, before running Task 2 Step 5.

**Files:**
- Modify: `hiya/hiya/Services/HiyaRepository.swift` (`LiveHiyaRepository`)

- [ ] **Step 1: Seed a note in `createPerson`**

Replace `LiveHiyaRepository.createPerson(...)` with this version (adds the seed insert):

```swift
    func createPerson(name: String, status: PersonStatus = .cold, notes: String? = nil) async throws -> Person {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = (trimmedNotes?.isEmpty == false) ? trimmedNotes : nil
        let userId = try await client.auth.user().id
        struct Insert: Encodable {
            let owner_id: UUID
            let name: String
            let status: String
            let status_changed_at: String?
            let notes: String?
        }
        let inserted: Person = try await client
            .from("people")
            .insert(Insert(
                owner_id: userId,
                name: trimmed,
                status: status.rawValue,
                status_changed_at: status == .warm ? Date.now.iso8601String : nil,
                notes: seed
            ))
            .select()
            .single()
            .execute()
            .value
        if let seed {
            struct NoteInsert: Encodable {
                let owner_id: UUID
                let person_id: UUID
                let body: String
                let created_at: String
            }
            try await client
                .from("person_notes")
                .insert(NoteInsert(
                    owner_id: userId,
                    person_id: inserted.id,
                    body: seed,
                    created_at: inserted.createdAt.iso8601String
                ))
                .execute()
        }
        return inserted
    }
```

- [ ] **Step 2: Add the four note methods + recompute helper**

Add to `LiveHiyaRepository` (place after `updatePersonNotes(...)`):

```swift
    func personNotes(personId: UUID) async throws -> [PersonNote] {
        try await client
            .from("person_notes")
            .select()
            .eq("person_id", value: personId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func addPersonNote(personId: UUID, body: String) async throws -> PersonNote {
        let userId = try await client.auth.user().id
        struct Insert: Encodable {
            let owner_id: UUID
            let person_id: UUID
            let body: String
        }
        let inserted: PersonNote = try await client
            .from("person_notes")
            .insert(Insert(owner_id: userId, person_id: personId, body: body))
            .select()
            .single()
            .execute()
            .value
        try await recomputeDifferentiator(personId: personId)
        return inserted
    }

    func updatePersonNote(id: UUID, body: String) async throws {
        struct Update: Encodable {
            let body: String
            let updated_at: String
        }
        struct Row: Decodable { let person_id: UUID }
        let row: Row = try await client
            .from("person_notes")
            .update(Update(body: body, updated_at: Date.now.iso8601String))
            .eq("id", value: id)
            .select("person_id")
            .single()
            .execute()
            .value
        try await recomputeDifferentiator(personId: row.person_id)
    }

    func deletePersonNote(id: UUID) async throws {
        struct Row: Decodable { let person_id: UUID }
        let row: Row = try await client
            .from("person_notes")
            .delete()
            .eq("id", value: id)
            .select("person_id")
            .single()
            .execute()
            .value
        try await recomputeDifferentiator(personId: row.person_id)
    }

    /// Keep `people.notes` equal to the oldest note's body (the duplicate-name
    /// differentiator), or null when the person has no notes.
    private func recomputeDifferentiator(personId: UUID) async throws {
        struct Row: Decodable { let body: String }
        let rows: [Row] = try await client
            .from("person_notes")
            .select("body")
            .eq("person_id", value: personId)
            .order("created_at", ascending: true)
            .limit(1)
            .execute()
            .value
        try await updatePersonNotes(id: personId, notes: rows.first?.body)
    }
```

- [ ] **Step 3: Run Task 2 Step 5** (the Mock tests) — now the app target compiles and tests pass. Then do Task 2 Step 6 commit.

---

## Task 4: Database migration + backfill

**Files:**
- Create: `supabase/migrations/20260524170000_add_person_notes_timeline.sql`

- [ ] **Step 1: Write the migration**

```sql
----------------------------------------------------------------------
-- person_notes: dated timeline of notes about a person. Each entry keeps an
-- immutable created_at ("learned on") plus an updated_at that is null until
-- the entry is first edited.
----------------------------------------------------------------------
create table public.person_notes (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  person_id  uuid not null references public.people(id) on delete cascade,
  body       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create index person_notes_person_created_idx
  on public.person_notes(person_id, created_at desc);

alter table public.person_notes enable row level security;

create policy "person_notes_select_own" on public.person_notes
  for select using (auth.uid() = owner_id);
create policy "person_notes_insert_own" on public.person_notes
  for insert with check (auth.uid() = owner_id);
create policy "person_notes_update_own" on public.person_notes
  for update using (auth.uid() = owner_id);
create policy "person_notes_delete_own" on public.person_notes
  for delete using (auth.uid() = owner_id);

----------------------------------------------------------------------
-- Backfill: seed one entry per person who already has a note. The "learned on"
-- date is the person's earliest conversation, falling back to when the person
-- record itself was created.
----------------------------------------------------------------------
insert into public.person_notes (owner_id, person_id, body, created_at)
select p.owner_id,
       p.id,
       p.notes,
       coalesce(
         (select min(c.occurred_at) from public.conversations c where c.person_id = p.id),
         p.created_at
       )
from public.people p
where p.notes is not null and btrim(p.notes) <> '';
```

- [ ] **Step 2: Apply to remote**

Run:
```bash
cd /Users/williamjin/Documents/Hiya
supabase db push --yes 2>&1 | tail -20
```
Expected: the new migration is listed as applied with no errors.

- [ ] **Step 3: Commit**

```bash
cd /Users/williamjin/Documents/Hiya
git add supabase/migrations/20260524170000_add_person_notes_timeline.sql
git commit -m "feat(notes): person_notes table, RLS, and backfill migration

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `PersonDetailViewModel` (TDD)

**Files:**
- Create: `hiya/hiya/ViewModels/PersonDetailViewModel.swift`
- Test: `hiya/hiyaTests/PersonDetailViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `hiya/hiyaTests/PersonDetailViewModelTests.swift`:

```swift
import Testing
import Foundation
@testable import hiya

@MainActor
struct PersonDetailViewModelTests {

    @Test func add_appendsAndReloads() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let vm = PersonDetailViewModel(repo: repo, person: p)

        await vm.add("climbing gym")

        #expect(vm.notes.count == 1)
        #expect(vm.notes.first?.body == "climbing gym")
    }

    @Test func add_ignoresBlank() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let vm = PersonDetailViewModel(repo: repo, person: p)

        await vm.add("   ")

        #expect(vm.notes.isEmpty)
    }

    @Test func edit_updatesBodyAndMarksEdited() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let vm = PersonDetailViewModel(repo: repo, person: p)
        await vm.add("first")
        let note = vm.notes.first!

        await vm.edit(note, to: "first edited")

        #expect(vm.notes.first?.body == "first edited")
        #expect(vm.notes.first?.wasEdited == true)
    }

    @Test func delete_removes() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex")
        let vm = PersonDetailViewModel(repo: repo, person: p)
        await vm.add("x")
        let note = vm.notes.first!

        await vm.delete(note)

        #expect(vm.notes.isEmpty)
    }

    @Test func load_showsSeededNote() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Alex", notes: "seed")
        let vm = PersonDetailViewModel(repo: repo, person: p)

        await vm.load()

        #expect(vm.notes.map(\.body) == ["seed"])
    }
}
```

- [ ] **Step 2: Run to verify failure (compile error)**

Run:
```bash
cd /Users/williamjin/Documents/Hiya
xcodebuild test -project hiya/hiya.xcodeproj -scheme hiya \
  -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  -only-testing:hiyaTests/PersonDetailViewModelTests \
  2>&1 | tee /tmp/hiya_test.log | tail -25
```
Expected: build FAILS — `cannot find 'PersonDetailViewModel' in scope`.

- [ ] **Step 3: Implement the view model**

Create `hiya/hiya/ViewModels/PersonDetailViewModel.swift`:

```swift
import Foundation

@MainActor
@Observable
final class PersonDetailViewModel {
    let repo: HiyaRepository
    let person: Person

    var notes: [PersonNote] = []
    var errorMessage: String?
    var isWorking = false

    init(repo: HiyaRepository, person: Person) {
        self.repo = repo
        self.person = person
    }

    func load() async {
        do {
            notes = try await repo.personNotes(personId: person.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func add(_ rawBody: String) async {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await repo.addPersonNote(personId: person.id, body: body)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func edit(_ note: PersonNote, to rawBody: String) async {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repo.updatePersonNote(id: note.id, body: body)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ note: PersonNote) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await repo.deletePersonNote(id: note.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run (new test file → clean):
```bash
cd /Users/williamjin/Documents/Hiya
xcodebuild clean test -project hiya/hiya.xcodeproj -scheme hiya \
  -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  -only-testing:hiyaTests/PersonDetailViewModelTests \
  2>&1 | tee /tmp/hiya_test.log | tail -25
```
Expected: all 5 `PersonDetailViewModelTests` pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/ViewModels/PersonDetailViewModel.swift hiya/hiyaTests/PersonDetailViewModelTests.swift
git commit -m "feat(notes): PersonDetailViewModel for the note timeline

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: `PersonDetailSheet` timeline UI

Replace the single notes TextField with the timeline. This is a full rewrite of the file.

**Files:**
- Modify: `hiya/hiya/Views/PersonDetailSheet.swift`

- [ ] **Step 1: Rewrite the file**

Replace the entire contents of `hiya/hiya/Views/PersonDetailSheet.swift` with:

```swift
import SwiftUI

struct PersonDetailSheet: View {
    let repo: HiyaRepository
    let person: Person

    @State private var vm: PersonDetailViewModel
    @State private var draft = ""
    @State private var editingNote: PersonNote?
    @State private var editText = ""
    @State private var isMoving = false
    @Environment(\.dismiss) private var dismiss

    init(repo: HiyaRepository, person: Person) {
        self.repo = repo
        self.person = person
        _vm = State(initialValue: PersonDetailViewModel(repo: repo, person: person))
    }

    private var canAdd: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        header
                        notesSection
                        if person.status == .cold {
                            moveToWarmButton
                        }
                        if let error = vm.errorMessage {
                            Text(error)
                                .font(Theme.FontScale.secondary())
                                .foregroundColor(Theme.valenceNegative)
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(Theme.textSecondary)
                        .font(Theme.FontScale.body())
                }
                ToolbarItem(placement: .principal) {
                    Text(person.name)
                        .font(Theme.FontScale.body())
                        .foregroundColor(Theme.textPrimary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task { await vm.load() }
        .alert("Edit note", isPresented: Binding(
            get: { editingNote != nil },
            set: { if !$0 { editingNote = nil } }
        )) {
            TextField("Note", text: $editText, axis: .vertical)
            Button("Save") {
                if let n = editingNote {
                    let t = editText
                    Task { await vm.edit(n, to: t) }
                }
                editingNote = nil
            }
            Button("Cancel", role: .cancel) { editingNote = nil }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                if person.status == .cold {
                    Text("JUST MET")
                        .font(Theme.FontScale.micro())
                        .tracking(1.2)
                        .foregroundColor(Theme.accentAmber)
                }
                Text("Last seen \(relative(person.lastLoggedAt))")
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("NOTES")
                .font(Theme.FontScale.bodyHeading())
                .tracking(1.2)
                .foregroundColor(Theme.textSecondary)

            addRow

            if vm.notes.isEmpty {
                Text("No notes yet. Jot down what you learn about \(person.name) — each note is dated.")
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(vm.notes) { note in
                    noteRow(note)
                }
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TextField("Add a note…", text: $draft, axis: .vertical)
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1...4)
                .padding(12)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            Button {
                let t = draft
                draft = ""
                Task { await vm.add(t) }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(canAdd ? Theme.accentLavender : Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(!canAdd || vm.isWorking)
        }
    }

    private func noteRow(_ note: PersonNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateLine(note))
                .font(Theme.FontScale.micro())
                .tracking(0.8)
                .foregroundColor(Theme.textSecondary)
            Text(note.body)
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .contentShape(Rectangle())
        .onTapGesture {
            editText = note.body
            editingNote = note
        }
        .contextMenu {
            Button {
                editText = note.body
                editingNote = note
            } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) {
                Task { await vm.delete(note) }
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var moveToWarmButton: some View {
        Button {
            Task { await moveToWarm() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.circle")
                Text("Move to Catch-ups")
            }
            .font(Theme.FontScale.body())
            .foregroundColor(Theme.accentLavender)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accentLavender.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
        .buttonStyle(.plain)
        .disabled(isMoving)
    }

    private func moveToWarm() async {
        isMoving = true
        defer { isMoving = false }
        do {
            try await repo.updatePersonStatus(id: person.id, status: .warm)
            // Someone you already knew was never a cold approach — reclassify
            // their logs so they leave the Approaches tally (today and history).
            try await repo.reclassifyConversations(personId: person.id, wasCold: false)
            dismiss()
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }

    private func dateLine(_ note: PersonNote) -> String {
        let learned = "Learned " + note.createdAt.formatted(date: .abbreviated, time: .omitted)
        if let edited = note.updatedAt {
            return learned + " · edited " + edited.formatted(date: .abbreviated, time: .omitted)
        }
        return learned
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: .now)
    }
}

#Preview {
    PersonDetailSheet(
        repo: MockHiyaRepository(),
        person: Person(
            id: UUID(),
            ownerId: UUID(),
            name: "Alex",
            status: .warm,
            statusChangedAt: .now,
            notes: "Met at the climbing gym.",
            createdAt: .now,
            lastLoggedAt: .now
        )
    )
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
cd /Users/williamjin/Documents/Hiya
xcodebuild build -project hiya/hiya.xcodeproj -scheme hiya \
  -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Views/PersonDetailSheet.swift
git commit -m "feat(notes): timeline UI in PersonDetailSheet

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Full suite + final verification

**Files:** none (verification only)

- [ ] **Step 1: Run the complete suite (clean, since tests were added)**

Run:
```bash
cd /Users/williamjin/Documents/Hiya
xcodebuild clean test -project hiya/hiya.xcodeproj -scheme hiya \
  -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  2>&1 | tee /tmp/hiya_test.log | tail -40
```

- [ ] **Step 2: Confirm the count**

Run:
```bash
grep -E "Test run with .* tests (passed|failed)|failed \(|error:" /tmp/hiya_test.log | tail -20
```
Expected: previous 85 tests + 9 (Task 2) + 5 (Task 5) = **99 tests, 0 failures**. If the count is short, a newly added test wasn't discovered — re-run `clean test` (DerivedData discovery caching).

- [ ] **Step 3: Confirm working tree is clean and pushed**

Run:
```bash
cd /Users/williamjin/Documents/Hiya
git status -sb
```
Expected: `## main...origin/main` with nothing to commit. (Push happens per the user's normal flow; do not push unless asked.)

---

## Self-Review Notes (already reconciled)

- **Spec coverage:** table+RLS+backfill (Task 4), `PersonNote` model (Task 1), four repo methods + differentiator recompute + `createPerson` seeding (Tasks 2–3), `PersonDetailViewModel` (Task 5), timeline UI with dated entries + edit/delete + retained move-to-warm (Task 6). Differentiator-sync rules are exercised by the Task 2 tests (add/second/edit-oldest/edit-newer/delete-oldest/delete-last).
- **Standalone-only:** logging a conversation note on an existing person is untouched; the only automatic entry is the `createPerson` seed (Tasks 2 & 3).
- **Edit semantics:** `updatePersonNote` sets `updated_at` and preserves `created_at` (verified in `updatePersonNote_onOldest_…` test); UI shows both via `dateLine`.
- **Differentiator source = oldest:** `recomputeDifferentiator` uses `min(by: createdAt)` (Mock) / `order created_at asc limit 1` (Live).
- **Method-name consistency:** `personNotes` / `addPersonNote` / `updatePersonNote` / `deletePersonNote` and `recomputeDifferentiator` are spelled identically across protocol, Mock, Live, VM, and tests.
- **Build-ordering caveat:** Task 3 must land before Task 2's test run because the protocol grew (called out in Task 2 Step 5 and Task 3 Step 3).
- **Deviation from spec wording:** spec said "swipe to delete"; in a `ScrollView` (not a `List`) the plan uses tap-to-edit + a context menu (Edit/Delete) instead — same capability, correct for the existing view structure.
```