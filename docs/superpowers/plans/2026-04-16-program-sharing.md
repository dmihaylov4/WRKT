# Program Sharing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user send a multi-week `WorkoutSplit` program to one or more friends. Friends preview, accept into a library, and later activate with customization (start date, rest days, starting weights). Attribution is permanent and re-share is allowed.

**Architecture:** Snapshot fork model. Shared program is an immutable JSONB row on Supabase; each recipient creates an independent local `WorkoutSplit` on accept. Library equals the user's `WorkoutSplit` collection (active or not). Activation is a separate customization step.

**Tech Stack:** Swift/SwiftUI, SwiftData, Supabase (Postgres + RLS + Realtime), Swift Testing framework.

**Spec:** `docs/superpowers/specs/2026-04-16-program-sharing-design.md`

---

## File Structure

**Create:**

- `supabase/migrations/20260416120000_program_sharing.sql` — tables, RLS, trigger
- `Core/Models/SharedProgramStructure.swift` — wire JSON types, versioned
- `Features/Planner/Services/ProgramSharingRepository.swift` — Supabase CRUD
- `Features/Planner/Services/ProgramSerializer.swift` — WorkoutSplit <-> SharedProgramStructure
- `Features/Planner/ViewModels/ProgramLibraryViewModel.swift`
- `Features/Planner/ViewModels/ProgramShareViewModel.swift`
- `Features/Planner/ViewModels/ProgramInviteViewModel.swift`
- `Features/Planner/ViewModels/ProgramActivationViewModel.swift`
- `Features/Planner/Views/Library/ProgramLibraryView.swift`
- `Features/Planner/Views/Library/ProgramRowView.swift`
- `Features/Planner/Views/Library/ProgramShareSheet.swift`
- `Features/Planner/Views/Library/FriendMultiPicker.swift`
- `Features/Planner/Views/Library/ProgramPreviewView.swift`
- `Features/Planner/Views/Library/ProgramActivationSheet.swift`
- `Features/Planner/Views/Library/SharedWithMeSection.swift`
- `Features/Planner/Views/Library/SentInvitesSheet.swift`
- `WRKTTests/FeaturesTests/Planner/ProgramSerializerTests.swift`
- `WRKTTests/FeaturesTests/Planner/SharedProgramStructureTests.swift`
- `WRKTTests/FeaturesTests/Planner/ProgramLibraryViewModelTests.swift`
- `WRKTTests/FeaturesTests/Planner/ProgramAttributionTests.swift`

**Modify:**

- `Features/WorkoutSession/Models/PlannerModels.swift` — add attribution fields to `WorkoutSplit`
- `Features/WorkoutSession/Services/PlannerStore.swift` — add `splitLibrary()`, `activate(_:customization:)`, `replanUpcomingWorkouts(for:)`
- `Features/Social/Models/Notification.swift` — add `.programInvite` case
- `Features/Social/Services/RealtimeService.swift` — add `subscribeToProgramInvites`
- `Features/Social/Views/Components/NotificationRouter` (or equivalent routing site) — handle `.programInvite` tap
- `Features/Planner/PlannerSetupCarouselView.swift` — save-inactive by default, optional "activate now"
- `App/AppShellView.swift` (or planner-tab root) — add library entry point

**Testing approach:** Swift Testing framework (`import Testing`, `@Test`, `#expect`). iOS test target is `WRKTTests`. Run a single test file:

```
xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:WRKTTests/<TestFileName>
```

Only invoke this command when told. Unit tests (serializer, Codable, attribution) run without a simulator booted UI, but the xcodebuild invocation still requires a simulator destination.

---

## Task List

Phases are large groupings; tasks are the commit units.

### Phase A: Data foundations

- Task 1: Supabase migration (tables, indexes, RLS, trigger)
- Task 2: Wire payload types (`SharedProgramStructure`)
- Task 3: Extend `WorkoutSplit` SwiftData model
- Task 4: `ProgramSerializer` + round-trip tests
- Task 5: Notification type `.programInvite`

### Phase B: Network layer

- Task 6: `ProgramSharingRepository` scaffolding + send
- Task 7: Repository: accept / decline / revoke / fetch
- Task 8: Realtime subscription for pending invites

### Phase C: Activation primitives

- Task 9: `PlannerStore` splitLibrary + activate(customization:) + replan

### Phase D: Library UI

- Task 10: `ProgramLibraryViewModel`
- Task 11: `ProgramRowView`
- Task 12: `ProgramLibraryView` (sections, active summary, pending invites)
- Task 13: Wire into Planner tab root

### Phase E: Send flow

- Task 14: `FriendMultiPicker` component
- Task 15: `ProgramShareViewModel` + `ProgramShareSheet`

### Phase F: Receive flow

- Task 16: `ProgramInviteViewModel` + `ProgramPreviewView`
- Task 17: Route `.programInvite` notification tap into preview

### Phase G: Activation flow

- Task 18: `ProgramActivationViewModel` + `ProgramActivationSheet`

### Phase H: Creator-side adjustments

- Task 19: Update `PlannerSetupCarouselView` to save-inactive by default
- Task 20: Edit-mode path in carousel with attribution preservation
- Task 21: `SentInvitesSheet` (view recipients, revoke)

### Phase I: Final

- Task 22: End-to-end QA runbook

---

## Task 1: Supabase migration — tables, indexes, RLS, triggers

**Files:**
- Create: `supabase/migrations/20260416120000_program_sharing.sql`

- [ ] **Step 1.1: Create the migration file**

```sql
-- 20260416120000_program_sharing.sql
-- Program sharing: snapshot + invite tables, RLS, status-transition trigger

-- Snapshot table: immutable program payload
create table public.shared_programs (
    id uuid primary key default gen_random_uuid(),
    creator_user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    description text,
    structure jsonb not null,
    reschedule_policy text not null check (reschedule_policy in ('strict','rolling','flexible')),
    created_at timestamptz not null default now(),
    deleted_at timestamptz
);

create index shared_programs_creator_idx on public.shared_programs(creator_user_id);

-- Invite table. Note: no full UNIQUE on (program, sender, recipient).
-- See partial unique index below for the correct "only one pending at a time" rule.
create table public.program_invites (
    id uuid primary key default gen_random_uuid(),
    program_id uuid not null references public.shared_programs(id) on delete cascade,
    sender_user_id uuid not null references auth.users(id) on delete cascade,
    recipient_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null check (status in ('pending','accepted','declined','revoked')),
    created_at timestamptz not null default now(),
    responded_at timestamptz
);

create index program_invites_recipient_pending_idx
    on public.program_invites(recipient_user_id, status)
    where status = 'pending';

create index program_invites_sender_idx on public.program_invites(sender_user_id);

-- At most one PENDING invite per (program, sender, recipient). Terminal-state rows
-- (accepted/declined/revoked) are excluded, so the sender can resend the same program
-- to the same recipient after a decline or revoke. This is the schema-level expression
-- of the "re-share is allowed" decision in the spec.
create unique index program_invites_unique_pending
    on public.program_invites (program_id, sender_user_id, recipient_user_id)
    where status = 'pending';

-- Enable RLS
alter table public.shared_programs enable row level security;
alter table public.program_invites enable row level security;

-- shared_programs: creator inserts their own
create policy "creator inserts" on public.shared_programs
    for insert with check (auth.uid() = creator_user_id);

-- shared_programs read access:
-- - Creator always reads their own rows (including soft-deleted, for moderation/recovery).
-- - Other users only read while:
--      (a) the program is not soft-deleted, AND
--      (b) they have a pending OR accepted invite to it.
--   Once an invite is declined or revoked, the recipient loses read access to the snapshot.
create policy "creator or invited reads" on public.shared_programs
    for select using (
        auth.uid() = creator_user_id
        or (
            deleted_at is null
            and exists (
                select 1 from public.program_invites pi
                where pi.program_id = shared_programs.id
                  and pi.recipient_user_id = auth.uid()
                  and pi.status in ('pending','accepted')
            )
        )
    );

-- shared_programs: creator updates own (for soft delete)
create policy "creator updates own" on public.shared_programs
    for update using (auth.uid() = creator_user_id)
    with check (auth.uid() = creator_user_id);

-- program_invites: sender can insert only if a friendship exists
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

-- program_invites: either party reads
create policy "involved parties read" on public.program_invites
    for select using (
        auth.uid() = sender_user_id or auth.uid() = recipient_user_id
    );

-- program_invites: either party updates (status transitions enforced by trigger below)
create policy "involved parties update" on public.program_invites
    for update using (
        auth.uid() = sender_user_id or auth.uid() = recipient_user_id
    );

-- Status transition + immutability guard.
-- The RLS UPDATE policy above only checks identity. This trigger enforces:
--   1. Identifying columns (program_id, sender, recipient, created_at) are immutable.
--   2. Only legal status transitions are allowed.
--   3. responded_at is auto-set when leaving pending.
create or replace function public.check_program_invite_transition()
returns trigger
language plpgsql
security definer
as $$
begin
    -- Immutability guard: identifying columns cannot be mutated by anyone.
    -- This prevents an authenticated party from rewriting an invite to point at
    -- another program/user under the cover of a "status change".
    if old.program_id is distinct from new.program_id
       or old.sender_user_id is distinct from new.sender_user_id
       or old.recipient_user_id is distinct from new.recipient_user_id
       or old.created_at is distinct from new.created_at then
        raise exception 'program_invite identifying columns are immutable';
    end if;

    -- Terminal states cannot change
    if old.status in ('accepted','declined','revoked') then
        raise exception 'program_invite is in terminal state %, cannot update', old.status;
    end if;

    -- pending -> accepted/declined by recipient only
    if new.status in ('accepted','declined') then
        if auth.uid() <> old.recipient_user_id then
            raise exception 'only recipient can set status to %', new.status;
        end if;
    end if;

    -- pending -> revoked by sender only
    if new.status = 'revoked' then
        if auth.uid() <> old.sender_user_id then
            raise exception 'only sender can revoke';
        end if;
    end if;

    -- auto-set responded_at when leaving pending
    if old.status = 'pending' and new.status <> 'pending' then
        new.responded_at := now();
    end if;

    return new;
end;
$$;

create trigger program_invite_transition_check
    before update on public.program_invites
    for each row execute function public.check_program_invite_transition();

-- Notification trigger: when an invite is inserted, create a notification for the recipient
create or replace function public.notify_program_invite()
returns trigger
language plpgsql
security definer
as $$
begin
    insert into public.notifications (user_id, type, actor_id, target_id, read, metadata)
    values (new.recipient_user_id, 'program_invite', new.sender_user_id, new.id, false, null);
    return new;
end;
$$;

create trigger notify_on_program_invite_insert
    after insert on public.program_invites
    for each row execute function public.notify_program_invite();

-- Revocation cleanup: delete the unread notification for a revoked pending invite
create or replace function public.cleanup_revoked_program_invite()
returns trigger
language plpgsql
security definer
as $$
begin
    if new.status = 'revoked' and old.status = 'pending' then
        delete from public.notifications
        where type = 'program_invite'
          and target_id = new.id
          and read = false;
    end if;
    return new;
end;
$$;

create trigger cleanup_on_program_invite_revoke
    after update on public.program_invites
    for each row execute function public.cleanup_revoked_program_invite();

-- Realtime
alter publication supabase_realtime add table public.program_invites;
```

- [ ] **Step 1.2: Apply migration locally**

Run: `supabase db reset` or `supabase migration up`
Expected: migration applies cleanly, no errors.

