# Edit Past Logs, Search, and Google-Maps-Style Location — Design

**Date:** 2026-05-25
**Status:** Approved (design), pending implementation plan

Four related quality-of-life features, built in four phases:

- **A. Edit past logs from a person's page** — tap an interaction in `PersonDetailSheet` to open the existing edit flow (e.g. add a location to a past interaction).
- **B. People text search** — filter the People list by name + note.
- **C. History log search** — search interactions by location, note, or person.
- **D. Google-Maps-style location field** — recents + current-location biasing for the WHERE picker.

Build order **A → B → C → D** (D is heaviest — CoreLocation). No DB schema change.

---

## A. Edit past logs from a person's page

`HistoryView` and `HomeView` already open `LogSheetView(repo:editing:)` for an existing `LoggedConversation`, and that editor already has the WHERE/location field. The only gap: `PersonDetailSheet`'s INTERACTIONS rows are display-only.

- `PersonDetailSheet`: `interactionRow(_:)` becomes tappable (wrap in a `Button` / `.onTapGesture` + `.contentShape`). Tapping sets `@State private var editingInteraction: LoggedConversation?`.
- Add `.sheet(item: $editingInteraction, onDismiss: { Task { await vm.load() } }) { entry in LogSheetView(repo: repo, editing: entry) }`.
- No view-model or repo change — `updateConversation` (with location) already exists; `vm.load()` refreshes the list after edit.

**Testing:** none new (reuses tested `updateConversation`); covered by manual smoke test.

---

## B. People text search

- `PeopleViewModel`: add `var searchText = ""`. Add a pure static filter and route `justMet`/`recurring` through it:
  ```swift
  static func matches(_ p: Person, query: String) -> Bool {
      let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if q.isEmpty { return true }
      return p.name.lowercased().contains(q) || (p.notes?.lowercased().contains(q) ?? false)
  }
  ```
  `justMet` / `recurring` filter `people` by `status` **and** `Self.matches($0, query: searchText)`.
- `PeopleView`: `.searchable(text: $vm.searchText, prompt: "Search people")` on the list. Empty query → full list (sections unchanged). When a section becomes empty under the filter, it simply doesn't render (existing `if !vm.justMet.isEmpty` guards).
- Add a "no matches" hint when both slices are empty but `searchText` is non-empty (so it doesn't look like the empty-app state).

**Testing:** `PeopleViewModel.matches` — name match, note match, case-insensitive, empty query = true; and that `justMet`/`recurring` honor the query.

---

## C. History log search

`HistoryViewModel` already loads the last 365 days into `sections`. Search filters that in-memory set — no new query.

- `HistoryViewModel`: add a pure static search and a convenience:
  ```swift
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
  Add `var allEntries: [LoggedConversation] { sections.flatMap(\.entries) }` and `func searchResults(query: String) -> [LoggedConversation] { Self.search(allEntries, query: query) }`.
- `HistoryView`: add `.searchable(text: $searchText, prompt: "Search location, note, or person")` (a `@State private var searchText = ""`). When `searchText` is non-empty, replace the calendar + day-sections content with a flat list of `vm.searchResults(query: searchText)` rendered as rows (date · person · location · note), each a button that sets `editing = entry` (reusing the existing edit sheet). When empty, render the existing calendar/day UI.
- A "no matches" row when results are empty and the query is non-empty.

**Testing:** `HistoryViewModel.search` — matches by location, note, person; case-insensitive; empty query → `[]`; results sorted newest-first.

---

## D. Google-Maps-style location field

### Recents
- Repo: `func recentLocations(limit: Int) async throws -> [String]` — distinct, non-empty conversation locations, most-recent-first.
  - Live: select `location, occurred_at` where `location` not null, order `occurred_at` desc; dedupe in Swift preserving order; take `limit`.
  - Mock: same over `conversations` (filter non-nil/non-empty `location`, sort by `occurredAt` desc, stable-dedupe, prefix `limit`).
- `LogSheetViewModel`: add `var recentLocations: [String] = []`; `load()` also assigns `recentLocations = (try? await repo.recentLocations(limit: 8)) ?? []`.

### Current-location biasing
- New `LocationProvider` (`@MainActor @Observable final class`, `NSObject`, `CLLocationManagerDelegate`):
  - `func requestWhenInUse()` → `CLLocationManager.requestWhenInUseAuthorization()`.
  - `locationManagerDidChangeAuthorization`: if authorized, `requestLocation()`.
  - `didUpdateLocations`: store `coordinate: CLLocationCoordinate2D?`.
  - `didFailWithError`: ignore (leave coordinate nil).
- `import CoreLocation`. No background use; "when in use" only.

### LocationSearchModel enhancements
- Add `var recents: [String] = []` (set by the view from `vm.recentLocations`).
- Add a `LocationProvider` (owned by the model) and set `completer.region` to an `MKCoordinateRegion` (~25 km span) around `provider.coordinate` whenever the coordinate is available, before issuing queries.
- `suggestions` logic:
  - **Empty query** → map `recents` → `[LocationSuggestion(title: $0, subtitle: "")]` (so `displayString == title`). Tag them as recents for UI (a `kind` enum or a parallel `isRecent` — simplest: expose `recents` directly to the view and only use `suggestions` for typed results).
  - **Non-empty query** → `completer.queryFragment = trimmed` (biased by region) → completer results as today.
- `func start()` → `provider.requestWhenInUse()` (called when the field appears).

### LogSheetView WHERE section
- `@FocusState private var locationFocused: Bool` on the location field.
- On appear of the section (or sheet `.task`): set `locationSearch.recents = vm.recentLocations` and call `locationSearch.start()` (requests permission).
- When `locationFocused` and `vm.location` is empty → show `locationSearch.recents` as tappable rows with a `clock` icon ("Recent"). When the user is typing → show `locationSearch.suggestions` (map results, mappin icon) as today. Tapping either sets `vm.location` and dismisses the list.
- Keep free-text entry (no requirement to pick a suggestion).

### Info.plist
- Add `NSLocationWhenInUseUsageDescription` = "Hiya uses your location to suggest nearby places when you log where you met someone."

**Testing:** `recentLocations` (Mock — distinct, recent-first, drops empty/nil, respects limit). `CLLocationManager`/`LocationProvider` and the completer are system-backed → not unit-tested; covered by manual smoke test (focus WHERE → permission prompt → nearby results; recents appear when empty).

---

## Out of scope (YAGNI)
- Storing coordinates per meeting / a map view of past meetings (location stays free text).
- Fuzzy/ranked search; substring `contains` is enough at this scale.
- Background location, "always" authorization.
- Searching People by logged-location (People search is name+note; location search lives in History).

## Files
- `Services/HiyaRepository.swift` (+ `MockHiyaRepository.swift`): `recentLocations`.
- `ViewModels/LocationProvider.swift` (create).
- `ViewModels/LocationSearchModel.swift`: recents + region.
- `ViewModels/LogSheetViewModel.swift`: load recents.
- `Views/LogSheetView.swift`: recents UI + focus + permission request.
- `Views/PersonDetailSheet.swift`: editable interaction rows.
- `ViewModels/PeopleViewModel.swift` + `Views/PeopleView.swift`: people search.
- `ViewModels/HistoryViewModel.swift` + `Views/HistoryView.swift`: log search.
- `Info.plist`: `NSLocationWhenInUseUsageDescription`.
- Tests: `MockHiyaRepositoryTests`, `PeopleViewModelTests`, `HistoryViewModelTests`.
