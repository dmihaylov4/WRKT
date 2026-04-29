# Cross-App Deep Dive Summary

Date: 2026-04-14
Scope: Train View, Plan View, Feed View, Cardio View, Profile View

## Executive Summary

Across the app, the same structural problems repeat:

1. Ownership is blurry. Views, view models, stores, services, and managers all perform writes directly.
2. Source of truth is often split. UI is frequently patched to hide stale state instead of fixing the underlying model contract.
3. Lifecycle-driven side effects are too common. `.task`, `.onAppear`, timers, and overlays trigger important writes and subscriptions from unstable UI owners.
4. Several product-facing actions are mislabeled or only partially implemented.
5. Expensive recomputation and persistence happen too often and from the wrong layers.

The app has strong feature breadth, but consistency is weak. The main risk is not one isolated bug. It is that state ownership is fragmented enough that fixes in one surface can easily drift from another.

## Repeated Cross-App Problems

### 1. State ownership is fragmented

This is the biggest system-wide issue.

Examples:

- Train: rest-timer next-set generation is split across timer manager, store, overlay, and exercise screen.
- Plan: planner completion lifecycle is disconnected from the workout completion path.
- Feed: views (`PostCard`, `EditPostView`) perform backend writes directly.
- Cardio: route enrichment exists in both `HealthKitManager` and `CardioDetailView`.
- Profile: `ProfileView` orchestrates sync, cache refresh, tutorial flow, and stats recompute itself.

Effect:

- behavior becomes hard to predict
- same feature gets implemented multiple times
- screens patch around stale data instead of consuming one authoritative flow

Recommendation:

- Define one write owner per domain:
  - workout session / train
  - planner
  - social posts
  - cardio enrichment
  - profile dashboard

Views should request actions. They should not invent persistence flows.

### 2. Source of truth is often duplicated or patched

Examples:

- Train: PR detection and workout persistence have multiple overlapping paths.
- Plan: UI masks stale planned-workout status rather than fixing planner state.
- Feed: comment counts are repaired through `NotificationCenter` and cache patching.
- Cardio: detail view mixes original `run`, latest store lookup, and local route override state.
- Profile: cached week progress and milestones are manually refreshed from partial triggers.

Effect:

- stale UI
- invisible correctness drift
- need for ad hoc refreshes and banners

Recommendation:

- Pick one durable source of truth for each core entity.
- Derive UI from that source instead of broadcasting repair events.

### 3. Lifecycle side effects are doing too much work

Examples:

- Train: save frequency too high; detached saves and timer-driven updates increase churn.
- Feed: subscriptions start/stop from view `.task` and `.onDisappear`; scrolling can trigger backend writes via map backfill.
- Cardio: detail/share flows perform on-demand HealthKit fetches and store writes from view code.
- Profile: HealthKit sync is triggered from a card subtree `.task`.

Effect:

- behavior depends on mount/unmount timing
- duplicate subscriptions or duplicate work become likely
- testability drops

Recommendation:

- Move important side effects to stable coordinators or domain services.
- Reserve view lifecycle hooks for lightweight orchestration only.

### 4. User-facing actions sometimes do not match actual behavior

Examples:

- Plan: "Start" on planned workout starts a generic quick workout instead of the planned one.
- Feed: "Undo delete" recreates a new post instead of restoring the original.
- Cardio/Profile: Apple Health "disconnect" semantics are weak/cosmetic.
- Profile: reset-all warning says cardio is preserved, but implementation clears runs.

Effect:

- trust damage
- support burden
- hidden data loss risk

Recommendation:

- Audit all destructive or stateful actions for contract honesty.
- If behavior is approximate, rename the action.
- If copy promises preservation or restoration, code must enforce it.

### 5. Expensive work is too eager and too local

Examples:

- Train: persistence too chatty; save strategy needs explicit debounce + flush rules.
- Feed: two-query feed merge pushes pagination/ranking complexity to client.
- Cardio: repeated sorting/filtering in the view layer; full resync enriches only a subset of history.
- Profile: detached stats recomputation and repeated preview rebuilds occur from the screen.

Effect:

- more CPU work in render paths
- more storage churn
- more opportunities for inconsistency

Recommendation:

- Push heavy ranking/aggregation into dedicated services or backend queries.
- Cache with explicit invalidation rules, not ad hoc triggers.

## Biggest Product Risks

1. Data-contract dishonesty:
   - reset-all semantics
   - undo-delete semantics
   - planned-workout start/completion semantics

2. Stale or divergent state:
   - planner status
   - feed comment counts
   - cardio detail refresh
   - profile caches
   - weekly streak / freeze display and rebuild behavior

3. Architectural drift:
   - each feature is solving ownership differently
   - same categories of bugs will continue unless domain boundaries are tightened

## Highest-Leverage Fixes

### Tier 1: Correctness and trust

1. Fix Profile reset-all semantics or copy.
2. Fix Plan start/completion path so planned workouts are actually planned workouts.
3. Remove or redesign Feed undo-delete unless true restore is supported.
4. Fix Cardio detail refresh so refreshed data is immediately visible.

### Tier 2: Ownership cleanup

1. Centralize Train rest-timer/set-generation flow.
2. Centralize social post mutations outside views.
3. Centralize cardio enrichment outside detail/share views.
4. Give Profile a dedicated dashboard state owner.

### Tier 3: Efficiency and durability

1. Implement explicit Train save coalescing with hard flush points.
2. Replace Feed dual-query pagination with one ordered backend feed query.
3. Normalize profile/dashboard cache invalidation rules.
4. Reduce view-layer repeated sorting/filtering in Cardio/Profile.

## Recommended Architecture Direction

The app would benefit from a more explicit feature-domain pattern:

1. Domain service/use-case owns writes and cross-entity orchestration.
2. View model/screen model owns presentation state and async calls into the domain.
3. View renders state and emits intents only.
4. Persistence and subscription lifecycles live below the view layer.

You do not need a rewrite. But each feature should move toward:

- one source of truth
- one mutation owner
- one lifecycle owner for subscriptions/background sync

## Bottom Line

The app's main weakness is not lack of features. It is inconsistent state architecture. The most valuable next step is to fix the product-contract bugs first, then standardize ownership boundaries so new work stops reproducing the same class of mistakes.

---

## Review

Date reviewed: 2026-04-15

This is a summary document. Claims were checked against the feature deep dives and the codebase.

### Verified as accurate

All four product-contract examples listed under "User-facing actions sometimes do not match actual behavior" are confirmed:
- Plan "Start" on a planned workout opens the generic type selector, not the planned workout
- Feed "Undo delete" calls `createPost(...)` producing a new post identity
- Apple Health disconnect is cosmetic (no OS-level permission revocation)
- Reset-all alert says runs are preserved; code wipes them

The architectural patterns described (fragmented ownership, lifecycle-driven side effects, stale-state patching) are all visible in the codebase and not overstated.

### One flag addressed

The "Biggest Product Risks" section previously omitted weekly streak / freeze display and rebuild behavior. That gap has now been added to the summary.

### No inaccuracies found

The cross-feature patterns and specific examples are all grounded in real code. Tier ordering and architecture direction are sound.
