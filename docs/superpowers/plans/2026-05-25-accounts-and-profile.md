# Real Accounts + Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add email+password accounts to Hiya — upgrade ("claim") the current anonymous user in place so all their data ports into a named "William Jin" account, with sign-in/out/create flows and an account section in Settings.

**Architecture:** A `SessionViewModel` gates the app: it shows the existing `RootView` when a session exists (anonymous or permanent), an `AuthView` when signed out, and auto-creates an anonymous session on fresh installs. Auth lives entirely in the repository (`auth.update/signUp/signIn/signOut` for Live; in-memory for Mock). No DB schema change — `profiles.display_name` already exists.

**Tech Stack:** SwiftUI (iOS 18.6, Xcode 26.1), Swift Testing, Supabase Swift (`client.auth`).

**Conventions:**
- **Test (editing existing tests):**
  ```bash
  cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild test \
    -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
    2>&1 | tee /tmp/hiya_test.log | grep -E "TEST (SUCCEEDED|FAILED)|: error:"
  ```
- **Adding new test functions/files** → use `clean test` (DerivedData caches discovery).
- **Build only** → replace `test` with `build`.
- SourceKit "Cannot find type / No such module 'Supabase'" mid-edit diagnostics are noise; `xcodebuild` is the source of truth.
- Commit to `main`; end commit messages with `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
- **Supabase API names** (`UserAttributes`, `update(user:)`, `signUp`, `signIn`, `signOut`, `User.isAnonymous`) are from supabase-swift 2.x; if the build reports a mismatched name, adjust to the SDK's actual signature (don't change the design).

---

## Prerequisite (manual, one-time — do FIRST)

In the Supabase dashboard for this project: **Authentication → Providers → Email → turn OFF "Confirm email"** (and ensure **Anonymous sign-ins** stay enabled). This makes claim/sign-up complete instantly without an email-verification round-trip the app isn't built to handle. This is a project setting, not code. The implementer should confirm with the user that it's done before manual end-to-end testing (unit tests don't need it).

---

## File Structure
- `hiya/hiya/Services/HiyaRepository.swift` — `AuthAccount` type; protocol auth requirements; Live implementations.
- `hiya/hiya/Services/MockHiyaRepository.swift` — in-memory auth (session state).
- `hiya/hiya/ViewModels/SessionViewModel.swift` (create) — gate state + auth actions.
- `hiya/hiya/Views/AppGateView.swift` (create) — loading / app / auth switch.
- `hiya/hiya/Views/AuthView.swift` (create) — signed-out sign in / create account.
- `hiya/hiya/hiyaApp.swift` — render `AppGateView` instead of `RootView`.
- `hiya/hiya/Views/SettingsView.swift` — account section + sign out.
- Tests: `hiya/hiyaTests/MockHiyaRepositoryTests.swift`, `hiya/hiyaTests/SessionViewModelTests.swift` (create).

---

### Task 1: Auth surface — `AuthAccount`, protocol, Live, Mock

**Files:** `Services/HiyaRepository.swift`, `Services/MockHiyaRepository.swift`, `hiyaTests/MockHiyaRepositoryTests.swift`

- [ ] **Step 1: Add `AuthAccount` + protocol requirements.** In `HiyaRepository.swift`, add the type just above `protocol HiyaRepository` (or below it, before `LoggedConversation`):
```swift
struct AuthAccount: Equatable, Sendable {
    let id: UUID
    let email: String?
    let isAnonymous: Bool
}
```
Add these requirements to the `protocol HiyaRepository` body (after `ensureSignedIn`):
```swift
    func currentAccount() async -> AuthAccount?
    func claimAccount(email: String, password: String, displayName: String) async throws -> Profile
    func signUp(email: String, password: String, displayName: String) async throws -> Profile
    func signIn(email: String, password: String) async throws -> Profile
    func signOut() async throws
    func updateDisplayName(_ name: String) async throws -> Profile