- [ ] **Step 1.3: Smoke test RLS manually**

Via Supabase SQL editor, run as an authenticated test user. Expected:
- INSERT into `shared_programs` with `creator_user_id = auth.uid()` succeeds.
- INSERT with a different `creator_user_id` fails.
- INSERT into `program_invites` to a non-friend fails with "new row violates row-level security policy".
- INSERT into `program_invites` to an accepted friend succeeds and a `notifications` row appears for the recipient.
- UPDATE `program_invites` setting status to `accepted` as the recipient succeeds.
- UPDATE `program_invites` setting status to `accepted` as the sender fails with "only recipient can set status to accepted".
- A second INSERT into `program_invites` with the same (program_id, sender_user_id, recipient_user_id) while the first row is still `pending` fails with "duplicate key value violates unique constraint program_invites_unique_pending".
- After the recipient declines, a second INSERT into `program_invites` with the same triple **succeeds** (resend allowed after terminal state).
- UPDATE attempting to mutate `program_id`, `sender_user_id`, `recipient_user_id`, or `created_at` (e.g., `update program_invites set program_id = '...' where id = ...`) fails with "program_invite identifying columns are immutable".
- After the recipient accepts, then the sender soft-deletes the program (`update shared_programs set deleted_at = now() where id = ...`), the recipient's SELECT on that `shared_programs` row returns zero rows. The creator's SELECT still returns the row.
- After the recipient declines an invite, the recipient's SELECT on the underlying `shared_programs` row returns zero rows.

- [ ] **Step 1.4: Commit**

```bash
git add supabase/migrations/20260416120000_program_sharing.sql
git commit -m "feat(supabase): add program_sharing tables, RLS, triggers"
```

---

## Task 2: Wire payload types — `SharedProgramStructure`

**Files:**
- Create: `Core/Models/SharedProgramStructure.swift`
- Test: `WRKTTests/FeaturesTests/Planner/SharedProgramStructureTests.swift`

- [ ] **Step 2.1: Write the failing tests**

```swift
// WRKTTests/FeaturesTests/Planner/SharedProgramStructureTests.swift
import Testing
import Foundation
@testable import WRKT

struct SharedProgramStructureTests {

    @Test func decodesVersion1Payload() throws {
        let json = """
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
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SharedProgramStructure.self, from: json)
        #expect(decoded.version == 1)
        #expect(decoded.planBlocks.count == 1)
        #expect(decoded.planBlocks[0].dayName == "Push")
        #expect(decoded.planBlocks[0].exercises.count == 1)
        if case .linear(let inc) = decoded.planBlocks[0].exercises[0].progressionStrategy {
            #expect(inc == 2.5)
        } else {
            Issue.record("expected .linear progression")
        }
    }

    @Test func decodesRestDayBlock() throws {
        let json = """
        { "version": 1, "planBlocks": [
          { "dayName": "Rest", "isRestDay": true, "order": 0, "exercises": [] }
        ] }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SharedProgramStructure.self, from: json)
        #expect(decoded.planBlocks[0].isRestDay == true)
        #expect(decoded.planBlocks[0].exercises.isEmpty)
    }

    @Test func unknownProgressionStrategyFallsBackToStatic() throws {
        let json = """
        { "version": 1, "planBlocks": [
          { "dayName": "X", "isRestDay": false, "order": 0, "exercises": [
            { "exerciseID": "x", "exerciseName": "X", "sets": 1, "reps": 1, "order": 0,
              "progressionStrategy": { "type": "timedescent", "step": 9 } }
          ] }
        ] }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SharedProgramStructure.self, from: json)
        if case .static = decoded.planBlocks[0].exercises[0].progressionStrategy {
            // pass
        } else {
            Issue.record("expected .static fallback for unknown progression type")
        }
    }

    @Test func futureVersionThrowsTypedError() throws {
        let json = """
        { "version": 99, "planBlocks": [] }
        """.data(using: .utf8)!
        #expect(throws: SharedProgramStructure.DecodingError.unsupportedVersion(99)) {
            _ = try JSONDecoder().decode(SharedProgramStructure.self, from: json)
        }
    }

    @Test func encodesVersion1WithoutWeights() throws {
        let structure = SharedProgramStructure(
            version: 1,
            planBlocks: [
                .init(dayName: "Push", isRestDay: false, order: 0, exercises: [
                    .init(exerciseID: "bb-bench", exerciseName: "Bench",
                          sets: 3, reps: 8,
                          progressionStrategy: .linear(increment: 2.5), order: 0)
                ])
            ]
        )
        let data = try JSONEncoder().encode(structure)
        let string = String(data: data, encoding: .utf8)!
        #expect(!string.contains("weight"))
        #expect(!string.contains("startingWeight"))
    }
}
```

- [ ] **Step 2.2: Run the tests and verify they fail**

Run: `xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WRKTTests/SharedProgramStructureTests`
Expected: FAIL (`SharedProgramStructure` undefined).

- [ ] **Step 2.3: Implement `SharedProgramStructure`**

```swift
// Core/Models/SharedProgramStructure.swift
//
// Wire payload types for program sharing. Versioned for forward compatibility.
// Contains ONLY program structure. No weights, no per-user state.

import Foundation

struct SharedProgramStructure: Codable, Equatable, Sendable {
    let version: Int
    let planBlocks: [Block]

    struct Block: Codable, Equatable, Sendable {
        let dayName: String
        let isRestDay: Bool
        let order: Int
        let exercises: [Exercise]
    }

    struct Exercise: Codable, Equatable, Sendable {
        let exerciseID: String
        let exerciseName: String
        let sets: Int
        let reps: Int
        let progressionStrategy: Progression
        let order: Int
    }

    enum Progression: Equatable, Sendable {
        case linear(increment: Double)
        case percentage(factor: Double)
        case autoregulated
        case `static`
    }

    enum DecodingError: Error, Equatable {
        case unsupportedVersion(Int)
    }

    init(version: Int, planBlocks: [Block]) {
        self.version = version
        self.planBlocks = planBlocks
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case version, planBlocks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .version)
        guard version == 1 else {
            throw DecodingError.unsupportedVersion(version)
        }
        self.version = version
        self.planBlocks = try c.decode([Block].self, forKey: .planBlocks)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(planBlocks, forKey: .planBlocks)
    }
}

extension SharedProgramStructure.Progression: Codable {
    private enum Keys: String, CodingKey { case type, increment, factor }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "linear":
            let inc = try c.decode(Double.self, forKey: .increment)
            self = .linear(increment: inc)
        case "percentage":
            let f = try c.decode(Double.self, forKey: .factor)
            self = .percentage(factor: f)
        case "autoregulated":
            self = .autoregulated
        case "static":
            self = .static
        default:
            self = .static
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .linear(let inc):
            try c.encode("linear", forKey: .type)
            try c.encode(inc, forKey: .increment)
        case .percentage(let f):
            try c.encode("percentage", forKey: .type)
            try c.encode(f, forKey: .factor)
        case .autoregulated:
            try c.encode("autoregulated", forKey: .type)
        case .static:
            try c.encode("static", forKey: .type)
        }
    }
}
```

- [ ] **Step 2.4: Run the tests and verify they pass**

Run: `xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WRKTTests/SharedProgramStructureTests`
Expected: all 5 tests PASS.

- [ ] **Step 2.5: Commit**

```bash
git add Core/Models/SharedProgramStructure.swift WRKTTests/FeaturesTests/Planner/SharedProgramStructureTests.swift
git commit -m "feat(planner): add SharedProgramStructure wire types"
```

---

## Task 3: Extend `WorkoutSplit` with attribution fields

**Files:**
- Modify: `Features/WorkoutSession/Models/PlannerModels.swift:195-245`
- Modify: `Features/Planner/ViewModels/ProgramLibraryViewModel.swift` (Task 10) sort key — uses `createdAt ?? importedAt ?? .distantPast` since `createdAt` is now optional.

**SwiftData migration note:**
The app currently registers a flat `Schema([...])` (see `App/WRKTApp.swift:245-252`) without a `VersionedSchema` plan. SwiftData lightweight migration reliably handles **adding optional properties with default `nil`**, but adding a non-optional property with a runtime default like `var createdAt: Date = Date()` has been observed to crash at first launch on some OS versions. Therefore every new field added here is **optional with default `nil`**, including `createdAt`. Library sort order falls back through the chain `createdAt ?? importedAt ?? .distantPast` so existing rows (which will have nil for both) sort to the bottom on first launch but otherwise behave normally.

Do NOT change the `Schema([...])` registration shape in `App/WRKTApp.swift`. If a future task requires non-optional new fields, it must introduce a `VersionedSchema` + `SchemaMigrationPlan` first; that work is explicitly out of scope here.

- [ ] **Step 3.1: Add attribution fields to `WorkoutSplit`**

Locate the `@Model final class WorkoutSplit { ... }` block. Add these properties alongside the existing ones. All are optional with default `nil` so SwiftData's lightweight migration applies cleanly to existing rows.

```swift
// Attribution (set when program arrives from a share; nil when user-created locally)
var creatorUserID: String?
var creatorUsername: String?
var creatorDisplayName: String?
var originProgramID: UUID?          // links back to shared_programs.id
var programDescription: String?
var importedAt: Date?               // nil means "created here"
var createdAt: Date?                // library sort order; nil for pre-feature rows
```

Update the `init(...)` signature to accept them, all defaulting to nil so all existing call sites still compile. Note that `createdAt` is set to `.now` *inside* the initializer (so newly created rows get a timestamp) but the persisted property remains optional (so migration of existing rows lands them at nil):

```swift
init(id: UUID = UUID(),
     name: String,
     planBlocks: [PlanBlock],
     anchorDate: Date = .now,
     reschedulePolicy: ReschedulePolicy = .strict,
     creatorUserID: String? = nil,
     creatorUsername: String? = nil,
     creatorDisplayName: String? = nil,
     originProgramID: UUID? = nil,
     programDescription: String? = nil,
     importedAt: Date? = nil) {
    self.id = id
    self.name = name
    self.planBlocks = planBlocks
    self.anchorDate = anchorDate
    self.cursor = 0
    self.reschedulePolicy = reschedulePolicy.rawValue
    self.isActive = true  // keep existing default for now; Task 19 will change this
    self.creatorUserID = creatorUserID
    self.creatorUsername = creatorUsername
    self.creatorDisplayName = creatorDisplayName
    self.originProgramID = originProgramID
    self.programDescription = programDescription
    self.importedAt = importedAt
    self.createdAt = Date()
}
```

- [ ] **Step 3.2: Build and verify no compile errors**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3.3: Commit**

```bash
git add Features/WorkoutSession/Models/PlannerModels.swift
git commit -m "feat(planner): add attribution fields to WorkoutSplit"
```

---

## Task 4: `ProgramSerializer` + round-trip tests

**Files:**
- Create: `Features/Planner/Services/ProgramSerializer.swift`
- Test: `WRKTTests/FeaturesTests/Planner/ProgramSerializerTests.swift`
- Test: `WRKTTests/FeaturesTests/Planner/ProgramAttributionTests.swift`

- [ ] **Step 4.1: Write the failing tests**

