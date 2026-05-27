# Account Deletion — Implementation Plan

> Executed inline. TDD where unit-testable; commit per task. From spec `2026-05-27-account-deletion-design.md`.

**Goal:** In-app permanent account + data deletion (App Store 5.1.1(v)), via a `SECURITY DEFINER` RPC.

---

## Task 1: Migration — `delete_current_user()` + hardening

**Files:** Create `supabase/migrations/20260527140000_add_account_deletion.sql`

```sql
-- Self-service account deletion. The anon key can't touch auth.users, so a
-- SECURITY DEFINER function deletes the *calling* user; cascades wipe all data.
create or replace function public.delete_current_user()
returns void
language sql
security definer
set search_path = public
as $$
  delete from auth.users where id = auth.uid();
$$;

revoke execute on function public.delete_current_user() from public;
grant execute on function public.delete_current_user() to authenticated;

-- Hardening: recompute_cold_flags is a SECURITY DEFINER helper only ever called
-- by triggers (which keep access as the definer). Stop it being a directly
-- callable RPC for ordinary clients.
revoke execute on function public.recompute_cold_flags(uuid) from anon, authenticated;
```

Apply: `supabase db push` (linked project `znvrlyjmbcqqkhgctcop`). Commit.

---

## Task 2: Repository surface

**Files:** Modify `HiyaRepository.swift` (protocol + Live), `MockHiyaRepository.swift`

- Protocol: add `func deleteAccount() async throws`
- Live:
```swift
func deleteAccount() async throws {
    try await client.rpc("delete_current_user").execute()
    try? await client.auth.signOut()
}
```
- Mock (add a `private(set) var didDeleteAccount = false`):
```swift
func deleteAccount() async throws {
    if let err = errorToThrow { errorToThrow = nil; throw err }
    didDeleteAccount = true
    authAccount = nil
    people = []
    conversations = []
    personNoteRows = []
    challengeRows = []
}
```

Build. Commit.

---

## Task 3: SessionViewModel.deleteAccount + tests

**Files:** Modify `SessionViewModel.swift`, `SessionViewModelTests.swift`

```swift
func deleteAccount() async {
    do {
        try await repo.deleteAccount()
    } catch {
        errorMessage = error.localizedDescription
        return
    }
    account = nil
    profile = nil
    hasGraduated = false
    hasOnboarded = false
    state = .auth
}
```

Tests (use existing `freshDefaults()`):
- `deleteAccount_success_routesToAuthAndClearsFlags`: seed graduated+onboarded true, mock returns ok → state `.auth`, account nil, and a fresh VM on the same defaults would route accordingly (flags cleared).
- `deleteAccount_failure_keepsStateAndSetsError`: `repo.errorToThrow = ...` → state unchanged, `errorMessage != nil`.

`clean test` (new test cases referencing the mock flag — DerivedData test discovery). Commit.

---

## Task 4: Settings UI — Delete account

**Files:** Modify `SettingsView.swift`

- Add `@State private var showDeleteConfirm = false`.
- At the bottom of `accountSection` (after permanent/claim views, inside both states — so place it in `accountSection` after the `if/else`), add a destructive button:
```swift
Button(role: .destructive) { showDeleteConfirm = true } label: {
    Text("Delete account")
        .font(Theme.FontScale.body())
        .foregroundColor(Theme.valenceNegative)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
}
.buttonStyle(.plain)
.disabled(session.isWorking)
```
- `.alert("Delete account?", isPresented: $showDeleteConfirm)` with destructive "Delete" → `Task { await session.deleteAccount(); dismiss() }` and a Cancel, message: "This permanently deletes your account and all your logs. This can't be undone."

Build. Commit.

---

## Manual verification
- Permanent account → Settings → Delete account → confirm → lands on AuthView; sign in attempt for that email fails (user gone); Supabase dashboard shows the user + rows removed.
- Anonymous account → same, data wiped, fresh anonymous on relaunch.
