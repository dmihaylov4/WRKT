# Plan View Deep Dive

Date: 2026-04-14

## Scope

For this review, "Plan View" includes:

- tab entry: `Features/Plan/PlanView.swift`
- calendar shell and coordination: `Features/Planner/CalendarMonthView.swift`
- day actions and plan cards: `Features/Planner/Components/DayActionCard.swift`, `Features/Planner/Components/PlannedWorkoutComponents.swift`, `Features/Planner/Components/DayDetailView.swift`, `Features/Planner/Components/CalendarGrid.swift`
- planner setup flow: `Features/Planner/PlannerSetupCarouselView.swift`
- planned workout editor: `Features/Planner/Views/PlannedWorkoutEditor.swift`
- planner domain model/store: `Features/WorkoutSession/Models/PlannerModels.swift`, `Features/WorkoutSession/Services/PlannerStore.swift`
- workout handoff into Train: `Features/WorkoutSession/Services/WorkoutStoreV2.swift`

## High-Level Read

Plan View has good product shape:

- one place for calendar, streaks, today actions, future planning, and retrospective logging
- supports both split-based plans and one-off planned workouts
- tries to connect planner with Train and HealthKit

Main problem: planner state model is split between:

- SwiftData models
- `PlannerStore`
- `CalendarMonthView` local caches/state
- `WorkoutStoreV2`
- `NotificationCenter`
- ad hoc UI-derived completion checks

Result:

- some planner features look complete in UI but are not actually closed-loop in data
- several paths mutate planner indirectly or not at all
- Plan View is doing too much orchestration inside a single SwiftUI view

## Current Flow Map

1. Plan tab mounts `CalendarMonthView` through `PlanView`: `Features/Plan/PlanView.swift:10-15`
2. Calendar owns month navigation, cache invalidation, HealthKit refresh, tutorial overlays, sheets, and day-action routing:
   - `Features/Planner/CalendarMonthView.swift:32-1024`
3. Split creation/editing goes through `PlannerSetupCarouselView`: `Features/Planner/PlannerSetupCarouselView.swift:12-563`
4. One-off/future-day planning goes through `PlannedWorkoutEditor`: `Features/Planner/Views/PlannedWorkoutEditor.swift:11-277`
5. Planned workout "start" ultimately needs to create `CurrentWorkout` via `WorkoutStoreV2.startPlannedWorkout(...)`: `Features/WorkoutSession/Services/WorkoutStoreV2.swift:232-264`
6. Planned workout completion should be reconciled by `PlannerStore.completePlannedWorkout(...)`: `Features/WorkoutSession/Services/PlannerStore.swift:195-226`

## What Is Working Well

### 1. Planner product coverage is broad

Planner supports:

- split generation
- future-day workout planning
- today quick actions
- retrospective logging
- plan-aware visual calendar cells

This is strong feature coverage for one tab.

### 2. Calendar tries to avoid obvious N-query issues

`CalendarMonthView` precomputes day stats and week progress:

- `Features/Planner/CalendarMonthView.swift:218-250`
- `Features/Planner/CalendarMonthView.swift:693-799`

Intent is good. Performance concern is not lack of care. It is too much view-owned cache orchestration.

### 3. Planned workout handoff into Train already exists

`PlannedWorkoutCard` can correctly start a planned workout and jump into live workout:

- `Features/Planner/Components/PlannedWorkoutComponents.swift:279-282`

That path is directionally right.

## Findings

### Critical 1. Today’s planned workout "Start" button does not start planned workout

In `DayActionCard`, when today has a planned workout, tapping "Start" does this:

- `Features/Planner/Components/DayActionCard.swift:193-208`

```swift
selectedAction = .startWorkout(date)
```

Then `CalendarMonthView.handleDayAction` handles `.startWorkout` by showing generic workout type selector:

- `Features/Planner/CalendarMonthView.swift:1009-1014`

That means user does **not** start the actual planned workout. They start generic quick-start flow instead.

Impact:

- today plan CTA breaks planner-to-train continuity
- planned ghost sets are bypassed
- completed workout may not carry `plannedWorkoutID`
- adherence/completion metrics become unreliable

Recommendation:

- introduce explicit `DayAction.startPlannedWorkout(PlannedWorkout)`
- today planned workout CTA should call `store.startPlannedWorkout(planned)` directly, same as `PlannedWorkoutCard`

### Critical 2. Planned workout completion lifecycle is disconnected

`PlannerStore.completePlannedWorkout(...)` exists:

- `Features/WorkoutSession/Services/PlannerStore.swift:195-226`

But I could not find a production call site. `rg` only finds definition.

Meanwhile workout completion in `WorkoutStoreV2.finishCurrentWorkout()`:

- `Features/WorkoutSession/Services/WorkoutStoreV2.swift:312-360`

creates `CompletedWorkout` with `plannedWorkoutID`, but never updates `PlannedWorkout` status, completion percentage, actual volume, or rolling cursor.

Impact:

- planner data model and workout history drift apart
- status stays stale unless UI infers completion from history
- split progression logic for rolling plans never truly closes loop

