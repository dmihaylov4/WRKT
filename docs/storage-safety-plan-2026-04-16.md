# WRKT Storage Safety Plan

Date: 2026-04-16

## Goal

Reduce the chance of user data loss caused by local persistence mistakes, schema changes, or partial startup failures.

This plan separates WRKT persistence into:

- durable data: must survive upgrades and app mistakes
- rebuildable data: can be wiped/recreated from durable sources

## Current Persistence Surfaces

### File-based local storage

Managed by `WorkoutStorage`:

- `workouts_v2.json`
  - completed workouts
  - PR index
- `runs_v2.json`
  - cardio / HealthKit runs
- `current_workout_v2.json`
  - active in-progress workout
- `ignored_healthkit_uuids.json`
- `discarded_workout_windows.json`

### SwiftData local storage

Main app container currently includes:

- planner:
  - `PlannedWorkout`
  - `PlannedExercise`
  - `WorkoutSplit`
  - `PlanBlock`
  - `PlanBlockExercise`
- cardio operational state:
  - `HealthSyncAnchor`
  - `RouteFetchTask`
  - `MapSnapshotCache`
- rewards/progression:
  - `EarnedPlate`
  - `BarbellConfig`
  - `RewardProgress`
  - `Achievement`
  - `ChallengeAssignment`
  - `RewardLedgerEntry`
  - `Wallet`
- profile/goals/stats caches:
  - `WeeklyGoal`
  - `ExercisePR`
  - `DexStamp`
  - stats summary models in `Features/Statistics/Models/StatModels.swift`
- local cache-style models:
  - `CachedPost`
  - `CachedProfile`
  - `CachedNotification`

### Remote durable storage

Primary durable remote content lives in Supabase:

- posts
- comments
- likes
- friendships / social graph
- remote profile data
- other social/domain entities stored there

## Classification

## Durable Data

These should be treated as migration-sensitive and user-history-critical.

### Durable local

- `CompletedWorkout`
- PR index in `workouts_v2.json`
- `Run` / `runs_v2.json`
- `CurrentWorkout` if you consider crash recovery important
- planner models:
  - `PlannedWorkout`
  - `PlannedExercise`
  - `WorkoutSplit`
  - `PlanBlock`
  - `PlanBlockExercise`
- rewards/progression:
  - `EarnedPlate`
  - `BarbellConfig`
  - `RewardProgress`
  - `Achievement`
  - `ChallengeAssignment`
  - `RewardLedgerEntry`
  - `Wallet`
- user goal state:
  - `WeeklyGoal`

### Durable remote

- Supabase posts
- comments
- likes
- social/profile records

## Rebuildable Data

These should never be able to put the app into a broken state if lost or reset.

- `RouteFetchTask`
- `MapSnapshotCache`
- `HealthSyncAnchor` (with care; reset should trigger safe re-sync)
- local cached social models:
  - `CachedPost`
  - `CachedProfile`
  - `CachedNotification`
- most derived stats summary models if they can be recomputed from durable workout history

## Best-Practice Rules For WRKT

### Rule 1: Persisted durable models are compatibility surfaces

For durable persisted data:

- do not add new required fields casually
- prefer optional/default-safe additions
- use explicit migration/versioning for breaking changes
- test against an existing store, not just clean install

### Rule 2: Rebuildable models should be disposable

For rebuildable models:

- app should tolerate wipe/reset
- startup repair should be allowed
- missing rows should trigger rebuild, not user-visible failure

### Rule 3: User history must not depend on operational queue state

Examples:

- route enrichment should be derivable from `Run + healthKitUUID`
- snapshot cache should be recreatable from route data
- sync anchors should be resettable with safe re-import behavior

## Current Strengths

- `workouts_v2.json` writes are atomic
- completed workouts + PR index have rotating backups
- `runs_v2.json` now has rotating backups plus startup auto-recovery
- startup auto-recovery exists when main workout file is present but empty
- local migration from legacy storage exists
- app has ModelContainer fallback path instead of hard crash

## Current Gaps

### 1. `current_workout_v2.json` has no rotating backup path

Risk:

- active session recovery depends on single-file atomic write only

### 2. SwiftData durable models do not have an explicit migration policy in repo

Risk:

- future incompatible field changes can break store opening

### 3. Rebuildable SwiftData models are not explicitly repaired on startup yet

Risk:

- queue/cache models still rely too much on schema stability

## Recommended Hardening Order

### Phase 1: Guardrails

- keep persisted SwiftData field additions backward-compatible by default
- require explicit user notification/review before adding required persisted fields
- add a repo note/checklist for persistence-safe changes

### Phase 2: Rebuildable SwiftData hardening

Make these explicitly disposable:

- `RouteFetchTask`
- `MapSnapshotCache`
- `HealthSyncAnchor`

Implementation direction:

- add startup validation/repair
- if rows are missing, stale, or incompatible:
  - clear them
  - rebuild from durable data

Examples:

- rebuild `RouteFetchTask` from `Run.needsHistoricalEnrichment`
- clear `MapSnapshotCache` and regenerate snapshots on demand
- reset `HealthSyncAnchor` and re-run safe sync path

### Phase 3: Extend backup coverage for durable local files

Strong candidate:

- decide whether `current_workout_v2.json` also deserves rotating backup + restore

Optional:

- keep current-workout recovery as atomic-only if you do not want extra complexity there

### Phase 4: User-facing export/restore

Best long-term protection:

- export local workout history
- export cardio history
- import/restore path

This is stronger than relying only on hidden local backups.

## Concrete Recommendations

### Recommendation A

Do next:

- make `RouteFetchTask`, `MapSnapshotCache`, and `HealthSyncAnchor` explicitly rebuildable

Why:

- highest leverage for reducing future SwiftData operational breakage
- lower risk than changing durable domain models

### Recommendation B

Do after that:

- decide whether `current_workout_v2.json` also deserves rotating backup/recovery

Why:

- this is now the main remaining local-file durability gap

### Recommendation C

Do before more persistence-heavy feature work:

- add a short repo checklist for schema-safe changes

Suggested checklist:

1. Is this persisted?
2. Is it durable or rebuildable?
3. If durable, is the change backward-compatible?
4. If not backward-compatible, what is the migration?
5. If rebuildable, can it be wiped and recreated safely?
6. Did we test with an existing local store?

## Short Version

- durable data should be migrated carefully
- rebuildable data should be wipeable/recreatable
- WRKT already protects completed workout history reasonably well
- WRKT should next harden rebuildable SwiftData queue/cache models and add better protection for runs
