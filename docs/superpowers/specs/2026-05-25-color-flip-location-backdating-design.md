# Color Flip, Per-Meeting Location, and Backdating — Design

**Date:** 2026-05-25
**Status:** Approved (design), pending implementation plan

Three related Hiya features, built in three sequenced phases under one spec:

- **A. Color flip** — make cold/Approaches feel cool and warm/Catch-ups feel warm (reverses today's amber=cold / lavender=warm scheme).
- **B. Per-meeting location** — optional place/address per logged meeting, with map autocomplete.
- **C. Backdating + durable cold origin** — record past meetings at chosen dates, with a per-person "this began as a cold approach" flag that classifies meetings chronologically.

Build order: **A → C → B**. A is isolated (quick win). C changes the conversation-classification data model (foundational). B rides on the log sheet and the same migration cadence.

---

## A. Cold/Warm color flip

### Current state
- `Theme.accentAmber` is the **cold/Approaches** semantic color.
- `Theme.accentLavender` is the **warm/Catch-ups** semantic color **and** the app's neutral chrome accent (tab-bar tint, gear icon, Save buttons, "+" buttons, nav links, date-picker tint, selected-person chips).

### Target
- Cold/Approaches → **lavender** (the cooler hue).
- Warm/Catch-ups → **amber** (the warmer hue).
- **Neutral chrome stays lavender** — it is not a cold/warm signal and must not flip. This is the central risk ("be very careful"): a blind token swap would recolor every button. We flip only the *semantic* sites.

### Mechanism — centralize the semantic mapping
Add to `Theme`:

```swift
// Semantic mode accents. Approaches read cool, Catch-ups read warm.
static let coldAccent = accentLavender
static let warmAccent = accentAmber

static func accent(for status: PersonStatus) -> Color {
    status == .cold ? coldAccent : warmAccent
}
```

Every place that currently encodes the cold/warm meaning as a flat color routes through `Theme.coldAccent` / `Theme.warmAccent` / `Theme.accent(for:)`. Neutral lavender usages keep referring to `Theme.accentLavender` directly. This makes semantic vs. neutral usage greppable and reduces a future flip to two lines.

### Ring gradients — no change required
`ProgressRingView` uses `Theme.accentGradient` ([lavender→amber], lavender-leading) for the cold ring and `Theme.accentGradientReversed` ([amber→lavender], amber-leading) for the warm ring. Under the *old* semantics (cold=amber) these led with the opposite hue — the intentional "oxymoron." Flipping the flat semantic colors to cold=lavender / warm=amber makes these same gradients **lead with their own mode's color**, so the rings now align naturally. The gradient assignments are left untouched; only the code comments lose the "oxymoron" framing. Ring gradient assignment is routed through a `Theme.gradient(for:)` helper for clarity.

### Sites to flip (semantic only)
Flip cold→lavender / warm→amber at these locations; verify each is semantic before touching:
- `HomeView`: mode toggle buttons (`modeButton(.cold/.warm, color:)`), the `pageMode == .cold ? amber : lavender` color vars, challenge-track accent.
- `PeopleView`: "JUST MET" section header; `ConsistencyStrip.color(for:)` (coldActive/coldIdle → lavender, warmActive/warmIdle → amber).
- `PersonDetailSheet`: "JUST MET" label.
- `HistoryView`: cold/warm legend dots, heatmap intensity colors (`hadCold` → lavender, warm → amber), and any cold/warm-keyed text.
- `InsightsView`: chart legend ("Approaches" → lavender, "Catch-ups" → amber) and the matching `.chartForegroundStyleScale`, plus cold/warm-keyed stat colors.
- `AddChallengeSheet` / `ChallengesView`: `case .cold → lavender`, `case .warm → amber`.
- `LogSheetView`: the "Add new <name>" affordance color if it semantically signals cold (else treat as neutral).

### Sites that stay lavender (neutral chrome — do not flip)
`RootView` tab tint; gear/“+”/nav-link icons; Save/primary buttons and their shadows; `DatePicker` tint; selected-person capsule chips; PersonDetailSheet "Move to Catch-ups" button. (When the button represents the warm action specifically, it may be intentionally lavender-neutral; keep as-is unless it reads as a cold/warm signal.)

### Testing
- `Theme.accent(for:)` returns lavender for `.cold`, amber for `.warm` (locks the flip direction).
- Manual simulator pass over Home (both modes), People strip, History heatmap, Insights chart.

---

## B. Per-meeting location (with map autocomplete)

### Data
- Migration: `alter table public.conversations add column location text;` (nullable).
- Store the **resolved display string** only (e.g. `"Blue Bottle, 1 Main St"`). No coordinates for now (YAGNI; lat/long can be added later for a map view).

### Model / repo
- `Conversation`: add `var location: String?` + CodingKey `location`.
- `LoggedConversation`: add `let location: String?` with a defaulted init param (`location: String? = nil`) so existing constructions compile.
- `HiyaRepository.logConversation(...)` and `updateConversation(...)`: add a `location: String?` parameter (no protocol default — update all call sites: `LogSheetViewModel.save`, tests, previews). Live repo includes `location` in insert/update payloads and `select`. Mock stores/returns it.
- Live `conversations(...)`, `personConversations(...)` selects include `location`.

### Map autocomplete component
- New `LocationSearchModel` — `@MainActor @Observable`, `NSObject`-backed, conforming to `MKLocalSearchCompleterDelegate`, wrapping `MKLocalSearchCompleter`.
  - `var query: String` → on set, assigns `completer.queryFragment`.
  - `private(set) var suggestions: [LocationSuggestion]` where `LocationSuggestion` holds `title` + `subtitle` and a `displayString` (`subtitle.isEmpty ? title : "\(title), \(subtitle)"`).
  - Delegate `completerDidUpdateResults` maps `completer.results` → suggestions.
  - `MKLocalSearchCompleter` needs no location permission (search completion only).
  - `import MapKit`.

### Log sheet UI
- Add a `WHERE (OPTIONAL)` section between `whenSection` and `valenceSection`:
  - A `TextField` bound to `vm.location`.
  - When focused and non-empty, show up to ~4 tappable suggestion rows from `LocationSearchModel`; tapping sets `vm.location = suggestion.displayString` and clears suggestions.
  - Free text is always allowed (no requirement to pick a suggestion).
- `LogSheetViewModel`: add `var location = ""`; seed from `editing?.location` on edit; pass `location.trimmedOrNil` to the repo on save.

### Display
- `PersonDetailSheet.interactionRow`: add a small location line (mappin icon + text) under the date when `entry.location` is present.
- `HistoryView` detail rows: show location where conversation detail is shown.

### Testing
- Repo round-trips `location` (Mock `logConversation` + `personConversations` / `conversations`).
- `LocationSuggestion.displayString` formats title/subtitle correctly.
- `LogSheetViewModel` seeds `location` from an edited entry and saves trimmed value (empty → nil).

---

## C. Backdating + durable cold origin (`met_cold`)

### Problem
`was_cold_at_time` is currently snapshotted from the person's *live* status by a BEFORE INSERT trigger. With backdated / out-of-order meetings this is wrong (every same-day cold log stays cold; a later-added earlier meeting isn't reclassified). Backfilling a friend's history needs classification that is **chronological and order-independent**, plus a **choosable** origin (Angie's first meeting was a real cold approach; another friend's may not be).

