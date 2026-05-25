# Edit, Search, and Maps-Style Location Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make past interactions editable from a person's page, add People and History search, and upgrade the location picker with recents + current-location biasing.

**Architecture:** Reuses the existing `LogSheetView(editing:)` for editing; adds pure, testable filter functions on the People/History view models for search; adds `recentLocations` to the repo and a `LocationProvider` (CoreLocation) that biases the MapKit completer. No DB schema change.

**Tech Stack:** SwiftUI (iOS 18.6, Xcode 26.1), Swift Testing, Supabase, MapKit (`MKLocalSearchCompleter`), CoreLocation (`CLLocationManager`).

**Conventions:**
- **Test (editing existing tests):**
  ```bash
  cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild test \
    -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
    2>&1 | tee /tmp/hiya_test.log | grep -E "TEST (SUCCEEDED|FAILED)|: error:"
  ```
- **Adding new test functions/files** → use `clean test`. **Build only** → replace `test` with `build`.
- SourceKit "Cannot find type / No such module" mid-edit diagnostics are noise; `xcodebuild` is the source of truth.
- Commit to `main`; end commit messages with `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.

---

## File Structure
- `Views/PersonDetailSheet.swift` — editable interaction rows (Phase A).
- `ViewModels/PeopleViewModel.swift` + `Views/PeopleView.swift` — people search (Phase B).
- `ViewModels/HistoryViewModel.swift` + `Views/HistoryView.swift` — log search (Phase C).
- `Services/HiyaRepository.swift` + `Services/MockHiyaRepository.swift` — `recentLocations` (Phase D).
- `ViewModels/LocationProvider.swift` (create) — CoreLocation (Phase D).
- `ViewModels/LocationSearchModel.swift` + `ViewModels/LogSheetViewModel.swift` + `Views/LogSheetView.swift` — recents + biasing (Phase D).
- `Info.plist` — `NSLocationWhenInUseUsageDescription` (Phase D).
- Tests: `MockHiyaRepositoryTests`, `PeopleViewModelTests`, `HistoryViewModelTests`.

---

# PHASE A — Edit past logs from a person's page

### Task A1: Tappable interaction rows in PersonDetailSheet

**Files:** `Views/PersonDetailSheet.swift`

- [ ] **Step 1: Add edit state.** After `@State private var loggingPast = false`:
```swift
    @State private var editingInteraction: LoggedConversation?
```

- [ ] **Step 2: Present the edit sheet.** Alongside the existing `.sheet(isPresented: $loggingPast ...)`, add:
```swift
        .sheet(item: $editingInteraction, onDismiss: { Task { await vm.load() } }) { entry in
            LogSheetView(repo: repo, editing: entry)
        }
```

- [ ] **Step 3: Make the row tappable.** In `interactionRow(_:)`, add to the outer `HStack` (after `.padding(.vertical, 10)`):
```swift
        .contentShape(Rectangle())
        .onTapGesture { editingInteraction = entry }
```

- [ ] **Step 4: Build.** Expected: BUILD SUCCEEDED.
```bash
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild build \
  -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  2>&1 | tee /tmp/hiya_build.log | grep -E "BUILD (SUCCEEDED|FAILED)|: error:"
```

- [ ] **Step 5: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Views/PersonDetailSheet.swift
git commit -m "feat(people): tap a past interaction to edit it

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

# PHASE B — People text search

### Task B1: PeopleViewModel filter

**Files:** `ViewModels/PeopleViewModel.swift`, `hiyaTests/PeopleViewModelTests.swift`

- [ ] **Step 1: Write the failing test.** Append to `PeopleViewModelTests` (inside the struct):
```swift
    @Test func matches_nameAndNoteCaseInsensitive() {
        let p = Person(id: UUID(), ownerId: UUID(), name: "Angie",
                       status: .warm, statusChangedAt: .now,
                       notes: "climbing gym", createdAt: .now, lastLoggedAt: .now)
        #expect(PeopleViewModel.matches(p, query: ""))         // empty → all
        #expect(PeopleViewModel.matches(p, query: "ang"))      // name
        #expect(PeopleViewModel.matches(p, query: "GYM"))      // note, case-insensitive
        #expect(!PeopleViewModel.matches(p, query: "zzz"))
    }

    @Test func search_filtersJustMetAndRecurring() async throws {
        let repo = MockHiyaRepository()
        _ = try await repo.createPerson(name: "Angie", status: .warm)
        _ = try await repo.createPerson(name: "Bob", status: .warm)
        let vm = PeopleViewModel(repo: repo)
        await vm.load()
        vm.searchText = "ang"
        #expect(vm.recurring.map(\.name) == ["Angie"])
    }
