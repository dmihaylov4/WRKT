# Program Sharing: Send a Workout Program to a Friend

Date: 2026-04-16
Status: Design (not yet approved for implementation)

## Problem

Users build multi-week training programs in WRKT (a `WorkoutSplit` with `PlanBlock`s and `PlanBlockExercise`s). Today there is no way to give that program to a friend. The friend has to rebuild it manually from a screenshot or a verbal description.

## Goal

Let a user send their program to one or more friends. The friend receives it, previews it, accepts it into their personal library, and later activates it on a schedule of their choosing.

## Non-Goals

- Public program discovery or a "program marketplace" (no shareable links, no public feed).
- Live-reference subscriptions where a follower's program updates when the creator edits theirs.
- Sharing individual single-day workouts (`PlannedWorkout`). Scope is multi-week programs only.
- Sharing weights, 1RM data, or any body-specific metrics.
- Sharing across platforms (WRKT to WRKT only).

## Decisions Made During Brainstorming

All confirmed by user:

1. Scope: multi-week program (`WorkoutSplit`), not single-day workouts. Dedicated flow distinct from any future single-workout share.
2. Delivery: snapshot (fork model). Recipient gets an independent copy. Sender edits do not propagate.
3. Recipient lifecycle: accept puts the program into a library. Activation is a separate explicit step that allows customization (start date, rest day layout, per-exercise starting weights).
4. Targeting: direct multi-friend send. No shareable links.
5. Snapshot content: structure only (exercise list, sets x reps, progression strategy, rest day layout, split name, optional creator description). No weights. No sender-specific history.
6. Invite UI: notification plus a persistent "Shared with me" section in the Planner. Lifecycle states are pending, accepted, declined, revoked. No expiry.
7. Sender picks from: "My Programs" library (any `WorkoutSplit` the user owns, active or not).
8. Attribution: permanent. Every forked program shows "originally by Alice" even after edits. Re-sharing is freely allowed; attribution on the snapshot travels with it unchanged.

## Architecture Overview

```
Sender                         Supabase                       Recipient
------                         --------                       ---------

My Programs library            shared_programs                Shared with me (pending)
(WorkoutSplit rows, local       id, creator_user_id,          (program_invites rows,
 SwiftData, active or not)      name, description,             status = pending)
        |                       structure JSONB,                      |
        |                       reschedule_policy,                    |
        |  Share                created_at, deleted_at                | Accept
        v                                                             v
 Friend picker                  program_invites                My Programs library
 (multi-select)                 id, program_id,                (new local WorkoutSplit
        |                       sender_user_id,                 forked from structure,
        |                       recipient_user_id,              with attribution fields)
        +---- INSERTs --------->status, created_at,                   |
                                responded_at                          | Activate
                                       |                              v
                                       v                       Activation sheet
                                 notifications                 (start date, rest days,
                                 (type=program_invite,          per-exercise weights)
                                  target_id=invite_id)                |
                                                                      v
                                                               PlannerStore activates
                                                               (existing logic generates
                                                                PlannedWorkouts)
```

Principles:

1. Snapshot at send, fork on accept. `shared_programs.structure` is immutable JSON. Recipient creates a fresh local `WorkoutSplit` from it on accept. Zero cross-user data coupling after that.
2. Library equals `WorkoutSplit` collection. No new "Library" model. A split is in the library if it exists locally. `isActive == true` means current.
3. Activation equals customization. Accepting adds to library. Activating is a separate sheet (start date, rest day layout, starting weights) that calls existing `PlannerStore` activation logic.
4. Reuse existing primitives. `FriendsListViewModel` for friend picking, `NotificationType` enum for the invite notification, `RealtimeService` for live invite updates, `PlannerSetupCarouselView` for any edit-mode flow.

## Data Model

### SwiftData additions

Extend `WorkoutSplit` (in `Features/WorkoutSession/Models/PlannerModels.swift`) with attribution and provenance fields. All new fields are optional so existing splits remain valid without migration.

```swift
@Model
final class WorkoutSplit {
    // existing fields unchanged:
    @Attribute(.unique) var id: UUID
    var name: String
    var planBlocks: [PlanBlock]
    var anchorDate: Date
    var cursor: Int
    var reschedulePolicy: String
    var isActive: Bool

    // new fields:
    var creatorUserID: String?     // Supabase auth UID of original creator
    var creatorUsername: String?   // cached for display, does not auto-update
    var creatorDisplayName: String? // cached
    var originProgramID: UUID?     // links back to shared_programs.id for debug/reshare
    var programDescription: String? // optional creator-written description
    var importedAt: Date?          // nil means "created here", non-nil means "forked from share"
    var createdAt: Date            // library sort order. Default .now for new rows.
}
```

