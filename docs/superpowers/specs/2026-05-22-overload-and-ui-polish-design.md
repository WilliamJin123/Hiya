# Hiya Slice 1.5 — Overload + UI Polish

**Goal:** Replace the default-Swift visual treatment with a distinctive dark calm aesthetic, and add an overload mechanic that rewards going past the daily goal with a visual celebration.

**Status:** Design approved by user 2026-05-22. Awaiting spec review → implementation plan.

**Branch:** `slice-1` (current) → merge to `main` → branch `slice-1.5-polish` for this work.

---

## Decisions captured

| Decision | Choice |
|---|---|
| Overload reward | Visual only. No XP, no schema change. (Account-wide XP system noted as future work — see `slice-2-notes.md`.) |
| UI direction | C · Soft Dark Calm — deep purple-black gradient bg, lavender→amber gradient ring, soft glow. |
| Title font ("Hiya") | Instrument Serif Regular |
| Body font | DM Sans (500/600/700) |
| Big counter numeral | Geist Mono (500/600) |
| Goal/overload visualization | C · Celebration center. At goal: ★ + "N DONE". Overload: "+N" + "C TOTAL". |
| Color mode | Locked to dark. No light theme this slice. |
| Implementation approach | Theme tokens file + bundled custom fonts. |

---

## Design tokens

A new file `hiya/hiya/Theme.swift` becomes the single source of truth.

### Colors

| Token | Hex | Use |
|---|---|---|
| `bgGradientTop` | `#0E0B14` | App background, top |
| `bgGradientBottom` | `#1B1726` | App background, bottom |
| `surface` | `#1F1A2A` | Log-sheet inputs, raised rows |
| `textPrimary` | `#E9E4F0` | Body, numerals, titles |
| `textSecondary` | `#8D85A3` | "of 10", timestamps, captions |
| `textOnAccent` | `#14111B` | Foreground on accent-colored buttons |
| `accentLavender` | `#B8A7E8` | Ring start, button bg, in-progress glow |
| `accentAmber` | `#F6C177` | Ring end, at-goal/overload accent + glow |
| `valencePositive` | `#A7D9B5` | Good chip + dot |
| `valenceNeutral` | `#F6C177` | OK chip + dot |
| `valenceNegative` | `#E0918B` | Rough chip + dot |
| `valenceNone` | `#4A4358` | Unrated dot |
| `divider` | white @ 8% (`.white.opacity(0.08)`) | Between log rows |
| `ringTrack` | white @ 7% (`.white.opacity(0.07)`) | Ring background stroke |

### Type scale

| Token | Font · Size · Weight | Tracking / Case | Use |
|---|---|---|---|
| `title` | Instrument Serif · 32 · Regular | — | "Hiya" nav title |
| `counter` | Geist Mono · 72 · 600 | — | Big number in ring (in-progress) |
| `counterOverload` | Geist Mono · 60 · 600 | — | "+N" in ring (overload) |
| `goalStar` | Instrument Serif · 84 · Regular | — | ★ at goal |
| `bodyHeading` | DM Sans · 14 · 600 | tracking 1.2, UPPERCASE | "TODAY", "HOW WAS IT?" |
| `body` | DM Sans · 16 · 500 | — | Person name, button label |
| `secondary` | DM Sans · 13 · 500 | — | Notes, "of 10" |
| `micro` | DM Sans · 11 · 600 | tracking 0.8, UPPERCASE | Time stamps, "+N EXTRA" |

### Other tokens

- Corner radii: `sm: 10`, `md: 14` (buttons, chips), `lg: 20` (cards, sheets)
- Spacing scale: `xs: 4`, `sm: 8`, `md: 16`, `lg: 24`, `xl: 32`
- Glow: blur radius 22pt at 45% opacity. Lavender during in-progress; amber at-goal and overload (overload bumps opacity to ~55%).

### Font bundling

