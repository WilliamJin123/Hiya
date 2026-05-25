# Onboarding + Daily Reminder Notifications — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a first-run animated onboarding walkthrough that sets the user's daily goals, and an opt-in (default-OFF) daily reminder notification that nudges the user to log an approach.

**Architecture:** Onboarding is a new `.onboarding` state in the existing `SessionViewModel` gate, rendered by a paged `OnboardingView`; it writes goals through the existing `updateGoals` repo method. Notifications keep pure policy (`ReminderPlanner`) separate from the iOS effect (`NotificationScheduler` protocol with Live + Mock), orchestrated by an `@Observable NotificationManager` injected via `.environment`.

**Tech Stack:** SwiftUI, Swift 6 concurrency, `@Observable` view models, Swift Testing, `UNUserNotificationCenter`, UserDefaults (injectable suite for test isolation).

**Conventions:**
- Test/build command (substitute `clean test` / `test` / `build` as each step says):
  ```
  cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild clean test -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | tee /tmp/hiya_test.log | grep -E "TEST (SUCCEEDED|FAILED)|: error:"
  ```
  Use `clean test` for any step that **adds a new test file** (DerivedData caches test discovery); plain `test` when only editing existing test files; `build` for view-only changes with no tests.
- The Xcode project uses synchronized folder groups — new `.swift` files under `hiya/hiya/...` and `hiya/hiyaTests/...` are picked up automatically; no `.pbxproj` editing.
- Commit trailer on every commit:
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```
- SourceKit "Cannot find type / No such module" warnings are indexer noise; xcodebuild is authoritative.

---

## File Structure

**Feature A — Onboarding**
- Modify `hiya/hiya/ViewModels/SessionViewModel.swift` — add `.onboarding` state, inject `UserDefaults`, `hasOnboarded` flag, `completeOnboarding()`, gate logic.
- Modify `hiya/hiyaTests/SessionViewModelTests.swift` — isolate via injected defaults suite; add onboarding-gate tests.
- Create `hiya/hiya/ViewModels/OnboardingViewModel.swift` — page index, goal drafts seeded from profile, `finish()`.
- Create `hiya/hiyaTests/OnboardingViewModelTests.swift`.
- Create `hiya/hiya/Views/OnboardingView.swift` — paged animated walkthrough (4 cards) + page dots + action button.
- Modify `hiya/hiya/Views/AppGateView.swift` — render `OnboardingView` for `.onboarding`.

**Feature B — Notifications**
- Create `hiya/hiya/Services/ReminderPlanner.swift` — `PlannedReminder` + pure `plan(...)`.
- Create `hiya/hiyaTests/ReminderPlannerTests.swift`.
- Create `hiya/hiya/Services/NotificationScheduler.swift` — `NotifAuthStatus`, protocol, `LiveNotificationScheduler`.
- Create `hiya/hiya/Services/MockNotificationScheduler.swift` — test/preview double (app target, like `MockHiyaRepository`).
- Create `hiya/hiya/ViewModels/NotificationManager.swift` — `@Observable` orchestrator.
- Create `hiya/hiyaTests/NotificationManagerTests.swift`.
- Modify `hiya/hiya/Views/SettingsView.swift` — Reminders section.
- Modify `hiya/hiya/Views/HomeView.swift` — refresh hooks + scenePhase + preview env.
- Modify `hiya/hiya/Views/AppGateView.swift` — instantiate + inject `NotificationManager`, refresh auth status.

---

# Feature A — Onboarding

## Task A1: SessionViewModel onboarding gate

**Files:**
- Modify: `hiya/hiya/ViewModels/SessionViewModel.swift`
- Test: `hiya/hiyaTests/SessionViewModelTests.swift`

- [ ] **Step 1: Rewrite the test file to isolate UserDefaults and cover the gate**

Replace the entire contents of `hiya/hiyaTests/SessionViewModelTests.swift` with:

```swift
import Testing
import Foundation
@testable import hiya

@MainActor
struct SessionViewModelTests {
    /// Fresh, isolated defaults per test so the onboarding/graduated flags
    /// never leak between tests or into the real app domain.
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

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

    @Test func start_freshUser_routesToOnboarding() async {
        let repo = MockHiyaRepository()            // anonymous session present
        let vm = SessionViewModel(repo: repo, defaults: freshDefaults())
        await vm.start()
        #expect(vm.state == .onboarding)           // not yet onboarded
    }