Migration: additive only. Existing `WorkoutSplit` rows on device get the new fields as nil / `.now` via default values. No schema version bump needed beyond SwiftData's automatic lightweight migration.

### Supabase schema

Two new tables. Migration file: `supabase/migrations/<timestamp>_program_sharing.sql`.

```sql
-- The snapshot of a shared program. Immutable once inserted.
create table public.shared_programs (
    id uuid primary key default gen_random_uuid(),
    creator_user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    description text,
    structure jsonb not null,         -- see "Structure payload" below
    reschedule_policy text not null,  -- "strict" | "rolling" | "flexible"
    created_at timestamptz not null default now(),
    deleted_at timestamptz             -- soft delete. Does not affect accepted copies.
);

create index shared_programs_creator_idx on public.shared_programs(creator_user_id);

-- The invite. One row per (program, sender, recipient).
create table public.program_invites (
    id uuid primary key default gen_random_uuid(),
    program_id uuid not null references public.shared_programs(id) on delete cascade,
    sender_user_id uuid not null references auth.users(id) on delete cascade,
    recipient_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null check (status in ('pending','accepted','declined','revoked')),
    created_at timestamptz not null default now(),
    responded_at timestamptz,
    unique (program_id, sender_user_id, recipient_user_id)
);

create index program_invites_recipient_pending_idx
    on public.program_invites(recipient_user_id, status)
    where status = 'pending';

create index program_invites_sender_idx
    on public.program_invites(sender_user_id);
```

Structure payload (JSON) for `shared_programs.structure`. Versioned for forward compatibility.

```json
{
  "version": 1,
  "planBlocks": [
    {
      "dayName": "Push",
      "isRestDay": false,
      "order": 0,
      "exercises": [
        {
          "exerciseID": "bb-bench",
          "exerciseName": "Barbell Bench Press",
          "sets": 3,
          "reps": 8,
          "progressionStrategy": { "type": "linear", "increment": 2.5 },
          "order": 0
        }
      ]
    },
    {
      "dayName": "Rest",
      "isRestDay": true,
      "order": 1,
      "exercises": []
    }
  ]
}
```

Explicitly NOT in the payload:
- `startingWeight` on any exercise (Q5-A decision).
- `anchorDate`, `cursor`. These are per-user schedule state, not program content.
- `isActive`. Meaningless on a shared snapshot.
- Any IDs from the sender's local SwiftData. UUIDs regenerate on fork.

### Why JSONB instead of normalized tables

1. Snapshot is immutable. Nothing ever updates the structure. Normalized tables would model change that never happens.
2. Recipient forks into their own normalized SwiftData on accept. Server never queries inside the structure.
3. Schema evolution is cheap via the `version` field. Recipient client picks a decoder based on version.
4. Preview rendering on the client is one round trip, one JSON parse.

## RLS Policies

### `shared_programs`

```sql
alter table public.shared_programs enable row level security;

-- Creator can insert their own programs
create policy "creator inserts" on public.shared_programs
    for insert with check (auth.uid() = creator_user_id);

-- Creator can read their own, or anyone with a pending/accepted invite can read
create policy "creator or invited reads" on public.shared_programs
    for select using (
        auth.uid() = creator_user_id
        or exists (
            select 1 from public.program_invites pi
            where pi.program_id = id
              and pi.recipient_user_id = auth.uid()
        )
    );

-- Creator soft-deletes by setting deleted_at (via UPDATE)
create policy "creator updates own" on public.shared_programs
    for update using (auth.uid() = creator_user_id)
    with check (auth.uid() = creator_user_id);

-- No hard delete by users. cascade on auth.users delete is fine.
```

### `program_invites`

```sql
alter table public.program_invites enable row level security;

-- Sender creates invites only to existing friends
-- (reuses existing friendship check; see FriendshipRepository pattern)
create policy "sender inserts to friends" on public.program_invites
    for insert with check (
        auth.uid() = sender_user_id
        and exists (
            select 1 from public.friendships f
            where f.status = 'accepted'
              and (
                  (f.user_id = auth.uid() and f.friend_id = recipient_user_id)
                  or (f.friend_id = auth.uid() and f.user_id = recipient_user_id)
              )
        )
    );

-- Both parties can read their invites
create policy "involved parties read" on public.program_invites
    for select using (
        auth.uid() = sender_user_id or auth.uid() = recipient_user_id
    );

-- Recipient updates (accept / decline); sender updates (revoke).
-- Status transitions enforced in a CHECK on UPDATE via trigger or stored proc.
create policy "involved parties update" on public.program_invites
    for update using (
        auth.uid() = sender_user_id or auth.uid() = recipient_user_id
    );
```

