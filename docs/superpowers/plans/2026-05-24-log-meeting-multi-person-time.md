# Log a Meeting: Multiple People + Chosen Time — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user log a single meeting involving one or more people at a time they choose (default now, past/future allowed), and edit the time of an existing log.

**Architecture:** Thread an `occurredAt: Date` through the repository and `LogSheetViewModel` (Task 1), expose it as a `DatePicker` (Task 2), then replace the single-person selection with a list of "targets" (existing people or new names) rendered as chips, writing one log per person sharing the same fields (Task 3). Edit mode stays single-person but gains time editing.

**Tech Stack:** SwiftUI, Swift 6, Swift Testing, `@Observable` view models, protocol-backed `HiyaRepository` (Live = Supabase, Mock = in-memory).

**Conventions:**
- All `xcodebuild` runs from `/Users/williamjin/Documents/Hiya/hiya`.
- Test command: `xcodebuild test -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A'`
- SourceKit may report spurious "Cannot find type X in scope" / "No such module" diagnostics in-editor; ignore them — `xcodebuild` is the source of truth.
- The Xcode project uses filesystem-synchronized groups (objectVersion 77), so new files in existing folders are picked up automatically — no `.pbxproj` edits.

**Spec:** `docs/superpowers/specs/2026-05-24-log-meeting-multi-person-time-design.md`

---

## File Structure

- **Modify** `hiya/Services/HiyaRepository.swift` — add `occurredAt` to `logConversation`/`updateConversation` protocol requirements; Live impls send `occurred_at`.
- **Modify** `hiya/Services/MockHiyaRepository.swift` — honor `occurredAt`; advance `lastLoggedAt` forward-only.
- **Modify** `hiya/ViewModels/LogSheetViewModel.swift` — add `occurredAt`; replace `selectedPerson` with `targets: [LogTarget]`; multi-resolve save with duplicate guard.
- **Modify** `hiya/Views/LogSheetView.swift` — WHEN `DatePicker`; person chips + type-to-add.
- **Modify** `hiya/hiyaTests/...` → actual path `hiyaTests/MockHiyaRepositoryTests.swift`, `hiyaTests/LogSheetViewModelTests.swift`, `hiyaTests/HomeViewModelTests.swift` — new tests.

---

## Task 1: Thread `occurredAt` through the data layer and view model

