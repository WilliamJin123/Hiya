# Themed Challenges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Catalog + custom themed challenges (hybrid prompt + optional target/duration), per-track, multiple active, stored in Supabase, surfaced on a dedicated screen and on the Home page.

**Architecture:** Bundled `ChallengeTemplate` catalog (constants) + a `challenges` Supabase table for started instances. `ChallengesViewModel` computes progress client-side from conversations and auto-completes met targets. A `ChallengesView` screen plus a compact per-mode card on Home.

**Tech Stack:** SwiftUI, Swift 6, Swift Testing, `@Observable`, protocol-backed `HiyaRepository`.

**Conventions:**
- `xcodebuild` from `/Users/williamjin/Documents/Hiya/hiya`; destination `platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A`.
- Run the test suite ONCE per checkpoint: `xcodebuild test ... 2>&1 | tee /tmp/hiya_test.log | grep -E ...`, then grep `/tmp/hiya_test.log` again — don't double-run xcodebuild.
- SourceKit "Cannot find type / No such module / unable to type-check" diagnostics are noise; xcodebuild is truth.
- Filesystem-synchronized Xcode groups: new files in existing folders are auto-included.

**Spec:** `docs/superpowers/specs/2026-05-24-themed-challenges-design.md`

---

## Task 1: Models + catalog + migration

**Files:**
- Create: `hiya/Models/Challenge.swift`
- Create: `hiya/Models/ChallengeTemplate.swift`
- Create: `supabase/migrations/20260524130000_add_challenges.sql`
- Test: `hiyaTests/ChallengeCatalogTests.swift`

- [ ] **Step 1: Write the failing catalog test**

`hiyaTests/ChallengeCatalogTests.swift`:

```swift
import Testing
import Foundation
@testable import hiya

struct ChallengeCatalogTests {
    @Test func catalog_isNonEmpty_withUniqueSlugs() {
        let slugs = ChallengeTemplate.catalog.map(\.slug)
        #expect(!slugs.isEmpty)
        #expect(Set(slugs).count == slugs.count, "slugs must be unique")
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `xcodebuild test ... | grep error:` → build fails (`ChallengeTemplate` undefined).

- [ ] **Step 3: Create `ChallengeTemplate.swift`**

```swift
import Foundation

enum ChallengeTrack: String, Codable, Sendable, Equatable, CaseIterable {
    case cold, warm, any
}

struct ChallengeTemplate: Identifiable, Sendable, Equatable {
    let slug: String
    let title: String
    let prompt: String
    let track: ChallengeTrack
    let targetCount: Int?
    let durationDays: Int?

    var id: String { slug }