    @Test func start_onboardedUser_entersApp() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hiya.hasOnboarded")
        let repo = MockHiyaRepository()
        let vm = SessionViewModel(repo: repo, defaults: defaults)
        await vm.start()
        #expect(vm.state == .app)
        #expect(vm.account?.isAnonymous == true)
    }

    @Test func completeOnboarding_setsFlagAndApp() async {
        let defaults = freshDefaults()
        let vm = SessionViewModel(repo: MockHiyaRepository(), defaults: defaults)
        await vm.start()
        #expect(vm.state == .onboarding)
        vm.completeOnboarding()
        #expect(vm.state == .app)
        // Flag persists: a new session on the same defaults skips onboarding.
        let vm2 = SessionViewModel(repo: MockHiyaRepository(), defaults: defaults)
        await vm2.start()
        #expect(vm2.state == .app)
    }

    @Test func claim_makesPermanentStaysInApp() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hiya.hasOnboarded")
        let vm = SessionViewModel(repo: MockHiyaRepository(), defaults: defaults)
        await vm.start()
        let ok = await vm.claim(email: "w@x.com", password: "secret1", displayName: "William Jin")
        #expect(ok)
        #expect(vm.state == .app)
        #expect(vm.account?.isAnonymous == false)
        #expect(vm.profile?.displayName == "William Jin")
    }

    @Test func signOut_routesToAuth() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hiya.hasOnboarded")
        let vm = SessionViewModel(repo: MockHiyaRepository(), defaults: defaults)
        await vm.start()
        await vm.signOut()
        #expect(vm.state == .auth)
        #expect(vm.account == nil)
    }

    @Test func signIn_routesToApp() async {
        let vm = SessionViewModel(repo: MockHiyaRepository(), defaults: freshDefaults())
        await vm.signOut()                          // start signed out
        let ok = await vm.signIn(email: "w@x.com", password: "secret1")
        #expect(ok)
        #expect(vm.state == .app)
        #expect(vm.account?.isAnonymous == false)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (plain `test` — editing an existing test file):
```
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild test -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | tee /tmp/hiya_test.log | grep -E "TEST (SUCCEEDED|FAILED)|: error:"
```
Expected: FAIL to compile — `SessionViewModel` has no `defaults:` init parameter, no `.onboarding` case, no `completeOnboarding()`.

- [ ] **Step 3: Implement the gate in SessionViewModel**

In `hiya/hiya/ViewModels/SessionViewModel.swift`:

Change the `State` enum (line ~7) to add `onboarding`:
```swift
    enum State: Equatable { case loading, app, onboarding, auth }
```

Replace the stored-properties + init + flags block (lines ~11–23) with:
```swift
    private let repo: HiyaRepository
    private let defaults: UserDefaults
    private(set) var state: State = .loading
    private(set) var account: AuthAccount?
    private(set) var profile: Profile?
    var isWorking = false
    var errorMessage: String?

    private let graduatedKey = "hiya.hasGraduatedToAccount"
    private let onboardedKey = "hiya.hasOnboarded"

    private var hasGraduated: Bool {
        get { defaults.bool(forKey: graduatedKey) }
        set { defaults.set(newValue, forKey: graduatedKey) }
    }
    private var hasOnboarded: Bool {
        get { defaults.bool(forKey: onboardedKey) }
        set { defaults.set(newValue, forKey: onboardedKey) }
    }

    init(repo: HiyaRepository, defaults: UserDefaults = .standard) {
        self.repo = repo
        self.defaults = defaults
    }
```

In `start()`, change both app-bound assignments from `state = .app` to gate on onboarding. The `.app` case becomes:
```swift
        case .app:
            account = acct
            profile = try? await repo.ensureSignedIn()
            state = hasOnboarded ? .app : .onboarding
```
and the `.createAnonymous` success line becomes:
```swift
                profile = try await repo.ensureSignedIn()
                account = await repo.currentAccount()
                state = hasOnboarded ? .app : .onboarding
```

In `signIn(...)` and `signUp(...)`, mark onboarding complete so returning/new real-account users never see the walkthrough. Add `self.hasOnboarded = true` right after `self.hasGraduated = true` in each of those `perform { ... }` closures.

Add this method (e.g. just after `signOut()`):
```swift
    func completeOnboarding() {
        hasOnboarded = true
        state = .app
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (plain `test`):
```
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild test -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | tee /tmp/hiya_test.log | grep -E "TEST (SUCCEEDED|FAILED)|: error:"
```
Expected: TEST SUCCEEDED, no failures. (`AppGateView` still compiles — it does not yet handle `.onboarding`, but a non-exhaustive `switch` over an enum is a compile error in Swift. **Add a temporary placeholder now** so the build passes: in `AppGateView.body`'s switch add `case .onboarding: loadingView` if a `loadingView` helper exists, else reuse the loading `ZStack`. Task A3 replaces it with the real view. To keep this step green, add:)
```swift
            case .onboarding:
                ZStack { Theme.bgGradient.ignoresSafeArea(); ProgressView().tint(Theme.accentLavender) }
```

- [ ] **Step 5: Commit**

```bash
cd /Users/williamjin/Documents/Hiya && git add hiya/hiya/ViewModels/SessionViewModel.swift hiya/hiyaTests/SessionViewModelTests.swift hiya/hiya/Views/AppGateView.swift && git commit -m "feat(onboarding): SessionViewModel onboarding gate state

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A2: OnboardingViewModel

**Files:**
- Create: `hiya/hiya/ViewModels/OnboardingViewModel.swift`
- Test: `hiya/hiyaTests/OnboardingViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `hiya/hiyaTests/OnboardingViewModelTests.swift`:
```swift
import Testing
import Foundation
@testable import hiya

@MainActor
struct OnboardingViewModelTests {
    @Test func seedsGoalsFromProfile() {
        var p = Profile.preview
        p.coldDailyGoal = 5
        p.warmDailyGoal = 8
        let vm = OnboardingViewModel(repo: MockHiyaRepository(), profile: p)
        #expect(vm.coldGoal == 5)
        #expect(vm.warmGoal == 8)
    }

    @Test func seedsDefaultsWhenNoProfile() {
        let vm = OnboardingViewModel(repo: MockHiyaRepository(), profile: nil)
        #expect(vm.coldGoal == 10)
        #expect(vm.warmGoal == 10)
    }

    @Test func nextAdvancesAndClamps() {
        let vm = OnboardingViewModel(repo: MockHiyaRepository(), profile: .preview)
        #expect(vm.page == 0)
        vm.next(); vm.next(); vm.next()
        #expect(vm.page == 3)
        #expect(vm.isLastPage)
        vm.next()                       // already last — stays
        #expect(vm.page == 3)
    }

    @Test func finishSavesGoals() async {
        let repo = MockHiyaRepository()
        let vm = OnboardingViewModel(repo: repo, profile: .preview)
        vm.coldGoal = 7
        vm.warmGoal = 12
        let ok = await vm.finish()
        #expect(ok)
        let saved = try? await repo.ensureSignedIn()
        #expect(saved?.coldDailyGoal == 7)
        #expect(saved?.warmDailyGoal == 12)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (`clean test` — new test file added):
```
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild clean test -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | tee /tmp/hiya_test.log | grep -E "TEST (SUCCEEDED|FAILED)|: error:"
```
Expected: FAIL to compile — `OnboardingViewModel` does not exist.

- [ ] **Step 3: Implement OnboardingViewModel**

Create `hiya/hiya/ViewModels/OnboardingViewModel.swift`:
```swift
import Foundation
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    private let repo: HiyaRepository

    static let pageCount = 4

    var page = 0
    var coldGoal: Int
    var warmGoal: Int
    private(set) var isSaving = false
    var errorMessage: String?

    init(repo: HiyaRepository, profile: Profile?) {
        self.repo = repo
        self.coldGoal = profile?.coldDailyGoal ?? 10
        self.warmGoal = profile?.warmDailyGoal ?? 10
    }

    var isLastPage: Bool { page == Self.pageCount - 1 }

    func next() {
        if page < Self.pageCount - 1 { page += 1 }
    }

    /// Persists the chosen goals. Returns true on success so the caller can
    /// then mark onboarding complete.
    func finish() async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await repo.updateGoals(coldDailyGoal: coldGoal, warmDailyGoal: warmGoal)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (plain `test` — file now exists and is discovered after the previous clean):
```
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild test -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | tee /tmp/hiya_test.log | grep -E "TEST (SUCCEEDED|FAILED)|: error:"
```
Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
cd /Users/williamjin/Documents/Hiya && git add hiya/hiya/ViewModels/OnboardingViewModel.swift hiya/hiyaTests/OnboardingViewModelTests.swift && git commit -m "feat(onboarding): OnboardingViewModel with goal seeding + save

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A3: OnboardingView (animated walkthrough) + gate wiring

**Files:**
- Create: `hiya/hiya/Views/OnboardingView.swift`
- Modify: `hiya/hiya/Views/AppGateView.swift`

No unit tests (pure SwiftUI view); verified by a successful `build`.

- [ ] **Step 1: Create OnboardingView**

Create `hiya/hiya/Views/OnboardingView.swift`:
```swift
import SwiftUI

struct OnboardingView: View {
    let repo: HiyaRepository
    let session: SessionViewModel
    @State private var vm: OnboardingViewModel

    init(repo: HiyaRepository, session: SessionViewModel) {
        self.repo = repo
        self.session = session
        _vm = State(initialValue: OnboardingViewModel(repo: repo, profile: session.profile))
    }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $vm.page) {
                    WelcomeCard().tag(0)
                    TwoKindsCard().tag(1)
                    HowToLogCard().tag(2)
                    SetGoalsCard(coldGoal: $vm.coldGoal, warmGoal: $vm.warmGoal).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: vm.page)

                if let error = vm.errorMessage {
                    Text(error)
                        .font(Theme.FontScale.secondary())
                        .foregroundColor(Theme.valenceNegative)
                        .padding(.horizontal, Theme.Spacing.md)
                }
                pageDots
                actionButton
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
        .preferredColorScheme(.dark)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<OnboardingViewModel.pageCount, id: \.self) { i in
                Circle()
                    .fill(i == vm.page ? Theme.accentLavender : Theme.ringTrack)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.bottom, Theme.Spacing.lg)
    }

    private var actionButton: some View {
        Button {
            if vm.isLastPage {
                Task {
                    if await vm.finish() { session.completeOnboarding() }
                }
            } else {
                withAnimation { vm.next() }
            }
        } label: {
            Text(vm.isLastPage ? "Get started" : "Continue")
                .font(Theme.FontScale.body().weight(.semibold))
                .foregroundColor(Theme.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.accentLavender)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .shadow(color: Theme.accentLavender.opacity(0.3), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(vm.isSaving)
        .padding(.horizontal, Theme.Spacing.md)
    }
}

// MARK: - Cards

private struct WelcomeCard: View {
    @State private var appeared = false
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            Text("Hiya")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accentGradient)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
            Text("A daily nudge to talk to people.")
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .onAppear {
            appeared = false
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appeared = true }
        }
    }
}