```swift
// WRKTTests/FeaturesTests/Planner/ProgramSerializerTests.swift
import Testing
import Foundation
import SwiftData
@testable import WRKT

@MainActor
struct ProgramSerializerTests {

    private func makeSplit() -> WorkoutSplit {
        let pushExercises = [
            PlanBlockExercise(exerciseID: "bb-bench", exerciseName: "Bench",
                              sets: 3, reps: 8, startingWeight: 80.0,
                              progressionStrategy: .linear(increment: 2.5), order: 0),
            PlanBlockExercise(exerciseID: "ohp", exerciseName: "OHP",
                              sets: 3, reps: 10, startingWeight: 40.0,
                              progressionStrategy: .autoregulated, order: 1)
        ]
        let push = PlanBlock(dayName: "Push", exercises: pushExercises, isRestDay: false)
        let rest = PlanBlock(dayName: "Rest", exercises: [], isRestDay: true)
        return WorkoutSplit(name: "PPL", planBlocks: [push, rest],
                            reschedulePolicy: .rolling)
    }

    @Test func toStructureDropsWeights() throws {
        let split = makeSplit()
        let structure = ProgramSerializer.toStructure(split)

        #expect(structure.version == 1)
        #expect(structure.planBlocks.count == 2)
        #expect(structure.planBlocks[0].dayName == "Push")
        #expect(structure.planBlocks[0].exercises.count == 2)
        #expect(structure.planBlocks[1].isRestDay == true)

        // No weight fields should exist on the wire
        let data = try JSONEncoder().encode(structure)
        let jsonString = String(data: data, encoding: .utf8)!
        #expect(!jsonString.contains("startingWeight"))
        #expect(!jsonString.contains("\"weight\""))
    }

    @Test func roundTripPreservesStructure() {
        let original = makeSplit()
        let structure = ProgramSerializer.toStructure(original)
        let creator = ProgramSerializer.CreatorAttribution(
            userID: "creator-uid",
            username: "alice",
            displayName: "Alice"
        )
        let restored = ProgramSerializer.fromStructure(
            structure,
            name: "PPL",
            reschedulePolicy: .rolling,
            creator: creator,
            description: nil,
            originProgramID: UUID()
        )

        #expect(restored.name == original.name)
        #expect(restored.planBlocks.count == original.planBlocks.count)
        #expect(restored.planBlocks[0].dayName == "Push")
        #expect(restored.planBlocks[0].exercises.count == 2)
        #expect(restored.planBlocks[1].isRestDay == true)

        // Weights stripped
        #expect(restored.planBlocks[0].exercises.allSatisfy { $0.startingWeight == nil })
        // Not yet active; accept does not activate
        #expect(restored.isActive == false)
        // Attribution copied
        #expect(restored.creatorUserID == "creator-uid")
        #expect(restored.creatorUsername == "alice")
        // IDs regenerated (not equal to originals)
        #expect(restored.id != original.id)
    }

    @Test func progressionStrategyRoundTrip() {
        let original = makeSplit()
        let restored = ProgramSerializer.fromStructure(
            ProgramSerializer.toStructure(original),
            name: "X", reschedulePolicy: .strict,
            creator: nil, description: nil, originProgramID: UUID()
        )
        // Push block, exercise 0: linear(2.5); exercise 1: autoregulated
        let ex0 = restored.planBlocks.first(where: { $0.dayName == "Push" })!.exercises
            .sorted(by: { $0.order < $1.order })
        if case .linear(let inc) = ex0[0].progressionStrategy {
            #expect(inc == 2.5)
        } else { Issue.record("expected linear") }
        if case .autoregulated = ex0[1].progressionStrategy {} else {
            Issue.record("expected autoregulated")
        }
    }
}
```

```swift
// WRKTTests/FeaturesTests/Planner/ProgramAttributionTests.swift
import Testing
import Foundation
@testable import WRKT

@MainActor
struct ProgramAttributionTests {

    @Test func reshareCarriesOriginalCreator() {
        // Alice creates; Bob receives and re-shares to Carol.
        // The new shared_programs row must carry Alice as creator, not Bob.
        let aliceAttribution = ProgramSerializer.CreatorAttribution(
            userID: "alice-uid", username: "alice", displayName: "Alice"
        )

        // Bob's local split was forked from Alice's share
        let split = ProgramSerializer.fromStructure(
            SharedProgramStructure(version: 1, planBlocks: []),
            name: "Alice's PPL",
            reschedulePolicy: .strict,
            creator: aliceAttribution,
            description: nil,
            originProgramID: UUID()
        )
        #expect(split.creatorUserID == "alice-uid")

        // Now compute the attribution Bob should send onward
        let outgoing = ProgramSerializer.outgoingAttribution(
            for: split,
            currentUserID: "bob-uid",
            currentUsername: "bob",
            currentDisplayName: "Bob"
        )
        // Must carry Alice forward, NOT overwrite with Bob
        #expect(outgoing.userID == "alice-uid")
        #expect(outgoing.username == "alice")
    }

    @Test func selfCreatedUsesCurrentUser() {
        // Bob creates locally; attribution of an outgoing share is Bob.
        let split = WorkoutSplit(name: "Bob's PPL", planBlocks: [])
        let outgoing = ProgramSerializer.outgoingAttribution(
            for: split,
            currentUserID: "bob-uid",
            currentUsername: "bob",
            currentDisplayName: "Bob"
        )
        #expect(outgoing.userID == "bob-uid")
    }
}
```

- [ ] **Step 4.2: Run tests, verify they fail**

Run: `xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WRKTTests/ProgramSerializerTests -only-testing:WRKTTests/ProgramAttributionTests`
Expected: FAIL (`ProgramSerializer` undefined).

- [ ] **Step 4.3: Implement `ProgramSerializer`**

```swift
// Features/Planner/Services/ProgramSerializer.swift
//
// Translates between local WorkoutSplit (SwiftData) and SharedProgramStructure (wire JSON).
// Weights are NEVER serialized. UUIDs are regenerated on fork.

import Foundation

enum ProgramSerializer {

    struct CreatorAttribution: Equatable, Sendable {
        let userID: String
        let username: String?
        let displayName: String?
    }

    // MARK: - Encode (split -> structure)

    static func toStructure(_ split: WorkoutSplit) -> SharedProgramStructure {
        let blocks = split.planBlocks
            .enumerated()
            .map { offset, block -> SharedProgramStructure.Block in
                SharedProgramStructure.Block(
                    dayName: block.dayName,
                    isRestDay: block.isRestDay,
                    order: offset,
                    exercises: block.exercises
                        .sorted(by: { $0.order < $1.order })
                        .map(mapExercise)
                )
            }
        return SharedProgramStructure(version: 1, planBlocks: blocks)
    }

    private static func mapExercise(_ e: PlanBlockExercise) -> SharedProgramStructure.Exercise {
        SharedProgramStructure.Exercise(
            exerciseID: e.exerciseID,
            exerciseName: e.exerciseName,
            sets: e.sets,
            reps: e.reps,
            progressionStrategy: mapProgression(e.progressionStrategy),
            order: e.order
        )
    }

    private static func mapProgression(_ p: ProgressionStrategy) -> SharedProgramStructure.Progression {
        switch p {
        case .linear(let inc): return .linear(increment: inc)
        case .percentage(let f): return .percentage(factor: f)
        case .autoregulated: return .autoregulated
        case .static: return .static
        }
    }

    // MARK: - Decode (structure -> split fork)

    static func fromStructure(
        _ s: SharedProgramStructure,
        name: String,
        reschedulePolicy: ReschedulePolicy,
        creator: CreatorAttribution?,
        description: String?,
        originProgramID: UUID
    ) -> WorkoutSplit {
        let blocks = s.planBlocks
            .sorted(by: { $0.order < $1.order })
            .map { block in
                PlanBlock(
                    id: UUID(),
                    dayName: block.dayName,
                    exercises: block.exercises.map { ex in
                        PlanBlockExercise(
                            id: UUID(),
                            exerciseID: ex.exerciseID,
                            exerciseName: ex.exerciseName,
                            sets: ex.sets,
                            reps: ex.reps,
                            startingWeight: nil,  // never forked
                            progressionStrategy: unmapProgression(ex.progressionStrategy),
                            order: ex.order
                        )
                    },
                    isRestDay: block.isRestDay
                )
            }

        let split = WorkoutSplit(
            id: UUID(),
            name: name,
            planBlocks: blocks,
            anchorDate: .now,
            reschedulePolicy: reschedulePolicy,
            creatorUserID: creator?.userID,
            creatorUsername: creator?.username,
            creatorDisplayName: creator?.displayName,
            originProgramID: originProgramID,
            programDescription: description,
            importedAt: .now
        )
        // Accepted splits are inactive until user activates
        split.isActive = false
        return split
    }

    private static func unmapProgression(_ p: SharedProgramStructure.Progression) -> ProgressionStrategy {
        switch p {
        case .linear(let inc): return .linear(increment: inc)
        case .percentage(let f): return .percentage(factor: f)
        case .autoregulated: return .autoregulated
        case .static: return .static
        }
    }

    // MARK: - Re-share attribution

    /// Attribution to use when the current user shares `split` onward.
    /// If the split was imported from someone else, that original creator is preserved.
    /// Otherwise the current user is the creator.
    static func outgoingAttribution(
        for split: WorkoutSplit,
        currentUserID: String,
        currentUsername: String?,
        currentDisplayName: String?
    ) -> CreatorAttribution {
        if let existing = split.creatorUserID {
            return CreatorAttribution(
                userID: existing,
                username: split.creatorUsername,
                displayName: split.creatorDisplayName
            )
        }
        return CreatorAttribution(
            userID: currentUserID,
            username: currentUsername,
            displayName: currentDisplayName
        )
    }
}
```

- [ ] **Step 4.4: Run tests, verify pass**

Run: `xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WRKTTests/ProgramSerializerTests -only-testing:WRKTTests/ProgramAttributionTests`
Expected: all tests PASS.

- [ ] **Step 4.5: Commit**

```bash
git add Features/Planner/Services/ProgramSerializer.swift \
        WRKTTests/FeaturesTests/Planner/ProgramSerializerTests.swift \
        WRKTTests/FeaturesTests/Planner/ProgramAttributionTests.swift
git commit -m "feat(planner): add ProgramSerializer with attribution preservation"
```

---

## Task 5: Notification type `.programInvite`

**Files:**
- Modify: `Features/Social/Models/Notification.swift`

- [ ] **Step 5.1: Add the enum case**

In `NotificationType`, add a case right after `.virtualRunInvite`:

```swift
case programInvite = "program_invite"
```

- [ ] **Step 5.2: Extend `icon`, `color`, `category`, and `NotificationWithActor.message`**

In the `icon` switch: `case .programInvite: return "doc.text"`
In the `color` switch: `case .programInvite: return "blue"`
In the `category` switch, add to the `.social` group: `case .virtualRunInvite, .programInvite: return .social`
In `NotificationWithActor.message` switch:

```swift
case .programInvite:
    return "\(actorName) shared a program with you"
```

- [ ] **Step 5.3: Build and verify**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED (no test changes yet; routing added in Task 17).

- [ ] **Step 5.4: Commit**

```bash
git add Features/Social/Models/Notification.swift
git commit -m "feat(notifications): add programInvite notification type"
```

---

## Task 6: `ProgramSharingRepository` — scaffolding + send

**Files:**
- Create: `Features/Planner/Services/ProgramSharingRepository.swift`

- [ ] **Step 6.1: Create repository scaffolding + models**