```

- [ ] **Step 2: Run** `clean test` — Expected: FAIL (no `matches` / `searchText`).

- [ ] **Step 3: Implement.** In `PeopleViewModel`, add the property (near the top, after `errorMessage`):
```swift
    var searchText: String = ""
```
Add the static filter (e.g. above `justMet`):
```swift
    static func matches(_ p: Person, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        return p.name.lowercased().contains(q) || (p.notes?.lowercased().contains(q) ?? false)
    }
```
Route both slices through it:
```swift
    var justMet: [Person] {
        people.filter { $0.status == .cold && Self.matches($0, query: searchText) }
            .sorted { $0.lastLoggedAt > $1.lastLoggedAt }
    }

    var recurring: [Person] {
        people.filter { $0.status == .warm && Self.matches($0, query: searchText) }
            .sorted { $0.lastLoggedAt > $1.lastLoggedAt }
    }
```

- [ ] **Step 4: Run** `clean test` — Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/ViewModels/PeopleViewModel.swift hiya/hiyaTests/PeopleViewModelTests.swift
git commit -m "feat(people): searchText filter on name + note

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task B2: PeopleView search bar

**Files:** `Views/PeopleView.swift`

- [ ] **Step 1: Add `.searchable`.** On the `ZStack` in `body` (the view content), after `.navigationTitle("People")` (or after `.toolbar { ... }`), add:
```swift
        .searchable(text: $vm.searchText, prompt: "Search people")
