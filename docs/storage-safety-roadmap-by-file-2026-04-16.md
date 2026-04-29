# WRKT Storage Safety Roadmap By File

Date: 2026-04-16

This roadmap turns the storage-safety plan into concrete implementation phases with exact files and intended outcomes.

## Phase 1: Rebuildable SwiftData Hardening

Goal:

- make low-value operational SwiftData models disposable
- prevent queue/cache model issues from threatening app startup or durable user history

### 1. `Features/Health/Models/HealthSyncAnchor.swift`

Models:

- `HealthSyncAnchor`
- `RouteFetchTask`
- `MapSnapshotCache`

Edits:

- keep new fields optional/default-safe unless explicit migration exists
- document these as rebuildable operational models
- avoid adding required persisted fields without migration review

Risk:

- low, if changes remain backward-compatible

### 2. `Features/Health/Services/HealthKitManager.swift`

Goal:

- make route queue, snapshot cache, and anchor usage explicitly repairable

Edits:

- add operational-state repair entry point, e.g. `repairOperationalHealthStateIfNeeded()`
- if route task set is missing/stale/incompatible:
  - recreate from `Run.needsHistoricalEnrichment`
- allow safe anchor reset path for `HealthSyncAnchor`
- keep rebuild idempotent
- keep rebuild tasks `allowAutoPost = false` by default unless explicitly new-content flow

Risk:

- medium
- main risk is duplicate enrichment work, not durable data loss

### 3. `Features/WorkoutSession/Services/WorkoutStoreV2.swift`

Goal:

- ensure startup can trigger safe operational repair after durable local data loads

Edits:

- after loading runs/workouts/current workout, call into a repair path for rebuildable cardio operational state
- preserve current durable data recovery behavior for completed workouts

Risk:

- low to medium
- startup timing and extra background work need watching

### 4. `App/WRKTApp.swift`

Goal:

- make app-level persistence policy explicit

Edits:

- add comments or small orchestration note distinguishing:
  - durable models in main schema
  - rebuildable operational models
- optional future split:
  - separate SwiftData containers for operational vs durable models

Risk:

- low if documentation/orchestration only
- higher if container split is attempted now

## Phase 2: Extend Local Backup Coverage

Goal:

- protect cardio history more like completed workout history

### 5. `Core/Persistence/WorkoutStorage.swift`

Goal:

- completed: `runs_v2.json` now has rotating backup + startup auto-recovery

Edits:

- added backup file naming for runs
- added debounced backup creation before `saveRuns(_:)`
- added `loadMostRecentNonEmptyRunsBackup()`
- startup can now recover runs from latest non-empty backup when main runs file exists but loads empty

Risk:

- medium
- touches durable local data path
- should be done carefully and tested with existing real files

### 6. `Features/WorkoutSession/Services/WorkoutStoreV2.swift`

Goal:

- completed: startup auto-recovery for runs now mirrors completed workout history

Edits:

- if runs file exists but decodes empty unexpectedly, restore from latest non-empty runs backup
- recovery remains narrow and does not trigger for brand-new empty installs

Risk:

- medium
- must avoid restoring stale runs over intentional user deletion/reset

## Phase 3: Persistence Guardrails In Repo

Goal:

- stop future mistakes before they ship

### 7. `docs/storage-safety-plan-2026-04-16.md`

Edits:

- keep as authoritative storage policy doc
- update when persistence surfaces change

### 8. New repo checklist doc

Suggested file:

- `docs/persistence-change-checklist.md`

Contents:

1. Is this persisted data?
2. Is it durable or rebuildable?
3. If durable, is the change backward-compatible?
4. If not, what migration handles it?
5. If rebuildable, can it be safely wiped and recreated?
6. Did we test against an existing local store?
7. Could this trigger duplicate posts, duplicate rewards, or silent resets?

Risk:

- very low

## Phase 4: Longer-Term Structural Improvements

Goal:

- reduce blast radius of future persistence mistakes

### 9. `App/WRKTApp.swift`

Future option:

- split SwiftData into:
  - durable domain container
  - rebuildable operational/cache container

Why:

- operational schema breakage should not threaten durable domain storage

Risk:

- high
- do not do this casually

### 10. `Core/Persistence/WorkoutStorage.swift` and export/import surface

Future option:

- add user-visible export/restore for:
  - completed workouts
  - runs
  - planner

Why:

- strongest protection against local corruption/device-loss mistakes

Risk:

- medium to high depending on format and UX

## Recommended Execution Order

1. `HealthSyncAnchor.swift`
2. `HealthKitManager.swift`
3. `WorkoutStoreV2.swift`
4. add persistence checklist doc
5. decide whether `current_workout_v2.json` should also get backup/recovery

## Best First Task

If you want the best next hardening step with manageable risk:

- Phase 1 is already the best completed hardening step
- next best is persistence checklist + deciding whether current workout needs backup/recovery

Why:

- it reduces future persistence mistakes without touching more durable data immediately