Three font files live at `hiya/hiya/Resources/Fonts/`:

- `InstrumentSerif-Regular.ttf` (Google Fonts)
- `DMSans-VariableFont_opsz,wght.ttf` (Google Fonts variable)
- `GeistMono-VariableFont_wght.ttf` (Vercel / Google Fonts variable)

`UIAppFonts` array registered in the project's Custom iOS Target Properties (manual Xcode step: Target → Info → add `UIAppFonts` array with the 3 filenames as strings).

PostScript names are pinned in `Theme.swift` with a comment showing how to verify them in Font Book.app (`⌘I` on the selected face).

`Font.custom(postScriptName, size:)` is used throughout. For variable fonts, weight is set via `.fontWeight()` modifier on the resulting `Text`.

### Dark mode lock

`hiyaApp.swift` applies `.preferredColorScheme(.dark)` to the WindowGroup. This is the only color mode we ship in this slice.

---

## Ring state model

`HomeViewModel` exposes a new computed property:

```swift
enum RingState: Equatable {
    case inProgress(count: Int, goal: Int, progress: Double)  // count < goal
    case atGoal(goal: Int)                                    // count == goal
    case overload(count: Int, goal: Int, extra: Int)          // count > goal
}

var ringState: RingState {
    if count < goal {
        let p = goal > 0 ? Double(count) / Double(goal) : 0
        return .inProgress(count: count, goal: goal, progress: p)
    } else if count == goal {
        return .atGoal(goal: goal)
    } else {
        return .overload(count: count, goal: goal, extra: count - goal)
    }
}
```

The existing `progress` getter stays (and still caps at 1.0 — correct because the ring is always fully filled at-goal/overload). The existing `progressCapsAt1WhenOverGoal` test remains valid.

---

## New component: `ProgressRingView`

File: `hiya/hiya/Views/ProgressRingView.swift`

One component, three layouts driven by `RingState`:

| State | Ring fill | Center content (top) | Center content (bottom) | Glow |
|---|---|---|---|---|
| `inProgress(count, goal, progress)` | Gradient lavender→amber, `trim` = progress | `count` (Geist Mono 72, textPrimary) | `"of N"` (DM Sans 13 secondary) | Lavender 40% |
| `atGoal(goal)` | Gradient lavender→amber, full | ★ (Instrument Serif 84 amber) | `"N DONE"` (DM Sans 13 micro amber) | Amber 45% |
| `overload(count, goal, extra)` | Gradient lavender→amber, full | `+extra` (Geist Mono 60 amber) | `"count TOTAL"` (DM Sans 13 micro amber) | Amber 55% |

Ring spec: stroke width 18pt, lineCap `.round`, rotated −90° so it starts at the top, ring frame 240×240pt.

Center content uses `.transition(.opacity.combined(with: .scale(scale: 0.92)))` so the at-goal moment feels rewarding when you log the goal-meeting person.

---

## View changes

### `HomeView`

- Wrap content in a `ZStack` with full-bleed `LinearGradient(Theme.bgGradientTop → Theme.bgGradientBottom, top → bottom)` ignoring safe areas
- Replace inline ring code with `ProgressRingView(state: vm.ringState)`
- Nav title rendered via `.toolbar { ToolbarItem(placement: .principal) { Text("Hiya").font(Theme.title) } }`
- Nav bar background hidden via `.toolbarBackground(.hidden, for: .navigationBar)` so the gradient shows through
- Log button: solid `Theme.accentLavender` background, `Theme.textOnAccent` foreground, radius 14, drop shadow `color: accentLavender @ 30%, radius: 14, y: 8`. **Replaces the current default-tint (iOS blue) `.borderedProminent` button.**
- Log rows: name in `Theme.body`, note in `Theme.secondary` color `Theme.textSecondary`, time in `Theme.micro` color `Theme.textSecondary`, dot Circle 9pt with valence color, divider `Theme.divider`
- "TODAY" header in `Theme.bodyHeading` color `Theme.textSecondary`
- Alert binding for `errorMessage` stays as-is