```

- [ ] **Step 2: Implement in Live (`LiveHiyaRepository`).** Add these methods (place after `ensureSignedIn`):
```swift
    func currentAccount() async -> AuthAccount? {
        guard client.auth.currentSession != nil else { return nil }
        guard let user = try? await client.auth.user() else { return nil }
        return AuthAccount(id: user.id, email: user.email, isAnonymous: user.isAnonymous)
    }

    func claimAccount(email: String, password: String, displayName: String) async throws -> Profile {
        // Attach credentials to the *current* (anonymous) user — same id, data preserved.
        try await client.auth.update(user: UserAttributes(email: email, password: password))
        return try await updateDisplayName(displayName)
    }

    func signUp(email: String, password: String, displayName: String) async throws -> Profile {
        try await client.auth.signUp(email: email, password: password)
        return try await updateDisplayName(displayName)
    }

    func signIn(email: String, password: String) async throws -> Profile {
        try await client.auth.signIn(email: email, password: password)
        return try await ensureSignedIn()   // session now exists → fetches that user's profile
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func updateDisplayName(_ name: String) async throws -> Profile {
        let userId = try await client.auth.user().id
        struct Update: Encodable { let display_name: String }
        return try await client
            .from("profiles")
            .update(Update(display_name: name))
            .eq("id", value: userId)
            .select()
            .single()
            .execute()
            .value
    }
```

- [ ] **Step 3: Implement in Mock (`MockHiyaRepository`).** Add a stored session near the other vars (after `var profile: Profile`):
```swift
    var authAccount: AuthAccount?
```
In `init(...)`, after `self.conversations = conversations`, seed an anonymous account matching the profile id:
```swift
        self.authAccount = AuthAccount(id: profile.id, email: nil, isAnonymous: true)
```
Update `ensureSignedIn()` to mirror Live's auto-anonymous (so a nil session re-anonymizes):
```swift
    func ensureSignedIn() async throws -> Profile {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        if authAccount == nil {
            authAccount = AuthAccount(id: profile.id, email: nil, isAnonymous: true)
        }
        return profile
    }
```
Add the auth methods (place after `ensureSignedIn`):
```swift
    func currentAccount() async -> AuthAccount? { authAccount }

    func claimAccount(email: String, password: String, displayName: String) async throws -> Profile {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        authAccount = AuthAccount(id: profile.id, email: email, isAnonymous: false)
        profile.displayName = displayName
        return profile
    }

    func signUp(email: String, password: String, displayName: String) async throws -> Profile {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        authAccount = AuthAccount(id: profile.id, email: email, isAnonymous: false)
        profile.displayName = displayName
        return profile
    }

    func signIn(email: String, password: String) async throws -> Profile {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        authAccount = AuthAccount(id: profile.id, email: email, isAnonymous: false)
        return profile
    }

    func signOut() async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        authAccount = nil
    }

    func updateDisplayName(_ name: String) async throws -> Profile {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        profile.displayName = name
        return profile
    }