```

- [ ] **Step 2: Handle "no matches".** In `content`, change the non-empty branch so a search with no results shows a hint instead of a bare list. Replace the `} else {` body's opening of the `List` with a guard:
```swift
        } else if vm.justMet.isEmpty && vm.recurring.isEmpty {
            VStack(spacing: Theme.Spacing.sm) {
                Spacer()
                Text("No people match \u{201C}\(vm.searchText)\u{201D}.")
                    .multilineTextAlignment(.center)
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
        } else {
            List {
                // ... existing justMet / recurring sections unchanged ...
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
```
(The first `if vm.people.isEmpty` branch — the true "no people yet" empty state — stays as-is and takes priority.)

- [ ] **Step 2b: Verify** the existing `content` structure is `if vm.people.isEmpty { emptyState } else { List {...} }`; insert the new `else if` between them so order is: people-empty → no-matches → list.

- [ ] **Step 3: Build.** Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Views/PeopleView.swift
git commit -m "feat(people): search bar over the People list

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

# PHASE C — History log search

### Task C1: HistoryViewModel search

**Files:** `ViewModels/HistoryViewModel.swift`, `hiyaTests/HistoryViewModelTests.swift`

- [ ] **Step 1: Write the failing test.** Append to `HistoryViewModelTests` (inside the struct). It builds `LoggedConversation`s inline:
```swift
    @Test func search_matchesLocationNoteOrPerson_caseInsensitive_newestFirst() {
        func log(_ person: String, _ note: String?, _ location: String?, daysAgo: Int) -> LoggedConversation {
            LoggedConversation(
                id: UUID(), personId: UUID(), personName: person,
                occurredAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
                valence: nil, note: note, improvementNote: nil, location: location
            )
        }
        let logs = [
            log("Angie", "great chat", "Blue Bottle", daysAgo: 2),
            log("Bob", "at E7", nil, daysAgo: 1),
            log("Cara", nil, "e7 climbing", daysAgo: 0),
        ]

        let byLocation = HistoryViewModel.search(logs, query: "e7")
        #expect(byLocation.map(\.personName) == ["Cara", "Bob"], "newest first; matches location and note")

        let byPerson = HistoryViewModel.search(logs, query: "ANGIE")
        #expect(byPerson.map(\.personName) == ["Angie"])

        #expect(HistoryViewModel.search(logs, query: "  ").isEmpty, "blank query → no results")
    }
```

- [ ] **Step 2: Run** `clean test` — Expected: FAIL (no `search`).

- [ ] **Step 3: Implement.** In `HistoryViewModel`, add:
```swift
    var allEntries: [LoggedConversation] { sections.flatMap(\.entries) }

    func searchResults(query: String) -> [LoggedConversation] {
        Self.search(allEntries, query: query)
    }

    static func search(_ logs: [LoggedConversation], query: String) -> [LoggedConversation] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return logs
            .filter {
                ($0.location?.lowercased().contains(q) ?? false) ||
                ($0.note?.lowercased().contains(q) ?? false) ||
                $0.personName.lowercased().contains(q)
            }
            .sorted { $0.occurredAt > $1.occurredAt }
    }
```

- [ ] **Step 4: Run** `clean test` — Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/ViewModels/HistoryViewModel.swift hiya/hiyaTests/HistoryViewModelTests.swift
git commit -m "feat(history): log search filter (location/note/person)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task C2: HistoryView search UI

**Files:** `Views/HistoryView.swift`

- [ ] **Step 1: Add search state.** After `@State private var editing: LoggedConversation?`:
```swift
    @State private var searchText = ""
```

- [ ] **Step 2: Swap content when searching + add `.searchable`.** In `body`, change the inner `VStack`:
```swift
            VStack(spacing: Theme.Spacing.md) {
                if searchText.isEmpty {
                    viewModePicker
                    if viewMode == .list {
                        listContent
                    } else {
                        calendarContent
                    }
                } else {
                    searchResultsContent
                }
            }
```
Add `.searchable` to the `ZStack` (place after `.toolbarBackground(.hidden, for: .navigationBar)`):
```swift
        .searchable(text: $searchText, prompt: "Search location, note, or person")
```

- [ ] **Step 3: Add the results view.** Add to `HistoryView` (e.g. after `listContent`):
```swift
    @ViewBuilder
    private var searchResultsContent: some View {
        let results = vm.searchResults(query: searchText)
        if results.isEmpty {
            emptyState(message: "No interactions match \u{201C}\(searchText)\u{201D}.")
        } else {
            List {
                ForEach(results) { entry in
                    Button {
                        editing = entry
                    } label: {
                        SearchResultRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Theme.divider)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
```

- [ ] **Step 4: Add `SearchResultRow`.** Add a private view at file scope (next to `EntryRow`), showing date + person + location + note:
```swift
private struct SearchResultRow: View {
    let entry: LoggedConversation

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Circle().fill(valenceColor).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.personName)
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textPrimary)
                if let location = entry.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle").font(.system(size: 11))
                        Text(location).lineLimit(1)
                    }
                    .font(Theme.FontScale.micro())
                    .foregroundColor(Theme.textSecondary)
                }
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(Theme.FontScale.secondary())
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(entry.occurredAt.formatted(date: .abbreviated, time: .omitted))
                .font(Theme.FontScale.micro())
                .tracking(0.5)
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var valenceColor: Color {
        switch entry.valence {
        case .positive: Theme.valencePositive
        case .neutral:  Theme.valenceNeutral
        case .negative: Theme.valenceNegative
        case .none:     Theme.valenceNone
        }
    }
}
```

- [ ] **Step 5: Build.** Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Views/HistoryView.swift
git commit -m "feat(history): search bar with tappable results

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

# PHASE D — Google-Maps-style location field

### Task D1: `recentLocations` on the repository

**Files:** `Services/HiyaRepository.swift`, `Services/MockHiyaRepository.swift`, `hiyaTests/MockHiyaRepositoryTests.swift`

- [ ] **Step 1: Protocol requirement.** Add to `protocol HiyaRepository` (after `personConversations`):
```swift
    func recentLocations(limit: Int) async throws -> [String]
```

- [ ] **Step 2: Live implementation.** Add to `LiveHiyaRepository` (after `personConversations`):
```swift
    func recentLocations(limit: Int = 8) async throws -> [String] {
        struct Row: Decodable { let location: String? }
        // Pull the most recent logs and dedupe locations in Swift (nils/blanks
        // skipped below) — avoids depending on a server-side null filter.
        let rows: [Row] = try await client
            .from("conversations")
            .select("location, occurred_at")
            .order("occurred_at", ascending: false)
            .limit(200)
            .execute()
            .value
        var seen = Set<String>()
        var out: [String] = []
        for r in rows {
            guard let loc = r.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty else { continue }
            if seen.insert(loc.lowercased()).inserted { out.append(loc) }
            if out.count >= limit { break }
        }
        return out
    }
```

- [ ] **Step 3: Mock implementation.** Add to `MockHiyaRepository` (after `personConversations`):
```swift
    func recentLocations(limit: Int = 8) async throws -> [String] {
        if let err = errorToThrow { errorToThrow = nil; throw err }
        var seen = Set<String>()
        var out: [String] = []
        for c in conversations.sorted(by: { $0.occurredAt > $1.occurredAt }) {
            guard let loc = c.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty else { continue }
            if seen.insert(loc.lowercased()).inserted { out.append(loc) }
            if out.count >= limit { break }
        }
        return out
    }
```

- [ ] **Step 4: Test.** Append to `MockHiyaRepositoryTests`:
```swift
    @Test func recentLocations_distinctRecentFirst_dropsBlanks() async throws {
        let repo = MockHiyaRepository()
        let p = try await repo.createPerson(name: "A", status: .warm, notes: nil, metCold: false)
        let cal = Calendar.current
        func at(_ ago: Int) -> Date { cal.date(byAdding: .day, value: -ago, to: .now)! }
        try await repo.logConversation(personId: p.id, occurredAt: at(5), valence: nil, note: nil, improvementNote: nil, location: "Gym")
        try await repo.logConversation(personId: p.id, occurredAt: at(3), valence: nil, note: nil, improvementNote: nil, location: "Cafe")
        try await repo.logConversation(personId: p.id, occurredAt: at(1), valence: nil, note: nil, improvementNote: nil, location: "Gym")   // dup, newer
        try await repo.logConversation(personId: p.id, occurredAt: at(0), valence: nil, note: nil, improvementNote: nil, location: "  ")    // blank

        let recents = try await repo.recentLocations(limit: 8)
        #expect(recents == ["Gym", "Cafe"], "distinct, most-recent occurrence first, blanks dropped")
    }
```

- [ ] **Step 5: Run** `clean test` — Expected: TEST SUCCEEDED.

- [ ] **Step 6: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Services/HiyaRepository.swift hiya/hiya/Services/MockHiyaRepository.swift hiya/hiyaTests/MockHiyaRepositoryTests.swift
git commit -m "feat(location): recentLocations repo method

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task D2: `LocationProvider` (CoreLocation)

**Files:** `ViewModels/LocationProvider.swift` (create)

- [ ] **Step 1: Implement.**
```swift
import Foundation
import CoreLocation
import Observation

/// Thin CoreLocation wrapper: requests "when in use" authorization and exposes
/// the latest coordinate (nil until granted + a fix arrives). Used only to bias
/// place-search results toward where the user is.
@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: CLLocationCoordinate2D?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.coordinate = loc.coordinate }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Leave coordinate nil — search just won't be biased.
    }
}
```

- [ ] **Step 2: Build.** Expected: BUILD SUCCEEDED. (No unit test — system dependency.)

- [ ] **Step 3: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/ViewModels/LocationProvider.swift
git commit -m "feat(location): CoreLocation provider for current-location biasing

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task D3: Recents + biasing in `LocationSearchModel`

**Files:** `ViewModels/LocationSearchModel.swift`

- [ ] **Step 1: Add recents, provider, and region biasing.** Replace the `LocationSearchModel` class body so it owns a `LocationProvider`, accepts `recents`, and biases the completer:
```swift
@MainActor
@Observable
final class LocationSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    /// Recently-used places (set by the view from the view model).
    var recents: [String] = []
    private(set) var suggestions: [LocationSuggestion] = []

    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                suggestions = []
                completer.queryFragment = ""
            } else {
                applyRegionIfAvailable()
                completer.queryFragment = trimmed
            }
        }
    }

    let provider = LocationProvider()
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// Called when the location field appears: ask for permission so results can
    /// be biased toward the user (no-op if already decided).
    func start() {
        provider.requestWhenInUse()
    }

    private func applyRegionIfAvailable() {
        if let c = provider.coordinate {
            completer.region = MKCoordinateRegion(
                center: c,
                latitudinalMeters: 25_000,
                longitudinalMeters: 25_000
            )
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results.prefix(4).map {
            LocationSuggestion(title: $0.title, subtitle: $0.subtitle)
        }
        Task { @MainActor in self.suggestions = Array(results) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.suggestions = [] }
    }

    func clear() {
        query = ""
        suggestions = []
    }
}
```
(`LocationSuggestion` is unchanged.)

- [ ] **Step 2: Build.** Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/ViewModels/LocationSearchModel.swift
git commit -m "feat(location): recents + current-location region biasing

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task D4: Load recents in LogSheetViewModel

**Files:** `ViewModels/LogSheetViewModel.swift`

- [ ] **Step 1: Add property.** Near `var location`:
```swift
    private(set) var recentLocations: [String] = []
