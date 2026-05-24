# Settings, Per-Mode Goals & Tab Navigation — Design

**Date:** 2026-05-24

## Goal

Give Approaches and Catch-ups independent daily goals, add a Settings screen to edit them, and introduce a bottom tab bar so the growing set of destinations has a clean home.

## Scope decisions (locked with user)

1. **Separate goal per mode.** Approaches and Catch-ups each have their own daily target (e.g. 3 / 8), consistent with the "never share a counter/ring/streak" rule and the cold-is-hard / warm-is-easy asymmetry.
2. **Bottom tab bar** is the navigation model (user delegated; chosen for cleanliness/scalability).
3. **`streakMode` is NOT surfaced** — it drives no logic, so editing it would be a no-op.

## Navigation

`RootView` becomes a `TabView` tinted with `Theme.accentLavender`:

| Tab | Content | Icon |
|---|---|---|
| Home | `HomeView` (rings + log + challenges) | `circle.dashed` |
| People | `PeopleView` | `person.2.fill` |
| History | `HistoryView` | `calendar` |
| Insights | *(added by the Insights spec)* | `chart.bar.fill` |

- Each tab wraps its content in its own `NavigationStack` (People/History currently rely on Home's stack via `NavigationLink`; as tabs they need their own).
- **Home toolbar is trimmed**: the calendar→History and person→People `NavigationLink`s are removed (now tabs). Home keeps the **Challenges** `target` link and gains a **Settings** gear (`gearshape`) that presents `SettingsView` as a sheet.
- This declutters Home's toolbar to: gear (leading) · mode title (principal) · target (trailing).

## Data model

`profiles` gains two columns; the legacy `daily_goal` is left in place (unused) to avoid a destructive change.

Migration `<ts>_add_per_mode_goals.sql`:
```sql
alter table public.profiles add column cold_daily_goal int not null default 10;
alter table public.profiles add column warm_daily_goal int not null default 10;
update public.profiles set cold_daily_goal = coalesce(daily_goal, 10),
                           warm_daily_goal = coalesce(daily_goal, 10);
```

`Profile` model gains:
```swift
var coldDailyGoal: Int = 10   // CodingKey "cold_daily_goal"
var warmDailyGoal: Int = 10   // CodingKey "warm_daily_goal"
```
Defaults keep the memberwise initializer (and `Profile.preview`) working without passing the new fields, and let Codable fall back if a key is ever absent.

`profiles` already has an owner-scoped UPDATE RLS policy (verified at plan time; if missing, the migration adds `profiles_update_own` gated on `auth.uid() = id`).

## Repository surface

Add to the protocol + Live + Mock:
- `updateGoals(coldDailyGoal: Int, warmDailyGoal: Int) async throws -> Profile` — persists both, returns the updated profile.

## HomeViewModel changes

Replace the single `var goal` with a per-mode lookup, and route the three goal-dependent methods through it:
```swift
func goal(for mode: PersonStatus) -> Int {
    switch mode {
    case .cold: return profile?.coldDailyGoal ?? 10
    case .warm: return profile?.warmDailyGoal ?? 10
    }
}
```
`progress(for:)`, `isGoalMet(for:)`, and `ringState(for:)` use `goal(for: mode)` instead of `goal`. The pure `static func ringState(count:goal:)` is unchanged (still takes an explicit goal), so its existing tests stand.

## UI

`SettingsView` (sheet) + `SettingsViewModel` (`@MainActor @Observable`):
- Loads the current profile (via `ensureSignedIn`), seeds two `Int` fields.
- Two `Stepper`s (range 1...50): "Approaches goal" and "Catch-ups goal", themed like the rest of the app.
- A Save button calls `updateGoals` and dismisses; on dismiss, Home refreshes (its `.sheet(onDismiss:)` already calls `vm.refresh()`), so the rings pick up new goals.
- Error surfaced inline (matches existing sheet patterns).

## Testing

- Mock `updateGoals` mutates `profile` and returns it.
- `MockHiyaRepositoryTests`: `updateGoals_setsBothGoals`.
- `HomeViewModelTests`: `goal(for:)` returns the right per-mode value; `ringState(for:)` reflects per-mode goals (cold vs warm goals differ → different ring states for the same counts).
- `SettingsViewModelTests`: load seeds fields from profile; save persists both goals.

## Out of scope

- Editing `displayName`, `timezone`, `streakMode` (timezone is auto; the others are inert or unused).
- Notifications (separate future feature).