### Data model
- New column: `alter table public.people add column met_cold boolean not null default false;`
  - Meaning: *the relationship began as a cold approach.* Durable — unaffected by lazy graduation (which only flips `status` cold→warm for bucketing).
  - Backfill: `met_cold = (status = 'cold') OR exists(cold conversation for this person)`.
- **Classification rule (the invariant):** for a `met_cold` person, the chronologically **earliest** meeting (`order by occurred_at, id`) has `was_cold_at_time = true` and every other meeting `false`; for a non-`met_cold` person, **all** meetings are `false`.

### Triggers (replace the snapshot trigger)
- Drop `set_was_cold_at_time_before_insert` + `set_was_cold_at_time()`.
- New `recompute_cold_flags(p uuid)` (plpgsql, security definer): set all of `p`'s conversations `was_cold_at_time = false`; if `people.met_cold` for `p`, set the earliest conversation's flag `true`.
- Triggers calling it:
  - conversations `AFTER INSERT` → recompute `NEW.person_id`.
  - conversations `AFTER DELETE` → recompute `OLD.person_id`.
  - conversations `AFTER UPDATE OF occurred_at, person_id` → recompute `NEW.person_id` (and `OLD.person_id` if it changed).
  - people `AFTER UPDATE OF met_cold` → recompute that person.