### `LogSheetView`

Drop the system `Form` (it fights theming) and use a custom `ScrollView { VStack { … } }`:

- Background: same gradient as Home
- Section headers: `Theme.bodyHeading` color `Theme.textSecondary`
- Name TextField: `Theme.surface` background, radius 10, padding 12, `Theme.textPrimary` text, `Theme.textSecondary` placeholder
- Suggestion rows: surface card style, tap-to-select; the list is hidden once a person is selected (existing behavior)
- Valence chips: pill shape, label DM Sans 14 weight 600. Selected = filled with valence color at 18% opacity + matching colored text; unselected = `Theme.surface` background + `Theme.textPrimary` text
- Note field: same surface background treatment, multiline (1–4 lines)
- Save: full-width lavender button matching Home's log button. **Replaces the default iOS-blue `.confirmationAction` toolbar button.**
- Cancel: subtle text button, top left, `Theme.textSecondary` color. **Replaces the default iOS-blue `.cancellationAction` toolbar button.**
- `.preferredColorScheme(.dark)` is inherited from the app

### `hiyaApp.swift`

Add `.preferredColorScheme(.dark)` to the WindowGroup contents.

---

## Tests

**3 new view-model tests** in `HomeViewModelTests.swift`:

```swift
@Test func ringState_isInProgress_whenBelowGoal() async throws { /* count=3 goal=10 → .inProgress(3, 10, 0.3) */ }
@Test func ringState_isAtGoal_whenExactlyGoal() async throws { /* count=10 goal=10 → .atGoal(10) */ }
@Test func ringState_isOverload_withCorrectExtra_whenAboveGoal() async throws { /* count=12 goal=10 → .overload(12, 10, 2) */ }
```

All 15 existing tests pass unchanged.

No new repository / mock tests (no behavior change in data layer). No new `LogSheetViewModel` tests (no behavior change). No automated UI tests; visuals verified via Preview + simulator smoke.

**Manual smoke (after implementation):**

1. Launch app → gradient bg, Instrument Serif "Hiya", Geist Mono counter, glow visible
2. Log up to (goal − 1) people → in-progress visuals, lavender glow, gradient ring fills
3. Log goal-th person → at-goal state: ★, "N DONE", amber glow, center crossfade animation
4. Log (goal + 1)-th person → overload state: "+1", "(goal+1) TOTAL", amber glow more intense
5. Log more → "+2", "+3"; "C TOTAL" updates accordingly
6. Force-quit & reopen → state persists, ring renders correct state on cold launch
7. Open LogSheet → matches gradient, custom textfield/chip/button treatments, no system Form styling

---

## Out of scope (Slice 2)

- Settings screen (change daily goal, streak mode)
- People view (full directory, delete entries)
- Streak counter
- Edit / delete a logged conversation
- Sign in with Apple (blocked on Apple Developer Program)
- XP / levels system (account-wide — user wants this eventually)
- Rating system rebuild (waiting for usage data)
- Light-mode theme
- Onboarding flow
- Haptics, confetti, sheet present animations beyond ring center-content crossfade
- Push notifications

If any of these become tempting during execution, STOP and add them to Slice 2 notes instead.

---

## Open items / known follow-ups after this slice

- `Theme.swift` will need a more explicit accessibility pass when we ship to real users (contrast ratios are good, but no Dynamic Type support is planned for this slice — using fixed sizes; revisit when adding settings).
- Variable fonts in iOS: setting custom axes (optical size for DM Sans) requires `Font.custom(...).fontWeight(...)`. If the axis behavior isn't right at runtime, fall back to static font files per weight.
- Manual UIAppFonts entry in project settings is a known friction point; if it becomes a recurring pain we'll script project.pbxproj patching in a future slice.
