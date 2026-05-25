# Color Flip, Location, and Backdating — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flip cold/warm semantic colors (cold→lavender, warm→amber), add a durable cold-origin flag with chronological meeting classification (enables backdating), and add an optional per-meeting location with map autocomplete.

**Architecture:** Three sequenced phases — A (color flip, view-only) → C (backdating + `met_cold`, data model) → B (location). Cold/warm classification moves from a status snapshot to a DB recompute keyed on a durable `people.met_cold` flag, mirrored in `MockHiyaRepository`. Color semantics are centralized in `Theme` so the flip is one place.

**Tech Stack:** SwiftUI (iOS 18.6, Xcode 26.1), Swift Testing, Supabase (Postgres + RLS + triggers), MapKit (`MKLocalSearchCompleter`).

**Conventions:**
- **Test command (editing existing tests):**
  ```bash
  cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild test \
    -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
    2>&1 | tee /tmp/hiya_test.log | grep -E "TEST (SUCCEEDED|FAILED)|failures"
  ```
- **When ADDING new test functions/files**, use `clean test` instead of `test` (DerivedData caches Swift Testing discovery).
- **Build only (no tests):** replace `test` with `build`.
- **Migrations:** `cd /Users/williamjin/Documents/Hiya && supabase db push --yes` (user has authorized running migrations).
- SourceKit may emit transient "Cannot find type / No such module" diagnostics mid-edit — ignore; `xcodebuild` is the source of truth.
- Commit directly to `main`. End commit messages with the `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer.

---

## File Structure

**Phase A (color flip):**
- Modify `hiya/hiya/Theme.swift` — add `coldAccent`, `warmAccent`, `accent(for:)`, `gradient(for:)`.
- Modify `hiya/hiya/Views/{HomeView,PeopleView,PersonDetailSheet,HistoryView,InsightsView,AddChallengeSheet,ChallengesView,LogSheetView,ProgressRingView}.swift` — flip semantic color sites.
- Create `hiya/hiyaTests/ThemeTests.swift` — lock the flip direction.

**Phase C (backdating + met_cold):**
- Create `supabase/migrations/20260525120000_add_met_cold_chronological_classification.sql`.
- Modify `hiya/hiya/Models/Person.swift` — add `metCold`.
- Modify `hiya/hiya/Services/HiyaRepository.swift` — `createPerson(...metCold:)`, new `updatePersonMetCold(id:metCold:)`.
- Modify `hiya/hiya/Services/MockHiyaRepository.swift` — `metCold`, `recomputeColdFlags`, rewrite `logConversation` classification, `updatePersonMetCold`.
- Modify `hiya/hiya/ViewModels/LogSheetViewModel.swift` — editable `origin`, pass `metCold` on create.
- Modify `hiya/hiya/Views/LogSheetView.swift` — origin segmented control for new people.
- Modify `hiya/hiya/Views/PersonDetailSheet.swift` — "Log a past meeting" button; switch `moveToWarm` to `updatePersonMetCold`.
- Modify `hiya/hiyaTests/MockHiyaRepositoryTests.swift`, create `hiya/hiyaTests/LogSheetViewModelTests.swift`.

**Phase B (location):**
- Create `supabase/migrations/20260525130000_add_meeting_location.sql`.
- Modify `hiya/hiya/Models/Conversation.swift` — add `location`.
- Modify `hiya/hiya/Services/HiyaRepository.swift` — `LoggedConversation.location`, `logConversation/updateConversation(...location:)`, Live row decoders.
- Modify `hiya/hiya/Services/MockHiyaRepository.swift` — store/return `location`.
- Create `hiya/hiya/ViewModels/LocationSearchModel.swift` — MapKit autocomplete.
- Modify `hiya/hiya/ViewModels/LogSheetViewModel.swift` — `location`.
- Modify `hiya/hiya/Views/LogSheetView.swift` — WHERE section.
- Modify `hiya/hiya/Views/PersonDetailSheet.swift` — show location in interaction rows.
- Modify tests.

---

# PHASE A — Color Flip

### Task A1: Centralize semantic accents in Theme

**Files:**
- Modify: `hiya/hiya/Theme.swift` (after the `accentGradientReversed` block, ~line 45)
- Test: `hiya/hiyaTests/ThemeTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `hiya/hiyaTests/ThemeTests.swift`:
```swift
import Testing
import SwiftUI
@testable import hiya

struct ThemeTests {
    @Test func accent_coldIsLavender_warmIsAmber() {
        #expect(Theme.accent(for: .cold) == Theme.accentLavender)
        #expect(Theme.accent(for: .warm) == Theme.accentAmber)
        #expect(Theme.coldAccent == Theme.accentLavender)
        #expect(Theme.warmAccent == Theme.accentAmber)
    }
}
```

- [ ] **Step 2: Run test to verify it fails** — Run the `clean test` command. Expected: FAIL (no `accent(for:)` / `coldAccent`).