Status-transition enforcement. Only these transitions are legal:

- pending to accepted (recipient only)
- pending to declined (recipient only)
- pending to revoked (sender only)
- terminal states (accepted, declined, revoked) cannot change

Implemented as a BEFORE UPDATE trigger on `program_invites` that rejects invalid transitions based on `auth.uid()` and the old/new status.

## Client Components

### New files

```
Core/Models/
    SharedProgramStructure.swift      -- JSON payload types (Codable)

Features/Planner/Services/
    ProgramSharingRepository.swift    -- Supabase CRUD for shared_programs + program_invites
    ProgramSerializer.swift           -- WorkoutSplit <-> SharedProgramStructure

Features/Planner/ViewModels/
    ProgramLibraryViewModel.swift     -- drives My Programs + Shared with me sections
    ProgramShareViewModel.swift       -- drives the send flow (friend picker + description)
    ProgramInviteViewModel.swift      -- drives preview + accept/decline
    ProgramActivationViewModel.swift  -- drives the activation sheet

Features/Planner/Views/Library/
    ProgramLibraryView.swift          -- two sections: My Programs, Shared with me
    ProgramRowView.swift              -- one row: name, attribution, summary, actions menu
    ProgramShareSheet.swift           -- friend multi-picker + description + send
    ProgramPreviewView.swift          -- read-only preview of any shared program
    ProgramActivationSheet.swift      -- start date, rest day layout, starting weights
    SharedWithMeSection.swift         -- list of pending invites
```

### Modifications to existing files

- `Features/Social/Models/Notification.swift`: add `case programInvite = "program_invite"`, icon, color, category (`.social`), message ("{actor} shared a program with you").
- `Features/WorkoutSession/Models/PlannerModels.swift`: extend `WorkoutSplit` with attribution fields (see Data Model).
- `Features/WorkoutSession/Services/PlannerStore.swift`: expose a `splitLibrary` accessor that returns all owned `WorkoutSplit`s (active + inactive), and an `activate(_:customization:)` method that takes an `ActivationCustomization` value (start date, rest day overrides, starting weights) instead of the current implicit activation.
- `Features/Planner/PlannerSetupCarouselView.swift`: after completing the carousel, save as inactive in the library by default. Add a "Save and activate now" vs "Save for later" choice on the final step. Current behavior is implicit activation; this change makes it explicit, which is also what the received-program flow needs.
- `App/AppShellView.swift` / Planner tab root: add routing to `ProgramLibraryView`.

### Serialization boundary

`ProgramSerializer` is the single place that translates between local `WorkoutSplit` and the wire format.

```swift
struct ProgramSerializer {
    static func toStructure(_ split: WorkoutSplit) -> SharedProgramStructure { ... }
    static func fromStructure(_ s: SharedProgramStructure,
                               creator: CreatorAttribution,
                               originProgramID: UUID) -> WorkoutSplit { ... }
}
```

Round-trip invariant under test: `fromStructure(toStructure(split))` produces a split with equal structural content, new UUIDs, no weights, no active flag.

## Flows

### Flow: Sender shares a program

1. User opens Planner > My Programs library.
2. Row action menu on any split: Share.
3. `ProgramShareSheet` opens.
   - Top: summary of the program being shared (read-only).
   - Middle: friend multi-select. Reuses a new `FriendMultiPicker` component based on `FriendsListViewModel`. Shows avatar + username.
   - Bottom: optional "Description" text field (maps to `shared_programs.description`), e.g. "My Feb-March cut program, 5 days/week."
   - Send button (disabled until at least one friend selected).
4. On Send:
   1. Serialize split to `SharedProgramStructure`.
   2. INSERT one row into `shared_programs` (atomic, one share = one snapshot).
   3. INSERT N rows into `program_invites`, one per recipient, all with status=pending.
   4. Backend notification trigger fires and inserts N `program_invite` rows into `notifications`.
   5. UI dismisses sheet. Haptic success. Toast: "Sent to Alice, Bob, Carol."
5. Error paths:
   - Network failure mid-flight: retry button in sheet. The sheet holds the serialized payload in memory and re-attempts as one transactional call. If partial success (some invite inserts failed), surface affected names and allow re-send for just those.
   - Friendship no longer valid for a recipient: RLS rejects the invite insert. UI surfaces "You are no longer friends with X. Sent to the others." Program row still inserted.
   - Duplicate pending invite (same program + same recipient): UNIQUE constraint. Skip silently with a "Already sent to X" note.

