# Settings, Per-Mode Goals & Tab Nav — Implementation Plan

> Execution checklist (inline, autonomous). Spec: `docs/superpowers/specs/2026-05-24-settings-per-mode-goals-design.md`

**Goal:** Independent Approaches/Catch-ups daily goals, a Settings sheet to edit them, and a bottom tab bar.

**Test destination:** `platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A`. One `clean test` run at the end (new tests added). `profiles_update_own` RLS already exists.

## File map
- Modify `hiya/hiya/Models/Profile.swift` — add `coldDailyGoal`/`warmDailyGoal` (default 10).
- Modify `hiya/hiya/Services/HiyaRepository.swift` — protocol + Live `updateGoals`.
- Modify `hiya/hiya/Services/MockHiyaRepository.swift` — Mock `updateGoals`.
- Modify `hiya/hiya/ViewModels/HomeViewModel.swift` — `goal(for:)`; route progress/isGoalMet/ringState through it; drop `var goal`.
- Create `hiya/hiya/ViewModels/SettingsViewModel.swift`.
- Create `hiya/hiya/Views/SettingsView.swift`.
- Modify `hiya/hiya/Views/RootView.swift` — `TabView`.
- Modify `hiya/hiya/Views/HomeView.swift` — drop History/People toolbar links; add Settings gear + sheet.
- Modify `hiya/hiyaTests/HomeViewModelTests.swift` — `vm.goal` → `vm.goal(for:)`; set `coldDailyGoal` in the 3 goal-specific Profiles.
- Modify `hiya/hiyaTests/MockHiyaRepositoryTests.swift` — `updateGoals_setsBothGoals`.
- Create `hiya/hiyaTests/SettingsViewModelTests.swift`.
- Create `supabase/migrations/20260524180000_add_per_mode_goals.sql`.

## Tasks

### T1 — Migration
```sql
alter table public.profiles add column cold_daily_goal int not null default 10;
alter table public.profiles add column warm_daily_goal int not null default 10;
update public.profiles set cold_daily_goal = coalesce(daily_goal, 10),
                           warm_daily_goal = coalesce(daily_goal, 10);
```
`supabase db push --yes`.

### T2 — Profile model
Add after `dailyGoal`:
```swift
var coldDailyGoal: Int = 10
var warmDailyGoal: Int = 10
```
CodingKeys: `case coldDailyGoal = "cold_daily_goal"`, `case warmDailyGoal = "warm_daily_goal"`. Defaults preserve the memberwise init for existing call sites.

### T3 — Repo `updateGoals`
Protocol: `func updateGoals(coldDailyGoal: Int, warmDailyGoal: Int) async throws -> Profile`.

Live:
```swift
func updateGoals(coldDailyGoal: Int, warmDailyGoal: Int) async throws -> Profile {
    let userId = try await client.auth.user().id
    struct Update: Encodable { let cold_daily_goal: Int; let warm_daily_goal: Int }
    return try await client.from("profiles")
        .update(Update(cold_daily_goal: coldDailyGoal, warm_daily_goal: warmDailyGoal))
        .eq("id", value: userId).select().single().execute().value
}
```
Mock:
```swift
func updateGoals(coldDailyGoal: Int, warmDailyGoal: Int) async throws -> Profile {
    if let err = errorToThrow { errorToThrow = nil; throw err }
    profile.coldDailyGoal = coldDailyGoal
    profile.warmDailyGoal = warmDailyGoal
    return profile
}
```

### T4 — HomeViewModel per-mode goal
Replace `var goal` with:
```swift
func goal(for mode: PersonStatus) -> Int {
    switch mode {
    case .cold: return profile?.coldDailyGoal ?? 10
    case .warm: return profile?.warmDailyGoal ?? 10
    }
}
```
`progress(for:)`, `isGoalMet(for:)`, `ringState(for:)` use `goal(for: mode)`. Keep `static func ringState(count:goal:)` as-is.

### T5 — SettingsViewModel + tests
```swift
@MainActor @Observable
final class SettingsViewModel {
    private let repo: HiyaRepository
    var coldGoal = 10
    var warmGoal = 10
    var isSaving = false
    var errorMessage: String?
    var didSave = false
    init(repo: HiyaRepository) { self.repo = repo }
    func load() async {
        do { let p = try await repo.ensureSignedIn(); coldGoal = p.coldDailyGoal; warmGoal = p.warmDailyGoal }
        catch { errorMessage = error.localizedDescription }
    }
    func save() async {
        isSaving = true; defer { isSaving = false }
        do { _ = try await repo.updateGoals(coldDailyGoal: coldGoal, warmDailyGoal: warmGoal); didSave = true }
        catch { errorMessage = error.localizedDescription }
    }
}
```
Tests: load seeds from profile; save persists both (assert mock.profile goals).

### T6 — SettingsView
Sheet: NavigationStack, dark, two `Stepper`s (1...50) bound to vm.coldGoal/warmGoal with themed rows, Save (calls `save()` then dismiss on `didSave`), Close. Error inline.

### T7 — RootView TabView
```swift
TabView {
    NavigationStack { HomeView(repo: repo) }.tabItem { Label("Home", systemImage: "circle.dashed") }
    NavigationStack { PeopleView(repo: repo) }.tabItem { Label("People", systemImage: "person.2.fill") }
    NavigationStack { HistoryView(repo: repo) }.tabItem { Label("History", systemImage: "calendar") }
}
.tint(Theme.accentLavender)
```
(Insights tab added by plan 2.) **HomeView already has its own NavigationStack** — keep HomeView's internal NavigationStack and DO NOT double-wrap: in RootView, Home tab = `HomeView(repo: repo)` directly (it owns its stack); People/History get wrapped since they don't.

### T8 — HomeView toolbar
Remove the calendar→History and person→People `ToolbarItem`s. Add leading gear:
```swift
ToolbarItem(placement: .navigationBarLeading) {
    Button { showingSettings = true } label: { Image(systemName: "gearshape").foregroundColor(Theme.accentLavender) }
}
```
Keep target→Challenges trailing. Add `@State private var showingSettings = false` and `.sheet(isPresented: $showingSettings, onDismiss: { Task { await vm.refresh() } }) { SettingsView(repo: repo) }`.

### T9 — Fix existing tests
- HomeViewModelTests:27 `vm.goal == 10` → `vm.goal(for: .cold) == 10`.
- Profiles at lines 118/145/161: add `coldDailyGoal: <same value>` right after `dailyGoal:` so the cold ring reads the intended goal.

## Self-review
- `var goal` removed; only referenced in test:27 (fixed) — HomeView uses `ringState(for:)`. ✓
- Profile defaults keep `Profile.preview` and untouched test inits compiling. ✓
- RootView: Home owns its NavigationStack; People/History wrapped. ✓