private struct TwoKindsCard: View {
    @State private var fill = false
    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            HStack(spacing: Theme.Spacing.lg) {
                miniRing(Theme.accentGradient, "Approaches", "New people", delay: 0)
                miniRing(Theme.accentGradientReversed, "Catch-ups", "People you know", delay: 0.18)
            }
            Text("Two kinds of conversation, kept separate: meet new people, and stay close to the ones you know.")
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .onAppear {
            fill = false
            withAnimation(.easeOut(duration: 0.9)) { fill = true }
        }
    }

    private func miniRing(_ gradient: LinearGradient, _ label: String, _ sub: String, delay: Double) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().stroke(Theme.ringTrack, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fill ? 0.8 : 0)
                    .stroke(gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.9).delay(delay), value: fill)
            }
            .frame(width: 96, height: 96)
            Text(label).font(Theme.FontScale.body()).foregroundColor(Theme.textPrimary)
            Text(sub).font(Theme.FontScale.secondary()).foregroundColor(Theme.textSecondary)
        }
    }
}

private struct HowToLogCard: View {
    @State private var appeared = false
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Text("Log it in a tap")
                .font(Theme.FontScale.title())
                .foregroundColor(Theme.textPrimary)

            HStack(spacing: Theme.Spacing.md) {
                Circle().fill(Theme.valencePositive).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Maya").font(Theme.FontScale.body()).foregroundColor(Theme.textPrimary)
                    Text("complimented her bag at the cafe")
                        .font(Theme.FontScale.secondary()).foregroundColor(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .opacity(appeared ? 1 : 0)
            .offset(x: appeared ? 0 : -30)

            HStack(spacing: Theme.Spacing.sm) {
                chip("Good", Theme.valencePositive)
                chip("OK", Theme.valenceNeutral)
                chip("Rough", Theme.valenceNegative)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.8)

            Text("Every chat counts — even the rough ones. Rate it and move on.")
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .onAppear {
            appeared = false
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) { appeared = true }
        }
    }