- [ ] **Step 3: Implement.** In `hiya/hiya/Theme.swift`, immediately after the `accentGradientReversed` static property (before `// MARK: - Font PostScript names`), add:
```swift
    // MARK: - Semantic mode accents
    //
    // Approaches (cold) read cool; Catch-ups (warm) read warm. Neutral chrome
    // (tab tint, buttons, gear) keeps using `accentLavender` directly — it is
    // not a cold/warm signal. Flip both lines below to re-theme the modes.
    static let coldAccent = accentLavender
    static let warmAccent = accentAmber

    static func accent(for status: PersonStatus) -> Color {
        status == .cold ? coldAccent : warmAccent
    }

    /// Ring gradient per mode: each leads with its own mode's color. (Cold leads
    /// lavender via `accentGradient`; warm leads amber via `accentGradientReversed`.)
    static func gradient(for status: PersonStatus) -> LinearGradient {
        status == .cold ? accentGradient : accentGradientReversed
    }
```

- [ ] **Step 4: Run test to verify it passes** — `clean test`. Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Theme.swift hiya/hiyaTests/ThemeTests.swift
git commit -m "feat(theme): semantic cold/warm accent helpers (cold→lavender, warm→amber)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task A2: Flip semantic color sites across views

**Files (modify each):** `HomeView.swift`, `PeopleView.swift`, `PersonDetailSheet.swift`, `HistoryView.swift`, `InsightsView.swift`, `AddChallengeSheet.swift`, `ChallengesView.swift`, `LogSheetView.swift`, `ProgressRingView.swift` (all under `hiya/hiya/Views/`).

**Rule:** anywhere a color currently encodes cold/warm meaning, flip it: **cold → lavender, warm → amber**. Leave *neutral chrome* lavender (tab tint, gear, "+"/Save/action buttons, date-picker tint, person chips) untouched.

- [ ] **Step 1: HomeView.swift** — apply these exact edits:
  - Line ~86–87 (mode buttons):
    ```swift
    modeButton(.cold, label: "Approaches", color: Theme.coldAccent)
    modeButton(.warm, label: "Catch-ups", color: Theme.warmAccent)
    ```
  - Line ~118 (ring gradient): `gradient: Theme.gradient(for: pageMode)`
  - Line ~136: `let color = Theme.accent(for: pageMode)`
  - Line ~156: `let accent = Theme.accent(for: pageMode)`
  - Line ~207 (challenge card accent — flip the literals):
    ```swift
    let accent = challenge.track == .warm ? Theme.accentAmber : Theme.accentLavender
    ```
  - Leave lines 41 (gear), 48 (wordmark gradient), 55 (target icon), 248 (lavender fill) as-is — neutral chrome.

- [ ] **Step 2: ProgressRingView.swift** — make the at-goal center content + burst follow the ring's mode instead of fixed amber.
  - Add a stored accent (line ~5, after `gradient`):
    ```swift
    var accent: Color = Theme.accentAmber
    ```
  - Line ~29: `GoalBurst(color: accent)`
  - Lines ~82, 86, 92, 97: replace each `Theme.accentAmber` in `centerContent` with `accent`.
  - In `HomeView.swift` where `ProgressRingView(...)` is constructed (same place as the `gradient:` arg, ~line 118), add `accent: Theme.accent(for: pageMode)`.
  - Leave `glowColor` / `Theme.Glow.*` untouched (subtle blur, not a primary signal).

- [ ] **Step 3: PeopleView.swift**
  - Line ~107 ("JUST MET" header): `.foregroundColor(Theme.coldAccent)`
  - Lines ~206–209 (`ConsistencyStrip.color(for:)`):
    ```swift
    case .coldActive: Theme.coldAccent
    case .coldIdle:   Theme.coldAccent.opacity(0.15)
    case .warmActive: Theme.warmAccent
    case .warmIdle:   Theme.warmAccent.opacity(0.15)
    ```
  - Leave line ~31 ("+" button) lavender.

- [ ] **Step 4: PersonDetailSheet.swift**
  - Line ~85 ("JUST MET" label): `.foregroundColor(Theme.coldAccent)`
  - Leave lines ~195, 242, 245 (add-note button, Move-to-Catch-ups button) lavender — action chrome.

- [ ] **Step 5: HistoryView.swift** — flip the cold/warm-keyed sites:
  - Line ~177 (legend "approaches" dot): `Circle().fill(Theme.coldAccent)`
  - Line ~183 (legend "catch-ups" dot): `Circle().fill(Theme.warmAccent)`
  - Line ~327 (`heatTint`, hadCold): `return Theme.coldAccent.opacity(intensity)`
  - Line ~328 (`heatTint`, else/warm): `return Theme.warmAccent.opacity(intensity)`
  - Line ~334 (`borderColor`, mixed cold+warm day) — the mixed-day border marks "this cold day also had warm"; keep it the *warm* accent now: `return Theme.warmAccent.opacity(0.65)`
  - Lines ~347 (`coldCount` text): `.foregroundColor(Theme.coldAccent)`
  - Line ~351 (warm count text): `.foregroundColor(Theme.warmAccent)`
  - Line ~399 (DayHeader approaches count): `.foregroundColor(Theme.coldAccent)`
  - Leave line ~367 (today pulse shadow, `Theme.accentLavender`) — neutral "today" highlight.

- [ ] **Step 6: InsightsView.swift**
  - Lines ~85–86 (`chartForegroundStyleScale`):
    ```swift
    "Approaches": Theme.coldAccent,
    "Catch-ups": Theme.warmAccent
    ```
  - Line ~98 (`becameRegulars` number — the cold→warm conversion count; lead with cold): `.foregroundColor(Theme.coldAccent)`
  - Line ~107 (`% conversion` caption — represents conversion into warm; use warm): `.foregroundColor(Theme.warmAccent)`

