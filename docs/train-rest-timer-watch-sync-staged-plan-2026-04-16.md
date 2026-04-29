# Train Rest Timer Ownership Staged Plan

Date: 2026-04-16

Scope:

- Train rest timer completion behavior
- iPhone workout session state
- Apple Watch companion sync
- Live Activity / lock-screen timer state

Goal:

- centralize rest-timer finish domain ownership without breaking current phone/watch behavior

## Problem

The rest timer is a cross-surface feature, but the domain consequences of "timer finished" are not clearly owned in one place.

Relevant current surfaces:

- iPhone workout domain state in [Features/WorkoutSession/Services/WorkoutStoreV2.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/WorkoutStoreV2.swift)
- iPhone timer state in `RestTimerManager.shared`
- iPhone -> Watch sync in [Core/Services/WatchConnectivityManager.swift](/Users/dimitarmihaylov/dev/WRKT/Core/Services/WatchConnectivityManager.swift)
- Watch -> iPhone control messages in [WRKT Watch Watch App/WatchConnectivityManager.swift](/Users/dimitarmihaylov/dev/WRKT/WRKT%20Watch%20Watch%20App/WatchConnectivityManager.swift)
- Watch rest-timer UI in [WRKT Watch Watch App/Views/RestTimerWatchView.swift](/Users/dimitarmihaylov/dev/WRKT/WRKT%20Watch%20Watch%20App/Views/RestTimerWatchView.swift)
- iPhone Live Activity timer mirroring in [Features/WorkoutSession/Services/LiveActivityManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/LiveActivityManager.swift)

Current architectural risk:

- the timer state is mirrored to multiple consumers
- watch can send workout/timer actions back to phone
- Live Activity independently mirrors countdown state
- if more than one layer decides the domain consequence of timer finish, next-set behavior can drift or duplicate

This is higher risk because watch sync is already involved.

## Current Observations

### 1. Phone currently mirrors timer state outward

In [Core/Services/WatchConnectivityManager.swift](/Users/dimitarmihaylov/dev/WRKT/Core/Services/WatchConnectivityManager.swift:112), the iPhone listens to both:

- `store.$currentWorkout`
- `RestTimerManager.shared.$state`

and sends a derived `WatchWorkoutState` to the watch.

This is good for mirroring.
It does not by itself define domain ownership.

### 2. Watch already sends control intents back to iPhone

In [WRKT Watch Watch App/WatchConnectivityManager.swift](/Users/dimitarmihaylov/dev/WRKT/WRKT%20Watch%20Watch%20App/WatchConnectivityManager.swift:70), the watch can send:

- `completeSet`
- `navigate`
- `startSet`
- `addAndStartSet`
- simple `WatchMessage` controls

This means the watch is already an input source into workout state transitions.

### 3. Watch rest view is presentation/control oriented

[RestTimerWatchView.swift](/Users/dimitarmihaylov/dev/WRKT/WRKT%20Watch%20Watch%20App/Views/RestTimerWatchView.swift:11) renders:

- countdown
- skip
- pause
- resume

This is the right role for the watch UI.
It should not become the independent owner of next-set generation logic.

### 4. Live Activity is also a state mirror

[LiveActivityManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/LiveActivityManager.swift:22) mirrors rest timer state and keeps the lock-screen countdown alive.

This should remain presentation/mirroring only.
It should not own workout mutations on timer finish.

## Recommended Ownership Model

Authoritative owner:

- `WorkoutStoreV2` on iPhone owns the domain consequence of rest-timer finish

Supporting roles:

- `RestTimerManager` owns countdown mechanics only
- Watch sends control/input events only
- Watch UI renders mirrored workout/timer state only
- Live Activity mirrors timer state only

In other words:

1. timer ends
2. one event is emitted
3. `WorkoutStoreV2` decides whether and how workout state changes
4. all other surfaces reflect that store state

## Explicit Non-Goals

Do not do these in the first pass:

- rewrite the entire timer/watch architecture
- move all timer logic to watch
- let both watch and phone mutate next-set state independently
- change visible timer UX and domain ownership in one large refactor

## Staged Plan

### Stage 0. Map and freeze current ownership assumptions

Deliverable:

- one internal inventory of all timer-finish and timer-control entry points

Must map:

- where timer starts on phone
- where timer pauses/resumes/skips on phone
- where watch sends timer-related controls
- where watch receives mirrored timer state
- whether any path outside store currently creates or starts a next set

Acceptance:

- no code changes yet
- exact file/function inventory exists

Why:

- with watch sync involved, changing behavior before mapping entry points is too risky

### Stage 1. Define one store-level timer-finish API

Deliverable:

- add one narrow domain method on `WorkoutStoreV2`

Recommended contract shape:

- `handleRestTimerFinished(...)`

Inputs should be minimal and explicit:

- active workout context
- source of event if useful (`phone`, `watch`, `notification`, `liveActivity`)
- optional exercise/entry identifiers if needed for sanity checks

Responsibilities of this method:

- verify there is still an active workout
- verify the active entry/exercise context is still valid
- decide whether next-set generation/start should happen
- avoid duplicate mutation if state is already advanced
- persist resulting workout state once

Non-responsibilities:

- countdown mechanics
- watch UI rendering
- lock-screen rendering

Acceptance:

- method exists
- can be called without changing current user-visible behavior yet

### Stage 2. Convert one phone-only path first

Deliverable:

- migrate the safest phone path to the new store method

Recommended first path:

- the in-workout iPhone path that currently reacts to timer finish while app is foregrounded

Why first:

- easiest to observe
- lower coordination risk than watch path
- keeps blast radius smaller

Acceptance:

- foreground phone timer-finish path uses store-owned domain handling
- watch behavior unchanged for now

### Stage 3. Convert watch timer-finish/control path into pure input events

Deliverable:

- watch-originated timer/control events call into the same store API on iPhone

Key rule:

- watch must not independently decide next-set mutation semantics

Instead:

- watch sends event
- iPhone store validates and applies exactly one mutation
- iPhone state is mirrored back to watch

Acceptance:

- one canonical mutation path for both phone and watch timer-finish semantics
- no duplicate next-set creation from dual ownership

### Stage 4. Convert remaining mirror layers to read-only behavior

Targets:

- Live Activity
- notification-related timer surfaces
- any overlay path

Rule:

- these layers can request/emit events if needed
- but they do not directly own workout-state mutation

Acceptance:

- no surface other than `WorkoutStoreV2` owns timer-finish domain mutation

### Stage 5. Delete duplicated legacy logic

Deliverable:

- remove old per-surface mutation code after each path proves stable

Do not remove early.
Legacy code should only be deleted after the replacement path is verified.

## Risk Controls

### Source tagging

Add optional source tagging to the new store handler:

- `phoneForeground`
- `watch`
- `notification`
- `liveActivity`

Why:

- helps log unexpected duplicate events
- helps confirm which surface still owns behavior during migration

### Idempotency guard

Store-level handler should be safe if called twice for the same timer completion window.

Examples:

- do not create two pending sets
- do not start the same next set twice
- do not persist duplicate transitions

### Watch-first safety rule

If phone and watch can both observe the same timer completion, phone store must win.

Watch should be treated as:

- input sender
- mirror consumer

not authoritative workout-mutation owner

### Logging

During migration, log:

- timer finished source
- active workout id
- active entry id
- mutation applied or skipped
- reason for skip

This is especially important for cross-device races.

## Validation Plan

### Phone foreground

- finish set on iPhone
- let timer expire
- verify next-set behavior exactly once

### Watch mirrored timer

- start workout on phone
- observe timer on watch
- let timer expire while watch is visible
- verify no duplicate next-set mutation

### Watch control path

- pause/resume/skip from watch
- verify phone state remains authoritative and consistent

### Background / return

- start timer on phone
- background phone / rely on watch or lock-screen visibility
- return to app
- verify no drift between workout state and timer-derived next-set state

### Live Activity

- start timer
- observe lock-screen/live activity countdown
- timer completes
- verify Live Activity mirrors completion without owning workout mutation

## Suggested File Order

1. [Core/Services/WatchConnectivityManager.swift](/Users/dimitarmihaylov/dev/WRKT/Core/Services/WatchConnectivityManager.swift)
2. [WRKT Watch Watch App/WatchConnectivityManager.swift](/Users/dimitarmihaylov/dev/WRKT/WRKT%20Watch%20Watch%20App/WatchConnectivityManager.swift)
3. `RestTimerManager` implementation file(s)
4. [Features/WorkoutSession/Services/WorkoutStoreV2.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/WorkoutStoreV2.swift)
5. [Features/WorkoutSession/Services/LiveActivityManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/LiveActivityManager.swift)
6. workout screen / overlay callers

## Recommendation

Do not treat this as a cleanup task.
Treat it as a cross-device state-ownership migration.

Best next implementation step:

- Stage 0 inventory
- then Stage 1 store-level API
- then migrate one foreground phone path before touching watch semantics