    private func chip(_ title: String, _ color: Color) -> some View {
        Text(title)
            .font(Theme.FontScale.secondary())
            .foregroundColor(Theme.textOnAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(color))
    }
}

private struct SetGoalsCard: View {
    @Binding var coldGoal: Int
    @Binding var warmGoal: Int
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Text("Set your daily goals")
                .font(Theme.FontScale.title())
                .foregroundColor(Theme.textPrimary)
            Text("How many a day feels right? Change these anytime in Settings.")
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
            goalStepper("Approaches", "New people", $coldGoal, Theme.coldAccent)
            goalStepper("Catch-ups", "People you know", $warmGoal, Theme.warmAccent)
            Spacer()
        }
        .padding(Theme.Spacing.xl)
    }

    private func goalStepper(_ title: String, _ sub: String, _ value: Binding<Int>, _ accent: Color) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.FontScale.body()).foregroundColor(Theme.textPrimary)
                Text(sub).font(Theme.FontScale.secondary()).foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Text("\(value.wrappedValue)")
                .font(.custom(Theme.FontName.counterMono, size: 22).weight(.semibold))
                .foregroundColor(accent)
                .frame(minWidth: 32, alignment: .trailing)
                .contentTransition(.numericText())
            Stepper("", value: value, in: 1...50).labelsHidden().fixedSize()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

#Preview {
    OnboardingView(repo: MockHiyaRepository(), session: SessionViewModel(repo: MockHiyaRepository()))
}
```

- [ ] **Step 2: Wire the gate to render OnboardingView**

In `hiya/hiya/Views/AppGateView.swift`, replace the temporary `.onboarding` placeholder added in Task A1 with:
```swift
            case .onboarding:
                OnboardingView(repo: repo, session: session)
```

- [ ] **Step 3: Build to verify it compiles**

Run (`build` — no new tests):
```
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild build -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | tee /tmp/hiya_build.log | grep -E "BUILD (SUCCEEDED|FAILED)|: error:"
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
cd /Users/williamjin/Documents/Hiya && git add hiya/hiya/Views/OnboardingView.swift hiya/hiya/Views/AppGateView.swift && git commit -m "feat(onboarding): animated four-card walkthrough + gate wiring

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

# Feature B — Daily reminder notifications

## Task B1: ReminderPlanner (pure policy)

**Files:**
- Create: `hiya/hiya/Services/ReminderPlanner.swift`
- Test: `hiya/hiyaTests/ReminderPlannerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `hiya/hiyaTests/ReminderPlannerTests.swift`:
```swift
import Testing
import Foundation
@testable import hiya