**Files:**
- Modify: `hiya/Services/HiyaRepository.swift`
- Modify: `hiya/Services/MockHiyaRepository.swift`
- Modify: `hiya/ViewModels/LogSheetViewModel.swift`
- Test: `hiyaTests/MockHiyaRepositoryTests.swift`, `hiyaTests/LogSheetViewModelTests.swift`, `hiyaTests/HomeViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `hiyaTests/MockHiyaRepositoryTests.swift` (inside the test struct):

```swift
@Test func logConversation_honorsOccurredAt_andAdvancesLastLoggedForwardOnly() async throws {
    let repo = MockHiyaRepository()
    let p = try await repo.createPerson(name: "Alex")
    let created = repo.people.first { $0.id == p.id }!.lastLoggedAt
    let earlier = Calendar.current.date(byAdding: .day, value: -3, to: created)!

    // Back-dated log: stored occurredAt is `earlier`, but last seen must NOT regress.
    try await repo.logConversation(personId: p.id, occurredAt: earlier, valence: nil, note: nil, improvementNote: nil)
    let conv = repo.conversations.first { $0.personId == p.id }!
    #expect(abs(conv.occurredAt.timeIntervalSince(earlier)) < 0.001)
    #expect(repo.people.first { $0.id == p.id }!.lastLoggedAt == created, "back-dating must not regress last seen")

    // Forward-dated log advances last seen.
    let later = Calendar.current.date(byAdding: .day, value: 2, to: created)!
    try await repo.logConversation(personId: p.id, occurredAt: later, valence: nil, note: nil, improvementNote: nil)
    #expect(repo.people.first { $0.id == p.id }!.lastLoggedAt == later)
}
```

Add to `hiyaTests/LogSheetViewModelTests.swift` (inside the test struct):

```swift
@Test func editing_initializesOccurredAtFromEntry() async {
    let when = Date(timeIntervalSince1970: 1_700_000_000)
    let entry = LoggedConversation(
        id: UUID(), personId: UUID(), personName: "Alex",
        occurredAt: when, valence: nil, note: nil, improvementNote: nil
    )
    let vm = LogSheetViewModel(repo: MockHiyaRepository(), editing: entry)
    #expect(abs(vm.occurredAt.timeIntervalSince(when)) < 0.001)
}
```

Add to `hiyaTests/HomeViewModelTests.swift` (inside the test struct):

```swift
@Test func backDatedLog_doesNotCountToday() async throws {
    let repo = MockHiyaRepository()
    let p = try await repo.createPerson(name: "Alex")
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
    try await repo.logConversation(personId: p.id, occurredAt: yesterday, valence: nil, note: nil, improvementNote: nil)

    let vm = HomeViewModel(repo: repo)
    await vm.refresh()

    #expect(vm.count(for: .cold) == 0, "a back-dated log should not count toward today")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | grep -E "error:|Compiling|FAILED" | head`
Expected: BUILD FAILS — `logConversation` has no `occurredAt:` parameter, and `LogSheetViewModel` has no `occurredAt` property.

- [ ] **Step 3: Add `occurredAt` to the protocol requirements**

In `hiya/Services/HiyaRepository.swift`, change the two protocol requirements:

```swift
    func logConversation(
        personId: UUID,
        occurredAt: Date,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws
    func updateConversation(
        id: UUID,
        occurredAt: Date,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws
```

- [ ] **Step 4: Update the Live implementation**

In `hiya/Services/HiyaRepository.swift`, replace `LiveHiyaRepository.logConversation` with:

```swift
    func logConversation(
        personId: UUID,
        occurredAt: Date = .now,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws {
        let userId = try await client.auth.user().id
        struct Insert: Encodable {
            let owner_id: UUID
            let person_id: UUID
            let occurred_at: String
            let valence: Conversation.Valence?
            let note: String?
            let improvement_note: String?
        }
        try await client
            .from("conversations")
            .insert(Insert(
                owner_id: userId,
                person_id: personId,
                occurred_at: occurredAt.iso8601String,
                valence: valence,
                note: note,
                improvement_note: improvementNote
            ))
            .execute()
    }
```

And replace `LiveHiyaRepository.updateConversation` with:

```swift
    func updateConversation(
        id: UUID,
        occurredAt: Date = .now,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws {
        struct Update: Encodable {
            let occurred_at: String
            let valence: Conversation.Valence?
            let note: String?
            let improvement_note: String?
        }
        try await client
            .from("conversations")
            .update(Update(
                occurred_at: occurredAt.iso8601String,
                valence: valence,
                note: note,
                improvement_note: improvementNote
            ))
            .eq("id", value: id)
            .execute()
    }
```

- [ ] **Step 5: Update the Mock implementation**

In `hiya/Services/MockHiyaRepository.swift`, replace `logConversation` with:

```swift
    func logConversation(
        personId: UUID,
        occurredAt: Date = .now,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        let currentStatus = people.first(where: { $0.id == personId })?.status ?? .warm
        let wasCold = (currentStatus == .cold)
        let conv = Conversation(
            id: UUID(),
            ownerId: profile.id,
            personId: personId,
            occurredAt: occurredAt,
            valence: valence,
            note: note,
            improvementNote: improvementNote,
            wasColdAtTime: wasCold,
            createdAt: .now
        )
        conversations.append(conv)
        // Mirror the DB trigger: last_logged_at only ever moves forward.
        if let idx = people.firstIndex(where: { $0.id == personId }), people[idx].lastLoggedAt < occurredAt {
            people[idx].lastLoggedAt = occurredAt
        }
    }
```

And replace `updateConversation` with:

```swift
    func updateConversation(
        id: UUID,
        occurredAt: Date = .now,
        valence: Conversation.Valence?,
        note: String?,
        improvementNote: String?
    ) async throws {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].occurredAt = occurredAt
        conversations[idx].valence = valence
        conversations[idx].note = note
        conversations[idx].improvementNote = improvementNote
    }
```

- [ ] **Step 6: Add `occurredAt` to the view model and pass it through**

In `hiya/ViewModels/LogSheetViewModel.swift`, add the stored property after `var improvementNote: String = ""`:

```swift
    var occurredAt: Date = .now
```

In `init`, inside the `if let editing {` branch, add (after the `improvementNote = ...` line):

```swift
            occurredAt = editing.occurredAt
```

In `save()`, update the edit branch call to pass the time:

```swift
            if let editing {
                try await repo.updateConversation(
                    id: editing.id,
                    occurredAt: occurredAt,
                    valence: valence,
                    note: noteToSend,
                    improvementNote: improvementToSend
                )
            } else {
```

And update the create branch's `logConversation` call:

```swift
                try await repo.logConversation(
                    personId: personId,
                    occurredAt: occurredAt,
                    valence: valence,
                    note: noteToSend,
                    improvementNote: improvementToSend
                )
```

- [ ] **Step 7: Run the full suite to verify it passes**

Run: `xcodebuild test -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | grep -E "error:|with [0-9]+ failure|honorsOccurredAt|initializesOccurredAtFromEntry|backDatedLog" | head`
Expected: the three new tests pass; no `error:` lines; no failures.

- [ ] **Step 8: Commit**

```bash
cd /Users/williamjin/Documents/Hiya
git add -A
git commit -m "feat(log): thread occurredAt through repo + log sheet view model

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Add the WHEN date/time picker to the log sheet

**Files:**
- Modify: `hiya/Views/LogSheetView.swift`

There is no clean unit test for SwiftUI layout; the VM-level behavior (default now, edit initializes from entry) is already covered by Task 1. Verify this task by building.

- [ ] **Step 1: Add a `whenSection` and place it in the form**

In `hiya/Views/LogSheetView.swift`, in `body`, add `whenSection` to the `VStack` right after `personSection`:

```swift
                        personSection
                        whenSection
                        valenceSection
```

- [ ] **Step 2: Implement `whenSection`**

Add this computed property to `LogSheetView` (next to the other section properties, e.g. after `personSection`):

```swift
    private var whenSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("WHEN")
            DatePicker(
                "",
                selection: $vm.occurredAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(Theme.accentLavender)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
cd /Users/williamjin/Documents/Hiya
git add -A
git commit -m "feat(log): WHEN date/time picker on the log sheet

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Multi-person logging — targets in the view model + chips in the view

**Files:**
- Modify: `hiya/ViewModels/LogSheetViewModel.swift`
- Modify: `hiya/Views/LogSheetView.swift`
- Test: `hiyaTests/LogSheetViewModelTests.swift`

The VM and view are tightly coupled (the view reads `selectedPerson`/`select`/`clearSelection`, which this task replaces), so they change together to keep the module building.

- [ ] **Step 1: Write the failing VM tests**

Add to `hiyaTests/LogSheetViewModelTests.swift` (inside the test struct):

```swift
@Test func save_createsOneLogPerTarget_sharingOccurredAt() async throws {
    let repo = MockHiyaRepository()
    let alex = try await repo.createPerson(name: "Alex")
    let vm = LogSheetViewModel(repo: repo)
    await vm.load()
    let when = Date(timeIntervalSince1970: 1_700_000_000)
    vm.occurredAt = when
    vm.addExisting(alex)
    vm.addNew("Bea")

    let ok = await vm.save()

    #expect(ok)
    #expect(repo.conversations.count == 2, "one log per target")
    #expect(repo.conversations.allSatisfy { abs($0.occurredAt.timeIntervalSince(when)) < 0.001 })
    #expect(repo.people.contains { $0.name == "Bea" }, "a new target is created as a person")
}

@Test func addExisting_ignoresDuplicates() async throws {
    let repo = MockHiyaRepository()
    let alex = try await repo.createPerson(name: "Alex")
    let vm = LogSheetViewModel(repo: repo)
    await vm.load()
    vm.addExisting(alex)
    vm.addExisting(alex)
    #expect(vm.targets.count == 1)
}

@Test func save_foldsTypedNameIntoTarget() async throws {
    let repo = MockHiyaRepository()
    let vm = LogSheetViewModel(repo: repo)
    await vm.load()
    vm.searchText = "Cara"   // typed but not explicitly added
    let ok = await vm.save()
    #expect(ok)
    #expect(repo.conversations.count == 1)
    #expect(repo.people.contains { $0.name == "Cara" })
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | grep -E "error:" | head`
Expected: BUILD FAILS — `addExisting`, `addNew`, and `targets` do not exist.

- [ ] **Step 3: Add the `LogTarget` type**

In `hiya/ViewModels/LogSheetViewModel.swift`, add at the bottom of the file (after the class closing brace):

```swift
enum LogTarget: Identifiable, Equatable {
    case existing(Person)
    case new(String)

    var id: String {
        switch self {
        case .existing(let p): "existing-\(p.id.uuidString)"
        case .new(let name):   "new-\(name.lowercased())"
        }
    }

    var displayName: String {
        switch self {
        case .existing(let p): p.name
        case .new(let name):   name
        }
    }
}
```

- [ ] **Step 4: Replace single-person state with targets**

In `LogSheetViewModel`, replace this line:

```swift
    private(set) var selectedPerson: Person?
```

with:

```swift
    private(set) var targets: [LogTarget] = []
```

Replace `filteredPeople` with a version that hides already-chosen people:

```swift
    var filteredPeople: [Person] {
        let chosen = Set(targets.compactMap { target -> UUID? in
            if case .existing(let p) = target { return p.id }
            return nil
        })
        let available = allPeople.filter { !chosen.contains($0.id) }
        let q = trimmedSearch.lowercased()
        guard !q.isEmpty else { return available }
        return available.filter { $0.name.lowercased().contains(q) }
    }

    /// Whether the typed text should offer a "create new person" row — only
    /// when it's non-empty and doesn't exactly match an existing person.
    var canAddTypedName: Bool {
        let q = trimmedSearch
        guard !q.isEmpty else { return false }
        return !allPeople.contains { $0.name.lowercased() == q.lowercased() }
    }
```

Replace `canSave` with:

```swift
    var canSave: Bool {
        if editing != nil { return true }
        return !targets.isEmpty || !trimmedSearch.isEmpty
    }
```

Replace the `select(_:)` and `clearSelection()` methods with:

```swift
    func addExisting(_ person: Person) {
        let target = LogTarget.existing(person)
        guard !targets.contains(where: { $0.id == target.id }) else { return }
        targets.append(target)
        searchText = ""
    }

    func addNew(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let target = LogTarget.new(name)
        guard !targets.contains(where: { $0.id == target.id }) else { return }
        targets.append(target)
        searchText = ""
    }

    func removeTarget(_ target: LogTarget) {
        targets.removeAll { $0.id == target.id }
    }
```

In `init`, replace the `preselectedPerson` branch:

```swift
        } else if let preselected = preselectedPerson {
            selectedPerson = preselected
            searchText = preselected.name
        }
```

with:

```swift
        } else if let preselected = preselectedPerson {
            targets = [.existing(preselected)]
        }
```

- [ ] **Step 5: Rewrite the create branch of `save()` to log every target**

In `LogSheetViewModel.save()`, replace the entire `else` branch (the create path, currently resolving `selectedPerson`/`trimmedSearch` to a single `personId` and calling `logConversation` once) with:

```swift
            } else {
                // Fold any leftover typed text into a target so the fast
                // "type one name and save" path still works.
                var finalTargets = targets
                let pending = trimmedSearch
                if !pending.isEmpty {
                    if let match = allPeople.first(where: { $0.name.lowercased() == pending.lowercased() }) {
                        let t = LogTarget.existing(match)
                        if !finalTargets.contains(where: { $0.id == t.id }) { finalTargets.append(t) }
                    } else {
                        let t = LogTarget.new(pending)
                        if !finalTargets.contains(where: { $0.id == t.id }) { finalTargets.append(t) }
                    }
                }
                guard !finalTargets.isEmpty else { return false }

                // Resolve each target to a person id (creating new people).
                var personIds: [UUID] = []
                for target in finalTargets {
                    switch target {
                    case .existing(let person):
                        personIds.append(person.id)
                    case .new(let name):
                        let created = try await repo.createPerson(name: name)
                        personIds.append(created.id)
                    }
                }

                // One log per person, all sharing the same time/valence/notes.
                for personId in personIds {
                    try await repo.logConversation(
                        personId: personId,
                        occurredAt: occurredAt,
                        valence: valence,
                        note: noteToSend,
                        improvementNote: improvementToSend
                    )
                }
            }
```

- [ ] **Step 6: Run the VM tests to verify they pass (view still references old API — build will fail; that's expected, fix in Step 7)**

Skip running here — the view still uses `vm.selectedPerson`. Proceed to Step 7, then build/test once.

- [ ] **Step 7: Rewrite the person section of the view for chips + type-to-add**

In `hiya/Views/LogSheetView.swift`, replace the entire `personSection` computed property with the following. The edit branch is unchanged (read-only name); the create branch now shows chips, a text field, and suggestion/create rows.

```swift
    @ViewBuilder
    private var personSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("PEOPLE")
            if vm.editing != nil {
                Text(vm.searchText)
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            } else {
                if !vm.targets.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(vm.targets) { target in
                                personChip(target)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                TextField("Add a person", text: $vm.searchText)
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textPrimary)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { if vm.canAddTypedName { vm.addNew(vm.searchText) } }
                    .padding(12)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                if !vm.filteredPeople.isEmpty || vm.canAddTypedName {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(vm.filteredPeople) { person in
                            Button {
                                vm.addExisting(person)
                            } label: {
                                HStack {
                                    Text(person.name)
                                        .font(Theme.FontScale.body())
                                        .foregroundColor(Theme.textPrimary)
                                    Spacer()
                                    Text(relativeLastLogged(person.lastLoggedAt))
                                        .font(Theme.FontScale.micro())
                                        .tracking(0.8)
                                        .foregroundColor(Theme.textSecondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                            }
                            .buttonStyle(.plain)
                        }
                        if vm.canAddTypedName {
                            Button {
                                vm.addNew(vm.searchText)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(Theme.accentAmber)
                                    Text("Add \u{201C}\(vm.trimmedSearch)\u{201D}")
                                        .font(Theme.FontScale.body())
                                        .foregroundColor(Theme.textPrimary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func personChip(_ target: LogTarget) -> some View {
        HStack(spacing: 6) {
            Text(target.displayName)
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textPrimary)
            Button {
                vm.removeTarget(target)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Theme.accentLavender.opacity(0.18)))
    }
```

Note: this removes the old `.onChange(of: vm.searchText)` selection-clearing logic (it referenced `vm.selectedPerson`, which no longer exists). The chip model makes it unnecessary.

- [ ] **Step 8: Run the full suite to verify everything passes**

Run: `xcodebuild test -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | grep -E "error:|with [0-9]+ failure|save_createsOneLogPerTarget|addExisting_ignoresDuplicates|save_foldsTypedNameIntoTarget" | head`
Expected: the three new tests pass; no `error:` lines; no failures.

- [ ] **Step 9: Commit**

```bash
cd /Users/williamjin/Documents/Hiya
git add -A
git commit -m "feat(log): multi-person logging via chips + type-to-add

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Final verification

- [ ] **Run the entire test suite once more and confirm zero failures.**

Run: `xcodebuild test -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' 2>&1 | grep -E "Test case '.*' (passed|failed)" | grep -c passed`
Then: `... | grep -c failed` (expect 0).

- [ ] **Push:** `cd /Users/williamjin/Documents/Hiya && git push`