### Flow: Recipient receives an invite

1. `notifications` row created. Notification bell badge increments via existing realtime path.
2. `ProgramLibraryViewModel` subscribes to `program_invites where recipient_user_id = me and status = pending` via `RealtimeService`. "Shared with me" section updates live.
3. Notification tap or Shared-with-me row tap opens `ProgramPreviewView`.
   - Header: creator avatar + display name, relative time ("3h ago").
   - Program name, description.
   - Collapsed list of plan blocks and exercises. Each block expandable.
   - CTAs: Accept, Decline.
4. Accept:
   1. `ProgramSharingRepository.accept(inviteID:)` called.
   2. Supabase: SELECT shared_programs.structure, UPDATE program_invites status=accepted, responded_at=now().
   3. Client: `ProgramSerializer.fromStructure(...)` creates a new local `WorkoutSplit` with fresh UUIDs, `isActive = false`, attribution fields populated from invite sender.
   4. Insert into SwiftData. Dismiss preview.
   5. Toast: "Added to My Programs." Library row highlights briefly.
5. Decline:
   1. UPDATE program_invites status=declined, responded_at=now().
   2. Row removed from Shared with me. No local side effects. Sender sees status change if they look at sent invites.
6. Edge cases:
   - Invite for a program whose `shared_programs` row is soft-deleted: Accept attempt surfaces "This program is no longer available." Invite gets updated to declined on the client's behalf. No local data created.
   - Invite already responded to (e.g., accepted on another device): realtime sync moves it out of pending before the user taps. If they beat the sync, UPDATE returns no rows; UI shows "Already responded on another device" and refreshes.

### Flow: Activate a program from the library

Applies to any library row (self-created or received).

1. User taps Activate on a library row, or the "No active program" CTA.
2. `ProgramActivationSheet` opens.
   - Section 1: Start date picker. Default: tomorrow. Constrained to a window of -7 to +30 days.
   - Section 2: Rest day layout. Reuses the Step3RestDays component from `PlannerSetupCarouselView`, initialized from the program's existing rest day layout. User can override.
   - Section 3: Starting weights. One row per non-rest exercise. Optional (empty = no preset weight, same as `startingWeight == nil` today). This section is populated by the user, never by the sender.
   - Confirm button.
3. On Confirm:
   1. If there is another `isActive == true` split, set it to false (existing PlannerStore behavior).
   2. Apply rest-day overrides to this split's `planBlocks`.
   3. Apply starting weights to `PlanBlockExercise.startingWeight`.
   4. Set `anchorDate = startDate`, `cursor = 0`, `isActive = true`.
   5. `PlannerStore` generates `PlannedWorkout` instances for the upcoming period (existing logic).
   6. Dismiss sheet. Navigate to Planner calendar view.
4. Cancel at any point discards the customization. The library row is unchanged.

### Flow: Edit a library program

1. Row action menu: Edit.
2. Opens `PlannerSetupCarouselView` in "edit mode," prefilled from the split's current content.
3. Editing is unrestricted: rename, change exercises, reorder, change progression strategies, change rest days, add/remove plan blocks, change reschedule policy.
4. Save writes back to the same `WorkoutSplit` row. Attribution fields (`creatorUserID`, `creatorUsername`, etc.) are NOT cleared; the creator stays even after edits.
5. Editing an active split is allowed. A confirmation appears: "You are editing the program you are currently running. This will not modify workouts you have already completed, and upcoming planned workouts will be regenerated from the new structure." On confirm, `PlannerStore` invalidates future planned workouts past today and regenerates from the new structure.

### Flow: Re-share a received program

1. User taps Share on a library row that was received from someone.
2. Same share sheet opens.
3. Serialization includes the original `creatorUserID`, `creatorUsername`, etc. as the new `shared_programs.creator_user_id` field? No: `creator_user_id` is the original creator (immutable). The re-sharer's identity is the `sender_user_id` on the new `program_invites` rows.
4. Recipient sees attribution: "originally by Alice" (the original creator), not "originally by Bob" (the re-sharer). Bob appears as the sender in the invite header but not as the creator once accepted.

This means `ProgramSerializer.toStructure` needs a `creatorAttribution` parameter when the split has a non-nil `creatorUserID`: it carries forward that attribution rather than overwriting it with the current user. The new `shared_programs` row's `creator_user_id` gets the original creator's UID.

### Flow: Sender revokes a pending invite