struct ReminderPlannerTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    @Test func disabledProducesNothing() {
        let out = ReminderPlanner.plan(enabled: false, hour: 18, minute: 0,
                                       now: date(2026, 5, 25, 9, 0), goalMetToday: false,
                                       horizonDays: 7, calendar: cal)
        #expect(out.isEmpty)
    }

    @Test func includesTodayWhenTimeFutureAndGoalNotMet() {
        let out = ReminderPlanner.plan(enabled: true, hour: 18, minute: 0,
                                       now: date(2026, 5, 25, 9, 0), goalMetToday: false,
                                       horizonDays: 7, calendar: cal)
        #expect(out.count == 7)
        #expect(out.first?.id == "hiya.reminder.2026-05-25")
    }

    @Test func skipsTodayWhenGoalMet() {
        let out = ReminderPlanner.plan(enabled: true, hour: 18, minute: 0,
                                       now: date(2026, 5, 25, 9, 0), goalMetToday: true,
                                       horizonDays: 7, calendar: cal)
        #expect(out.count == 6)
        #expect(out.first?.id == "hiya.reminder.2026-05-26")
    }

    @Test func skipsTodayWhenTimePassed() {
        let out = ReminderPlanner.plan(enabled: true, hour: 18, minute: 0,
                                       now: date(2026, 5, 25, 20, 0), goalMetToday: false,
                                       horizonDays: 7, calendar: cal)
        #expect(out.count == 6)
        #expect(out.first?.id == "hiya.reminder.2026-05-26")
    }

    @Test func fireDateMatchesConfiguredTime() {
        let out = ReminderPlanner.plan(enabled: true, hour: 18, minute: 30,
                                       now: date(2026, 5, 25, 9, 0), goalMetToday: false,
                                       horizonDays: 1, calendar: cal)
        #expect(out.count == 1)
        let comps = cal.dateComponents([.hour, .minute], from: out[0].fireDate)
        #expect(comps.hour == 18)
        #expect(comps.minute == 30)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (`clean test` — new test file):
```
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild clean test -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | tee /tmp/hiya_test.log | grep -E "TEST (SUCCEEDED|FAILED)|: error:"
```
Expected: FAIL to compile — `ReminderPlanner` does not exist.

- [ ] **Step 3: Implement ReminderPlanner**

Create `hiya/hiya/Services/ReminderPlanner.swift`:
```swift
import Foundation

/// One scheduled daily reminder. Pure value type — no UNNotification dependency,
/// so it can be planned and asserted on in tests.
struct PlannedReminder: Equatable, Sendable {
    let id: String
    let fireDate: Date
    let title: String
    let body: String
}

/// Pure scheduling policy for the daily approach reminder. Decides *which*
/// reminders should exist; the `NotificationScheduler` decides how to register
/// them with the OS.
enum ReminderPlanner {
    static let idPrefix = "hiya.reminder."
    static let title = "Time for an approach"
    static let body = "Say hi to someone new today — even a small one counts."

    /// One reminder per day for the next `horizonDays`, at `hour:minute`.
    /// Today is skipped when the goal is already met or the time has passed.
    static func plan(
        enabled: Bool,
        hour: Int,
        minute: Int,
        now: Date,
        goalMetToday: Bool,
        horizonDays: Int,
        calendar: Calendar
    ) -> [PlannedReminder] {
        guard enabled else { return [] }
        let startDay = calendar.startOfDay(for: now)
        var result: [PlannedReminder] = []
        for offset in 0..<horizonDays {
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: startDay),
                let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
            else { continue }
            if offset == 0 {
                if goalMetToday { continue }
                if fire <= now { continue }
            }
            result.append(PlannedReminder(id: idPrefix + dayKey(day, calendar: calendar),
                                          fireDate: fire, title: title, body: body))
        }
        return result
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (plain `test`):
```
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild test -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | tee /tmp/hiya_test.log | grep -E "TEST (SUCCEEDED|FAILED)|: error:"
```
Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
cd /Users/williamjin/Documents/Hiya && git add hiya/hiya/Services/ReminderPlanner.swift hiya/hiyaTests/ReminderPlannerTests.swift && git commit -m "feat(notifications): pure ReminderPlanner scheduling policy

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task B2: NotificationScheduler protocol + Live + Mock

**Files:**
- Create: `hiya/hiya/Services/NotificationScheduler.swift`
- Create: `hiya/hiya/Services/MockNotificationScheduler.swift`

No standalone tests in this task (exercised via `NotificationManagerTests` in B3); verified by `build`.

- [ ] **Step 1: Create the protocol, status type, and Live implementation**

Create `hiya/hiya/Services/NotificationScheduler.swift`:
```swift
import Foundation
import UserNotifications

/// App-level view of notification authorization, decoupled from UNAuthorizationStatus.
enum NotifAuthStatus: Equatable, Sendable {
    case notDetermined, authorized, denied
}

/// The seam between the app and `UNUserNotificationCenter`. MainActor-isolated
/// because it is only ever driven by `NotificationManager` (also MainActor).
@MainActor
protocol NotificationScheduler {
    func authorizationStatus() async -> NotifAuthStatus
    func requestAuthorization() async -> Bool
    /// Removes all of Hiya's pending reminder requests and registers the given set.
    func replaceReminders(_ reminders: [PlannedReminder]) async
    func pendingReminderIDs() async -> [String]
}

@MainActor
final class LiveNotificationScheduler: NotificationScheduler {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> NotifAuthStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func replaceReminders(_ reminders: [PlannedReminder]) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func pendingReminderIDs() async -> [String] {
        let pending = await center.pendingNotificationRequests()
        return pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.idPrefix) }
    }
}
```

- [ ] **Step 2: Create the Mock implementation**

Create `hiya/hiya/Services/MockNotificationScheduler.swift`:
```swift
import Foundation

/// In-memory scheduler for tests and previews. Records calls instead of touching
/// the OS. Lives in the app target (like `MockHiyaRepository`) so previews use it too.
@MainActor
final class MockNotificationScheduler: NotificationScheduler {
    var status: NotifAuthStatus = .notDetermined
    var grantOnRequest = true
    private(set) var requestCount = 0
    private(set) var scheduled: [PlannedReminder] = []