```

- [ ] **Step 2: Load in `load()`.** Add at the end of `load()`'s `do` block (after `allPeople = ...`):
```swift
            recentLocations = (try? await repo.recentLocations(limit: 8)) ?? []
```

- [ ] **Step 3: Build.** Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/ViewModels/LogSheetViewModel.swift
git commit -m "feat(location): load recent locations for the log sheet

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task D5: WHERE section UI — recents + focus + permission

**Files:** `Views/LogSheetView.swift`

- [ ] **Step 1: Add focus state.** After `@State private var locationSearch = LocationSearchModel()`:
```swift
    @FocusState private var locationFocused: Bool
```

- [ ] **Step 2: Seed recents + request permission.** Change the view's `.task` (currently `.task { if vm.editing == nil { await vm.load() } }`) so it also wires the location model. Replace it with:
```swift
            .task {
                if vm.editing == nil { await vm.load() }
                locationSearch.recents = vm.recentLocations
                locationSearch.start()
            }
```
> Note: for the edit path `vm.load()` isn't called, so `vm.recentLocations` is empty — that's fine (recents simply won't show when editing; map search still works).

- [ ] **Step 3: Rewrite `whereSection`** to add focus + a recents list when empty:
```swift
    private var whereSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("WHERE (OPTIONAL)")
            TextField("Place or address", text: $vm.location)
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textPrimary)
                .autocorrectionDisabled()
                .focused($locationFocused)
                .padding(12)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .onChange(of: vm.location) { _, newValue in
                    locationSearch.query = newValue
                }

            if locationFocused
                && vm.location.trimmingCharacters(in: .whitespaces).isEmpty
                && !locationSearch.recents.isEmpty {
                // Recents (Google-Maps style) when the field is focused but empty.
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(locationSearch.recents, id: \.self) { place in
                        locationRow(icon: "clock", text: place) {
                            vm.location = place
                            locationFocused = false
                        }
                    }
                }
            } else if !locationSearch.suggestions.isEmpty {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(locationSearch.suggestions) { s in
                        locationRow(icon: "mappin.circle", text: s.displayString) {
                            vm.location = s.displayString
                            locationSearch.clear()
                            locationFocused = false
                        }
                    }
                }
            }
        }
    }

    private func locationRow(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(Theme.textSecondary)
                Text(text)
                    .font(Theme.FontScale.secondary())
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .buttonStyle(.plain)
    }