- [ ] **Step 7: AddChallengeSheet.swift & ChallengesView.swift** — both have a track→color switch (`AddChallengeSheet` ~198–199, `ChallengesView` ~171–172):
    ```swift
    case .cold: Theme.coldAccent
    case .warm: Theme.warmAccent
    ```

- [ ] **Step 8: LogSheetView.swift**
  - Line ~130 ("Add new <name>" plus icon) — neutralize to the app action accent: `.foregroundColor(Theme.accentLavender)`. (It's an action affordance, not a mode signal; this avoids a lone amber icon.)
  - Leave lines ~172, 190, 271, 274 (person chip, date-picker tint, Save button) lavender.

- [ ] **Step 9: Build to verify it compiles**
```bash
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild build \
  -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  2>&1 | tee /tmp/hiya_build.log | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 10: Manual check (optional but recommended).** Launch the app; confirm: Home cold mode reads lavender (ring + toggle), warm reads amber; People "JUST MET" header lavender; activity strip cold bars lavender / warm bars amber; History legend + heatmap swapped; Insights chart legend swapped. Neutral buttons/tabs still lavender.

- [ ] **Step 11: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Views
git commit -m "style: flip cold/warm semantics — cold reads lavender, warm reads amber

Routes mode colors through Theme.coldAccent/warmAccent/accent(for:). The ring
gradients align with the new semantics automatically (the old 'oxymoron' was
defined against the previous mapping); neutral chrome stays lavender.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

# PHASE C — Backdating + durable cold origin (`met_cold`)

### Task C1: Migration — `met_cold` + chronological recompute

**Files:**
- Create: `supabase/migrations/20260525120000_add_met_cold_chronological_classification.sql`

- [ ] **Step 1: Write the migration**
```sql
-- Durable "this relationship began as a cold approach" flag, independent of
-- the live cold/warm bucket (which graduates over time). Classification of
-- was_cold_at_time moves from a status snapshot to a chronological recompute.

alter table public.people
  add column met_cold boolean not null default false;

-- Backfill: met cold if still cold (a pending approach) or any conversation
-- was logged while cold.
update public.people p
   set met_cold = true
 where p.status = 'cold'
    or exists (
      select 1 from public.conversations c
       where c.person_id = p.id and c.was_cold_at_time
    );

-- Retire the BEFORE INSERT status snapshot — classification is now chronological.
drop trigger if exists set_was_cold_at_time_before_insert on public.conversations;
drop function if exists public.set_was_cold_at_time();

-- Recompute one person's flags: earliest meeting (occurred_at, id) is cold iff
-- met_cold; every other meeting is warm.
create or replace function public.recompute_cold_flags(p uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  earliest uuid;
  is_cold boolean;
begin
  select met_cold into is_cold from public.people where id = p;
  update public.conversations set was_cold_at_time = false
   where person_id = p and was_cold_at_time;
  if coalesce(is_cold, false) then
    select id into earliest
      from public.conversations
     where person_id = p
     order by occurred_at asc, id asc
     limit 1;
    if earliest is not null then
      update public.conversations set was_cold_at_time = true where id = earliest;
    end if;
  end if;
end;
$$;

-- Trigger glue for conversations. Recompute only fires on inserts/deletes and
-- on changes to occurred_at/person_id, so the was_cold_at_time UPDATE inside
-- recompute does NOT re-fire it (no recursion).
create or replace function public.recompute_cold_flags_on_conversation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'DELETE') then
    perform public.recompute_cold_flags(old.person_id);
    return old;
  end if;
  perform public.recompute_cold_flags(new.person_id);
  if (tg_op = 'UPDATE' and old.person_id is distinct from new.person_id) then
    perform public.recompute_cold_flags(old.person_id);
  end if;
  return new;
end;
$$;

drop trigger if exists recompute_cold_flags_conv on public.conversations;
create trigger recompute_cold_flags_conv
  after insert or delete or update of occurred_at, person_id
  on public.conversations
  for each row execute function public.recompute_cold_flags_on_conversation();

-- Trigger glue for people: recompute when met_cold changes.
create or replace function public.recompute_cold_flags_on_person()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.recompute_cold_flags(new.id);
  return new;
end;
$$;

drop trigger if exists recompute_cold_flags_person on public.people;
create trigger recompute_cold_flags_person
  after update of met_cold on public.people
  for each row execute function public.recompute_cold_flags_on_person();

-- One-time normalize for existing data.
do $$
declare r record;
begin
  for r in select id from public.people loop
    perform public.recompute_cold_flags(r.id);
  end loop;
end $$;
```

- [ ] **Step 2: Apply the migration**
```bash
cd /Users/williamjin/Documents/Hiya && supabase db push --yes
```
Expected: applies `20260525120000_add_met_cold_chronological_classification` with no errors.

- [ ] **Step 3: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add supabase/migrations/20260525120000_add_met_cold_chronological_classification.sql
git commit -m "feat(db): met_cold flag + chronological was_cold_at_time recompute

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task C2: `Person.metCold` model field

**Files:**
- Modify: `hiya/hiya/Models/Person.swift`

- [ ] **Step 1: Add the property.** After `var notes: String? = nil` add:
```swift
    var metCold: Bool = false
```
- [ ] **Step 2: Add the CodingKey.** After `case notes` add:
```swift
        case metCold = "met_cold"
```
- [ ] **Step 3: Build** (no behavior change yet). Expected: BUILD SUCCEEDED. (`metCold` has a default so existing `Person(...)` call sites still compile.)
- [ ] **Step 4: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Models/Person.swift
git commit -m "feat(model): Person.metCold

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task C3: Repository — `createPerson(metCold:)` + `updatePersonMetCold`

**Files:**
- Modify: `hiya/hiya/Services/HiyaRepository.swift` (protocol + Live)

- [ ] **Step 1: Protocol.** Change the `createPerson` requirement (line ~7) to:
```swift
    func createPerson(name: String, status: PersonStatus, notes: String?, metCold: Bool) async throws -> Person
```
Add after `func updatePersonStatus(...)`:
```swift
    func updatePersonMetCold(id: UUID, metCold: Bool) async throws
```

- [ ] **Step 2: Live `createPerson`.** Update the signature default and `Insert` struct:
```swift
    func createPerson(name: String, status: PersonStatus = .cold, notes: String? = nil, metCold: Bool = false) async throws -> Person {
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
            let met_cold: Bool
        }
        let inserted: Person = try await client
            .from("people")
            .insert(Insert(
                owner_id: userId,
                name: trimmed,
                status: status.rawValue,
                status_changed_at: status == .warm ? Date.now.iso8601String : nil,
                notes: seed,
                met_cold: metCold
            ))
            .select()
            .single()
            .execute()
            .value
```
(Leave the rest of the method — the note-seed block and `return inserted` — unchanged.)

- [ ] **Step 3: Live `updatePersonMetCold`.** Add near `updatePersonStatus`:
```swift
    func updatePersonMetCold(id: UUID, metCold: Bool) async throws {
        struct Update: Encodable { let met_cold: Bool }
        try await client
            .from("people")
            .update(Update(met_cold: metCold))
            .eq("id", value: id)
            .execute()
    }
```

- [ ] **Step 4: Build.** (Call sites compile via Mock change in C4; build will fail until C4 + C5 done — so defer the build verify to C5. Skip building here.)

- [ ] **Step 5: Commit** (after C4 compiles — or commit C3+C4+C5 together at end of C5). Recommend committing C3–C5 as one unit; mark this task's commit step "done via C5".

---

### Task C4: Mock — `metCold`, `recomputeColdFlags`, classification

**Files:**
- Modify: `hiya/hiya/Services/MockHiyaRepository.swift`

- [ ] **Step 1: `createPerson`.** Add `metCold` param + set it on the Person:
```swift
    func createPerson(name: String, status: PersonStatus = .cold, notes: String? = nil, metCold: Bool = false) async throws -> Person {
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
            metCold: metCold,
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

- [ ] **Step 2: Rewrite `logConversation`** to append then recompute (drop the status snapshot):
```swift
    func logConversation(
        personId: UUID,
        occurredAt: Date = .now,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        let conv = Conversation(
            id: UUID(),
            ownerId: profile.id,
            personId: personId,
            occurredAt: occurredAt,
            valence: valence,
            note: note,
            improvementNote: improvementNote,
            wasColdAtTime: false,
            createdAt: .now
        )
        conversations.append(conv)
        // Mirror the DB trigger: last_logged_at only ever moves forward.
        if let idx = people.firstIndex(where: { $0.id == personId }), people[idx].lastLoggedAt < occurredAt {
            people[idx].lastLoggedAt = occurredAt
        }
        recomputeColdFlags(personId: personId)
    }
```

- [ ] **Step 3: `updateConversation`** — recompute after mutating occurred_at:
At the end of the existing `updateConversation` body (after setting fields), add:
```swift
        recomputeColdFlags(personId: conversations[idx].personId)
```

- [ ] **Step 4: `deleteConversation`** — recompute the affected person after removal:
```swift
    func deleteConversation(id: UUID) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        let personId = conversations.first(where: { $0.id == id })?.personId
        conversations.removeAll { $0.id == id }
        if let personId { recomputeColdFlags(personId: personId) }
    }
```

- [ ] **Step 5: `updatePersonMetCold`.** Add near `updatePersonStatus`:
```swift
    func updatePersonMetCold(id: UUID, metCold: Bool) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        guard let i = people.firstIndex(where: { $0.id == id }) else { return }
        people[i].metCold = metCold
        recomputeColdFlags(personId: id)
    }
```

- [ ] **Step 6: Add `recomputeColdFlags`** (private, near `recomputeDifferentiator`):
```swift
    /// Mirror the DB recompute: a met_cold person's chronologically earliest
    /// meeting is cold and the rest warm; a non-met_cold person's are all warm.
    private func recomputeColdFlags(personId: UUID) {
        guard let person = people.first(where: { $0.id == personId }) else { return }
        let mine = conversations.indices.filter { conversations[$0].personId == personId }
        for i in mine { conversations[i].wasColdAtTime = false }
        guard person.metCold else { return }
        let earliest = mine.min { a, b in
            if conversations[a].occurredAt != conversations[b].occurredAt {
                return conversations[a].occurredAt < conversations[b].occurredAt
            }
            return conversations[a].id.uuidString < conversations[b].id.uuidString
        }
        if let earliest { conversations[earliest].wasColdAtTime = true }
    }
```

- [ ] **Step 7: Build** to confirm C3+C4 compile together.
```bash
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild build \
  -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  2>&1 | tee /tmp/hiya_build.log | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```
Expected: BUILD SUCCEEDED. (Other `createPerson` callers — `PeopleViewModel.addPerson`, `LogSheetViewModel.save` — still compile because `metCold` defaults to `false` on the concrete types; the protocol existential calls that omit it are addressed in C5/C6.)

> ⚠️ Protocol note: callers using `repo` typed as `HiyaRepository` cannot rely on the default arg. `PeopleViewModel.addPerson` calls `createPerson(name:status:notes:)` through the protocol — it MUST be updated to pass `metCold:`. Do it now:
- In `hiya/hiya/ViewModels/PeopleViewModel.swift` (~line 118): `_ = try await self.repo.createPerson(name: trimmed, status: .warm, notes: notes, metCold: false)`

- [ ] **Step 8: Commit C3+C4 together**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Services/HiyaRepository.swift hiya/hiya/Services/MockHiyaRepository.swift hiya/hiya/ViewModels/PeopleViewModel.swift
git commit -m "feat(repo): metCold + chronological cold-flag recompute (mock + live)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task C5: Tests — classification under backdating

**Files:**
- Modify: `hiya/hiyaTests/MockHiyaRepositoryTests.swift`

- [ ] **Step 1: Add tests** (append inside the test struct). These use `repo.conversations` directly (a `var` on the Mock) sorted by `occurredAt`:
```swift
    @Test func metCold_earliestMeetingIsColdRestWarm() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Angie", status: .cold, notes: nil, metCold: true)
        let cal = Calendar.current
        func day(_ ago: Int) -> Date { cal.date(byAdding: .day, value: -ago, to: .now)! }
        // Insert out of chronological order.
        try await repo.logConversation(personId: p.id, occurredAt: day(2), valence: nil, note: "gym tue", improvementNote: nil)
        try await repo.logConversation(personId: p.id, occurredAt: day(7), valence: nil, note: "met sunday", improvementNote: nil)
        try await repo.logConversation(personId: p.id, occurredAt: day(0), valence: nil, note: "gym today", improvementNote: nil)

        let sorted = repo.conversations.filter { $0.personId == p.id }.sorted { $0.occurredAt < $1.occurredAt }
        #expect(sorted.first?.note == "met sunday")
        #expect(sorted.first?.wasColdAtTime == true)
        #expect(sorted.dropFirst().allSatisfy { $0.wasColdAtTime == false })
    }

    @Test func notMetCold_allMeetingsWarm() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Old Friend", status: .warm, notes: nil, metCold: false)
        try await repo.logConversation(personId: p.id, valence: nil, note: nil, improvementNote: nil)
        try await repo.logConversation(personId: p.id, valence: nil, note: nil, improvementNote: nil)
        #expect(repo.conversations.allSatisfy { $0.wasColdAtTime == false })
    }

    @Test func updatePersonMetCold_flipsClassification() async throws {
        let repo = MockHiyaRepository()
        let cal = Calendar.current
        let p = try await repo.createPerson(name: "Sam", status: .warm, notes: nil, metCold: false)
        try await repo.logConversation(personId: p.id, occurredAt: cal.date(byAdding: .day, value: -3, to: .now)!, valence: nil, note: "first", improvementNote: nil)
        try await repo.logConversation(personId: p.id, occurredAt: .now, valence: nil, note: "second", improvementNote: nil)
        #expect(repo.conversations.allSatisfy { $0.wasColdAtTime == false })

        try await repo.updatePersonMetCold(id: p.id, metCold: true)
        let sorted = repo.conversations.sorted { $0.occurredAt < $1.occurredAt }
        #expect(sorted.first?.wasColdAtTime == true)
        #expect(sorted.last?.wasColdAtTime == false)

        try await repo.updatePersonMetCold(id: p.id, metCold: false)
        #expect(repo.conversations.allSatisfy { $0.wasColdAtTime == false })
    }

    @Test func deletingEarliest_promotesNextEarliestToCold() async throws {
        let repo = MockHiyaRepository()
        let cal = Calendar.current
        let p = try await repo.createPerson(name: "Angie", status: .cold, notes: nil, metCold: true)
        try await repo.logConversation(personId: p.id, occurredAt: cal.date(byAdding: .day, value: -5, to: .now)!, valence: nil, note: "earliest", improvementNote: nil)
        try await repo.logConversation(personId: p.id, occurredAt: .now, valence: nil, note: "later", improvementNote: nil)
        let earliestId = repo.conversations.min { $0.occurredAt < $1.occurredAt }!.id

        try await repo.deleteConversation(id: earliestId)

        #expect(repo.conversations.count == 1)
        #expect(repo.conversations.first?.note == "later")
        #expect(repo.conversations.first?.wasColdAtTime == true)
    }

    @Test func createPerson_metCold_persists() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "X", status: .cold, notes: nil, metCold: true)
        #expect(repo.people.first(where: { $0.id == p.id })?.metCold == true)
    }
```

- [ ] **Step 2: Run tests** with `clean test` (new tests added). Expected: TEST SUCCEEDED, all five pass. (Pre-existing tests that call `createPerson(name:)` still pass — `metCold` defaults to `false` on the concrete `MockHiyaRepository`.)

- [ ] **Step 3: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiyaTests/MockHiyaRepositoryTests.swift
git commit -m "test(repo): chronological cold-flag classification under backdating

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task C6: Log sheet — editable origin sets `metCold`

**Files:**
- Modify: `hiya/hiya/ViewModels/LogSheetViewModel.swift`
- Modify: `hiya/hiya/Views/LogSheetView.swift`
- Create: `hiya/hiyaTests/LogSheetViewModelTests.swift`

- [ ] **Step 1: VM — replace `creationMode` with an editable `origin`.** In `LogSheetViewModel.swift`:
  - Change the stored property (line ~22) from `private let creationMode: PersonStatus` to:
    ```swift
    /// How a *new* person is created: `.cold` = a cold approach (met_cold), `.warm`
    /// = someone you already knew. Editable in the sheet when creating a new person.
    var origin: PersonStatus
    ```
  - In `init`, replace `self.creationMode = creationMode` with `self.origin = creationMode`.
  - In `filteredPeople` (line ~35): `guard origin == .warm else { return [] }`
  - In `save()` fold-existing branch (line ~138): `if origin == .warm,`
  - In `save()` create branch (line ~160):
    ```swift
    let created = try await repo.createPerson(name: name, status: origin, notes: noteToSend, metCold: origin == .cold)
    ```

- [ ] **Step 2: View — origin picker for new people.** In `LogSheetView.swift`, inside `personSection`, in the `else` branch (the non-editing path), directly after the `TextField("Add a person", ...)` block, add:
```swift
                if vm.canAddTypedName {
                    Picker("How did you meet?", selection: $vm.origin) {
                        Text("Cold approach").tag(PersonStatus.cold)
                        Text("Already knew them").tag(PersonStatus.warm)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)
                }
```

- [ ] **Step 3: Write VM tests** — create `hiya/hiyaTests/LogSheetViewModelTests.swift`:
```swift
import Testing
import Foundation
@testable import hiya

@MainActor
struct LogSheetViewModelTests {
    @Test func newColdApproach_createsMetColdPerson() async throws {
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo, creationMode: .cold)
        await vm.load()
        vm.searchText = "Angie"
        #expect(vm.origin == .cold)

        let ok = await vm.save()
        #expect(ok)
        let angie = repo.people.first { $0.name == "Angie" }
        #expect(angie?.metCold == true)
        #expect(angie?.status == .cold)
    }

    @Test func alreadyKnew_createsWarmNotMetCold() async throws {
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo, creationMode: .cold)
        await vm.load()
        vm.searchText = "Old Friend"
        vm.origin = .warm

        let ok = await vm.save()
        #expect(ok)
        let friend = repo.people.first { $0.name == "Old Friend" }
        #expect(friend?.metCold == false)
        #expect(friend?.status == .warm)
    }

    @Test func backdatedFirstMeeting_isCold() async throws {
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo, creationMode: .cold)
        await vm.load()
        vm.searchText = "Angie"
        vm.occurredAt = Calendar.current.date(byAdding: .day, value: -7, to: .now)!

        _ = await vm.save()
        #expect(repo.conversations.first?.wasColdAtTime == true)
    }
}
```

- [ ] **Step 4: Run tests** with `clean test` (new file). Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/ViewModels/LogSheetViewModel.swift hiya/hiya/Views/LogSheetView.swift hiya/hiyaTests/LogSheetViewModelTests.swift
git commit -m "feat(log): choosable origin (cold approach vs already knew them) for new people

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task C7: Detail sheet — "Log a past meeting" + Move-to-Catch-ups uses `met_cold`

**Files:**
- Modify: `hiya/hiya/Views/PersonDetailSheet.swift`

- [ ] **Step 1: Switch `moveToWarm`** to clear `met_cold` instead of `reclassifyConversations`. Replace the body's reclassify line (~259):
```swift
            try await repo.updatePersonStatus(id: person.id, status: .warm)
            // They were never a cold approach — clear the cold origin so the
            // recompute marks all their meetings as warm catch-ups.
            try await repo.updatePersonMetCold(id: person.id, metCold: false)
            dismiss()
```
(Remove the `reclassifyConversations` call.)

- [ ] **Step 2: Add a "Log a past meeting" entry point.** Add state + sheet to `PersonDetailSheet`:
  - Add property: `@State private var loggingPast = false`
  - In the `VStack` (after `interactionsSection`, before `notesSection`), add a button:
    ```swift
    Button {
        loggingPast = true
    } label: {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus")
            Text("Log a past meeting")
        }
        .font(Theme.FontScale.body())
        .foregroundColor(Theme.accentLavender)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.accentLavender.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
    .buttonStyle(.plain)
    ```
  - Add the sheet modifier (alongside the existing `.alert`):
    ```swift
    .sheet(isPresented: $loggingPast, onDismiss: { Task { await vm.load() } }) {
        LogSheetView(repo: repo, preselectedPerson: person)
    }
    ```

- [ ] **Step 3: Build.** Expected: BUILD SUCCEEDED.
```bash
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild build \
  -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  2>&1 | tee /tmp/hiya_build.log | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

- [ ] **Step 4: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Views/PersonDetailSheet.swift
git commit -m "feat(people): 'Log a past meeting' entry point; Move-to-Catch-ups clears met_cold

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

# PHASE B — Per-meeting location (map autocomplete)

### Task B1: Migration — `conversations.location`

**Files:**
- Create: `supabase/migrations/20260525130000_add_meeting_location.sql`

- [ ] **Step 1: Write the migration**
```sql
-- Optional free-text location per meeting (place name or address).
alter table public.conversations
  add column location text;
```
- [ ] **Step 2: Apply** — `cd /Users/williamjin/Documents/Hiya && supabase db push --yes`. Expected: applies cleanly.
- [ ] **Step 3: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add supabase/migrations/20260525130000_add_meeting_location.sql
git commit -m "feat(db): conversations.location

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task B2: Models + repo carry `location`

**Files:**
- Modify: `hiya/hiya/Models/Conversation.swift`
- Modify: `hiya/hiya/Services/HiyaRepository.swift`
- Modify: `hiya/hiya/Services/MockHiyaRepository.swift`

- [ ] **Step 1: `Conversation`.** Add `var location: String? = nil` after `var improvementNote: String? = nil`, and `case location` to `CodingKeys` (after `case improvementNote`).

- [ ] **Step 2: `LoggedConversation`** (in `HiyaRepository.swift`). Add `let location: String?` after `let improvementNote: String?`, and add an init param `location: String? = nil` (place after `wasColdAtTime: Bool = false`), assigning `self.location = location`.

- [ ] **Step 3: Protocol** — add `location` to both methods:
```swift
    func logConversation(
        personId: UUID,
        occurredAt: Date,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?,
        location: String?
    ) async throws
    func updateConversation(
        id: UUID,
        occurredAt: Date,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?,
        location: String?
    ) async throws
```

- [ ] **Step 4: Live `logConversation`** — add `location: String? = nil` param, `let location: String?` to `Insert`, and `location: location` to the insert call.

- [ ] **Step 5: Live `updateConversation`** — add `location: String? = nil` param, `let location: String?` to `Update`, and `location: location` to the update call.

- [ ] **Step 6: Live row decoders** — in BOTH `conversations(start:end:)` and `personConversations(personId:)`:
  - add `let location: String?` to the `Row` struct,
  - add `location` to the `.select("...")` string,
  - add `location: $0.location` to the `LoggedConversation(...)` mapping.

- [ ] **Step 7: Mock `logConversation`** — add `location: String? = nil` param; pass `location: location` into the `Conversation(...)` init (after `improvementNote`). Mock `updateConversation` — add `location: String? = nil` param and set `conversations[idx].location = location`. Mock `conversations(...)` and `personConversations(...)` mappings — add `location: conv.location` to each `LoggedConversation(...)`.

- [ ] **Step 8: Update the one non-test caller.** `LogSheetViewModel.save()` calls `logConversation` and `updateConversation` — add `location: nil` to both for now (real value wired in B4). This keeps the build green.

- [ ] **Step 9: Build.** Expected: BUILD SUCCEEDED.

- [ ] **Step 10: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Models/Conversation.swift hiya/hiya/Services/HiyaRepository.swift hiya/hiya/Services/MockHiyaRepository.swift hiya/hiya/ViewModels/LogSheetViewModel.swift
git commit -m "feat(model): per-meeting location plumbed through repo

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task B3: Location autocomplete model

**Files:**
- Create: `hiya/hiya/ViewModels/LocationSearchModel.swift`
- Test: `hiya/hiyaTests/LocationSearchModelTests.swift` (create)

- [ ] **Step 1: Write the failing test** — `hiya/hiyaTests/LocationSearchModelTests.swift`:
```swift
import Testing
@testable import hiya

struct LocationSearchModelTests {
    @Test func displayString_joinsTitleAndSubtitle() {
        #expect(LocationSuggestion(title: "Blue Bottle", subtitle: "1 Main St").displayString == "Blue Bottle, 1 Main St")
    }
    @Test func displayString_titleOnlyWhenNoSubtitle() {
        #expect(LocationSuggestion(title: "Blue Bottle", subtitle: "").displayString == "Blue Bottle")
    }
}
```

- [ ] **Step 2: Run** `clean test` — Expected: FAIL (no `LocationSuggestion`).

- [ ] **Step 3: Implement** `hiya/hiya/ViewModels/LocationSearchModel.swift`:
```swift
import Foundation
import MapKit
import Observation

struct LocationSuggestion: Identifiable, Equatable {
    let title: String
    let subtitle: String
    var id: String { displayString }
    var displayString: String { subtitle.isEmpty ? title : "\(title), \(subtitle)" }
}

@MainActor
@Observable
final class LocationSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [LocationSuggestion] = []

    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                suggestions = []
                completer.queryFragment = ""
            } else {
                completer.queryFragment = trimmed
            }
        }
    }

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results.prefix(4).map {
            LocationSuggestion(title: $0.title, subtitle: $0.subtitle)
        }
        Task { @MainActor in self.suggestions = Array(results) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.suggestions = [] }
    }

    func clear() {
        query = ""
        suggestions = []
    }
}
```

- [ ] **Step 4: Run** `clean test` — Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/ViewModels/LocationSearchModel.swift hiya/hiyaTests/LocationSearchModelTests.swift
git commit -m "feat(location): MapKit autocomplete model

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task B4: Log sheet — WHERE section + save location

**Files:**
- Modify: `hiya/hiya/ViewModels/LogSheetViewModel.swift`
- Modify: `hiya/hiya/Views/LogSheetView.swift`
- Modify: `hiya/hiyaTests/LogSheetViewModelTests.swift`

- [ ] **Step 1: VM — add `location` state.** In `LogSheetViewModel`:
  - Add `var location: String = ""` near `var note`.
  - In `init`, in the `if let editing` branch, add `location = editing.location ?? ""`.
  - In `save()`, compute `let locationToSend = location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : location.trimmingCharacters(in: .whitespacesAndNewlines)` and pass `location: locationToSend` into BOTH the `updateConversation` and `logConversation` calls (replacing the `location: nil` placeholders from B2 Step 8).

- [ ] **Step 2: View — WHERE section.** In `LogSheetView.swift`:
  - Add `@State private var locationSearch = LocationSearchModel()` to the view.
  - Insert a `whereSection` between `whenSection` and `valenceSection` in the body `VStack`.
  - Add the computed view:
    ```swift
    private var whereSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("WHERE (OPTIONAL)")
            TextField("Place or address", text: $vm.location)
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textPrimary)
                .autocorrectionDisabled()
                .padding(12)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .onChange(of: vm.location) { _, newValue in
                    locationSearch.query = newValue
                }
            if !locationSearch.suggestions.isEmpty {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(locationSearch.suggestions) { s in
                        Button {
                            vm.location = s.displayString
                            locationSearch.clear()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.circle")
                                    .foregroundColor(Theme.textSecondary)
                                Text(s.displayString)
                                    .font(Theme.FontScale.secondary())
                                    .foregroundColor(Theme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    ```

- [ ] **Step 3: Add VM tests** (append to `LogSheetViewModelTests.swift`):
```swift
    @Test func save_sendsTrimmedLocation() async throws {
        let repo = MockHiyaRepository()
        let vm = LogSheetViewModel(repo: repo, creationMode: .warm)
        await vm.load()
        vm.searchText = "Angie"
        vm.location = "  Blue Bottle, 1 Main St  "
        _ = await vm.save()
        #expect(repo.conversations.first?.location == "Blue Bottle, 1 Main St")
    }

    @Test func editing_seedsLocation() async throws {
        let repo = MockHiyaRepository()
        let entry = LoggedConversation(
            id: UUID(), personId: UUID(), personName: "Angie",
            occurredAt: .now, valence: nil, note: nil, improvementNote: nil,
            location: "The Gym"
        )
        let vm = LogSheetViewModel(repo: repo, editing: entry)
        #expect(vm.location == "The Gym")
    }
```

- [ ] **Step 4: Run** `clean test` — Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/ViewModels/LogSheetViewModel.swift hiya/hiya/Views/LogSheetView.swift hiya/hiyaTests/LogSheetViewModelTests.swift
git commit -m "feat(log): WHERE section with map autocomplete; saves meeting location

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task B5: Show location in interaction history

**Files:**
- Modify: `hiya/hiya/Views/PersonDetailSheet.swift`

- [ ] **Step 1: Add a location line** in `interactionRow(_:)`, inside the inner `VStack(alignment: .leading, ...)`, after the date `Text(...)` and before the note block:
```swift
                if let location = entry.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle")
                            .font(.system(size: 11))
                        Text(location)
                            .font(Theme.FontScale.micro())
                            .lineLimit(1)
                    }
                    .foregroundColor(Theme.textSecondary)
                }
```

- [ ] **Step 2: Build.** Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Views/PersonDetailSheet.swift
git commit -m "feat(people): show meeting location in interaction history

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task B6: Mock location round-trip test

**Files:**
- Modify: `hiya/hiyaTests/MockHiyaRepositoryTests.swift`

- [ ] **Step 1: Add test**
```swift
    @Test func logConversation_storesAndReturnsLocation() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "Angie", status: .warm, notes: nil, metCold: false)
        try await repo.logConversation(personId: p.id, valence: nil, note: nil, improvementNote: nil, location: "The Gym")
        let history = try await repo.personConversations(personId: p.id)
        #expect(history.first?.location == "The Gym")
    }
```

- [ ] **Step 2: Run** `clean test` — Expected: TEST SUCCEEDED.

- [ ] **Step 3: Final full test run** to confirm the whole suite is green:
```bash
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild clean test \
  -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  2>&1 | tee /tmp/hiya_test.log | grep -E "TEST (SUCCEEDED|FAILED)|failures"
```
Expected: TEST SUCCEEDED.

- [ ] **Step 4: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiyaTests/MockHiyaRepositoryTests.swift
git commit -m "test(repo): location round-trips through logConversation

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation
- Update memory: `[[hiya_ring_gradient_oxymoron]]` (oxymoron retired — rings now align with cold=lavender/warm=amber) and `[[hiya_cold_warm_full_separation]]` (cold/warm now also separated by the durable `met_cold` flag + chronological classification).
- Manual smoke test: backfill "Angie" (cold approach, dated last Sunday) + warm catch-ups Tue/Wed/Fri with locations; confirm her strip shows a lavender first-meeting bar + amber catch-up bars, INTERACTIONS list shows dates + places, and she sits under Catch-ups after a Home refresh.