- One-time `recompute_cold_flags` over all existing people after the `met_cold` backfill, to normalize.

Live status no longer affects `was_cold_at_time` at all — classification is purely `met_cold` + chronology. Lazy graduation (`graduatePastDuePeople`) is unchanged and continues to manage the Just-Met/Catch-ups bucket.

### Model / repo
- `Person`: add `var metCold: Bool = false` + CodingKey `met_cold` (defaulted so existing inits/previews compile).
- `createPerson(name:status:notes:metCold:)` — add `metCold: Bool = false`. Cold-approach creation passes `true`; "add someone you know" passes `false`; backfill passes the chosen value. Live inserts `met_cold`; Mock sets it then recomputes.
- New `updatePersonMetCold(id:metCold:)` — Live updates the column (trigger recomputes); Mock sets it then recomputes.
- `PersonDetailSheet`'s "Move to Catch-ups" action sets `met_cold = false` via `updatePersonMetCold` (they were never a cold approach), replacing the current `reclassifyConversations(wasCold:false)` call; the trigger/Mock recompute makes all their meetings warm.
- Mock: add private `recomputeColdFlags(personId:)` mirroring the SQL (sort by `occurredAt` then `id`; clear all; set earliest `true` iff `person.metCold`). Call it after `logConversation`, `updateConversation`, `deleteConversation`, `createPerson` (when `metCold`/has seed), and `updatePersonMetCold`. `logConversation` stops snapshotting from status and instead appends then recomputes.

### Backfill UX — reuse the log sheet
- **Backdating** already works: the log sheet's "WHEN" `DatePicker` accepts any past date/time. No new date UI.
- **Origin choice for new people:** in the log sheet's person section, when the entered name will create a *new* person, show a small "How did you meet?" segmented control — `Cold approach` / `Already knew them` — pre-set from the caller's `creationMode` (Home-cold → cold approach, Home-warm → already knew them) and overridable. The choice sets `metCold` (cold approach → true). For existing selected people, no toggle (their `met_cold` is fixed).
- **Add more past meetings:** add a "Log a past meeting" button to `PersonDetailSheet` that opens `LogSheetView(preselectedPerson: person)`; backdate via the existing picker.

### Angie walkthrough
1. Open the log sheet, type "Angie" (new), choose **Cold approach** (`met_cold = true`), set the date to last Sunday, save → Angie created (`status = cold`, `met_cold = true`); her one meeting is cold.
2. From Angie's detail sheet, "Log a past meeting" for Tuesday, Wednesday, Friday. Recompute keeps Sunday cold and the rest warm.
3. On the next Home refresh, graduation sees her last meeting (Friday) < today and flips `status` to warm → she appears under Catch-ups. Her strip shows a lavender (cold) first-meeting bar + amber (warm) catch-up bars.

A friend whose first meeting was *not* a cold approach → choose **Already knew them** (`met_cold = false`) → all meetings warm, never touches Approaches stats.

### Testing
- Mock: backdated/out-of-order inserts classify the earliest meeting cold iff `metCold`; non-`metCold` → all warm.
- `createPerson(metCold:)` persists the flag; `updatePersonMetCold` flips it and recomputes.
- Deleting the earliest meeting promotes the next-earliest to cold (for a `metCold` person).
- `LogSheetViewModel` origin choice maps to `metCold` on create.

---

## Migrations summary (two, one-time)
1. `..._add_meeting_location.sql` — `conversations.location text`.
2. `..._add_met_cold_chronological_classification.sql` — `people.met_cold`, backfill, drop old snapshot trigger, add `recompute_cold_flags` + triggers, one-time recompute.

## Out of scope (YAGNI)
- Location coordinates / in-app map view.
- Dedicated bulk-backfill screen (reusing the log sheet covers the need).
- Editing `met_cold` from a settings/admin surface beyond "Move to Catch-ups".