```

- [ ] **Step 4: Write Mock auth tests.** Append to `hiyaTests/MockHiyaRepositoryTests.swift` (inside the struct, before the final `}`):
```swift
    // MARK: - Accounts

    @Test func defaultAccount_isAnonymous() async {
        let repo = MockHiyaRepository()
        let acct = await repo.currentAccount()
        #expect(acct?.isAnonymous == true)
        #expect(acct?.email == nil)
    }

    @Test func claimAccount_keepsIdMakesPermanent_setsName() async throws {
        let repo = MockHiyaRepository()
        let before = await repo.currentAccount()
        let profile = try await repo.claimAccount(email: "w@x.com", password: "secret1", displayName: "William Jin")
        let after = await repo.currentAccount()
        #expect(after?.isAnonymous == false)
        #expect(after?.email == "w@x.com")
        #expect(after?.id == before?.id, "claim must preserve the user id so data stays owned")
        #expect(profile.displayName == "William Jin")
    }

    @Test func signOut_thenCurrentAccountIsNil() async throws {
        let repo = MockHiyaRepository()
        try await repo.signOut()
        let acct = await repo.currentAccount()
        #expect(acct == nil)
    }

    @Test func signIn_restoresPermanentAccount() async throws {
        let repo = MockHiyaRepository()
        try await repo.signOut()
        _ = try await repo.signIn(email: "w@x.com", password: "secret1")
        let acct = await repo.currentAccount()
        #expect(acct?.isAnonymous == false)
        #expect(acct?.email == "w@x.com")
    }

    @Test func updateDisplayName_persists() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.updateDisplayName("Will")
        #expect(p.displayName == "Will")
        #expect(repo.profile.displayName == "Will")
    }
```

- [ ] **Step 5: Run tests** (`clean test` — new functions). Expected: TEST SUCCEEDED. (`MockHiyaRepository.profile` is a non-optional `var`, so mutating `displayName` compiles.)

- [ ] **Step 6: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Services/HiyaRepository.swift hiya/hiya/Services/MockHiyaRepository.swift hiya/hiyaTests/MockHiyaRepositoryTests.swift
git commit -m "feat(auth): repository auth surface (claim/signUp/signIn/signOut/displayName)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `SessionViewModel` (gate + auth actions)

**Files:** `ViewModels/SessionViewModel.swift` (create), `hiyaTests/SessionViewModelTests.swift` (create)

- [ ] **Step 1: Write the failing test** — `hiyaTests/SessionViewModelTests.swift`:
```swift
import Testing
import Foundation
@testable import hiya

@MainActor
struct SessionViewModelTests {
    @Test func decide_appWhenAccountPresent() {
        let acct = AuthAccount(id: UUID(), email: nil, isAnonymous: true)
        #expect(SessionViewModel.decide(account: acct, hasGraduated: false) == .app)
        #expect(SessionViewModel.decide(account: acct, hasGraduated: true) == .app)
    }
    @Test func decide_authWhenNoSessionButGraduated() {
        #expect(SessionViewModel.decide(account: nil, hasGraduated: true) == .auth)
    }
    @Test func decide_createAnonymousWhenFresh() {
        #expect(SessionViewModel.decide(account: nil, hasGraduated: false) == .createAnonymous)
    }

    @Test func start_anonymousSession_entersApp() async {
        let repo = MockHiyaRepository()          // default: anonymous session present
        let vm = SessionViewModel(repo: repo)
        await vm.start()
        #expect(vm.state == .app)
        #expect(vm.account?.isAnonymous == true)
    }

    @Test func claim_makesPermanentStaysInApp() async {
        let repo = MockHiyaRepository()
        let vm = SessionViewModel(repo: repo)
        await vm.start()
        let ok = await vm.claim(email: "w@x.com", password: "secret1", displayName: "William Jin")
        #expect(ok)
        #expect(vm.state == .app)
        #expect(vm.account?.isAnonymous == false)
        #expect(vm.profile?.displayName == "William Jin")
    }

    @Test func signOut_routesToAuth() async {
        let repo = MockHiyaRepository()
        let vm = SessionViewModel(repo: repo)
        await vm.start()
        await vm.signOut()
        #expect(vm.state == .auth)
        #expect(vm.account == nil)
    }

    @Test func signIn_routesToApp() async {
        let repo = MockHiyaRepository()
        let vm = SessionViewModel(repo: repo)
        await vm.signOut()                        // start signed out
        let ok = await vm.signIn(email: "w@x.com", password: "secret1")
        #expect(ok)
        #expect(vm.state == .app)
        #expect(vm.account?.isAnonymous == false)
    }
}
```

- [ ] **Step 2: Run** `clean test` — Expected: FAIL (no `SessionViewModel`).

- [ ] **Step 3: Implement** `ViewModels/SessionViewModel.swift`:
```swift
import Foundation
import Observation