    func authorizationStatus() async -> NotifAuthStatus { status }

    func requestAuthorization() async -> Bool {
        requestCount += 1
        status = grantOnRequest ? .authorized : .denied
        return grantOnRequest
    }

    func replaceReminders(_ reminders: [PlannedReminder]) async { scheduled = reminders }

    func pendingReminderIDs() async -> [String] { scheduled.map(\.id) }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run (`build`):
```
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild build -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | tee /tmp/hiya_build.log | grep -E "BUILD (SUCCEEDED|FAILED)|: error:"
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
cd /Users/williamjin/Documents/Hiya && git add hiya/hiya/Services/NotificationScheduler.swift hiya/hiya/Services/MockNotificationScheduler.swift && git commit -m "feat(notifications): NotificationScheduler protocol + Live + Mock

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task B3: NotificationManager

**Files:**
- Create: `hiya/hiya/ViewModels/NotificationManager.swift`
- Test: `hiya/hiyaTests/NotificationManagerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `hiya/hiyaTests/NotificationManagerTests.swift`:
```swift
import Testing
import Foundation
@testable import hiya

@MainActor
struct NotificationManagerTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    @Test func defaultsAreOffAtSixPM() {
        let m = NotificationManager(scheduler: MockNotificationScheduler(), defaults: freshDefaults())
        #expect(m.enabled == false)
        #expect(m.hour == 18)
        #expect(m.minute == 0)
    }

    @Test func enableRequestsAuthAndSchedules() async {
        let sched = MockNotificationScheduler()
        let m = NotificationManager(scheduler: sched, defaults: freshDefaults())
        let ok = await m.enable()
        #expect(ok)
        #expect(sched.requestCount == 1)
        #expect(m.enabled)
        #expect(m.authorizationStatus == .authorized)
        #expect(!sched.scheduled.isEmpty)
    }

    @Test func deniedAuthLeavesDisabled() async {
        let sched = MockNotificationScheduler()
        sched.grantOnRequest = false
        let m = NotificationManager(scheduler: sched, defaults: freshDefaults())
        let ok = await m.enable()
        #expect(!ok)
        #expect(!m.enabled)
        #expect(m.authorizationStatus == .denied)
        #expect(sched.scheduled.isEmpty)
    }

    @Test func disableClearsSchedule() async {
        let sched = MockNotificationScheduler()
        let m = NotificationManager(scheduler: sched, defaults: freshDefaults())
        _ = await m.enable()
        await m.disable()
        #expect(!m.enabled)
        #expect(sched.scheduled.isEmpty)
    }

    @Test func refreshNoOpWhenDisabled() async {
        let sched = MockNotificationScheduler()
        let m = NotificationManager(scheduler: sched, defaults: freshDefaults())
        await m.refresh(goalMetToday: false)
        #expect(sched.scheduled.isEmpty)   // never enabled → nothing scheduled
    }

    @Test func enabledStatePersistsAcrossInstances() async {
        let defaults = freshDefaults()
        let sched = MockNotificationScheduler()
        let m = NotificationManager(scheduler: sched, defaults: defaults)
        _ = await m.enable()
        await m.setTime(makeTime(hour: 9, minute: 15))
        let m2 = NotificationManager(scheduler: MockNotificationScheduler(), defaults: defaults)
        #expect(m2.enabled)
        #expect(m2.hour == 9)
        #expect(m2.minute == 15)
    }

    private func makeTime(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now)!
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (`clean test` — new test file):
```
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild clean test -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | tee /tmp/hiya_test.log | grep -E "TEST (SUCCEEDED|FAILED)|: error:"
```
Expected: FAIL to compile — `NotificationManager` does not exist.

- [ ] **Step 3: Implement NotificationManager**

Create `hiya/hiya/ViewModels/NotificationManager.swift`:
```swift
import Foundation
import Observation

/// Owns the daily-reminder preference (default OFF) and keeps the OS schedule in
/// sync via a `NotificationScheduler`. Injected into the environment for Settings
/// and Home to drive.
@MainActor
@Observable
final class NotificationManager {
    private let scheduler: any NotificationScheduler
    private let defaults: UserDefaults

    private let enabledKey = "hiya.notif.dailyEnabled"
    private let hourKey = "hiya.notif.dailyHour"
    private let minuteKey = "hiya.notif.dailyMinute"
    static let horizonDays = 7

    private(set) var enabled: Bool
    private(set) var hour: Int
    private(set) var minute: Int
    private(set) var authorizationStatus: NotifAuthStatus = .notDetermined

    init(scheduler: any NotificationScheduler, defaults: UserDefaults = .standard) {
        self.scheduler = scheduler
        self.defaults = defaults
        self.enabled = defaults.bool(forKey: enabledKey)                 // default false
        self.hour = (defaults.object(forKey: hourKey) as? Int) ?? 18
        self.minute = (defaults.object(forKey: minuteKey) as? Int) ?? 0
    }

    /// The configured reminder time as a `Date` (today at hour:minute) for binding
    /// to a `DatePicker(.hourAndMinute)`.
    var time: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await scheduler.authorizationStatus()
    }

