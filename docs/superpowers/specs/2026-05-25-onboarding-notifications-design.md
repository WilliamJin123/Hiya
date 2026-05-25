# Onboarding + Daily Reminder Notifications — Design

**Date:** 2026-05-25
**Status:** Approved

## Goal

Two engagement features for Hiya, built independently in this order:

1. **Onboarding** — an animated, first-run walkthrough that explains Approaches vs Catch-ups and sets the user's two daily goals.
2. **Notifications** — a single opt-in daily reminder to log an approach, off by default, with a smart suppression so it never nags after the goal is met.

No backend/schema changes. Notifications are local (`UNUserNotificationCenter`). Goals already persist via the existing `updateGoals(coldDailyGoal:warmDailyGoal:)` repo method.

---

## Feature A — Onboarding (animated walkthrough)

### Gating

- New device-local flag: `UserDefaults` key `hiya.hasOnboarded` (default `false`).
- `SessionViewModel.State` gains a `.onboarding` case (alongside `loading`, `app`, `auth`).
- In `start()`, the paths that would resolve to `.app` (the launch `.app` path and the `.createAnonymous` path) instead resolve to `.onboarding` when `hasOnboarded == false`.
- Explicit `signIn` / `signUp` continue to set `.app` directly — returning users never re-onboard.
- `completeOnboarding()` on `SessionViewModel`: sets `hasOnboarded = true` and `state = .app`.
- `AppGateView` renders `OnboardingView` for the `.onboarding` case, injecting `session` and `repo`.

This means onboarding fires only on the genuine first-run (anonymous-first boot) path. Because William has existing data but no flag, he sees it once on next launch; the goal steppers seed from his current profile values, so nothing is lost.

### Screens

Four paged cards in a `TabView` with `.tabViewStyle(.page)`. Each card animates its content in on appear (spring transforms + opacity; rings use an animated `trim(from:to:)` fill). A per-card `@State var appeared = false` set `true` in `onAppear` drives `withAnimation`.

1. **Welcome** — Hiya wordmark scales in (spring), tagline fades up.
2. **Two kinds of conversation** — a lavender ring and an amber ring draw-fill, staggered. Labelled *Approaches* (new people) and *Catch-ups* (people you know). Uses existing `Theme.coldAccent` (lavender) / `Theme.warmAccent` (amber).
3. **How you log** — a sample log row slides in; Good / OK / Rough valence chips pop in sequence.
4. **Set your goals** — two steppers seeded from the current profile (`coldDailyGoal`, `warmDailyGoal`), a live ring preview reflecting the chosen numbers, and a **Get started** button.

### Data flow

- `OnboardingViewModel` (`@MainActor @Observable`): holds `page`, `coldGoal`, `warmGoal` (seeded from a passed-in `Profile`, falling back to 10/10), `isSaving`, `errorMessage`.
- `finish()` calls `repo.updateGoals(coldDailyGoal:warmDailyGoal:)`; on success it returns true so the view calls `session.completeOnboarding()`.
- On failure, surface `errorMessage` and stay on the goals card.

### Files

- Create: `hiya/hiya/Views/OnboardingView.swift` (container + four card subviews).
- Create: `hiya/hiya/ViewModels/OnboardingViewModel.swift`.
- Modify: `hiya/hiya/ViewModels/SessionViewModel.swift` (`.onboarding` state, gate check, `completeOnboarding()`).
- Modify: `hiya/hiya/Views/AppGateView.swift` (render `OnboardingView` for `.onboarding`).

---

## Feature B — Daily approach reminder (local notifications)

Opt-in, **default OFF**. Permission is requested only when the user enables the toggle (not during onboarding), so the two features stay fully independent.

### Units (policy separated from effect)

**`ReminderPlanner`** — pure, no I/O. Static function:

```
plan(enabled: Bool,
     time: (hour: Int, minute: Int),
     now: Date,
     goalMetToday: Bool,
     horizonDays: Int,
     calendar: Calendar) -> [PlannedReminder]
```

- Returns `[]` when `enabled == false`.
- Otherwise emits one `PlannedReminder` per day for the next `horizonDays` days (default 7) at the set time.
- **Skips today** when `goalMetToday == true` or the fire time has already passed for today.
- Each reminder has a stable per-day identifier `hiya.reminder.<yyyy-MM-dd>`, a `fireDate`, and fixed title/body copy.

`PlannedReminder`: `{ id: String, fireDate: Date, title: String, body: String }`.

**`NotificationScheduler`** — protocol + Live + Mock; the only unit that touches `UNUserNotificationCenter`.

