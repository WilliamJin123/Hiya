# Real Accounts + Profile — Design

**Date:** 2026-05-25
**Status:** Approved (design), pending implementation plan

Add email+password accounts to Hiya (currently Supabase anonymous-only auth), let the user upgrade their existing anonymous account in place (porting all their data into a named "William Jin" account), and surface account management in Settings.

## Goals
- Convert ("claim") the current anonymous user into a permanent email+password account **without moving any data** — the auth user id is preserved, so every owned row stays owned.
- Keep today's frictionless **anonymous-first** boot for brand-new installs.
- Sign in / sign out / create-new-account flows.
- A profile/account section folded into the existing Settings screen, with an editable display name.

## Non-goals (YAGNI)
- OAuth / Sign in with Apple / magic links (email+password only).
- Password reset, email change, account deletion (can come later).
- Multi-account on one device beyond sign-out → sign-in.

---

## Auth model

A user is one of:
- **Anonymous** — `auth.user().isAnonymous == true`, no email. Today's default.
- **Permanent** — has an email (from claim, sign-up, or sign-in).

`profiles` is 1:1 with `auth.users` (created by the `handle_new_user` trigger) and already has a `display_name` column with `profiles_update_own` RLS — **no schema change needed**.

### Claim-in-place (the data "port")
"Create account" while anonymous calls `auth.update(user: UserAttributes(email:, password:))`, attaching credentials to the **same** user id, then sets `display_name`. Because the id is unchanged, all existing people/conversations/notes (owned by that id) remain the user's. No migration, no row reassignment.

The claim happens on whichever device holds the data (its anonymous session). Afterward, signing in with that email on another device yields the same id → same data.

---

## Components

### 1. Repository auth surface (`HiyaRepository` protocol + Live + Mock)

New `AuthAccount` value type:
```swift
struct AuthAccount: Equatable, Sendable {
    let id: UUID
    let email: String?
    let isAnonymous: Bool
}
```

New methods:
- `func currentAccount() async -> AuthAccount?` — current session's account, or `nil` if there's no session. (Live: `nil` when `client.auth.currentSession == nil`; else build from `client.auth.user()` using `id`, `email`, `isAnonymous`.)
- `func claimAccount(email: String, password: String, displayName: String) async throws -> Profile` — `auth.update(user: .init(email: email, password: password))`, then update `profiles.display_name`, return the fresh `Profile`.
- `func signUp(email: String, password: String, displayName: String) async throws -> Profile` — `auth.signUp(email:password:)`, then set `display_name`, return `Profile`. (Used by the Auth screen's "create new" path when signed out.)
- `func signIn(email: String, password: String) async throws -> Profile` — `auth.signIn(email:password:)`, return that user's `Profile`.
- `func signOut() async throws` — `auth.signOut()`.
- `func updateDisplayName(_ name: String) async throws -> Profile` — update `profiles.display_name`, return `Profile`.

`ensureSignedIn()` is unchanged (still auto-creates an anonymous session when none exists) — used only on the fresh-install path, gated by the session view model.

### 2. Session gate (`SessionViewModel` + `AppGateView`)

`hiyaApp` renders `AppGateView(repo:)` which owns a `SessionViewModel`:

```swift
enum SessionState: Equatable { case loading, app, auth }
```

`start()` logic:
1. If `currentAccount()` returns non-nil (anonymous **or** permanent) → `.app`.
2. Else if `hasGraduatedToAccount` (persisted `@AppStorage`/`UserDefaults` bool) → `.auth`.
3. Else → `try? await ensureSignedIn()` (create anonymous) → `.app`.

Transitions:
- `signOut()` → set `hasGraduatedToAccount = true`, `state = .auth`.
- `signIn` / `signUp` / `claim` success → set `hasGraduatedToAccount = true`, `state = .app`.

The decision is extracted as a pure static function for testing:
```swift
enum GateDecision: Equatable { case app, auth, createAnonymous }
static func decide(account: AuthAccount?, hasGraduated: Bool) -> GateDecision
// account != nil → .app ; nil && hasGraduated → .auth ; nil && !hasGraduated → .createAnonymous
```

`AppGateView` shows: `.loading` → a themed splash/spinner; `.app` → the existing `RootView(repo:)`; `.auth` → `AuthView`. On `.app`, existing screens call `ensureSignedIn()` as they do today and find the live session.

> Why a flag instead of always re-anonymizing on no-session: once a device has had a real account, a silent new anonymous account would hide the user's real data behind a stranger account. The flag makes "signed out" mean "show sign-in."

### 3. `AuthView` (signed-out)

A single screen with email + password fields and a segmented Sign in / Create account toggle, plus a display-name field when creating. Calls `signIn` or `signUp` on the session view model; inline `errorMessage` for failures. On success → `.app`.

### 4. Settings account section

At the top of the existing `SettingsView`, above the goal steppers, an account section driven by `SettingsViewModel`:
- **Anonymous:** a "Claim your account" form — display name (prefilled **William Jin**, editable), email, password — calls `claimAccount`. Copy explains it keeps all current data.
- **Permanent:** editable display name (save → `updateDisplayName`), email shown read-only, and a **Sign out** button (calls the session view model's `signOut`, which flips the gate to `.auth`).

`SettingsViewModel` additions: `account: AuthAccount?`, `displayName`, `email`, claim/sign-out/update-display-name actions + their `isSaving`/`errorMessage`. `load()` also fetches `currentAccount()`.

`SettingsView` needs a way to trigger the gate's sign-out. Pass a sign-out closure (or the `SessionViewModel`) into `SettingsView` from `AppGateView`/`HomeView`, so signing out re-routes the whole app to `.auth`.

---

## Supabase configuration (manual prerequisite)

In the Supabase dashboard, **Auth → Providers → Email → disable "Confirm email"** so claim/sign-up complete instantly without an email round-trip. With confirmation on, `auth.update`/`signUp` would queue verification the app isn't built to handle. This is a one-toggle change in the user's project; documented in the plan as a prerequisite step (not code).

Anonymous sign-ins must remain enabled (already are).

---

## Error handling
- All auth calls surface failures as an inline `errorMessage` on the relevant form (existing pattern).
- Common cases: invalid credentials (sign-in), email already registered (claim/sign-up), weak password, offline. Messages come from `error.localizedDescription`.
- Claim/sign-up disabled until email looks valid (`contains("@")`) and password length ≥ 6.

## Testing
- `SessionViewModel.decide(account:hasGraduated:)` — the three branches (`.app`, `.auth`, `.createAnonymous`).
- Mock auth: `claimAccount` flips `isAnonymous → false`, sets email + display name, preserves the same profile id/data; `signOut` clears the session (`currentAccount()` → nil); `signIn` restores a permanent account; `updateDisplayName` persists.
- `SettingsViewModel`: claim populates account + display name; sign-out clears; display-name update persists; error path sets `errorMessage`.

Mock state: add `private var session: AuthAccount?` (defaults to an anonymous account so existing tests that call `ensureSignedIn`/data methods keep working), `email`/`isAnonymous` tracked on it; `profile.displayName` updated by claim/updateDisplayName.

## Out of scope / future
- Password reset & email change flows.
- Account deletion.
- Surfacing display name elsewhere in the UI (greeting on Home, etc.).