@MainActor
@Observable
final class SessionViewModel {
    enum State: Equatable { case loading, app, auth }
    enum GateDecision: Equatable { case app, auth, createAnonymous }

    private let repo: HiyaRepository
    private(set) var state: State = .loading
    private(set) var account: AuthAccount?
    private(set) var profile: Profile?
    var isWorking = false
    var errorMessage: String?

    private let graduatedKey = "hiya.hasGraduatedToAccount"
    private var hasGraduated: Bool {
        get { UserDefaults.standard.bool(forKey: graduatedKey) }
        set { UserDefaults.standard.set(newValue, forKey: graduatedKey) }
    }

    init(repo: HiyaRepository) { self.repo = repo }

    /// Pure gate decision: a live session → app; otherwise sign-in if this device
    /// has had a real account, else create a fresh anonymous session.
    static func decide(account: AuthAccount?, hasGraduated: Bool) -> GateDecision {
        if account != nil { return .app }
        return hasGraduated ? .auth : .createAnonymous
    }

    func start() async {
        let acct = await repo.currentAccount()
        switch Self.decide(account: acct, hasGraduated: hasGraduated) {
        case .app:
            account = acct
            profile = try? await repo.ensureSignedIn()
            state = .app
        case .auth:
            state = .auth
        case .createAnonymous:
            do {
                profile = try await repo.ensureSignedIn()
                account = await repo.currentAccount()
                state = .app
            } catch {
                errorMessage = error.localizedDescription
                state = .auth
            }
        }
    }

    func claim(email: String, password: String, displayName: String) async -> Bool {
        await perform {
            self.profile = try await self.repo.claimAccount(email: email, password: password, displayName: displayName)
            self.account = await self.repo.currentAccount()
            self.hasGraduated = true
        }
    }

    func signUp(email: String, password: String, displayName: String) async -> Bool {
        await perform {
            self.profile = try await self.repo.signUp(email: email, password: password, displayName: displayName)
            self.account = await self.repo.currentAccount()
            self.hasGraduated = true
            self.state = .app
        }
    }

    func signIn(email: String, password: String) async -> Bool {
        await perform {
            self.profile = try await self.repo.signIn(email: email, password: password)
            self.account = await self.repo.currentAccount()
            self.hasGraduated = true
            self.state = .app
        }
    }

    func signOut() async {
        do {
            try await repo.signOut()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        account = nil
        profile = nil
        hasGraduated = true
        state = .auth
    }

    func updateDisplayName(_ name: String) async -> Bool {
        await perform { self.profile = try await self.repo.updateDisplayName(name) }
    }

    @discardableResult
    private func perform(_ action: () async throws -> Void) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do { try await action(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
}
```

- [ ] **Step 4: Run** `clean test` — Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/ViewModels/SessionViewModel.swift hiya/hiyaTests/SessionViewModelTests.swift
git commit -m "feat(auth): SessionViewModel gate + auth actions

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `AppGateView`, `AuthView`, app entry

**Files:** `Views/AppGateView.swift` (create), `Views/AuthView.swift` (create), `hiyaApp.swift`

- [ ] **Step 1: Create `AuthView`** — `Views/AuthView.swift`:
```swift
import SwiftUI

struct AuthView: View {
    let session: SessionViewModel

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = "William Jin"

    enum Mode: String, CaseIterable { case signIn = "Sign in", createNew = "Create account" }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 &&
        (mode == .signIn || !displayName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Hiya")
                        .font(Theme.FontScale.wordmark())
                        .foregroundStyle(Theme.accentGradient)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.xl)

                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if mode == .createNew {
                        field("Name", text: $displayName, secure: false, keyboard: .default)
                    }
                    field("Email", text: $email, secure: false, keyboard: .emailAddress)
                    field("Password", text: $password, secure: true, keyboard: .default)

                    if let error = session.errorMessage {
                        Text(error)
                            .font(Theme.FontScale.secondary())
                            .foregroundColor(Theme.valenceNegative)
                    }

                    Button {
                        Task {
                            switch mode {
                            case .signIn: _ = await session.signIn(email: email, password: password)
                            case .createNew: _ = await session.signUp(email: email, password: password, displayName: displayName)
                            }
                        }
                    } label: {
                        Text(mode.rawValue)
                            .font(Theme.FontScale.body())
                            .foregroundColor(Theme.textOnAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSubmit ? Theme.accentLavender : Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit || session.isWorking)
                }
                .padding(Theme.Spacing.md)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func field(_ placeholder: String, text: Binding<String>, secure: Bool, keyboard: UIKeyboardType) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled(keyboard == .emailAddress)
            }
        }
        .font(Theme.FontScale.body())
        .foregroundColor(Theme.textPrimary)
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

#Preview {
    AuthView(session: SessionViewModel(repo: MockHiyaRepository()))
}
```

- [ ] **Step 2: Create `AppGateView`** — `Views/AppGateView.swift`:
```swift
import SwiftUI

struct AppGateView: View {
    let repo: HiyaRepository
    @State private var session: SessionViewModel