- `authorizationStatus() async -> NotifAuthStatus` (`.notDetermined | .authorized | .denied`)
- `requestAuthorization() async -> Bool`
- `replaceReminders(_ reminders: [PlannedReminder]) async` — removes all pending Hiya reminder requests (those with the `hiya.reminder.` prefix) and adds the supplied ones via `UNCalendarNotificationTrigger`.
- `pendingReminderIDs() async -> [String]` (for tests/inspection).
- `LiveNotificationScheduler` wraps `UNUserNotificationCenter.current()`. `MockNotificationScheduler` records calls and stores pending IDs.

**`NotificationManager`** — `@MainActor @Observable`, orchestrator injected via `.environment` like `SessionViewModel`.

- Owns settings in `UserDefaults`: `hiya.notif.dailyEnabled` (Bool, default false), `hiya.notif.dailyHour` (Int, default 18), `hiya.notif.dailyMinute` (Int, default 0).
- Published: `enabled`, `hour`, `minute`, `authorizationStatus`.
- `enable() async -> Bool`: requests authorization; if granted sets `enabled = true` and schedules; if denied, leaves `enabled = false` and updates `authorizationStatus` so the UI can show a hint.
- `disable() async`: `enabled = false`, calls `replaceReminders([])`.
- `setTime(hour:minute:) async`: persists and reschedules (when enabled).
- `refresh(goalMetToday:) async`: recomputes the plan via `ReminderPlanner` and applies it via the scheduler. No-op when disabled.

### Smart suppression (best-effort)

When the user logs an approach and the cold goal becomes met, the app re-plans (`refresh(goalMetToday: true)`), which removes today's pending reminder. Local notifications cannot run code at fire time, so if the app is never opened the reminder still fires — correct behavior, since nothing was logged.

### Settings UI

New "Reminders" section in `SettingsView`:

- A *Daily approach reminder* `Toggle` bound through `NotificationManager.enable()` / `disable()`.
- When enabled, a `DatePicker(.hourAndMinute)` for the time, calling `setTime(...)` on change.
- When `authorizationStatus == .denied`, show a caption hint to enable notifications in iOS Settings.

No Info.plist key is required for local notifications.

### Integration points

- `HomeView`: after a successful log and on appear, call `notificationManager.refresh(goalMetToday: vm.isGoalMet(for: .cold))`.
- `AppGateView`: on `scenePhase` change to `.active`, call `refresh(...)` (reads goal-met from a fresh `HomeViewModel` query or a lightweight check). To avoid duplicating goal logic, `HomeView`'s appear refresh is the primary trigger; the scenePhase hook reschedules with the last-known goal-met state.

### Files

- Create: `hiya/hiya/Services/ReminderPlanner.swift` (+ `PlannedReminder`).
- Create: `hiya/hiya/Services/NotificationScheduler.swift` (protocol, Live, `NotifAuthStatus`).
- Create: `hiya/hiya/Services/MockNotificationScheduler.swift` (test double) — or colocate in test target.
- Create: `hiya/hiya/ViewModels/NotificationManager.swift`.
- Modify: `hiya/hiya/Views/SettingsView.swift` (Reminders section).
- Modify: `hiya/hiya/Views/HomeView.swift` (refresh hooks).
- Modify: `hiya/hiya/Views/AppGateView.swift` (instantiate + inject `NotificationManager`, scenePhase refresh).

---

## Testing (Swift Testing + mocks)

- **`ReminderPlannerTests`**: disabled → empty; `goalMetToday` true → today skipped; time-already-passed → today skipped; horizon produces N reminders; identifiers and fire dates correct for a fixed `now`.
- **`NotificationManagerTests`** (with `MockNotificationScheduler`): `enable()` requests auth and schedules; denied auth leaves disabled; `disable()` clears; `refresh(goalMetToday:)` re-plans.
- **`SessionViewModelTests`**: onboarding gate — new user → `.onboarding`; `hasOnboarded` true → `.app`; explicit sign-in → `.app`; `completeOnboarding()` sets flag + `.app`.
- **`OnboardingViewModelTests`**: goals seed from profile; `finish()` calls `updateGoals` with the chosen values and reports success.

UserDefaults-backed state in tests uses an injectable `UserDefaults` (a fresh suite per test) to stay isolated.

## Non-goals (YAGNI)

- No follow-up or streak-protection notifications (only the daily approach reminder).
- No notification permission ask during onboarding.
- No "replay intro" entry point.
- No server-side / push notifications.
