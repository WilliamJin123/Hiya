# Account Deletion — Design

**Status:** Approved (2026-05-27)

**Goal:** Let a user permanently delete their account and all associated data from inside the app, satisfying App Store Guideline 5.1.1(v) (apps that support account creation must support in-app account deletion).

## Problem

The app ships only the Supabase **anon** key. The anon key cannot delete an `auth.users` row — that requires admin (`service_role`) privileges, which must never ship in a client. So deletion has to be brokered server-side.

## Approach: a `SECURITY DEFINER` RPC

A Postgres function `public.delete_current_user()` deletes the *calling* user:

```sql
delete from auth.users where id = auth.uid();
```

- `SECURITY DEFINER` so it runs with the privileges needed to delete from the `auth` schema.
- Scoped to `auth.uid()`, so a caller can only ever delete **themselves** — no parameter, no way to target another user.
- Execute revoked from `public`, granted to `authenticated` (covers both permanent and anonymous sessions, which both carry the `authenticated` role).
- All data cascades: `auth.users → profiles (on delete cascade) → people / conversations / person_notes / challenges (on delete cascade)`. One delete wipes everything.

### Bundled hardening

The same migration revokes execute on the helper `public.recompute_cold_flags(uuid)` from `anon, authenticated`. It is `SECURITY DEFINER` and only ever invoked by triggers (which run as the definer and keep access), but PostgREST otherwise exposes it as a callable RPC — a low-severity data-tampering vector. Revoking closes it.

## Client flow

- `HiyaRepository.deleteAccount()` — Live calls the RPC, then best-effort local `auth.signOut()` (the JWT is dead after deletion, so a server-side revoke failure is ignored). Mock clears its in-memory account/data and can throw via `errorToThrow`.
- `SessionViewModel.deleteAccount()` — on success, clears `account`/`profile`, resets the `hasGraduatedToAccount` and `hasOnboarded` UserDefaults flags (a truly fresh device), and routes to `.auth`. On failure, surfaces `errorMessage` and stays put.
- **UI:** a destructive "Delete account" row at the bottom of the Settings account section, shown for **both** permanent and anonymous accounts, behind a confirmation alert: "This permanently deletes your account and all your logs. This can't be undone."

## Testing

- `SessionViewModelTests`: `deleteAccount` success routes to `.auth` and clears flags; failure keeps state and sets `errorMessage`.
- Mock repo records the deletion and honors `errorToThrow`.
- The SQL function's auth scoping is enforced structurally (`where id = auth.uid()`, no params) — not unit-testable from the app; verified manually against the live DB.

## Non-goals

- No "export my data before deleting" flow (YAGNI for launch).
- No grace period / soft delete — deletion is immediate and permanent, as the copy states.
- No re-confirmation by password.
