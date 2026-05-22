# Hiya Slice 1.6 — Edit Notes + Improvement Notes

**Goal:** Let users edit/delete logged conversations in-app, and add a second optional text field per log capturing "what could've been better."

**Status:** Design approved by user 2026-05-22. Awaiting spec review → implementation plan.

**Branch:** Will be `slice-1.6-edit-improve` branched off `main` (after Slice 1.5 merge).

---

## Decisions captured

| Decision | Choice |
|---|---|
| Shape of "improvement" field | Second free-text field per log — nullable `improvement_note` column on `conversations`. Doesn't preclude a future multi-dimensional rating rebuild. |
| What's editable | Notes (both fields) + valence + delete. Person and timestamp are immutable. |
| Edit entry UX | Tap a row in today's list → edit sheet opens prefilled. Single edit path; delete is a button inside the sheet. No swipe gestures. |
| Implementation shape | Extend `LogSheetViewModel`/`LogSheetView` with an `editing: LoggedConversation?` parameter — same form, different behavior. No new view file. |

---

## Schema

**New migration** at `supabase/migrations/<timestamp>_add_improvement_note.sql`:

```sql
alter table public.conversations
  add column improvement_note text;
```

The existing per-row RLS policies cover the new column. No index needed.

---

## Model updates

### `Conversation`

```swift
struct Conversation: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let ownerId: UUID
    let personId: UUID
    var occurredAt: Date
    var valence: Valence?
    var note: String?
    var improvementNote: String?    // NEW
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case personId = "person_id"
        case occurredAt = "occurred_at"
        case valence
        case note
        case improvementNote = "improvement_note"
        case createdAt = "created_at"
    }
}
```

### `LoggedConversation`

```swift
struct LoggedConversation: Identifiable, Sendable, Equatable {
    let id: UUID
    let personId: UUID              // NEW — needed for edit flow
    let personName: String
    let occurredAt: Date
    let valence: Conversation.Valence?
    let note: String?
    let improvementNote: String?    // NEW
}
```

---

## Repository changes

### `HiyaRepository` protocol

```swift
// logConversation gains improvementNote (breaking change — no default)
func logConversation(
    personId: UUID,
    valence: Conversation.Valence?,
    note: String?,
    improvementNote: String?
) async throws

// NEW
func updateConversation(
    id: UUID,
    valence: Conversation.Valence?,
    note: String?,
    improvementNote: String?
) async throws

// NEW
func deleteConversation(id: UUID) async throws
```

### `LiveHiyaRepository`

- `logConversation`: insert now includes `improvement_note`
- `updateConversation`: PostgREST `.from("conversations").update(...).eq("id", value: id).execute()`. RLS enforces ownership server-side; no client-side ownership check.
- `deleteConversation`: PostgREST `.from("conversations").delete().eq("id", value: id).execute()`
- `todaysLog`: select string adds `person_id, improvement_note`; `Row` decoder + mapping updated accordingly

### `MockHiyaRepository`

- Store `improvementNote` in in-memory `Conversation` array
- `updateConversation`: locate by `id` in the array, mutate in place
- `deleteConversation`: filter out by `id`
- `todaysLog`: include `personId` and `improvementNote` in the returned `LoggedConversation`

---

## View-model updates

### `LogSheetViewModel`

**New state:**
- `var improvementNote: String = ""`
- `private(set) var editing: LoggedConversation? = nil`

**New initializer:**

```swift
init(repo: HiyaRepository, editing: LoggedConversation? = nil) {
    self.repo = repo
    self.editing = editing
    if let editing {
        searchText = editing.personName
        valence = editing.valence
        note = editing.note ?? ""
        improvementNote = editing.improvementNote ?? ""
    }
}
```

**Behavior changes:**
- `canSave` returns `true` whenever `editing != nil` (a person is already attached); preserves existing logic for create mode.
- `save()` branches:
  - If `editing != nil`: call `repo.updateConversation(id: editing.id, valence:, note:, improvementNote:)`
  - Else: existing create flow + `improvementNote` parameter
  - Trims notes; nil-out empty strings
- New `delete()` method, only valid when `editing != nil`. Calls `repo.deleteConversation(id:)`. Returns `Bool`.