Recommendation:

- on workout finish, if `plannedWorkoutID != nil`, resolve matching `PlannedWorkout` and call one authoritative planner completion method
- planner completion should be part of workout finish transaction, not optional later cleanup

### Critical 3. Plan UI mixes persisted planner state with history-derived completion state

`PlannedWorkoutCard` computes completion from workout history:

- `Features/Planner/Components/PlannedWorkoutComponents.swift:22-24`

and then overrides displayed badge/text even if `planned.workoutStatus` says something else:

- `Features/Planner/Components/PlannedWorkoutComponents.swift:26-53`

Impact:

- UI may look "correct" while `PlannedWorkout.workoutStatus` remains stale
- planner history and planner model can diverge
- downstream features depending on `PlannedWorkout.status` can still be wrong

Recommendation:

- use derived-completion fallback only as temporary guard
- fix source of truth first
- planner status should not need to be cosmetically patched in UI

### High 4. Editing planned workouts erases data

`PlannedWorkoutEditor.loadExistingWorkout()` loads `notes`:

- `Features/Planner/Views/PlannedWorkoutEditor.swift:205-219`

But `savePlannedWorkout()` rebuilds `PlannedExercise` like this:

- `Features/Planner/Views/PlannedWorkoutEditor.swift:221-232`

with:

- `progressionStrategy: .static`
- no `notes`
- no `lastPerformance`

Impact:

- editing existing planned workout can silently drop progression strategy
- notes are lost
- contextual history is lost

Recommendation:

- preserve all editable and non-editable fields when round-tripping existing planned exercises
- avoid rebuilding full child model when only some fields changed

### High 5. `CalendarMonthView` is a god view

This single view owns:

- month navigation
- swipe gestures
- day selection
- planned workout loading
- HealthKit pull-to-refresh
- auto-sync
- week progress cache
- day stats cache
- streak cache
- tutorial frame capture
- routing to four different flows

See:

- `Features/Planner/CalendarMonthView.swift:32-250`
- `339-640`
- `693-1024`

Impact:

- hard to reason about correctness
- hard to test small planner behaviors
- state invalidation bugs become likely
- user edits in calendar can interact with unrelated cache logic

Recommendation:

- split into:
  - `CalendarViewModel` / coordinator
  - `CalendarDataProvider`
  - `CalendarTutorialController`
  - pure rendering views for header/grid/day detail

### High 6. Planner creation logic is duplicated and bypasses `PlannerStore.createSplit`

`PlannerStore.createSplit(...)` exists:

- `Features/WorkoutSession/Services/PlannerStore.swift:31-41`

But `PlannerSetupCarouselView.generatePlan()` inserts `WorkoutSplit` directly, saves context directly, then separately calls `plannerStore.generatePlannedWorkouts(...)`:

- `Features/Planner/PlannerSetupCarouselView.swift:440-528`

Impact:

- duplicate split-creation logic
- planner invariants can drift between entry points
- store abstraction becomes partial and unreliable

Recommendation:

- move split creation/edit/replace logic behind `PlannerStore`
- UI should not know insert/save/generate sequence

### High 7. Multiple active splits are possible

`activeSplit()` fetches first active split:

- `Features/WorkoutSession/Services/PlannerStore.swift:305-311`

No uniqueness enforcement exists in model:

- `Features/WorkoutSession/Models/PlannerModels.swift:194-243`

`PlannerSetupCarouselView.generatePlan()` only deactivates `existingSplit` if one was loaded into local UI state:

- `Features/Planner/PlannerSetupCarouselView.swift:493-497`

Impact:

- multiple active splits can exist if state is stale, imported, debug-created, or created from another path
- "first active split wins" is non-deterministic business logic

Recommendation:

- enforce single-active-split invariant in `PlannerStore`
- before activating new split, deactivate all others in one transaction

### Medium 8. Planner policies are only partially implemented

`WorkoutSplit.planBlock(for:cursor:)`:

- strict: date-based
- rolling: cursor-based
- flexible: placeholder comment saying more complex logic required

See:

- `Features/WorkoutSession/Models/PlannerModels.swift:220-243`

Problem:

- `generatePlannedWorkouts(for:days:)` loops every date and asks `planBlock(for: date, cursor: split.cursor)`:
  - `Features/WorkoutSession/Services/PlannerStore.swift:43-83`

For rolling/flexible, this can produce same block repeatedly across dates because cursor does not advance during generation.

Impact:

- planner model claims support for policies not fully implemented
- future expansion will likely break fast unless model/store contract is redesigned

Recommendation:

- either restrict production UI to `.strict` explicitly
- or redesign generation semantics for rolling/flexible before exposing them

### Medium 9. `CalendarMonthView` cache pipeline is complex and potentially stale

Examples:

- 100ms debounce: `Features/Planner/CalendarMonthView.swift:632-640`
- detached background recompute over captured snapshots: `693-799`
- manual reload notifications: `481-484`, `817-842`

Impact:

- stale cache windows are possible during rapid edits/month changes
- debugging visual mismatches will be painful
- detached task ordering can race with later state changes