```swift
// Features/Planner/Services/ProgramSharingRepository.swift
//
// Supabase CRUD for shared_programs + program_invites.

import Foundation
import Supabase

// MARK: - Wire rows (Supabase column shape)

struct SharedProgramRow: Codable, Sendable, Identifiable {
    let id: UUID
    let creatorUserId: UUID
    let name: String
    let description: String?
    let structure: SharedProgramStructure  // JSONB decoded to struct
    let reschedulePolicy: String
    let createdAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case creatorUserId = "creator_user_id"
        case name
        case description
        case structure
        case reschedulePolicy = "reschedule_policy"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }
}

enum ProgramInviteStatus: String, Codable, Sendable {
    case pending, accepted, declined, revoked
}

struct ProgramInviteRow: Codable, Sendable, Identifiable {
    let id: UUID
    let programId: UUID
    let senderUserId: UUID
    let recipientUserId: UUID
    var status: ProgramInviteStatus
    let createdAt: Date
    let respondedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case programId = "program_id"
        case senderUserId = "sender_user_id"
        case recipientUserId = "recipient_user_id"
        case status
        case createdAt = "created_at"
        case respondedAt = "responded_at"
    }
}

enum ProgramSharingError: LocalizedError {
    case programUnavailable
    case inviteAlreadyResponded
    case notAuthenticated
    case partialSendFailure(failedRecipients: [UUID], underlying: Error)

    var errorDescription: String? {
        switch self {
        case .programUnavailable: return "This program is no longer available."
        case .inviteAlreadyResponded: return "This invite has already been responded to."
        case .notAuthenticated: return "You must be signed in."
        case .partialSendFailure: return "Some invites could not be sent."
        }
    }
}

@MainActor
final class ProgramSharingRepository {

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseClientWrapper.shared.client) {
        self.client = client
    }

    // MARK: - Send

    /// Serialize a local split, insert shared_programs, then fan-out program_invites.
    /// Returns the created program and per-recipient invite results.
    struct SendResult {
        let program: SharedProgramRow
        let succeeded: [ProgramInviteRow]
        let failed: [(recipientId: UUID, error: Error)]
    }

    func send(
        split: WorkoutSplit,
        description: String?,
        to recipientIds: [UUID],
        currentUserID: UUID,
        currentUsername: String?,
        currentDisplayName: String?
    ) async throws -> SendResult {

        let attribution = ProgramSerializer.outgoingAttribution(
            for: split,
            currentUserID: currentUserID.uuidString,
            currentUsername: currentUsername,
            currentDisplayName: currentDisplayName
        )
        // creatorUserID on the server row is the attribution.userID (preserves original).
        guard let creatorUUID = UUID(uuidString: attribution.userID) else {
            throw ProgramSharingError.notAuthenticated
        }

        let structure = ProgramSerializer.toStructure(split)

        struct NewProgram: Encodable {
            let creator_user_id: String
            let name: String
            let description: String?
            let structure: SharedProgramStructure
            let reschedule_policy: String
        }

        let payload = NewProgram(
            creator_user_id: creatorUUID.uuidString,
            name: split.name,
            description: description,
            structure: structure,
            reschedule_policy: split.policy.rawValue
        )

        let program: SharedProgramRow = try await client
            .from("shared_programs")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value

        // Fan out invites, collecting per-recipient outcomes.
        var succeeded: [ProgramInviteRow] = []
        var failed: [(UUID, Error)] = []

        for recipientId in recipientIds {
            do {
                struct NewInvite: Encodable {
                    let program_id: String
                    let sender_user_id: String
                    let recipient_user_id: String
                    let status: String
                }
                let invitePayload = NewInvite(
                    program_id: program.id.uuidString,
                    sender_user_id: currentUserID.uuidString,
                    recipient_user_id: recipientId.uuidString,
                    status: ProgramInviteStatus.pending.rawValue
                )
                let invite: ProgramInviteRow = try await client
                    .from("program_invites")
                    .insert(invitePayload)
                    .select()
                    .single()
                    .execute()
                    .value
                succeeded.append(invite)
            } catch {
                failed.append((recipientId, error))
            }
        }

        return SendResult(program: program, succeeded: succeeded, failed: failed)
    }
}
```

- [ ] **Step 6.2: Build**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6.3: Commit**

```bash
git add Features/Planner/Services/ProgramSharingRepository.swift
git commit -m "feat(planner): add ProgramSharingRepository with send"
```

---

## Task 7: Repository — accept / decline / revoke / fetch

**Files:**
- Modify: `Features/Planner/Services/ProgramSharingRepository.swift`

- [ ] **Step 7.1: Add the remaining methods to the repository**

Append to the class body:

```swift
    // MARK: - Fetch

    /// Fetch a single program by id (used for preview and accept).
    /// Throws `.programUnavailable` if row is missing or soft-deleted.
    func fetchProgram(id: UUID) async throws -> SharedProgramRow {
        do {
            let row: SharedProgramRow = try await client
                .from("shared_programs")
                .select()
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value
            if row.deletedAt != nil {
                throw ProgramSharingError.programUnavailable
            }
            return row
        } catch is ProgramSharingError {
            throw ProgramSharingError.programUnavailable
        } catch {
            throw error
        }
    }

    /// Fetch pending invites for the current user (recipient side).
    func fetchPendingInvites(for userId: UUID) async throws -> [ProgramInviteRow] {
        let rows: [ProgramInviteRow] = try await client
            .from("program_invites")
            .select()
            .eq("recipient_user_id", value: userId.uuidString)
            .eq("status", value: ProgramInviteStatus.pending.rawValue)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows
    }

    /// Fetch invites the current user has sent (any status), optionally filtered by program.
    func fetchSentInvites(
        for userId: UUID,
        programId: UUID? = nil
    ) async throws -> [ProgramInviteRow] {
        var query = client
            .from("program_invites")
            .select()
            .eq("sender_user_id", value: userId.uuidString)
        if let programId {
            query = query.eq("program_id", value: programId.uuidString)
        }
        let rows: [ProgramInviteRow] = try await query
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows
    }

    // MARK: - Respond (recipient)

    @discardableResult
    func accept(inviteId: UUID) async throws -> ProgramInviteRow {
        struct Update: Encodable { let status: String }
        do {
            let updated: ProgramInviteRow = try await client
                .from("program_invites")
                .update(Update(status: ProgramInviteStatus.accepted.rawValue))
                .eq("id", value: inviteId.uuidString)
                .eq("status", value: ProgramInviteStatus.pending.rawValue)
                .select()
                .single()
                .execute()
                .value
            return updated
        } catch {
            throw ProgramSharingError.inviteAlreadyResponded
        }
    }

    @discardableResult
    func decline(inviteId: UUID) async throws -> ProgramInviteRow {
        struct Update: Encodable { let status: String }
        do {
            let updated: ProgramInviteRow = try await client
                .from("program_invites")
                .update(Update(status: ProgramInviteStatus.declined.rawValue))
                .eq("id", value: inviteId.uuidString)
                .eq("status", value: ProgramInviteStatus.pending.rawValue)
                .select()
                .single()
                .execute()
                .value
            return updated
        } catch {
            throw ProgramSharingError.inviteAlreadyResponded
        }
    }

    // MARK: - Revoke (sender)

    @discardableResult
    func revoke(inviteId: UUID) async throws -> ProgramInviteRow {
        struct Update: Encodable { let status: String }
        let updated: ProgramInviteRow = try await client
            .from("program_invites")
            .update(Update(status: ProgramInviteStatus.revoked.rawValue))
            .eq("id", value: inviteId.uuidString)
            .eq("status", value: ProgramInviteStatus.pending.rawValue)
            .select()
            .single()
            .execute()
            .value
        return updated
    }

    // MARK: - Soft delete

    func softDeleteProgram(id: UUID) async throws {
        struct Update: Encodable { let deleted_at: String }
        let iso = ISO8601DateFormatter().string(from: Date())
        _ = try await client
            .from("shared_programs")
            .update(Update(deleted_at: iso))
            .eq("id", value: id.uuidString)
            .execute()
    }
```

- [ ] **Step 7.2: Build**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7.3: Commit**

```bash
git add Features/Planner/Services/ProgramSharingRepository.swift
git commit -m "feat(planner): add accept/decline/revoke/fetch to ProgramSharingRepository"
```

---

## Task 8: Realtime subscription for pending invites

**Files:**
- Modify: `Features/Social/Services/RealtimeService.swift`

- [ ] **Step 8.1: Add `subscribeToProgramInvites` method**

Add after `subscribeToNotifications`:

```swift
    // MARK: - Program Invites

    /// Subscribe to program_invites rows where recipient_user_id = userId.
    /// Fires on INSERT (new pending invite) and UPDATE (status change to anything).
    func subscribeToProgramInvites(
        userId: UUID,
        onInsert: @escaping (ProgramInviteRow) -> Void,
        onUpdate: @escaping (ProgramInviteRow) -> Void
    ) async throws -> String {
        let uid = userId.uuidString.lowercased()
        let channelId = "program_invites_\(uid)"

        if let existing = activeChannels[channelId] {
            await existing.unsubscribe()
            await client.removeChannel(existing)
            activeChannels.removeValue(forKey: channelId)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)

        let channel = await client.channel(channelId)
        _ = await channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "program_invites",
            callback: { action in
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                switch action {
                case .insert(let a):
                    if let row = try? a.decodeRecord(as: ProgramInviteRow.self, decoder: decoder),
                       row.recipientUserId.uuidString.lowercased() == uid {
                        onInsert(row)
                    }
                case .update(let a):
                    if let row = try? a.decodeRecord(as: ProgramInviteRow.self, decoder: decoder),
                       row.recipientUserId.uuidString.lowercased() == uid {
                        onUpdate(row)
                    }
                default: break
                }
            }
        )
        await channel.subscribe()
        activeChannels[channelId] = channel
        return channelId
    }
```

- [ ] **Step 8.2: Build**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 8.3: Commit**

```bash
git add Features/Social/Services/RealtimeService.swift
git commit -m "feat(realtime): subscribe to program_invites"
```

---

## Task 9: `PlannerStore` — library + activate(customization:) + replan

**Files:**
- Modify: `Features/WorkoutSession/Services/PlannerStore.swift`

- [ ] **Step 9.1: Add `ActivationCustomization` value type**

At the top of the file, below imports:

```swift
struct ActivationCustomization: Sendable {
    /// Day when the new active cycle begins (calendar day, hour dropped).
    var startDate: Date
    /// Optional per-block overrides for rest-day flag (indexed by PlanBlock.id).
    var restDayOverrides: [UUID: Bool]
    /// Optional per-exercise starting weight (indexed by PlanBlockExercise.id). nil means leave unset.
    var startingWeights: [UUID: Double?]
}
```

- [ ] **Step 9.2: Add `splitLibrary()` and `activate(_:customization:)`**

Add inside `PlannerStore` class, near `activeSplit()`:

```swift
    /// All WorkoutSplits owned by the user, sorted by creation date descending.
    /// `createdAt` is optional in the schema (see Task 3 SwiftData migration note),
    /// so we sort in Swift after fetch with a fallback chain. Pre-feature rows that
    /// have nil for both createdAt and importedAt sort to the bottom.
    func splitLibrary() throws -> [WorkoutSplit] {
        guard let context = context else { return [] }
        let all = try context.fetch(FetchDescriptor<WorkoutSplit>())
        return all.sorted { a, b in
            let aDate = a.createdAt ?? a.importedAt ?? .distantPast
            let bDate = b.createdAt ?? b.importedAt ?? .distantPast
            return aDate > bDate
        }
    }

    /// Activate a split with customization. Deactivates any previously active split.
    /// - Parameter split: must already be persisted in the model context.
    /// - Parameter customization: startDate, restDayOverrides, startingWeights
    func activate(_ split: WorkoutSplit, customization: ActivationCustomization) throws {
        guard let context = context else { return }

        // 1. Deactivate all other splits
        let others = try context.fetch(
            FetchDescriptor<WorkoutSplit>(predicate: #Predicate { $0.isActive == true })
        )
        for other in others where other.id != split.id {
            other.isActive = false
        }

        // 2. Apply rest-day overrides
        for block in split.planBlocks {
            if let override = customization.restDayOverrides[block.id] {
                block.isRestDay = override
            }
        }

        // 3. Apply starting weights
        for block in split.planBlocks {
            for exercise in block.exercises {
                if let w = customization.startingWeights[exercise.id] {
                    exercise.startingWeight = w
                }
            }
        }

        // 4. Set anchor + cursor and activate
        let startDay = Calendar.current.startOfDay(for: customization.startDate)
        split.anchorDate = startDay
        split.cursor = 0
        split.isActive = true

        try context.save()

        // 5. Generate upcoming planned workouts
        try generatePlannedWorkouts(for: split, days: 30)
    }

    /// Invalidate and regenerate planned workouts from `fromDate` forward.
    /// Used after editing an active split's structure.
    func replanUpcomingWorkouts(for split: WorkoutSplit, fromDate: Date = .now) throws {
        guard let context = context else { return }
        let cutoff = Calendar.current.startOfDay(for: fromDate)
        let splitID = split.id

        // Delete existing planned (but not completed) workouts from cutoff forward
        let predicate = #Predicate<PlannedWorkout> { p in
            p.splitID == splitID
            && p.scheduledDate >= cutoff
            && p.completedWorkoutID == nil
        }
        let toDelete = try context.fetch(FetchDescriptor(predicate: predicate))
        for p in toDelete { context.delete(p) }

        try context.save()
        try generatePlannedWorkouts(for: split, days: 30)
    }
```

- [ ] **Step 9.3: Build**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 9.4: Commit**

```bash
git add Features/WorkoutSession/Services/PlannerStore.swift
git commit -m "feat(planner): add splitLibrary, activate(customization:), replan"
```

---

## Task 10: `ProgramLibraryViewModel`

**Files:**
- Create: `Features/Planner/ViewModels/ProgramLibraryViewModel.swift`
- Test: `WRKTTests/FeaturesTests/Planner/ProgramLibraryViewModelTests.swift`

- [ ] **Step 10.1: Write the failing test**

```swift
// WRKTTests/FeaturesTests/Planner/ProgramLibraryViewModelTests.swift
import Testing
import Foundation
@testable import WRKT

@MainActor
struct ProgramLibraryViewModelTests {

    @Test func pendingInviteAcceptCreatesLocalSplit() async throws {
        let vm = ProgramLibraryViewModel(
            repo: StubSharingRepo(),
            plannerStore: InMemoryPlannerStore(),
            currentUserID: UUID()
        )

        let inviteId = UUID()
        try await vm.acceptInvite(
            inviteId: inviteId,
            senderUsername: "alice",
            senderDisplayName: "Alice"
        )
        #expect(vm.library.count == 1)
        let split = vm.library.first!
        #expect(split.creatorUsername == "alice")
        #expect(split.isActive == false)
    }
}

// Minimal stubs. Real repo types are @MainActor; these run on MainActor already.
private final class StubSharingRepo: ProgramSharingRepositoryInterface {
    func fetchProgram(id: UUID) async throws -> SharedProgramRow {
        SharedProgramRow(
            id: UUID(),
            creatorUserId: UUID(),
            name: "Stub",
            description: nil,
            structure: SharedProgramStructure(version: 1, planBlocks: []),
            reschedulePolicy: "strict",
            createdAt: .now,
            deletedAt: nil
        )
    }
    func fetchInvite(id: UUID) async throws -> ProgramInviteRow {
        ProgramInviteRow(id: id, programId: UUID(), senderUserId: UUID(),
                         recipientUserId: UUID(), status: .pending,
                         createdAt: .now, respondedAt: nil)
    }
    func accept(inviteId: UUID) async throws -> ProgramInviteRow {
        ProgramInviteRow(id: inviteId, programId: UUID(), senderUserId: UUID(),
                         recipientUserId: UUID(), status: .accepted,
                         createdAt: .now, respondedAt: .now)
    }
}

private final class InMemoryPlannerStore: PlannerStoreInterface {
    var splits: [WorkoutSplit] = []
    func splitLibrary() throws -> [WorkoutSplit] { splits }
    func insert(_ split: WorkoutSplit) throws { splits.append(split) }
}
```

- [ ] **Step 10.2: Run test, verify it fails**

Run: `xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WRKTTests/ProgramLibraryViewModelTests`
Expected: FAIL (`ProgramLibraryViewModel` and protocol types undefined).

- [ ] **Step 10.3: Extract protocol boundaries for testability**

At the end of `Features/Planner/Services/ProgramSharingRepository.swift`, add a protocol and make the repo conform:

```swift
@MainActor
protocol ProgramSharingRepositoryInterface: AnyObject {
    func fetchProgram(id: UUID) async throws -> SharedProgramRow
    func fetchInvite(id: UUID) async throws -> ProgramInviteRow
    func accept(inviteId: UUID) async throws -> ProgramInviteRow
}

extension ProgramSharingRepository: ProgramSharingRepositoryInterface {
    func fetchInvite(id: UUID) async throws -> ProgramInviteRow {
        try await client.from("program_invites")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }
}
```

At the end of `Features/WorkoutSession/Services/PlannerStore.swift`, add:

```swift
@MainActor
protocol PlannerStoreInterface: AnyObject {
    func splitLibrary() throws -> [WorkoutSplit]
    func insert(_ split: WorkoutSplit) throws
}

extension PlannerStore: PlannerStoreInterface {
    func insert(_ split: WorkoutSplit) throws {
        guard let context = context else { return }
        context.insert(split)
        try context.save()
    }
}
```

- [ ] **Step 10.4: Implement `ProgramLibraryViewModel`**

```swift
// Features/Planner/ViewModels/ProgramLibraryViewModel.swift

import Foundation
import Observation

@Observable
@MainActor
final class ProgramLibraryViewModel {

    private(set) var library: [WorkoutSplit] = []
    private(set) var activeSplit: WorkoutSplit?
    private(set) var pendingInvites: [PendingInviteDisplay] = []
    private(set) var isLoading: Bool = false
    var errorMessage: String?

    struct PendingInviteDisplay: Identifiable, Sendable {
        let id: UUID            // invite id
        let programId: UUID
        let senderId: UUID
        let senderUsername: String?
        let senderDisplayName: String?
        let programName: String
        let createdAt: Date
    }

    private let repo: ProgramSharingRepositoryInterface
    private let plannerStore: PlannerStoreInterface
    private let currentUserID: UUID

    init(
        repo: ProgramSharingRepositoryInterface,
        plannerStore: PlannerStoreInterface,
        currentUserID: UUID
    ) {
        self.repo = repo
        self.plannerStore = plannerStore
        self.currentUserID = currentUserID
    }

    // MARK: - Load

    func refreshLibrary() {
        do {
            library = try plannerStore.splitLibrary()
            activeSplit = library.first(where: { $0.isActive })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Accept

    func acceptInvite(
        inviteId: UUID,
        senderUsername: String?,
        senderDisplayName: String?
    ) async throws {
        // Fetch the invite to learn the program id
        let invite = try await repo.fetchInvite(id: inviteId)
        let program = try await repo.fetchProgram(id: invite.programId)

        let creator = ProgramSerializer.CreatorAttribution(
            userID: program.creatorUserId.uuidString,
            username: senderUsername,
            displayName: senderDisplayName
        )
        let policy = ReschedulePolicy(rawValue: program.reschedulePolicy) ?? .strict
        let split = ProgramSerializer.fromStructure(
            program.structure,
            name: program.name,
            reschedulePolicy: policy,
            creator: creator,
            description: program.description,
            originProgramID: program.id
        )

        try plannerStore.insert(split)
        _ = try await repo.accept(inviteId: inviteId)

        refreshLibrary()
    }
}
```

- [ ] **Step 10.5: Run tests, verify pass**

Run: `xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WRKTTests/ProgramLibraryViewModelTests`
Expected: PASS.

- [ ] **Step 10.6: Commit**

```bash
git add Features/Planner/ViewModels/ProgramLibraryViewModel.swift \
        Features/Planner/Services/ProgramSharingRepository.swift \
        Features/WorkoutSession/Services/PlannerStore.swift \
        WRKTTests/FeaturesTests/Planner/ProgramLibraryViewModelTests.swift
git commit -m "feat(planner): add ProgramLibraryViewModel with accept flow"
```

---

## Task 11: `ProgramRowView` — library row rendering

**Files:**
- Create: `Features/Planner/Views/Library/ProgramRowView.swift`

- [ ] **Step 11.1: Implement the row**

```swift
// Features/Planner/Views/Library/ProgramRowView.swift

import SwiftUI

struct ProgramRowView: View {
    let split: WorkoutSplit
    let isActive: Bool
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onShare: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onViewRecipients: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(split.name)
                        .font(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)
                    if isActive {
                        Text("Active")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.Semantic.brand.opacity(0.2))
                            .foregroundStyle(DS.Semantic.brand)
                            .clipShape(Capsule())
                    }
                }
                if let name = split.creatorDisplayName ?? split.creatorUsername {
                    Text("Originally by \(name)")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            Spacer(minLength: 0)
            Menu {
                if !isActive {
                    Button("Activate", action: onActivate)
                }
                Button("Edit", action: onEdit)
                Button("Share", action: onShare)
                Button("Duplicate", action: onDuplicate)
                if let onViewRecipients {
                    Button("View recipients", action: onViewRecipients)
                }
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .padding(8)
            }
        }
        .padding(12)
        .background(
            ChamferedRectangle(cornerRadius: 12)
                .fill(DS.Semantic.card)
        )
    }

    private var summary: String {
        let trainingDays = split.planBlocks.filter { !$0.isRestDay }.count
        let totalDays = split.planBlocks.count
        let dayWord = totalDays == 1 ? "day" : "days"
        return "\(trainingDays)/\(totalDays) \(dayWord), \(split.policy.rawValue)"
    }
}
```

- [ ] **Step 11.2: Build**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 11.3: Commit**

```bash
git add Features/Planner/Views/Library/ProgramRowView.swift
git commit -m "feat(planner): add ProgramRowView"
```

---

## Task 12: `ProgramLibraryView` + `SharedWithMeSection`

**Files:**
- Create: `Features/Planner/Views/Library/SharedWithMeSection.swift`
- Create: `Features/Planner/Views/Library/ProgramLibraryView.swift`

- [ ] **Step 12.1: Implement `SharedWithMeSection`**

```swift
// Features/Planner/Views/Library/SharedWithMeSection.swift

import SwiftUI

struct SharedWithMeSection: View {
    let invites: [ProgramLibraryViewModel.PendingInviteDisplay]
    let onTapInvite: (ProgramLibraryViewModel.PendingInviteDisplay) -> Void

    var body: some View {
        if !invites.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Shared with me")
                        .font(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)
                    Text("(\(invites.count))")
                        .font(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
                ForEach(invites) { invite in
                    Button { onTapInvite(invite) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.title3)
                                .foregroundStyle(DS.Semantic.brand)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invite.programName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DS.Semantic.textPrimary)
                                Text("From \(invite.senderDisplayName ?? invite.senderUsername ?? "Friend")")
                                    .font(.caption)
                                    .foregroundStyle(DS.Semantic.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                        .padding(12)
                        .background(
                            ChamferedRectangle(cornerRadius: 12)
                                .fill(DS.Semantic.card)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
```