```
(Delete the old `whereSection`'s suggestion-only block — it's fully replaced above.)

- [ ] **Step 4: Build.** Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Add the Info.plist key.** In `hiya/hiya/Info.plist`, add inside the top-level `<dict>`:
```xml
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Hiya uses your location to suggest nearby places when you log where you met someone.</string>
```

- [ ] **Step 6: Build again** to confirm the plist is valid. Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**
```bash
cd /Users/williamjin/Documents/Hiya
git add hiya/hiya/Views/LogSheetView.swift hiya/hiya/Info.plist
git commit -m "feat(location): recents + nearby suggestions in the WHERE picker

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task D6: Full verification + manual smoke test

- [ ] **Step 1: Full test run** (`clean test`). Expected: TEST SUCCEEDED.
```bash
cd /Users/williamjin/Documents/Hiya/hiya && xcodebuild clean test \
  -scheme hiya -destination 'platform=iOS Simulator,id=59837F17-D420-4D67-A5D6-771BF46F433A' \
  2>&1 | tee /tmp/hiya_test.log | grep -E "TEST (SUCCEEDED|FAILED)|: error:"
```

- [ ] **Step 2: Manual smoke test** (simulator; set a simulated location via Features → Location):
  1. Person detail → tap a past interaction → editor opens → add a location → save → row shows the location.
  2. People tab → search a name/note → list filters; clear → full list.
  3. History → search "e7" (or a known place/person) → flat results; tap one → edit.
  4. Log sheet → focus WHERE (empty) → recents appear (after you've logged a few places); permission prompt appears the first time; type → nearby suggestions.

- [ ] **Step 3:** No commit (verification only).

---

## Self-review notes
- **No DB migration** — `conversations.location` already exists (Phase B of the prior plan).
- **Edit already exists in History/Home** — Phase A only fills the person-page gap; the editor (incl. WHERE) is unchanged.
- **Search is in-memory** — People filters `people`; History filters the already-loaded 365-day `sections`. No new queries except `recentLocations`.
- **Graceful location** — denied/undecided permission leaves `provider.coordinate == nil`, so the completer just isn't region-biased; recents and plain search still work.
- **Post-implementation:** update the [[hiya_accounts]]-adjacent notes only if needed; consider a brief memory that location uses CoreLocation "when in use" + recents.