    /// Turn the reminder on: request permission, persist, schedule. Returns granted.
    func enable() async -> Bool {
        let granted = await scheduler.requestAuthorization()
        authorizationStatus = granted ? .authorized : .denied
        guard granted else { return false }
        enabled = true
        defaults.set(true, forKey: enabledKey)
        await reschedule(goalMetToday: false)
        return true
    }

    func disable() async {
        enabled = false
        defaults.set(false, forKey: enabledKey)
        await scheduler.replaceReminders([])
    }

    func setTime(_ date: Date) async {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        hour = c.hour ?? 18
        minute = c.minute ?? 0
        defaults.set(hour, forKey: hourKey)
        defaults.set(minute, forKey: minuteKey)
        if enabled { await reschedule(goalMetToday: false) }
    }

    /// Recompute and apply the schedule. Called by Home on appear / after a log /
    /// on foreground. No-op when disabled.
    func refresh(goalMetToday: Bool) async {
        guard enabled else { return }
        await reschedule(goalMetToday: goalMetToday)
    }

    private func reschedule(goalMetToday: Bool, now: Date = .now) async {
        let plan = ReminderPlanner.plan(
            enabled: enabled, hour: hour, minute: minute,
            now: now, goalMetToday: goalMetToday,
            horizonDays: Self.horizonDays, calendar: .current
        )
        await scheduler.replaceReminders(plan)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (plain `test`):
```
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild test -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | tee /tmp/hiya_test.log | grep -E "TEST (SUCCEEDED|FAILED)|: error:"
```
Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
cd /Users/williamjin/Documents/Hiya && git add hiya/hiya/ViewModels/NotificationManager.swift hiya/hiyaTests/NotificationManagerTests.swift && git commit -m "feat(notifications): NotificationManager orchestrator (default off)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task B4: UI wiring — Settings section, AppGateView injection, Home refresh hooks

**Files:**
- Modify: `hiya/hiya/Views/AppGateView.swift`
- Modify: `hiya/hiya/Views/SettingsView.swift`
- Modify: `hiya/hiya/Views/HomeView.swift`

View-only; verified by `build`.

- [ ] **Step 1: Instantiate + inject NotificationManager in AppGateView**

In `hiya/hiya/Views/AppGateView.swift`:

Add the stored manager + scenePhase below the existing `session` property:
```swift
    @State private var notifications: NotificationManager
    @Environment(\.scenePhase) private var scenePhase
```
Update `init` to create it:
```swift
    init(repo: HiyaRepository) {
        self.repo = repo
        _session = State(initialValue: SessionViewModel(repo: repo))
        _notifications = State(initialValue: NotificationManager(scheduler: LiveNotificationScheduler()))
    }
```
Inject it into the app tree — the `.app` case becomes:
```swift
            case .app:
                RootView(repo: repo)
                    .environment(session)
                    .environment(notifications)
```
Add an auth-status refresh on the outer `Group` (next to the existing `.task`):
```swift
        .task { await notifications.refreshAuthorizationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await notifications.refreshAuthorizationStatus() }
            }
        }
```
(Scheduling refresh is driven by Home, which knows the goal-met state; here we only keep `authorizationStatus` current in case the user toggled notifications in iOS Settings.)

- [ ] **Step 2: Add the Reminders section to SettingsView**

In `hiya/hiya/Views/SettingsView.swift`:

Add to the environment reads (after the existing `@Environment(SessionViewModel.self)` line):
```swift
    @Environment(NotificationManager.self) private var notifications
```
In `body`, insert `remindersSection` into the main `VStack` after the goal rows / `errorMessage` block and before `saveButton`:
```swift
                        remindersSection
```
Add this computed section (e.g. after `accountSection`):
```swift
    @ViewBuilder
    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("REMINDERS")
                .font(Theme.FontScale.bodyHeading())
                .tracking(1.2)
                .foregroundColor(Theme.textSecondary)

            Toggle(isOn: Binding(
                get: { notifications.enabled },
                set: { on in
                    Task {
                        if on { _ = await notifications.enable() }
                        else { await notifications.disable() }
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily approach reminder")
                        .font(Theme.FontScale.body())
                        .foregroundColor(Theme.textPrimary)
                    Text("A nudge to approach someone — skipped once you hit your goal.")
                        .font(Theme.FontScale.secondary())
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accentLavender)
            .padding(Theme.Spacing.md)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            if notifications.enabled {
                HStack {
                    Text("Time")
                        .font(Theme.FontScale.body())
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    DatePicker("", selection: Binding(
                        get: { notifications.time },
                        set: { newDate in Task { await notifications.setTime(newDate) } }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                }
                .padding(Theme.Spacing.md)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }

            if notifications.authorizationStatus == .denied {
                Text("Notifications are off in iOS Settings. Turn them on for Hiya to send reminders.")
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.valenceNegative)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await notifications.refreshAuthorizationStatus() }
    }
```
Update the `#Preview` at the bottom to inject the manager:
```swift
#Preview {
    SettingsView(repo: MockHiyaRepository())
        .environment(SessionViewModel(repo: MockHiyaRepository()))
        .environment(NotificationManager(scheduler: MockNotificationScheduler()))
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 3: Add refresh hooks to HomeView**

In `hiya/hiya/Views/HomeView.swift`:

Add environment reads after the existing `@AppStorage` line (top of `HomeView`):
```swift
    @Environment(NotificationManager.self) private var notifications
    @Environment(\.scenePhase) private var scenePhase
```
Add a helper near the bottom of `HomeView` (before the closing brace of the struct, alongside other private methods):
```swift
    private func syncReminders() async {
        await notifications.refresh(goalMetToday: vm.isGoalMet(for: .cold))
    }
```
Wire it into the existing refresh points. Change the three relevant modifiers on the `NavigationStack`:
```swift
            .sheet(isPresented: $showingSettings, onDismiss: { Task { await vm.refresh(); await syncReminders() } }) {
                SettingsView(repo: repo)
            }
            .task { await vm.refresh(); await challengesVM.load(); await syncReminders() }
            .refreshable { await vm.refresh(); await challengesVM.load(); await syncReminders() }
            .sheet(item: $sheetMode, onDismiss: { Task { await vm.refresh(); await challengesVM.load(); await syncReminders() } }) { sheet in
                switch sheet {
                case .create(let p, let mode):
                    LogSheetView(repo: repo, preselectedPerson: p, creationMode: mode)
                case .edit(let entry):
                    LogSheetView(repo: repo, editing: entry)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await vm.refresh(); await syncReminders() }
                }
            }
```
Update the `#Preview` to inject the manager:
```swift
#Preview {
    HomeView(repo: MockHiyaRepository())
        .environment(NotificationManager(scheduler: MockNotificationScheduler()))
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 4: Update RootView preview (it renders HomeView, which now needs the env)**

In `hiya/hiya/Views/RootView.swift`, update the `#Preview` so the injected `HomeView` resolves the environment object:
```swift
#Preview {
    RootView(repo: MockHiyaRepository())
        .environment(NotificationManager(scheduler: MockNotificationScheduler()))
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 5: Build, then run the full test suite**

Run (`build` first to catch view errors fast):
```
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild build -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | tee /tmp/hiya_build.log | grep -E "BUILD (SUCCEEDED|FAILED)|: error:"
```
Expected: BUILD SUCCEEDED.

Then the full suite (plain `test` — no new test files in B4):
```
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild test -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | tee /tmp/hiya_test.log | grep -E "TEST (SUCCEEDED|FAILED)|: error:"
```
Expected: TEST SUCCEEDED, 0 failures.

- [ ] **Step 6: Commit**

```bash
cd /Users/williamjin/Documents/Hiya && git add hiya/hiya/Views/AppGateView.swift hiya/hiya/Views/SettingsView.swift hiya/hiya/Views/HomeView.swift hiya/hiya/Views/RootView.swift && git commit -m "feat(notifications): Settings reminders section + Home/gate wiring

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Manual verification (after all tasks)

These can't be unit-tested; do them in the simulator:

1. **Onboarding first-run.** Delete the app from the simulator (resets `hasOnboarded` and the anonymous session), relaunch → four animated cards appear; set goals; **Get started** → lands on Home with the chosen goals reflected in the rings.
2. **No re-onboard.** Force-quit and relaunch → goes straight to Home (flag persisted).
3. **Reminder opt-in.** Settings → toggle *Daily approach reminder* on → iOS permission prompt appears → grant. Time picker shows (default 6:00 PM). Deny instead → toggle reverts, denied hint shows.
4. **Smart suppression.** With the reminder on, log approaches until the cold goal is met → returning to Home reschedules with today removed (inspect via a debug print of `pendingReminderIDs()` if desired).

---

## Self-Review

**Spec coverage:**
- Onboarding gate (`.onboarding` state, `hasOnboarded`, `completeOnboarding`, sign-in skips) → Task A1. ✓
- Four animated cards + goal-setting via `updateGoals` → Tasks A2 (VM) + A3 (View). ✓
- `ReminderPlanner` pure policy (disabled→empty, goal-met/time-passed skip today, horizon, IDs, fire time) → Task B1. ✓
- `NotificationScheduler` protocol + Live + Mock → Task B2. ✓
- `NotificationManager` default-OFF, enable/disable/setTime/refresh, persistence → Task B3. ✓
- Settings Reminders section (toggle, time picker, denied hint) → Task B4. ✓
- Home refresh hooks + AppGateView injection + scenePhase → Task B4. ✓
- No Info.plist key (local notifications) → reflected by absence of an Info.plist task. ✓
- Test isolation via injected `UserDefaults` suite → A1 + B3. ✓

**Placeholder scan:** No TBD/"handle errors"/"similar to"; every code step shows complete code. ✓

**Type consistency:** `PlannedReminder` fields (`id/fireDate/title/body`) consistent across B1/B2/B3. `NotifAuthStatus` cases consistent (B2/B3/B4). `ReminderPlanner.plan` signature (`enabled/hour/minute/now/goalMetToday/horizonDays/calendar`) identical in tests (B1), `NotificationManager.reschedule` (B3). `NotificationManager` API (`enabled/hour/minute/time/authorizationStatus/enable/disable/setTime/refresh/refreshAuthorizationStatus`) used consistently in B4. `MockNotificationScheduler` members (`status/grantOnRequest/requestCount/scheduled`) match B2 definition and B3 tests. `SessionViewModel(repo:defaults:)` + `completeOnboarding()` + `.onboarding` consistent across A1/A3. ✓