### `HomeViewModel`

No changes. (Refresh after edit/delete is triggered by the existing `onDismiss` of the sheet.)

---

## View updates

### `LogSheetView`

- New optional parameter `editing: LoggedConversation? = nil`, forwarded to the view model.
- **Person section**: when editing, render a read-only label on a `Theme.surface` card showing the person name (no TextField, no suggestions, no `onChange`). When creating, existing TextField + suggestions.
- **Valence section**: unchanged structure. In edit mode the pre-filled chip is auto-selected.
- **NEW "WHAT COULD'VE BEEN BETTER?" section** — placed between valence and the existing note section. Same `Theme.surface` text-field treatment as the regular note (multi-line 1–4).
- **Save button** — label is `"Update"` when editing, `"Save"` when creating; same lavender styling.
- **Delete button** — only rendered when editing. Below Save. `Theme.valenceNegative` text on `Theme.surface` background. Tapping it shows a `.confirmationDialog`. On confirm, calls `vm.delete()` and `dismiss()` on success.

### `HomeView`

Replace the boolean sheet trigger with an `Identifiable` enum:

```swift
enum LogSheetMode: Identifiable {
    case create
    case edit(LoggedConversation)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let c): "edit-\(c.id.uuidString)"
        }
    }
}

@State private var sheetMode: LogSheetMode?
```

- Log button sets `sheetMode = .create`.
- `LogRow` becomes a `Button(action: onTap)` wrapping its existing content with `.buttonStyle(.plain)`. `onTap` closure sets `sheetMode = .edit(entry)`.
- Single `.sheet(item: $sheetMode, onDismiss: { Task { await vm.refresh() } }) { mode in ... }`:
  ```swift
  switch mode {
  case .create: LogSheetView(repo: repo)
  case .edit(let entry): LogSheetView(repo: repo, editing: entry)
  }
  ```

The visual appearance of `LogRow` is unchanged — only the tap target is added.

---

## Tests

**7 new `LogSheetViewModelTests`:**

1. `init_withEditing_prefillsFields` — given a `LoggedConversation`, VM exposes matching `searchText`, `valence`, `note`, `improvementNote`
2. `canSave_isTrueWhenEditing_evenWithoutChanges`
3. `save_inEditMode_callsUpdateConversationNotInsert` — asserts `repo.conversations.count` unchanged, but row mutated
4. `save_inCreateMode_passesImprovementNote` — verifies improvement note flows to insert
5. `save_inEditMode_persistsImprovementNote` — verifies improvement note flows to update
6. `delete_returnsTrue_andRemovesConversation`
7. `delete_setsErrorOnFailure_returnsFalse`

**Existing tests:** all 18 will compile-fail until callers of `logConversation` pass `improvementNote: nil`. ~10 mechanical updates (in mock + tests). After that, all 18 should pass unchanged.

No new `HomeViewModelTests`; no new repository tests beyond what the view-model tests exercise via the mock.

### Manual smoke (after implementation)

1. Open today's list → tap a row → edit sheet opens, all fields prefilled, person name shown as read-only
2. Edit note, add improvement note → tap **Update** → row reflects updated note preview, sheet dismisses, ring count unchanged
3. Tap another row → change valence chip → **Update** → dot color changes
4. Tap row → **Delete** → confirmation dialog → confirm → row disappears, ring count decrements
5. Force-quit → reopen → all edits/deletes persist (came from Supabase, not memory)
6. Supabase Dashboard → `conversations` table → spot-check edited row has updated values; deleted row is gone

---

## Out of scope — Slice 2 / later

- **Rating system rebuild** (multi-dimensional). `improvement_note` is a simple text column, not the rebuild. The rebuild remains open work pending real usage data.
- People view (full directory, delete people, fix mistyped names)
- Settings screen (daily goal, streak mode)
- Streak counter
- Edit person name (depends on People view)
- Edit `occurredAt` (timestamp is implicit "when you logged")
- Edit history / audit log
- Sign in with Apple (blocked on Apple Developer Program)
- Push notifications, haptics
- Light-mode theme

If any of these become tempting during execution, STOP and add to slice-2 notes instead.