    init(repo: HiyaRepository) {
        self.repo = repo
        _session = State(initialValue: SessionViewModel(repo: repo))
    }

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ZStack {
                    Theme.bgGradient.ignoresSafeArea()
                    ProgressView().tint(Theme.accentLavender)
                }
            case .app:
                RootView(repo: repo)
                    .environment(session)
            case .auth:
                AuthView(session: session)
            }
        }
        .task {
            if session.state == .loading { await session.start() }
        }
    }
}

#Preview {
    AppGateView(repo: MockHiyaRepository())
}
```

- [ ] **Step 3: Point the app at the gate.** In `hiyaApp.swift`, replace `RootView(repo: repo)` with `AppGateView(repo: repo)`:
```swift
        WindowGroup {
            AppGateView(repo: repo)
                .preferredColorScheme(.dark)
        }
```

- [ ] **Step 4: Build.** Expected: BUILD SUCCEEDED. (Manual run optional now; Settings wiring is Task 4. The app should boot anonymously into the tabs exactly as before.)

- [ ] **Step 5: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Views/AppGateView.swift hiya/hiya/Views/AuthView.swift hiya/hiya/hiyaApp.swift
git commit -m "feat(auth): app gate (anonymous-first) + sign-in/create screen

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Settings account section + sign out

**Files:** `Views/SettingsView.swift`

- [ ] **Step 1: Inject the session + add account form state.** In `SettingsView`, add below `@State private var vm`:
```swift
    @Environment(SessionViewModel.self) private var session
    @State private var claimEmail = ""
    @State private var claimPassword = ""
    @State private var nameDraft = ""
```

- [ ] **Step 2: Add the account section to the top of the body.** In `body`, change the `VStack` so the account section comes first, before the `Text("DAILY GOALS")`:
```swift
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        accountSection

                        Text("DAILY GOALS")
                            .font(Theme.FontScale.bodyHeading())
                            .tracking(1.2)
                            .foregroundColor(Theme.textSecondary)
