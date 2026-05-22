# Slice 2 — Future Work

Captured at the end of Slice 1. Order is a rough priority guess; revisit after a few days of real usage of Slice 1.

## Rating system rebuild (decide before implementing more)

Slice 1 ships a single `conversations.valence` column with `positive | neutral | negative`. User wants to expand this into multiple dimensions — initial idea was something like **vibes / conversation quality / overall**, but the actual dimensions are unsettled.

Decision deferred to: after a few days of Slice 1 use, when there's a real signal about which dimensions matter.

When revisiting, weigh:
- **How many dimensions actually get filled in?** Each extra dimension multiplies the friction tax per log. Real-world skip rate of the single chip in Slice 1 is the strongest input.
- **Dimensions to consider:** vibes (emotional tone), conversation quality (content/substance), overall (gestalt), depth (surface vs. real), energy (drained vs. lit-up), closeness change (drifted vs. closer), novelty (familiar pattern vs. new territory).
- **Scale:** 3-level (good/ok/rough) is fast; 1–5 stars gives more resolution but more cognitive load.
- **Schema options:** (a) extra nullable columns on `conversations`, (b) JSON column, (c) separate `conversation_ratings` table. (a) is simplest; (c) is right if dimensions become user-customizable.
- **Migration plan:** existing `valence` rows should map cleanly into whatever the new schema is.

## Slice 2 — features to ship

1. **Settings screen**
   - Change daily goal (already a column on `profiles`, just needs UI)
   - Toggle streak mode (hard vs. soft)
   - Sign out / reset (handy for testing)
2. **People view**
   - Full directory of everyone you've logged
   - Tap to see history with that person
   - **Delete a person** (slice 1 has no way to remove a mis-typed name without going to the Supabase Dashboard)
3. **Streak counter on Home**
   - Display current streak in days
   - Visual cue when at risk (e.g., evening with goal unmet)
4. **Edit / delete a logged conversation**
   - Swipe-to-delete in the today list
   - Tap to edit valence/note
5. **Sign in with Apple**
   - Requires Apple Developer Program ($99/year) enrollment
   - Swap anonymous sign-in for SIWA flow; profile migration path needed
6. **End-of-day prompt** (notification)
   - "You logged X/N today — anyone you forgot?"
   - Needs Apple Developer Program + APNs setup

## Bigger / later

- **XP and levels**: per-conversation XP, bonuses for new people / reconnections, levels unlock content (question packs, conversation starters).
- **Screen Time / DeviceActivity API integration**: opt-in "lock distracting apps until I've logged 5 people." Real differentiator from soft-motivation apps.
- **Custom conversation starters / question packs**: pre-MVP idea from the original brainstorm.
- **Events**: "ask people to do X" — group invites and follow-ups.

## Known gotchas / tech debt from Slice 1

- `Profile.preview` is in `MockHiyaRepository.swift` — move to its own file when the codebase grows.
- `HomeView.alert` binding for `errorMessage` requires `errorMessage` to be settable from outside the view model (currently not `private(set)`). Acceptable for slice 1 but worth a cleaner error-presentation API as views multiply.
- Timezone column on `profiles` defaults to `'UTC'`; the iOS app uses `Calendar.current` instead of the profile timezone for the "today" window. Fine for a single-device user but reconcile when adding multi-device sync or web companion.
- `LiveHiyaRepository.todaysLog` decodes the joined `people` embed with snake_case field names directly (not via `CodingKeys`). If we add more such queries, factor into a typed row helper.
- Test target retains the Xcode-generated placeholder `hiyaTests.swift` — harmless but could be deleted.