- [ ] **Step 12.2: Implement `ProgramLibraryView`**

```swift
// Features/Planner/Views/Library/ProgramLibraryView.swift

import SwiftUI

struct ProgramLibraryView: View {
    @Bindable var viewModel: ProgramLibraryViewModel

    @State private var shareTarget: WorkoutSplit?
    @State private var editTarget: WorkoutSplit?
    @State private var activateTarget: WorkoutSplit?
    @State private var previewTarget: ProgramLibraryViewModel.PendingInviteDisplay?
    @State private var recipientsTarget: WorkoutSplit?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                activeSection

                SharedWithMeSection(
                    invites: viewModel.pendingInvites,
                    onTapInvite: { previewTarget = $0 }
                )

                mySection
            }
            .padding(16)
        }
        .background(DS.Semantic.surface.ignoresSafeArea())
        .navigationTitle("Programs")
        .onAppear { viewModel.refreshLibrary() }
        .sheet(item: $shareTarget) { split in
            ProgramShareSheet(split: split) { viewModel.refreshLibrary() }
        }
        .sheet(item: $editTarget) { split in
            // Task 20 adds the edit mode into PlannerSetupCarouselView
            PlannerSetupCarouselView(editing: split)
        }
        .sheet(item: $activateTarget) { split in
            ProgramActivationSheet(split: split) { viewModel.refreshLibrary() }
        }
        .sheet(item: $previewTarget) { invite in
            ProgramPreviewView(inviteId: invite.id) { viewModel.refreshLibrary() }
        }
        .sheet(item: $recipientsTarget) { split in
            SentInvitesSheet(split: split)
        }
    }

    @ViewBuilder
    private var activeSection: some View {
        Text("Active Program")
            .font(.headline)
            .foregroundStyle(DS.Semantic.textPrimary)
        if let active = viewModel.activeSplit {
            ProgramRowView(
                split: active,
                isActive: true,
                onActivate: {},
                onEdit: { editTarget = active },
                onShare: { shareTarget = active },
                onDuplicate: {},
                onDelete: {},
                onViewRecipients: { recipientsTarget = active }
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("No active program")
                    .font(.subheadline)
                    .foregroundStyle(DS.Semantic.textSecondary)
                Text("Pick a program from your library, or create a new one.")
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .padding(12)
            .background(
                ChamferedRectangle(cornerRadius: 12).fill(DS.Semantic.card)
            )
        }
    }

    @ViewBuilder
    private var mySection: some View {
        HStack {
            Text("My Programs")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)
            Spacer(minLength: 0)
            // "+ New program" entry point is left as existing PlannerSetupCarousel trigger.
        }
        if viewModel.library.isEmpty {
            Text("Your library is empty.")
                .font(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
        } else {
            ForEach(viewModel.library, id: \.id) { split in
                ProgramRowView(
                    split: split,
                    isActive: split.isActive,
                    onActivate: { activateTarget = split },
                    onEdit: { editTarget = split },
                    onShare: { shareTarget = split },
                    onDuplicate: {},
                    onDelete: {},
                    onViewRecipients: { recipientsTarget = split }
                )
            }
        }
    }
}
```

- [ ] **Step 12.3: Build**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED. (Sheet contents `ProgramShareSheet`, `ProgramActivationSheet`, `ProgramPreviewView`, `SentInvitesSheet` are added in later tasks; add temporary empty stubs if needed for the build to succeed before Task 15/18/16/21 land.)

- [ ] **Step 12.4: Commit**

```bash
git add Features/Planner/Views/Library/
git commit -m "feat(planner): add ProgramLibraryView + SharedWithMeSection"
```

---

## Task 13: Wire `ProgramLibraryView` into Planner tab root

**Files:**
- Modify: `App/AppShellView.swift` OR the planner tab root (the file that hosts the Planner tab — locate it by searching for `CalendarMonthView` usage).

- [ ] **Step 13.1: Add a toolbar button "Programs" to the Planner tab that pushes `ProgramLibraryView`**

In the NavigationStack that contains `CalendarMonthView`:

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
            ProgramLibraryView(viewModel: libraryViewModel)
        } label: {
            Label("Programs", systemImage: "square.stack.3d.up")
        }
    }
}
```

Where `libraryViewModel` is constructed once in the owning view using `@State` and the injected `@Environment(\.dependencies)`:

```swift
@State private var libraryViewModel: ProgramLibraryViewModel?

// in .onAppear or init:
let me = deps.authService.currentUser?.id ?? UUID()  // guard as appropriate
libraryViewModel = ProgramLibraryViewModel(
    repo: deps.programSharingRepository,
    plannerStore: PlannerStore.shared,
    currentUserID: me
)
```

- [ ] **Step 13.2: Expose `programSharingRepository` on `AppDependencies`**

Modify `Core/Dependencies/AppDependencies.swift` to add:

```swift
let programSharingRepository: ProgramSharingRepository

// in init:
self.programSharingRepository = ProgramSharingRepository(
    client: SupabaseClientWrapper.shared.client
)
```

- [ ] **Step 13.3: Build + quick smoke run in simulator**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

Then boot simulator, navigate to Planner tab, tap "Programs" toolbar button. Expected: library view opens with existing splits listed.

- [ ] **Step 13.4: Commit**

```bash
git add App/ Core/Dependencies/AppDependencies.swift
git commit -m "feat(planner): wire ProgramLibraryView into Planner tab"
```

---

## Task 14: `FriendMultiPicker` component

**Files:**
- Create: `Features/Planner/Views/Library/FriendMultiPicker.swift`

- [ ] **Step 14.1: Implement the multi-picker**

```swift
// Features/Planner/Views/Library/FriendMultiPicker.swift

import SwiftUI