```
(Leave the rest of the `VStack` — goal rows, error, save button — unchanged.)

- [ ] **Step 3: Add the account views.** Add these methods to `SettingsView` (e.g. above `goalRow`):
```swift
    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("ACCOUNT")
                .font(Theme.FontScale.bodyHeading())
                .tracking(1.2)
                .foregroundColor(Theme.textSecondary)

            if session.account?.isAnonymous == false {
                permanentAccountView
            } else {
                claimAccountView
            }

            if let error = session.errorMessage {
                Text(error)
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.valenceNegative)
            }
        }
    }

    private var permanentAccountView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Name").foregroundColor(Theme.textSecondary)
                Spacer()
            }
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Your name", text: $nameDraft)
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textPrimary)
                    .padding(12)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                Button("Save") {
                    Task { _ = await session.updateDisplayName(nameDraft) }
                }
                .foregroundColor(Theme.accentLavender)
                .disabled(nameDraft.trimmingCharacters(in: .whitespaces).isEmpty || session.isWorking)
            }
            Text(session.account?.email ?? "")
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textSecondary)

            Button {
                Task { await session.signOut() }
            } label: {
                Text("Sign out")
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.valenceNegative)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .buttonStyle(.plain)
        }
    }

    private var claimAccountView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Create an account to keep your data safe and sign in on other devices. All your current logs stay yours.")
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Name", text: $nameDraft)
                .textInputAutocapitalization(.words)
                .padding(12).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .foregroundColor(Theme.textPrimary)
            TextField("Email", text: $claimEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .padding(12).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .foregroundColor(Theme.textPrimary)
            SecureField("Password", text: $claimPassword)
                .padding(12).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .foregroundColor(Theme.textPrimary)
            Button {
                Task { _ = await session.claim(email: claimEmail, password: claimPassword, displayName: nameDraft) }
            } label: {
                Text("Create account")
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canClaim ? Theme.accentLavender : Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(!canClaim || session.isWorking)
        }
    }

    private var canClaim: Bool {
        claimEmail.contains("@") && claimPassword.count >= 6 &&
        !nameDraft.trimmingCharacters(in: .whitespaces).isEmpty
    }
```

- [ ] **Step 4: Seed `nameDraft`.** Change the existing `.task { await vm.load() }` modifier to also seed the name draft from the profile:
```swift
        .task {
            await vm.load()
            nameDraft = session.profile?.displayName ?? "William Jin"
        }
```

- [ ] **Step 5: Fix previews that now need the environment.** `SettingsView`'s `#Preview` must inject a session (the `@Environment(SessionViewModel.self)` is non-optional). Update it:
```swift
#Preview {
    SettingsView(repo: MockHiyaRepository())
        .environment(SessionViewModel(repo: MockHiyaRepository()))
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 6: Build.** Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Views/SettingsView.swift
git commit -m "feat(auth): account section in Settings — claim, display name, sign out

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Full verification + manual smoke test

- [ ] **Step 1: Full test run** (`clean test`). Expected: TEST SUCCEEDED.
```bash
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild clean test \
  -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  2>&1 | tee /tmp/hiya_test.log | grep -E "TEST (SUCCEEDED|FAILED)|: error:"
```

- [ ] **Step 2: Confirm the Supabase prerequisite** ("Confirm email" disabled) with the user, then manual smoke test in the simulator:
  1. App boots into the tabs (anonymous) as before; existing data present.
  2. Settings → ACCOUNT shows "Create account" → enter William Jin + email + password → Create → section flips to the permanent view with the email; all data still present (same id).
  3. Settings → Sign out → app routes to the Auth screen.
  4. Auth screen → Sign in with the same email/password → back into the app with the same data.
  5. Relaunch after sign-out shows the Auth screen (not a fresh anonymous account).

- [ ] **Step 3:** No commit (verification only). If smoke test reveals issues, fix and re-run Task 5.

---

## Self-review notes
- **No DB migration** — `profiles.display_name` exists with `profiles_update_own` RLS.
- **`ensureSignedIn()` unchanged** — still the only auto-anonymous path; the gate ensures it's only hit when appropriate.
- **Sign-out teardown:** flipping `session.state` to `.auth` replaces `RootView` with `AuthView`; the open Settings sheet is torn down with its presenter (no manual dismiss needed).
- **Post-implementation:** consider a memory note that Hiya now has email+password accounts via claim-in-place (anonymous→permanent), gated by `SessionViewModel`.