1. Sender navigates to "Sent invites" (an affordance on the library row: "View who this is shared with").
2. Lists recipients and their current statuses.
3. For any `pending` invite, sender can tap Revoke.
4. UPDATE program_invites status=revoked.
5. Notification trigger deletes the original `program_invite` notification from the recipient's bell if it is still unread.
6. If the recipient is viewing the preview when revocation hits, realtime subscription updates the view to "This invite has been revoked" and closes.

## Notifications Integration

Add new type in `Features/Social/Models/Notification.swift`:

```swift
case programInvite = "program_invite"
```

Icon: `doc.badge.plus` or `figure.strengthtraining.traditional.circle`. Color: blue. Category: `.social`.

Message: `"\(actorName) shared a program with you"`.

Target ID: `program_invites.id`.

Tap action: `NotificationRouter` opens `ProgramPreviewView(inviteID:)`.

### No "program accepted" back-notification (by default)

We do NOT create a counter-notification to the sender when the recipient accepts. Rationale: low value, high spam risk (if I send to 5 friends I get 5 notifications), and the sender can check the library row's "View who this is shared with" surface. If requested later, gate it behind a sender preference.

## Realtime

One new subscription path in `RealtimeService`: user subscribes to their own `program_invites` rows where `status = 'pending'`.

- New invite arrives: push into `ProgramLibraryViewModel.pendingInvites`.
- Invite status changes (revoked, accepted via another device): remove from pending list.

Existing notification realtime path handles the bell update; nothing new there.

## UI Placement

Planner tab gains a top-level sectioned layout:

```
Planner
  Active Program                                [edit] [settings]
    <active WorkoutSplit summary, calendar view>

  Shared with me (N)                                     [show]
    <pending invite cards, one per program_invite>

  My Programs                                     [+ New program]
    <rows of WorkoutSplit: name, attribution, actions>
```

- "Active Program" is the existing calendar/month view, unchanged visually except for an "edit" entry point.
- "Shared with me" only renders when N > 0.
- "My Programs" replaces the current implicit single-split model with a clear list. Each row has a menu: Activate, Edit, Share, Duplicate, Delete.

Settings and existing planner setup carousel entry point remain, but now creating a program lands in My Programs by default rather than auto-activating.

## Testing Strategy

### Unit tests

1. `ProgramSerializer` round trip: `fromStructure(toStructure(x))` yields a `WorkoutSplit` structurally equal to `x` (modulo UUIDs, `isActive`, and weights stripped).
2. `SharedProgramStructure` Codable: forward compat. Decode a structure with an unknown `progressionStrategy.type` into `ProgressionStrategy.static` rather than failing.
3. `SharedProgramStructure` Codable: decode a structure with `version > 1` surfaces a typed `UnsupportedVersionError` that the UI renders as "Update the app to open this program."
4. Attribution preservation: re-sharing a received program produces a snapshot whose `creator_user_id` matches the original creator, not the re-sharer.
5. No weights in payload: `toStructure` never includes a `startingWeight` field; a static assertion at encode time.

### Integration tests (Supabase mock or test project)

1. Send flow: N recipients produces exactly one `shared_programs` row and N `program_invites` rows.
2. RLS: insert invite to a non-friend is rejected.
3. RLS: SELECT on `shared_programs` as an uninvited user with no creator relationship returns zero rows.
4. Status transition trigger: illegal transitions rejected.
5. Revoke then accept race: second operation fails gracefully with a typed error.

### UI tests

1. Send sheet disables Send with zero friends selected; enables with at least one.
2. Preview view renders all plan blocks and exercises; weights absent.
3. Activation sheet: selecting a past start date is rejected; selecting a date more than 30 days out is rejected.
4. Library row with `creatorUserID` set shows attribution; row without it does not.

## Migration and Rollout

1. Supabase migration creates tables and RLS policies.
2. iOS app ships with additive `WorkoutSplit` fields. Existing local data continues to work.
3. No feature flag needed initially. If we want to stage rollout, gate the Share button on a remote config flag.
4. Accept flow is tolerant of older clients: a pre-1.0 client simply won't see the new notification type and won't render pending invites. No data corruption risk.

## Open Questions

None at this time. All earlier ambiguities have been resolved during brainstorming (see Decisions Made).

## Explicitly Deferred

The following are out of scope for this spec and should not be added to the implementation plan:

- Shareable links / public programs.
- Program marketplace or discovery.
- Live-reference subscription model.
- Program ratings or reviews.
- Program categories or tags.
- Multi-language program descriptions.
- Import from third-party services.
- A "fork counter" or social analytics.
- Push notifications (only in-app notifications are in scope; push can layer on the existing notification-service path later).