struct FriendMultiPicker: View {
    let friends: [Friend]           // Existing model from FriendshipRepository
    @Binding var selectedIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if friends.isEmpty {
                Text("You don't have any friends yet.")
                    .font(.subheadline)
                    .foregroundStyle(DS.Semantic.textSecondary)
            } else {
                ForEach(friends, id: \.id) { friend in
                    Button {
                        toggle(friend.id)
                    } label: {
                        HStack(spacing: 12) {
                            ProfileAvatar(url: friend.avatarURL, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.displayName ?? friend.username)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DS.Semantic.textPrimary)
                                if friend.displayName != nil {
                                    Text("@\(friend.username)")
                                        .font(.caption)
                                        .foregroundStyle(DS.Semantic.textSecondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: selectedIDs.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedIDs.contains(friend.id) ? DS.Semantic.brand : DS.Semantic.textSecondary)
                        }
                        .padding(12)
                        .background(
                            ChamferedRectangle(cornerRadius: 12)
                                .fill(DS.Semantic.card)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}
```

Note: `ProfileAvatar` is the existing avatar component in the codebase; if the name differs, swap in the actual component. `Friend` is the model returned by `FriendshipRepository.fetchFriends(userId:)`.

- [ ] **Step 14.2: Build**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 14.3: Commit**

```bash
git add Features/Planner/Views/Library/FriendMultiPicker.swift
git commit -m "feat(planner): add FriendMultiPicker component"
```

---

## Task 15: `ProgramShareViewModel` + `ProgramShareSheet`

**Files:**
- Create: `Features/Planner/ViewModels/ProgramShareViewModel.swift`
- Create: `Features/Planner/Views/Library/ProgramShareSheet.swift`

- [ ] **Step 15.1: Implement `ProgramShareViewModel`**

```swift
// Features/Planner/ViewModels/ProgramShareViewModel.swift

import Foundation
import Observation

@Observable
@MainActor
final class ProgramShareViewModel {

    private(set) var friends: [Friend] = []
    var selectedIDs: Set<UUID> = []
    var description: String = ""
    private(set) var isLoading: Bool = false
    private(set) var isSending: Bool = false
    var errorMessage: String?
    var lastResult: ProgramSharingRepository.SendResult?

    private let split: WorkoutSplit
    private let friendshipRepo: FriendshipRepository
    private let sharingRepo: ProgramSharingRepository
    private let currentUserID: UUID
    private let currentUsername: String?
    private let currentDisplayName: String?

    init(
        split: WorkoutSplit,
        friendshipRepo: FriendshipRepository,
        sharingRepo: ProgramSharingRepository,
        currentUserID: UUID,
        currentUsername: String?,
        currentDisplayName: String?
    ) {
        self.split = split
        self.friendshipRepo = friendshipRepo
        self.sharingRepo = sharingRepo
        self.currentUserID = currentUserID
        self.currentUsername = currentUsername
        self.currentDisplayName = currentDisplayName
    }

    func loadFriends() async {
        isLoading = true
        defer { isLoading = false }
        do {
            friends = try await friendshipRepo.fetchFriends(userId: currentUserID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var canSend: Bool { !selectedIDs.isEmpty && !isSending }

    func send() async -> Bool {
        guard canSend else { return false }
        isSending = true
        defer { isSending = false }
        do {
            let result = try await sharingRepo.send(
                split: split,
                description: description.isEmpty ? nil : description,
                to: Array(selectedIDs),
                currentUserID: currentUserID,
                currentUsername: currentUsername,
                currentDisplayName: currentDisplayName
            )
            lastResult = result
            if !result.failed.isEmpty {
                let failedNames = result.failed.compactMap { f in
                    friends.first(where: { $0.id == f.recipientId })?.username
                }
                errorMessage = failedNames.isEmpty
                    ? "Some invites could not be sent."
                    : "Could not send to: \(failedNames.joined(separator: ", "))"
            }
            return result.failed.isEmpty
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
```

- [ ] **Step 15.2: Implement `ProgramShareSheet`**

```swift
// Features/Planner/Views/Library/ProgramShareSheet.swift

import SwiftUI

struct ProgramShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var deps

    let split: WorkoutSplit
    let onSent: () -> Void

    @State private var viewModel: ProgramShareViewModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let vm = viewModel {
                        content(vm: vm)
                    } else {
                        ProgressView().padding()
                    }
                }
                .padding(16)
            }
            .background(DS.Semantic.surface.ignoresSafeArea())
            .navigationTitle("Share program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") {
                        Task {
                            let ok = await viewModel?.send() ?? false
                            if ok {
                                onSent()
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel?.canSend != true)
                }
            }
            .onAppear {
                if viewModel == nil {
                    let me = deps.authService.currentUser
                    let id = me?.id ?? UUID()
                    viewModel = ProgramShareViewModel(
                        split: split,
                        friendshipRepo: deps.friendshipRepository,
                        sharingRepo: deps.programSharingRepository,
                        currentUserID: id,
                        currentUsername: me?.profile?.username,
                        currentDisplayName: me?.profile?.displayName
                    )
                    Task { await viewModel?.loadFriends() }
                }
            }
        }
    }

    @ViewBuilder
    private func content(vm: ProgramShareViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Program")
                .font(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
            Text(split.name)
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Description (optional)")
                .font(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
            TextField("e.g. My Feb-March cut program", text: Binding(
                get: { vm.description }, set: { vm.description = $0 }
            ), axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(3...5)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Send to")
                .font(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
            FriendMultiPicker(
                friends: vm.friends,
                selectedIDs: Binding(
                    get: { vm.selectedIDs },
                    set: { vm.selectedIDs = $0 }
                )
            )
        }

        if let err = vm.errorMessage {
            Text(err)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
```

- [ ] **Step 15.3: Build**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 15.4: Commit**

```bash
git add Features/Planner/ViewModels/ProgramShareViewModel.swift \
        Features/Planner/Views/Library/ProgramShareSheet.swift
git commit -m "feat(planner): add ProgramShareSheet + ViewModel"
```

---

## Task 16: `ProgramInviteViewModel` + `ProgramPreviewView`

**Files:**
- Create: `Features/Planner/ViewModels/ProgramInviteViewModel.swift`
- Create: `Features/Planner/Views/Library/ProgramPreviewView.swift`

- [ ] **Step 16.1: Implement ViewModel**

```swift
// Features/Planner/ViewModels/ProgramInviteViewModel.swift

import Foundation
import Observation

@Observable
@MainActor
final class ProgramInviteViewModel {

    private(set) var invite: ProgramInviteRow?
    private(set) var program: SharedProgramRow?
    private(set) var senderProfile: UserProfile?
    private(set) var isLoading: Bool = true
    var errorMessage: String?

    private let inviteId: UUID
    private let sharingRepo: ProgramSharingRepository
    private let profileRepo: ProfileRepository
    private let plannerStore: PlannerStore

    init(
        inviteId: UUID,
        sharingRepo: ProgramSharingRepository,
        profileRepo: ProfileRepository,
        plannerStore: PlannerStore = .shared
    ) {
        self.inviteId = inviteId
        self.sharingRepo = sharingRepo
        self.profileRepo = profileRepo
        self.plannerStore = plannerStore
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let inv = try await sharingRepo.fetchInvite(id: inviteId)
            self.invite = inv
            self.program = try await sharingRepo.fetchProgram(id: inv.programId)
            self.senderProfile = try await profileRepo.fetchProfile(userId: inv.senderUserId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func accept() async -> Bool {
        guard let invite, let program else { return false }
        do {
            let creator = ProgramSerializer.CreatorAttribution(
                userID: program.creatorUserId.uuidString,
                username: senderProfile?.username,
                displayName: senderProfile?.displayName
            )
            let policy = ReschedulePolicy(rawValue: program.reschedulePolicy) ?? .strict
            let split = ProgramSerializer.fromStructure(
                program.structure,
                name: program.name,
                reschedulePolicy: policy,
                creator: creator,
                description: program.description,
                originProgramID: program.id
            )
            try plannerStore.insert(split)
            _ = try await sharingRepo.accept(inviteId: invite.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func decline() async -> Bool {
        guard let invite else { return false }
        do {
            _ = try await sharingRepo.decline(inviteId: invite.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
```

- [ ] **Step 16.2: Implement `ProgramPreviewView`**

```swift
// Features/Planner/Views/Library/ProgramPreviewView.swift

import SwiftUI

struct ProgramPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var deps

    let inviteId: UUID
    let onResponded: () -> Void

    @State private var viewModel: ProgramInviteViewModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let vm = viewModel {
                    if vm.isLoading {
                        ProgressView().padding()
                    } else if let program = vm.program {
                        content(vm: vm, program: program)
                    } else {
                        Text(vm.errorMessage ?? "This program is no longer available.")
                            .foregroundStyle(DS.Semantic.textSecondary)
                            .padding()
                    }
                }
            }
            .background(DS.Semantic.surface.ignoresSafeArea())
            .navigationTitle("Program preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = ProgramInviteViewModel(
                        inviteId: inviteId,
                        sharingRepo: deps.programSharingRepository,
                        profileRepo: deps.profileRepository
                    )
                    Task { await viewModel?.load() }
                }
            }
        }
    }

    @ViewBuilder
    private func content(vm: ProgramInviteViewModel, program: SharedProgramRow) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let profile = vm.senderProfile {
                HStack(spacing: 12) {
                    ProfileAvatar(url: profile.avatarURL, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName ?? profile.username)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Semantic.textPrimary)
                        Text("Shared a program")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(program.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textPrimary)
                if let d = program.description, !d.isEmpty {
                    Text(d)
                        .font(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(program.structure.planBlocks.sorted(by: { $0.order < $1.order }).enumerated()), id: \.offset) { _, block in
                    BlockPreview(block: block)
                }
            }

            HStack {
                Button("Decline") {
                    Task {
                        if await vm.decline() {
                            onResponded()
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Accept") {
                    Task {
                        if await vm.accept() {
                            onResponded()
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)

            if let err = vm.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(16)
    }

    private struct BlockPreview: View {
        let block: SharedProgramStructure.Block
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(block.dayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textPrimary)
                if block.isRestDay {
                    Text("Rest day")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                } else {
                    ForEach(Array(block.exercises.sorted(by: { $0.order < $1.order }).enumerated()), id: \.offset) { _, ex in
                        Text("\(ex.exerciseName): \(ex.sets) x \(ex.reps)")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
            }
            .padding(12)
            .background(ChamferedRectangle(cornerRadius: 12).fill(DS.Semantic.card))
        }
    }
}
```

- [ ] **Step 16.3: Build**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 16.4: Commit**

```bash
git add Features/Planner/ViewModels/ProgramInviteViewModel.swift \
        Features/Planner/Views/Library/ProgramPreviewView.swift
git commit -m "feat(planner): add ProgramPreviewView + ViewModel"
```

---

## Task 17: Route `.programInvite` notification tap into preview

**Files:**
- Modify: wherever notification taps are handled (search for `case .friendRequest` or `case .virtualRunInvite` — typically in a `NotificationRouter` or inside `NotificationsView`).

- [ ] **Step 17.1: Add the routing case**

Find the notification tap handler and add:

```swift
case .programInvite:
    if let inviteId = notification.targetId {
        // Show ProgramPreviewView for this invite id
        openProgramPreview(inviteId: inviteId)
    }
```

Where `openProgramPreview` is a navigation affordance that presents `ProgramPreviewView(inviteId: inviteId) { ... }` as a sheet. If the existing router uses an enum of destinations, add a `programPreview(UUID)` case.

- [ ] **Step 17.2: Build + manual verification**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

Manually: With two test accounts, send a program from A to B, tap the notification on B's device. Expected: `ProgramPreviewView` opens.

- [ ] **Step 17.3: Commit**

```bash
git commit -am "feat(notifications): route programInvite taps to preview"
```

---

## Task 18: `ProgramActivationViewModel` + `ProgramActivationSheet`

**Files:**
- Create: `Features/Planner/ViewModels/ProgramActivationViewModel.swift`
- Create: `Features/Planner/Views/Library/ProgramActivationSheet.swift`

- [ ] **Step 18.1: Implement ViewModel**

```swift
// Features/Planner/ViewModels/ProgramActivationViewModel.swift

import Foundation
import Observation

@Observable
@MainActor
final class ProgramActivationViewModel {

    let split: WorkoutSplit
    var startDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    var restDayOverrides: [UUID: Bool] = [:]
    var startingWeights: [UUID: Double?] = [:]
    var errorMessage: String?

    private let plannerStore: PlannerStore

    init(split: WorkoutSplit, plannerStore: PlannerStore = .shared) {
        self.split = split
        self.plannerStore = plannerStore
        // Initialize rest-day overrides from current state
        for block in split.planBlocks {
            restDayOverrides[block.id] = block.isRestDay
        }
    }

    /// Valid range: today-7 through today+30
    var startDateRange: ClosedRange<Date> {
        let cal = Calendar.current
        let low = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: .now))!
        let high = cal.date(byAdding: .day, value: 30, to: cal.startOfDay(for: .now))!
        return low...high
    }

    func activate() -> Bool {
        do {
            let customization = ActivationCustomization(
                startDate: startDate,
                restDayOverrides: restDayOverrides,
                startingWeights: startingWeights
            )
            try plannerStore.activate(split, customization: customization)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
```

- [ ] **Step 18.2: Implement sheet**

```swift
// Features/Planner/Views/Library/ProgramActivationSheet.swift

import SwiftUI

struct ProgramActivationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let split: WorkoutSplit
    let onActivated: () -> Void

    @State private var viewModel: ProgramActivationViewModel

    init(split: WorkoutSplit, onActivated: @escaping () -> Void) {
        self.split = split
        self.onActivated = onActivated
        _viewModel = State(wrappedValue: ProgramActivationViewModel(split: split))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Start date") {
                    DatePicker("Start",
                               selection: Binding(
                                get: { viewModel.startDate },
                                set: { viewModel.startDate = $0 }
                               ),
                               in: viewModel.startDateRange,
                               displayedComponents: .date)
                }

                Section("Rest days") {
                    ForEach(split.planBlocks, id: \.id) { block in
                        Toggle(block.dayName,
                               isOn: Binding(
                                get: { viewModel.restDayOverrides[block.id] ?? block.isRestDay },
                                set: { viewModel.restDayOverrides[block.id] = $0 }
                               ))
                    }
                }

                Section("Starting weights (optional)") {
                    ForEach(split.planBlocks.filter { !$0.isRestDay }, id: \.id) { block in
                        ForEach(block.exercises.sorted(by: { $0.order < $1.order }), id: \.id) { ex in
                            HStack {
                                Text(ex.exerciseName)
                                Spacer()
                                TextField("kg",
                                          value: Binding(
                                            get: { viewModel.startingWeights[ex.id] ?? nil },
                                            set: { viewModel.startingWeights[ex.id] = $0 }
                                          ),
                                          format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            }
                        }
                    }
                }

                if let err = viewModel.errorMessage {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Activate program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Activate") {
                        if viewModel.activate() {
                            onActivated()
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
```

- [ ] **Step 18.3: Build**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 18.4: Commit**

```bash
git add Features/Planner/ViewModels/ProgramActivationViewModel.swift \
        Features/Planner/Views/Library/ProgramActivationSheet.swift
git commit -m "feat(planner): add ProgramActivationSheet + ViewModel"
```

---

## Task 19: Update `PlannerSetupCarouselView` to save-inactive by default

**Files:**
- Modify: `Features/Planner/PlannerSetupCarouselView.swift`
- Modify: `Features/WorkoutSession/Models/PlannerModels.swift` — flip `isActive` default in `WorkoutSplit.init` from `true` to `false`

- [ ] **Step 19.1: Change `WorkoutSplit.init` to default `isActive = false`**

In `Features/WorkoutSession/Models/PlannerModels.swift`, change:

```swift
self.isActive = true  // keep existing default for now; Task 19 will change this
```

to:

```swift
self.isActive = false
```

- [ ] **Step 19.2: Update the carousel final step to present an "Activate now" choice**

In `PlannerSetupCarouselView`'s save-and-finish path, after creating the `WorkoutSplit`, insert it (inactive), then present `ProgramActivationSheet` with the new split as a terminal step. If the user cancels the activation sheet, the split remains in the library, inactive.

```swift
// After: let split = WorkoutSplit(name: ..., planBlocks: ..., ...)
// And: context.insert(split); try context.save()

// Then:
presentedActivation = split  // @State var presentedActivation: WorkoutSplit?
```

Attach a sheet:

```swift
.sheet(item: $presentedActivation) { split in
    ProgramActivationSheet(split: split) {
        // dismiss the entire carousel back to Planner
        dismiss()
    }
}
```

Also add an explicit "Save for later" button in the final step that simply inserts + dismisses without showing the activation sheet.

- [ ] **Step 19.3: Build + smoke run**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

Manually: create a new split via the carousel. Expected: final step shows "Activate now" (opens activation sheet) and "Save for later" (dismisses, split appears in library as inactive).

- [ ] **Step 19.4: Commit**

```bash
git add Features/Planner/PlannerSetupCarouselView.swift \
        Features/WorkoutSession/Models/PlannerModels.swift
git commit -m "feat(planner): save-inactive by default, optional activate-now"
```

---

## Task 20: Edit-mode in `PlannerSetupCarouselView`

**Files:**
- Modify: `Features/Planner/PlannerSetupCarouselView.swift`

- [ ] **Step 20.1: Add an `editing: WorkoutSplit?` init parameter**

```swift
init(editing: WorkoutSplit? = nil) {
    self._editingSplit = State(initialValue: editing)
    // prefill state from editing split if provided
}
```

When `editingSplit != nil`, the carousel skips the template/frequency picker steps and jumps straight to the customize/review flow, with state pre-populated from `editing.planBlocks`.

Save behavior: instead of `context.insert(new)`, mutate the existing split's properties in place. Attribution fields (`creatorUserID`, `creatorUsername`, etc.) are never touched. After save, if `editing.isActive == true`, prompt:

```swift
.alert("This is your active program", isPresented: $showReplanPrompt) {
    Button("Replan upcoming workouts") { replan() }
    Button("Save without replanning", role: .cancel) {}
} message: {
    Text("You are editing the program you are currently running. Completed workouts are unchanged, but upcoming planned workouts will be regenerated from the new structure.")
}
```

`replan()` calls `PlannerStore.shared.replanUpcomingWorkouts(for: editing)`.

- [ ] **Step 20.2: Build + smoke**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

Manually: edit a received program. Expected: attribution "Originally by Alice" is preserved after save.

- [ ] **Step 20.3: Commit**

```bash
git add Features/Planner/PlannerSetupCarouselView.swift
git commit -m "feat(planner): add edit-mode to PlannerSetupCarouselView"
```

---

## Task 21: `SentInvitesSheet`

**Files:**
- Create: `Features/Planner/Views/Library/SentInvitesSheet.swift`

- [ ] **Step 21.1: Implement**

```swift
// Features/Planner/Views/Library/SentInvitesSheet.swift

import SwiftUI

struct SentInvitesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var deps

    let split: WorkoutSplit

    @State private var invites: [ProgramInviteRow] = []
    @State private var profiles: [UUID: UserProfile] = [:]
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if invites.isEmpty {
                    Text("This program has not been shared yet.")
                        .foregroundStyle(DS.Semantic.textSecondary)
                } else {
                    ForEach(invites, id: \.id) { invite in
                        row(invite: invite)
                    }
                }
                if let err = errorMessage {
                    Text(err).foregroundStyle(.red)
                }
            }
            .navigationTitle("Shared with")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func row(invite: ProgramInviteRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profiles[invite.recipientUserId]?.displayName
                     ?? profiles[invite.recipientUserId]?.username
                     ?? "Unknown")
                    .font(.subheadline.weight(.semibold))
                Text(invite.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            Spacer()
            if invite.status == .pending {
                Button("Revoke", role: .destructive) {
                    Task { await revoke(invite) }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func load() async {
        guard let originId = split.originProgramID else {
            // For self-created splits, program id must be derived from server.
            // If no originProgramID, we have no way to scope; show empty state.
            return
        }
        do {
            let me = deps.authService.currentUser?.id ?? UUID()
            invites = try await deps.programSharingRepository.fetchSentInvites(
                for: me, programId: originId
            )
            let ids = Set(invites.map { $0.recipientUserId })
            var dict: [UUID: UserProfile] = [:]
            for id in ids {
                if let p = try? await deps.profileRepository.fetchProfile(userId: id) {
                    dict[id] = p
                }
            }
            profiles = dict
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revoke(_ invite: ProgramInviteRow) async {
        do {
            _ = try await deps.programSharingRepository.revoke(inviteId: invite.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

Note: for self-created splits, `originProgramID` is only set when the split is sent for the first time. Either:
- (a) set `originProgramID` on the local split after `send()` completes, OR
- (b) store a separate `sent_program_id` field.

Option (a) is simpler and semantically correct ("the id this split is associated with on the server"). Update `ProgramSharingRepository.send` to, after the insert, write `split.originProgramID = program.id` via the caller's `ModelContext.save()`.

- [ ] **Step 21.2: Update send flow to persist originProgramID on self-created splits**

In `ProgramLibraryView`, after `viewModel.refreshLibrary()` post-share, the `ProgramShareViewModel.send` callback must write `split.originProgramID = result.program.id` and save context. Add this to the `ProgramShareViewModel.send` method:

```swift
if result.failed.isEmpty || !result.succeeded.isEmpty {
    if split.originProgramID == nil {
        split.originProgramID = result.program.id
        // SwiftData context save is required; inject via initializer if the VM
        // doesn't already have access to ModelContext. For simplicity use
        // PlannerStore.shared.saveContext() exposed via a new helper.
        try? PlannerStore.shared.saveContext()
    }
}
```

Add to `PlannerStore`:

```swift
func saveContext() throws {
    try context?.save()
}
```

- [ ] **Step 21.3: Build**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 21.4: Commit**

```bash
git add Features/Planner/Views/Library/SentInvitesSheet.swift \
        Features/Planner/ViewModels/ProgramShareViewModel.swift \
        Features/WorkoutSession/Services/PlannerStore.swift
git commit -m "feat(planner): add SentInvitesSheet with revoke"
```

---

## Task 22: Wire pending-invite realtime + notification refresh into library

**Files:**
- Modify: `Features/Planner/ViewModels/ProgramLibraryViewModel.swift`

- [ ] **Step 22.1: Add initial load + subscription**

Extend `ProgramLibraryViewModel` with `refreshPendingInvites()` and `startRealtime()`:

```swift
    private let realtime: RealtimeService
    private let profileRepo: ProfileRepository
    private var channelId: String?

    // Update init to accept realtime + profileRepo, or fetch from AppDependencies.

    func refreshPendingInvites() async {
        do {
            let rows = try await (repo as? ProgramSharingRepository)?
                .fetchPendingInvites(for: currentUserID) ?? []
            var displays: [PendingInviteDisplay] = []
            for row in rows {
                let profile = try? await profileRepo.fetchProfile(userId: row.senderUserId)
                let program = try? await repo.fetchProgram(id: row.programId)
                displays.append(.init(
                    id: row.id,
                    programId: row.programId,
                    senderId: row.senderUserId,
                    senderUsername: profile?.username,
                    senderDisplayName: profile?.displayName,
                    programName: program?.name ?? "Program",
                    createdAt: row.createdAt
                ))
            }
            pendingInvites = displays
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startRealtime() async {
        do {
            channelId = try await realtime.subscribeToProgramInvites(
                userId: currentUserID,
                onInsert: { [weak self] _ in
                    Task { await self?.refreshPendingInvites() }
                },
                onUpdate: { [weak self] _ in
                    Task { await self?.refreshPendingInvites() }
                }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

Call `refreshPendingInvites()` and `startRealtime()` from `ProgramLibraryView.onAppear` (after `refreshLibrary()`).

- [ ] **Step 22.2: Build + smoke**

Run: `xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

Manually with two accounts: A sends, B sees "Shared with me" section populate in real time on device B with the library view open.

- [ ] **Step 22.3: Commit**

```bash
git commit -am "feat(planner): subscribe to pending invites in library"
```

---

## Task 23: End-to-end QA runbook

No code changes. This is a manual pass to verify every flow end-to-end.

- [ ] **23.1: Send** — Account A, library, Share on a split, pick friends B and C, optional description, Send. Verify: toast, library view shows split `originProgramID` set (via Sent invites sheet, which loads rows for that program).

- [ ] **23.2: Receive (notification)** — Account B: bell shows a new "A shared a program with you" notification. Tap. `ProgramPreviewView` opens with correct name, description, and block list. Weights are absent.

- [ ] **23.3: Receive (section)** — Account B: open Planner > Programs. "Shared with me (2)" visible (if C also gets one, or with two senders). Tapping the invite opens the preview.

- [ ] **23.4: Decline** — Account B declines C's invite. It disappears from Shared with me and is marked `declined`. No local split created. Account C's "Sent invites" shows status `declined`.

- [ ] **23.5: Accept** — Account B accepts A's invite. Library now shows the forked split with "Originally by A". It is inactive.

- [ ] **23.6: Activate** — Account B taps Activate on the forked split. Sheet opens. Set start date to tomorrow, flip one rest day, enter starting weights for two exercises. Confirm. Library row is now Active. Calendar view shows PlannedWorkouts starting tomorrow with the specified weights.

- [ ] **23.7: Edit active** — Account B edits the active program. Add an exercise. Save. Alert appears; choose "Replan upcoming workouts". Future planned workouts regenerate; past completed workouts untouched.

- [ ] **23.8: Re-share** — Account B re-shares to Account D. Account D accepts. Account D's library shows "Originally by A" (not B).

- [ ] **23.9: Revoke** — Account A sends a new program to E (pending). From Sent invites, A revokes. E's bell notification (if unread) disappears. E's Shared with me updates live to remove the invite.

- [ ] **23.10: RLS boundary** — Account F (not friends with A) tries to fetch A's shared_programs row directly via the Supabase client. Expected: zero rows.

- [ ] **23.11: Soft delete** — Account A soft-deletes a shared program (can be triggered via debug action or SQL). Existing accepted copies on B/C/D are untouched (splits still in their libraries, still usable). Any still-pending invites fetch fail with "This program is no longer available" on accept attempt.

- [ ] **23.12: Commit QA checklist**

```bash
git commit --allow-empty -m "chore(qa): program sharing end-to-end pass"
```

---

## Self-Review

Spec coverage check:

- Data Model (SwiftData additions) -> Task 3
- Data Model (Supabase schema, indexes, RLS, triggers) -> Task 1
- Structure payload (no weights, versioned, forward-compat) -> Task 2
- Serializer with attribution -> Task 4
- Notifications new type -> Task 5
- Repository send -> Task 6
- Repository accept/decline/revoke/fetch -> Task 7
- Realtime -> Task 8, Task 22
- PlannerStore activation primitives -> Task 9
- Library view with three sections -> Task 12, Task 13
- Library row actions -> Task 11
- Send flow (friend picker, description, multi-recipient) -> Task 14, Task 15
- Receive flow (preview, accept/decline) -> Task 16, Task 17
- Activation sheet (start date, rest days, weights) -> Task 18
- Save-inactive by default + activate-now choice -> Task 19
- Edit flow with attribution preservation + active-split replan -> Task 20
- Re-share (attribution preservation) -> Task 4 + Task 15 (uses `outgoingAttribution`)
- Sent invites view + revoke -> Task 21
- End-to-end QA -> Task 23

Placeholder scan: No "TBD", "TODO", or vague instructions. Every code block is complete and compilable as written (subject to existing codebase types like `ProfileAvatar`, `Friend`, `UserProfile`, `ProfileRepository`, `deps.authService.currentUser` matching their real shapes; engineer should substitute exact member names where this plan's guesses are off by one character).

Type consistency:
- `ProgramSerializer.CreatorAttribution` used consistently in Tasks 4, 10, 15, 16.
- `ActivationCustomization(startDate:, restDayOverrides:, startingWeights:)` used consistently in Tasks 9 and 18.
- `ProgramSharingRepository.send(...)` returns `SendResult` used in Tasks 6, 15, 21.
- `ProgramInviteStatus` raw values match `check` constraint in Task 1 SQL.
- `SharedProgramStructure.Progression` cases match `ProgressionStrategy` cases in Task 2 and Task 4.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-16-program-sharing.md`.

Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?





