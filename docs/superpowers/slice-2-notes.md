# Slice 2 — Future Work

Originally captured at the end of Slice 1; substantially revised on 2026-05-22 after design conversation around Cold/Warm people, dual streaks, and unique-per-day counting.

Order is rough priority guess; revisit after a few days of real Slice 1.6 usage.

---

## Core model change: Cold/Warm as person status

Each `Person` gains a status: **Cold** (stranger / not-yet-engaged) or **Warm** (relationship in progress).

- New person added → starts **Cold**
- First conversation logged with them today → that conversation counts as a **Cold conversation**. The person **stays Cold for the rest of the day** (so a second or third conversation with the same fresh person today is still a Cold conversation — they're not "warm" until you've actually had time apart).
- Once the daily cycle resets (lazy graduation runs on the next app refresh after start-of-today crosses their last-log time), they become **Warm**.
- Every subsequent conversation from that point = **Warm conversation**.
- **No manual promote/demote** — Slice 2.4 dropped the idea. Time-based auto-graduation handles every realistic case, and exposing a manual override read as ambiguous in the UI (swipe button showed "Cold" as the *target* state on a Warm person, looked like a misclassification). If a "feels-like-cold-again" use case shows up later we can revisit.

**Why this shape:** the user specifically struggles with cold approaches (initiating with strangers) far more than with follow-ups. Treating Cold/Warm as a *person property* — not a per-log chip — means zero friction at log time (no chip to tap), the conversation type is auto-derived from the person's current status, and the People view can section neatly by status.

The word "approach" is dropped in user-facing copy — just **Cold** and **Warm**.

### Schema sketch
- Add `people.status text not null default 'cold' check (status in ('cold','warm'))`
- Add `people.status_changed_at timestamptz` for "when did this person graduate"
- Migration: existing people with ≥1 conversation → Warm; those with 0 → Cold (none should exist post-slice-1, but defensive)
- Add `conversations.was_cold_at_time boolean` (snapshot of the person's status at log time, so historical stats don't shift when statuses change later)

---

## Counting model: unique people per day

Daily goal counts **unique people logged today**, not total conversations.

- Talking to Alex 3× today = 1 toward today's goal
- Talking to Alex today and tomorrow = 1 toward each day
- Closes the "rack up 10 by relogging the same person 10×" loophole
- Adjust `HomeViewModel.refresh()` to dedupe `todaysLog` by `personId` for the count, while still showing every individual log row in the Today section

---

## Streaks: two concurrent systems behind an in-view toggle

Two independent streak counters run in the background, but the UI surfaces them one at a time via an **in-view Cold/Warm toggle** rather than cluttering the screen with both. Picking a side puts you in that "mode" for the current view — streak shown, list filtered, stats specific to that side.

| Streak | Increments when | Visual lean |
|--------|-----------------|-------------|
| **Cold streak** | ≥1 Cold conversation that day | accent/amber, "stretch" feel — flame motif |
| **Warm streak** | ≥1 Warm conversation that day | lavender, "warmth" feel — softer glow |

Both streaks always update silently in the data layer — toggling just changes which one is on-screen. No setting needed; no streak-mode preference in Settings. The toggle is itself the streak mode.

**Toggle scope question (open):** is the Cold/Warm selection global (set once, applies across Home and People) or per-screen (Home toggle independent of People toggle)? Lean global — feels more cohesive — but per-screen gives more flexibility for users who want to see one side's streak while browsing the other's list. Decide during implementation.

---

## Home screen evolution

Current Slice 1.6 ring shows count toward 10. Slice 2 layout:

- **Cold | Warm segmented toggle** near the top, below the title
- **Unique-people-today ring** stays as the shared overall progress indicator (doesn't toggle — represents total activity regardless of mode)
- **Below the ring:** the selected mode's streak counter, today's count of that type ("3 cold today"), and any mode-specific affordances
- **Today's log section:** filtered to the selected mode (only Cold convos when on Cold, only Warm when on Warm), with a small "show all" affordance to see the unfiltered list
- Log rows still visually mark their type subtly (flame for Cold rows, neutral for Warm) so even in the unfiltered "show all" view the type is glanceable

The earlier "stretch day" gold-star concept disappears as a separate marker — the cold streak counter does that work, more honestly (a single cold conversation increments the streak whether the user hits the daily total or not).

---

## Follow-up nudge surface

Lightweight section ("Follow up with") suggesting Warm people you haven't logged in a while, e.g., 7+ days.

- Pulls from People where `status = 'warm' AND last_logged_at < now() - 7 days`
- Sorted by oldest-not-seen first, capped at ~3
- Tapping a row pre-fills the log sheet with that person
- Avoids cycling the same suggestions: once you re-log someone they drop off the list naturally

---

## People view

Two switchable lists driven by the same Cold/Warm toggle as Home:

- **Cold list** — people you've added but never logged a conversation with (in practice, mostly empty since the LogSheet flow creates-and-logs in one step)
- **Warm list** — everyone you've ever had a conversation with, sorted by last-seen-recency

Per-row actions:
- Tap a row → opens a detail sheet for editing **per-person notes** (free-text about who this person is — distinct from per-conversation notes which live on the log)
- Trailing swipe → Delete (with confirmation, flagging the cascade on conversations)

No leading swipe / manual promote/demote — see "Core model change" above.

---

## Settings screen

Lean — most decisions are no longer toggles:

- Change daily goal (already a column on `profiles`, just needs UI)
- Sign out / reset (handy for testing, debug visibility)
- Eventually: notification preferences

(The streak-mode toggle is gone — replaced by dual concurrent streaks.)

---

## Rating system rebuild (still deferred)

Slice 1 ships a single `conversations.valence` column with `positive | neutral | negative`, and Slice 1.6 adds an `improvement_note` free-text field. Original intent was to expand into multiple dimensions — vibes / conversation quality / overall — but the actual dimensions remain unsettled.

Decision still deferred to: after a few days of real Slice 1.6 use, when there's a real signal about which dimensions matter.

When revisiting, weigh:
- **How many dimensions actually get filled in?** Each extra dimension multiplies the friction tax per log. Skip rate of the single chip + improvement_note in Slice 1.6 is the strongest input.
- **Dimensions to consider:** vibes (emotional tone), conversation quality (content/substance), overall (gestalt), depth (surface vs. real), energy (drained vs. lit-up), closeness change (drifted vs. closer), novelty (familiar pattern vs. new territory).
- **Scale:** 3-level (good/ok/rough) is fast; 1–5 stars gives more resolution but more cognitive load.
- **Schema options:** (a) extra nullable columns on `conversations`, (b) JSON column, (c) separate `conversation_ratings` table. (a) is simplest; (c) is right if dimensions become user-customizable.
- **Migration plan:** existing `valence` rows should map cleanly into whatever the new schema is.

---

## Notifications (requires Apple Developer Program enrollment, $99/yr)

- **End-of-day prompt:** "You logged X/N today — anyone you forgot?"
- **Streak-at-risk:** evening nudge if cold or warm streak would break tonight
- Cadence and copy still TBD; build the surface only after SIWA is in place

---

## Sign in with Apple

- Requires Apple Developer Program enrollment
- Swap anonymous sign-in for SIWA flow
- Profile migration path: link existing anon UID to the SIWA identity, preserve people + conversations history

---

## Open questions remaining for Slice 2

- **Follow-up window length** (currently sketched at 7 days for the nudge surface) — tunable per-user later?
- **Manual override UX** — long-press on a person? Dedicated edit screen? Toggle in conversation history?
- **Day boundary** — still using `Calendar.current` on device, not profile timezone. Reconcile when adding any cross-device or web companion.

---

## Bigger / later

- **XP and levels:** previously considered as primary reward mechanism, but decided against for Slice 2 — solo app, no external audience for XP, dual-streak does the motivational work more honestly. Could revisit if/when there's a social layer.
- **Screen Time / DeviceActivity API integration:** opt-in "lock distracting apps until I've logged N people." Real differentiator from soft-motivation apps.
- **Custom conversation starters / question packs:** pre-MVP idea from the original brainstorm.
- **Events:** "ask people to do X" — group invites and follow-ups.

---

## Known gotchas / tech debt from Slice 1.x

- `Profile.preview` is in `MockHiyaRepository.swift` — move to its own file when the codebase grows.
- `HomeView.alert` binding for `errorMessage` requires `errorMessage` to be settable from outside the view model (currently not `private(set)`). Acceptable for slice 1 but worth a cleaner error-presentation API as views multiply.
- Timezone column on `profiles` defaults to `'UTC'`; the iOS app uses `Calendar.current` instead of the profile timezone for the "today" window. Fine for a single-device user but reconcile when adding multi-device sync or web companion.
- `LiveHiyaRepository.todaysLog` decodes the joined `people` embed with snake_case field names directly (not via `CodingKeys`). If we add more such queries, factor into a typed row helper.
- Test target retains the Xcode-generated placeholder `hiyaTests.swift` — harmless but could be deleted.
- Today's log on `HomeView` is a plain `VStack` (not inside a `ScrollView`); if more than ~6 logs land in a day on a small device it'll clip. Defer until it actually bites.