    static let catalog: [ChallengeTemplate] = [
        .init(slug: "open-question", title: "Open with a question", prompt: "Start a conversation with an open-ended question.", track: .cold, targetCount: nil, durationDays: nil),
        .init(slug: "genuine-compliment", title: "Genuine compliment", prompt: "Give someone you don't know a sincere compliment.", track: .cold, targetCount: nil, durationDays: nil),
        .init(slug: "three-new-faces", title: "Three new faces", prompt: "Approach three new people this week.", track: .cold, targetCount: 3, durationDays: 7),
        .init(slug: "one-today", title: "One today", prompt: "Approach one new person today.", track: .cold, targetCount: 1, durationDays: 1),
        .init(slug: "go-deeper", title: "Go deeper", prompt: "Ask a catch-up about something beyond small talk.", track: .warm, targetCount: nil, durationDays: nil),
        .init(slug: "reconnect-x2", title: "Reconnect ×2", prompt: "Catch up with two people you've lost touch with this week.", track: .warm, targetCount: 2, durationDays: 7),
        .init(slug: "phone-away", title: "Phone away", prompt: "Have a full conversation without checking your phone.", track: .any, targetCount: nil, durationDays: nil),
        .init(slug: "listen-more", title: "Listen more", prompt: "Spend a conversation mostly listening.", track: .any, targetCount: nil, durationDays: nil),
    ]
}
```

- [ ] **Step 4: Create `Challenge.swift`**

```swift
import Foundation

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

    var isComplete: Bool { completedAt != nil }
    var endDate: Date? {
        guard let d = durationDays else { return nil }
        return Calendar.current.date(byAdding: .day, value: d, to: startedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case title
        case prompt
        case track
        case targetCount = "target_count"
        case durationDays = "duration_days"
        case source
        case templateSlug = "template_slug"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

/// Fields needed to start a challenge — built from a catalog template or the
/// custom form, passed to the repository's startChallenge.
struct ChallengeDraft: Sendable, Equatable {
    var title: String
    var prompt: String
    var track: ChallengeTrack
    var targetCount: Int?
    var durationDays: Int?
    var source: ChallengeSource
    var templateSlug: String?

    init(template t: ChallengeTemplate) {
        title = t.title; prompt = t.prompt; track = t.track
        targetCount = t.targetCount; durationDays = t.durationDays
        source = .catalog; templateSlug = t.slug
    }

    init(title: String, prompt: String, track: ChallengeTrack, targetCount: Int?, durationDays: Int?) {
        self.title = title; self.prompt = prompt; self.track = track
        self.targetCount = targetCount; self.durationDays = durationDays
        self.source = .custom; self.templateSlug = nil
    }
}
```

- [ ] **Step 5: Create the migration `supabase/migrations/20260524130000_add_challenges.sql`**

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

create index challenges_owner_started_idx
  on public.challenges(owner_id, started_at desc);

alter table public.challenges enable row level security;

create policy "challenges_select_own" on public.challenges
  for select using (auth.uid() = owner_id);
create policy "challenges_insert_own" on public.challenges
  for insert with check (auth.uid() = owner_id);
create policy "challenges_update_own" on public.challenges
  for update using (auth.uid() = owner_id);
create policy "challenges_delete_own" on public.challenges
  for delete using (auth.uid() = owner_id);
```

- [ ] **Step 6: Run the suite** — `... | tee /tmp/hiya_test.log | grep -E "error:|with [0-9]+ failure"`; expect catalog test passes, 0 failures.

- [ ] **Step 7: Commit** — `git add -A && git commit -m "feat(challenges): models, bundled catalog, table migration"`.

---

## Task 2: Repository — challenge CRUD

**Files:**
- Modify: `hiya/Services/HiyaRepository.swift` (protocol + Live)
- Modify: `hiya/Services/MockHiyaRepository.swift`
- Test: `hiyaTests/MockHiyaRepositoryTests.swift`

- [ ] **Step 1: Write failing mock tests**

Add to `MockHiyaRepositoryTests`:

```swift
@Test func challenges_startListCompleteAbandon() async throws {
    let repo = MockHiyaRepository()
    let draft = ChallengeDraft(title: "Test", prompt: "p", track: .cold, targetCount: 2, durationDays: 7)
    let started = try await repo.startChallenge(draft)
    #expect(try await repo.challenges().count == 1)
    #expect(started.completedAt == nil)

    try await repo.completeChallenge(id: started.id)
    #expect(try await repo.challenges().first?.completedAt != nil)

    try await repo.abandonChallenge(id: started.id)
    #expect(try await repo.challenges().isEmpty)
}
```

- [ ] **Step 2: Run → fails** (methods undefined).

- [ ] **Step 3: Add protocol requirements** (in `HiyaRepository` protocol):

```swift
    func challenges() async throws -> [Challenge]
    func startChallenge(_ draft: ChallengeDraft) async throws -> Challenge
    func completeChallenge(id: UUID) async throws
    func abandonChallenge(id: UUID) async throws
```

- [ ] **Step 4: Implement in `MockHiyaRepository`**

Add stored property near the others: `var challengeRows: [Challenge] = []`. Then:

```swift
    func challenges() async throws -> [Challenge] {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        return challengeRows.sorted { $0.startedAt > $1.startedAt }
    }

    func startChallenge(_ draft: ChallengeDraft) async throws -> Challenge {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        let c = Challenge(
            id: UUID(), ownerId: profile.id,
            title: draft.title, prompt: draft.prompt, track: draft.track,
            targetCount: draft.targetCount, durationDays: draft.durationDays,
            source: draft.source, templateSlug: draft.templateSlug,
            startedAt: .now, completedAt: nil
        )
        challengeRows.append(c)
        return c
    }

    func completeChallenge(id: UUID) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        if let i = challengeRows.firstIndex(where: { $0.id == id }) {
            challengeRows[i].completedAt = .now
        }
    }

    func abandonChallenge(id: UUID) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        challengeRows.removeAll { $0.id == id }
    }
```

- [ ] **Step 5: Implement in `LiveHiyaRepository`**

```swift
    func challenges() async throws -> [Challenge] {
        try await client
            .from("challenges")
            .select()
            .order("started_at", ascending: false)
            .execute()
            .value
    }

    func startChallenge(_ draft: ChallengeDraft) async throws -> Challenge {
        let userId = try await client.auth.user().id
        struct Insert: Encodable {
            let owner_id: UUID
            let title: String
            let prompt: String
            let track: String
            let target_count: Int?
            let duration_days: Int?
            let source: String
            let template_slug: String?
        }
        return try await client
            .from("challenges")
            .insert(Insert(
                owner_id: userId, title: draft.title, prompt: draft.prompt,
                track: draft.track.rawValue, target_count: draft.targetCount,
                duration_days: draft.durationDays, source: draft.source.rawValue,
                template_slug: draft.templateSlug
            ))
            .select().single().execute().value
    }

    func completeChallenge(id: UUID) async throws {
        struct Update: Encodable { let completed_at: String }
        try await client.from("challenges")
            .update(Update(completed_at: Date.now.iso8601String))
            .eq("id", value: id).execute()
    }

    func abandonChallenge(id: UUID) async throws {
        try await client.from("challenges").delete().eq("id", value: id).execute()
    }
```

- [ ] **Step 6: Run suite** → challenge CRUD test passes, 0 failures.
- [ ] **Step 7: Commit** — `feat(challenges): repository CRUD (live + mock)`.

---

## Task 3: ChallengesViewModel

**Files:**
- Create: `hiya/ViewModels/ChallengesViewModel.swift`
- Test: `hiyaTests/ChallengesViewModelTests.swift`

- [ ] **Step 1: Write failing tests**

`hiyaTests/ChallengesViewModelTests.swift`:

```swift
import Testing
import Foundation
@testable import hiya

@MainActor
struct ChallengesViewModelTests {
    private func conv(_ pid: UUID, cold: Bool, daysAgo: Int, now: Date) -> LoggedConversation {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        return LoggedConversation(id: UUID(), personId: pid, personName: "X",
                                  occurredAt: d, valence: nil, note: nil,
                                  improvementNote: nil, wasColdAtTime: cold)
    }

    @Test func progress_countsUniquePeopleOnTrackInWindow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let ch = Challenge(id: UUID(), ownerId: UUID(), title: "t", prompt: "p",
                           track: .cold, targetCount: 3, durationDays: 7,
                           source: .custom, templateSlug: nil, startedAt: start, completedAt: nil)
        let a = UUID(); let b = UUID()
        let convs = [
            conv(a, cold: true, daysAgo: 1, now: now),
            conv(a, cold: true, daysAgo: 0, now: now),   // same person, still 1 unique
            conv(b, cold: true, daysAgo: 1, now: now),
            conv(UUID(), cold: false, daysAgo: 1, now: now), // warm, ignored
            conv(UUID(), cold: true, daysAgo: 10, now: now), // before window start
        ]
        let p = ChallengesViewModel.progress(for: ch, in: convs, now: now)
        #expect(p == 2)
    }

    @Test func load_autoCompletesMetTargetedChallenge() async throws {
        let repo = MockHiyaRepository()
        let person = try await repo.createPerson(name: "Alex")
        try await repo.logConversation(personId: person.id, occurredAt: .now, valence: nil, note: nil, improvementNote: nil)
        _ = try await repo.startChallenge(ChallengeDraft(title: "One", prompt: "p", track: .cold, targetCount: 1, durationDays: 1))

        let vm = ChallengesViewModel(repo: repo)
        await vm.load()

        #expect(vm.active.isEmpty)
        #expect(vm.completed.count == 1)
    }

    @Test func activeChallenges_forTrack_includesAny() async throws {
        let repo = MockHiyaRepository()
        _ = try await repo.startChallenge(ChallengeDraft(title: "cold", prompt: "p", track: .cold, targetCount: nil, durationDays: nil))
        _ = try await repo.startChallenge(ChallengeDraft(title: "warm", prompt: "p", track: .warm, targetCount: nil, durationDays: nil))
        _ = try await repo.startChallenge(ChallengeDraft(title: "any", prompt: "p", track: .any, targetCount: nil, durationDays: nil))

        let vm = ChallengesViewModel(repo: repo)
        await vm.load()

        #expect(Set(vm.activeChallenges(for: .cold).map(\.title)) == ["cold", "any"])
        #expect(Set(vm.activeChallenges(for: .warm).map(\.title)) == ["warm", "any"])
    }
}
```

- [ ] **Step 2: Run → fails.**

- [ ] **Step 3: Implement `ChallengesViewModel`**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class ChallengesViewModel {
    private let repo: HiyaRepository
    private(set) var challenges: [Challenge] = []
    private(set) var recentConversations: [LoggedConversation] = []
    private(set) var isLoading = false
    var errorMessage: String?

    init(repo: HiyaRepository) { self.repo = repo }

    var active: [Challenge] { challenges.filter { !$0.isComplete } }
    var completed: [Challenge] { challenges.filter(\.isComplete) }

    func progress(for challenge: Challenge) -> Int {
        Self.progress(for: challenge, in: recentConversations, now: .now)
    }

    func activeChallenges(for track: PersonStatus) -> [Challenge] {
        let want: ChallengeTrack = (track == .cold) ? .cold : .warm
        return active.filter { $0.track == want || $0.track == .any }
    }

    func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let all = try await repo.challenges()
            let earliest = all.filter { !$0.isComplete }.map(\.startedAt).min()
            let start = earliest ?? Calendar.current.date(byAdding: .day, value: -30, to: .now)!
            let convs = try await repo.conversations(start: start, end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!)
            self.challenges = all
            self.recentConversations = convs
            await autoComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start(_ draft: ChallengeDraft) async { await mutate { _ = try await self.repo.startChallenge(draft) } }
    func complete(_ id: UUID) async { await mutate { try await self.repo.completeChallenge(id: id) } }
    func abandon(_ id: UUID) async { await mutate { try await self.repo.abandonChallenge(id: id) } }

    private func autoComplete() async {
        for c in active where c.targetCount != nil {
            if progress(for: c) >= (c.targetCount ?? .max) {
                try? await repo.completeChallenge(id: c.id)
            }
        }
        // reload challenge rows if anything was completed
        if let refreshed = try? await repo.challenges() { self.challenges = refreshed }
    }

    private func mutate(_ action: () async throws -> Void) async {
        errorMessage = nil
        do { try await action(); await load() }
        catch { errorMessage = error.localizedDescription }
    }

    static func progress(for challenge: Challenge, in conversations: [LoggedConversation], now: Date) -> Int {
        guard challenge.targetCount != nil else { return 0 }
        let start = challenge.startedAt
        let upper = min(now, challenge.endDate ?? now)
        let matching = conversations.filter { c in
            guard c.occurredAt >= start, c.occurredAt <= upper else { return false }
            switch challenge.track {
            case .cold: return c.wasColdAtTime
            case .warm: return !c.wasColdAtTime
            case .any:  return true
            }
        }
        return Set(matching.map(\.personId)).count
    }
}
```

- [ ] **Step 4: Run suite** → 3 new tests pass, 0 failures.
- [ ] **Step 5: Commit** — `feat(challenges): view model with progress + auto-complete`.

---

## Task 4: Challenges screen + Home entry point

**Files:**
- Create: `hiya/Views/ChallengesView.swift`
- Create: `hiya/Views/CustomChallengeSheet.swift`
- Modify: `hiya/Views/HomeView.swift` (toolbar button)

No unit tests (SwiftUI); verify by build. Logic is covered by Task 3.

- [ ] **Step 1: Create `ChallengesView.swift`** — a `NavigationStack`-free screen pushed from Home, with `Theme.bgGradient`, a List with two sections (ACTIVE, COMPLETED), a `+` toolbar item presenting a chooser (browse catalog / create custom), and swipe-to-abandon. Active card shows title, prompt, a track chip, and a progress bar (`vm.progress(for:) / targetCount`) when targeted, plus "Mark done". Catalog browse is a sheet listing `ChallengeTemplate.catalog` grouped by track; tapping calls `vm.start(.init(template:))`. Use `Theme` tokens; track chip color: cold=`accentAmber`, warm=`accentLavender`, any=`textSecondary`. (Full view code written during execution, mirroring existing view style in `PeopleView`/`HistoryView`.)

- [ ] **Step 2: Create `CustomChallengeSheet.swift`** — form: title TextField, prompt TextField, track `Picker`(segmented Approaches/Catch-ups/Either), target stepper (0 = none), duration picker (None/3/7/14/30). Save builds `ChallengeDraft(title:prompt:track:targetCount:durationDays:)` and calls a passed `onCreate` closure → `vm.startCustom`.

- [ ] **Step 3: Add Home toolbar entry** — in `HomeView` toolbar, a leading `NavigationLink` (beside the calendar) to `ChallengesView(repo: repo)`, icon `target`, tint `accentLavender`.

- [ ] **Step 4: Build** → `BUILD SUCCEEDED`.
- [ ] **Step 5: Commit** — `feat(challenges): challenges screen + custom create + home entry`.

---

## Task 5: Home surfacing

**Files:**
- Modify: `hiya/Views/HomeView.swift`

- [ ] **Step 1: Add a `ChallengesViewModel` to HomeView**, loaded in `.task`/`.refreshable` alongside `vm.refresh()`.

- [ ] **Step 2: Add a `challengeSection(for pageMode:)`** rendered in `pageContent` (below the log button): if `challengesVM.activeChallenges(for: pageMode)` is non-empty, a "CHALLENGE" heading and a compact card per challenge (title, prompt, and `progress/target` if targeted). Tapping navigates to `ChallengesView`. Hidden when empty.

- [ ] **Step 3: Build** → `BUILD SUCCEEDED`.
- [ ] **Step 4: Commit** — `feat(challenges): surface active challenges on Home`.

---

## Final verification

- [ ] Run the full suite once; confirm 0 failures.
- [ ] `git push`.
- [ ] Remind user to apply migrations (`supabase db push`): `20260524120000_backfill_person_notes` and `20260524130000_add_challenges`.