Recommendation:

- centralize cache generation in one cancelable view model task
- key results by month + data version
- avoid detached tasks inside view where possible

### Medium 10. Planner still relies on `NotificationCenter` for local data refresh

Examples:

- post reload from editor: `Features/Planner/Views/PlannedWorkoutEditor.swift:257-258`, `271-272`
- post reload from planned workout delete: `Features/Planner/Components/PlannedWorkoutComponents.swift:290-291`
- receive reload in calendar/day detail:
  - `Features/Planner/CalendarMonthView.swift:481-484`
  - `Features/Planner/Components/DayDetailView.swift:202-203`

Impact:

- implicit coupling
- hard to trace update flow
- easy to miss a refresh path

Recommendation:

- use SwiftData query-driven refresh where possible
- otherwise move updates through explicit planner coordinator/store

### Low 11. `DayActionCard` API already shows planner/UI drift

`hasCompletedWorkouts` is passed in:

- `Features/Planner/Components/DayActionCard.swift:13`

but not used in behavior.

Impact:

- small signal, but indicates feature rules changed and API did not get cleaned up

Recommendation:

- remove dead inputs or use them intentionally

## Efficiency Opportunities

### 1. Make planner transactional

Planner operations should be single transactions:

- create split
- replace split
- generate workouts
- start planned workout
- complete planned workout
- delete planned workout

Right now those operations are fragmented across views and stores.

### 2. Introduce one planner source of truth

Good target:

- `PlannerStore` owns all plan mutations
- `CalendarViewModel` owns all calendar-derived caches and routing
- views render only

### 3. Stop mixing persisted truth with UI-derived truth

Examples to fix:

- planned completion shown from `completedWorkouts.contains { plannedWorkoutID == planned.id }`
- planned status separately stored in `PlannedWorkout.status`

This needs one canonical rule.

### 4. Separate split plans from one-off planned workouts

Current model mixes:

- generated split-based workouts
- ad hoc manually planned future workouts

That is workable, but lifecycle rules differ. Handoff and completion logic will stay messy until those rules are explicit.

## Suggested Refactor Order

### Phase 1: correctness first

1. Fix today planned workout start path
2. Wire `finishCurrentWorkout()` into `PlannerStore.completePlannedWorkout(...)`
3. Fix `PlannedWorkoutEditor` round-trip data loss
4. Enforce single-active-split invariant

### Phase 2: planner architecture

1. move all split creation/replacement into `PlannerStore`
2. remove `NotificationCenter`-based local refresh where SwiftData/query can handle it
3. split `CalendarMonthView` responsibilities

### Phase 3: policy / future-proofing

1. either fully implement rolling/flexible policies or mark them unsupported
2. formalize relationship between split-generated and ad hoc planned workouts

## Bottom Line

Plan View is useful and feature-rich, but data lifecycle is not fully trustworthy yet.

Best summary:

- UI breadth: strong
- domain closure: incomplete
- ownership boundaries: weak
- correctness risk: real, especially around starting/completing planned workouts

If I were choosing only three fixes first, I would do:

1. fix today planned workout start path
2. complete planned workout lifecycle on workout finish
3. stop editor from erasing plan data

---

## Review

Date reviewed: 2026-04-15

### Verified as accurate

**Critical 1 -- DayActionCard "Start" drops planned workout context**: Confirmed. `DayActionCard.swift:195` fires `.startWorkout(date)` when the user taps Start on a today planned workout. `CalendarMonthView.handleDayAction` at line 1011 handles that case by showing `workoutTypeSelectorSheet` -- a generic flow. `WorkoutStoreV2.startPlannedWorkout(_:)` is never called from this path. The correct path (via `PlannedWorkoutCard`) exists in `PlannedWorkoutComponents.swift:279-282` but is a separate UI surface. There are two Start buttons with different behaviors.

**Critical 2 -- `completePlannedWorkout` has no production call site**: Confirmed. A search across the entire `Features/` tree finds the function only at its definition in `PlannerStore.swift:195`. It is never called.

**High 4 -- `PlannedWorkoutEditor` erases progression strategy on save**: Confirmed. `PlannedWorkoutEditor.swift:229` writes `progressionStrategy: .static` unconditionally, overwriting any existing strategy on the planned exercise.

**High 6 -- `PlannerSetupCarouselView.generatePlan()` bypasses `PlannerStore.createSplit`**: Confirmed. Lines 507-515 construct `WorkoutSplit(...)` directly, call `context.insert(split)`, and save context -- `PlannerStore.createSplit` is never used from this path.

**Low 11 -- `hasCompletedWorkouts` is a dead input**: Confirmed. The property is declared at `DayActionCard.swift:13` and passed from `DayDetailView.swift:85`, but is not referenced anywhere in `DayActionCard.body`.

### One wording fix already applied

**Finding 3 -- source-of-truth wording**: This has now been reworded in the main document. The issue is not that the UI fabricates completion from nowhere; it is that the UI mixes history-derived completion with stale persisted planner status. The source-of-truth mismatch remains valid.

### File references

All file paths and referenced types exist and are valid.
