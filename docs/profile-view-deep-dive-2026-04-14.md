# Profile View Deep Dive

Date: 2026-04-14
Scope: `ProfileView`, `PreferencesView`, `SettingsView`, `ConnectionsView`, `PlateWallView`, `BarbellPreviewView`, `WeeklyProgressTypes`

## Executive Summary

Profile View is feature-rich, but it is carrying too many responsibilities:

1. It mixes dashboard rendering, HealthKit sync orchestration, stats recomputation, tutorial flow, badge refresh, and settings navigation in one screen.
2. Preferences and connection flows contain misleading data-reset and disconnect semantics.
3. Profile cache invalidation is inconsistent, so parts of the screen can go stale while other parts resync aggressively.
4. Barbell/profile customization data lives in view-layer static tables instead of a single rewards domain model.

Biggest correctness problem is the reset contract: UI says cardio/runs will be preserved, but the implementation clears them.

## Findings

### 1. "Reset all data" contract is false

Severity: High

The reset alert and footer both tell the user that runs/cardio from HealthKit will be preserved ([Features/Profile/Views/PreferencesView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/PreferencesView.swift:85), [Features/Profile/Views/PreferencesView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/PreferencesView.swift:414)).

But `resetAllData()` does this:

- `store.clearAllWorkouts()` ([Features/Profile/Views/PreferencesView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/PreferencesView.swift:505))
- `try? await WorkoutStorage.shared.wipeAllData()` which explicitly includes runs ([Features/Profile/Views/PreferencesView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/PreferencesView.swift:534))
- `resetHealthKitState()` then calls `store.clearAllRuns()` ([Features/Profile/Views/PreferencesView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/PreferencesView.swift:538), [Features/Profile/Views/PreferencesView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/PreferencesView.swift:600))

So the code does not preserve cardio history locally. It wipes it.

Recommendation:

- Fix either the implementation or the user-facing copy.
- The invariant must be explicit:
  - either "reset removes all local health-derived history too"
  - or "reset preserves imported cardio history and only removes app-owned data"

Right now user consent is being collected under false wording.

### 2. Apple Health "Disconnect" is mostly an app-side state change, not true revocation

Severity: Medium-High

`ConnectionsViewModel.disconnect(.health)` does not revoke access or even clear imported data. It only sets `connectionState = .disconnected`, stops background observers, and updates local UI state ([Features/Profile/Views/ConnectionsView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ConnectionsView.swift:90)).

This is a misleading product contract:

- HealthKit permissions remain granted at OS level
- previously imported data remains
- a later sync/request can reconnect immediately

To its credit, `resetHealthKitState()` in preferences comments that iOS does not allow programmatic revocation ([Features/Profile/Views/PreferencesView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/PreferencesView.swift:590)). `ConnectionsView` does not surface that nuance.

Recommendation:

- Rename this action to something honest like `Stop syncing` or `Disable background sync`.
- If true disconnect is impossible, the UI must say so clearly and point users to system settings for permission revocation.

### 3. Profile screen owns too much orchestration

Severity: Medium-High

`ProfileView` is doing all of this itself:

- HealthKit sync orchestration via `syncHealthKitMinutes()` ([Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift:59))
- streak validation and weekly progress cache refresh ([Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift:70))
- detached stats recomputation in `refreshStats()` ([Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift:132))
- dex preview rebuilds ([Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift:163))
- tutorial frame capture and spotlight sequencing ([Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift:504))
- social badge refresh ([Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift:431))

This makes the screen hard to reason about and fragile to edit.

Recommendation:

- Split into explicit owners:
  - profile dashboard view model
  - profile tutorial controller
  - stats refresh coordinator
  - health sync coordinator
- Profile screen should compose prepared state, not orchestrate half the app.

### 4. Health sync lifecycle is tied to a card subtree

Severity: Medium

The periodic HealthKit sync is triggered from a `.task` attached to `ProgressOverviewCard` inside the list section ([Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift:239), [Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift:250)).

That means sync lifecycle is tied to a conditional subview that depends on:

- `progress.first`
- `goals.first`
- `cachedWeekProgress`

This is a weak owner for side effects. If that subtree is recreated, the task can rerun. If the subtree is absent, sync does not happen there at all.

Recommendation:

- Move profile-level sync triggers to the screen root or a dedicated coordinator.
- Render cards from state; do not let card mount semantics drive data synchronization.

### 5. Cache invalidation is incomplete and uneven

Severity: Medium

Profile tries to cache expensive values:

- `cachedWeekProgress`
- `cachedMilestones`
- `dexPreviewCache`

([Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift:41))

But invalidation is patchy:

- week progress only refreshes on `completedWorkouts.count` change and appear/sync paths ([Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift:450), [Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift:463))
- `currentWeekProgress(...)` depends on `WeeklyTrainingSummary`, `runs`, goals, and reward cutoff state, not just completed workout count ([Features/Profile/Models/WeeklyProgressTypes.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Models/WeeklyProgressTypes.swift:54))
- stats refresh is detached and keyed off count change only, not edits/deletes/goal changes ([Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift:139))

Result:

- dashboard can show stale weekly progress
- card refresh behavior depends on which subsystem changed the data
- recompute timing becomes opportunistic instead of deterministic

Recommendation:

- Define explicit invalidation rules per cached artifact.
- Better: derive profile dashboard state in one profile model and update it from known inputs rather than ad hoc `onChange` patches.

### 6. PR Collection header has a broken/empty navigation affordance

Severity: Medium

In the PR Collection header there is a `NavigationLink(destination: AchievementsDexView())` with an empty label block ([Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift:336)).

That is either:

- dead code
- or a missing CTA the user can no longer see/tap reliably

Recommendation:

- Remove it or give it an actual visible label like `See all`.
- Dead navigation scaffolding inside a hot screen is a maintenance smell and likely a product bug.

### 7. Social preference toggles use a stale captured user snapshot

Severity: Medium-Low

`PreferencesView.socialFeaturesSection` captures `let user = SupabaseAuthService.shared.currentUser` and then binds toggles to `user.profile?.autoPostPRs` / `user.profile?.autoPostCardio`, while writes happen asynchronously through `updateProfile(...)` ([Features/Profile/Views/PreferencesView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/PreferencesView.swift:299)).

Problems:

- getter reads from a captured snapshot, not a dedicated observable local state
- setter fires async backend update with no local optimistic state, loading state, or error handling
- quick successive toggles can feel laggy or revert unpredictably if the auth/profile object refreshes later

Recommendation:

- Back these toggles with observable local state owned by a settings/profile model.
- Reflect pending/error states explicitly.

### 8. Barbell configuration data is view-owned instead of domain-owned

Severity: Medium-Low

`BarbellPreviewView` defines large static data tables for `PlateTier`, `BarSkin`, and `StickerOption` inside the view file ([Features/Profile/Views/BarbellPreviewView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/BarbellPreviewView.swift:15), [Features/Profile/Views/BarbellPreviewView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/BarbellPreviewView.swift:88), [Features/Profile/Views/BarbellPreviewView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/BarbellPreviewView.swift:112)).

But the rewards/barbell domain already exists elsewhere through:

- `EarnedPlate`, `BarbellConfig` ([Features/Rewards/Models/BarbellModels.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/BarbellModels.swift:7), [Features/Rewards/Models/BarbellModels.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/BarbellModels.swift:45))
- `BarbellProgressService` ([Features/Rewards/Services/BarbellProgressService.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Services/BarbellProgressService.swift:9))

This is a maintenance trap:

- unlock rules and visuals can drift
- profile view becomes source of truth for reward definitions by accident
- harder to reuse barbell metadata elsewhere

Recommendation:

- Move barbell metadata to a shared rewards/barbell domain module.
- Views should consume barbell definitions, not define them.

## Efficiency / Simplicity Opportunities

1. Move Profile dashboard state into one view model/coordinator.
2. Replace ad hoc caches with explicit derived-state computation and invalidation.
3. Make reset and disconnect semantics honest and consistent.
4. Consolidate barbell metadata into one domain source of truth.
5. Remove dead navigation/UI scaffolding from PR Collection.

## Suggested Refactor Order

1. Fix reset-all wording/behavior first because it is a user trust issue.
2. Fix Apple Health disconnect semantics so settings language matches reality.
3. Extract profile orchestration out of `ProfileView`.
4. Normalize cache invalidation for weekly progress/stats/dex.
5. Then centralize barbell metadata and clean up UI leftovers.

## Open Questions

1. Should `Reset all data` preserve imported cardio history or not?
2. Is Apple Health disconnect intended to mean `stop background sync` rather than `revoke connection`?
3. Is the barbell customization system supposed to be profile-only presentation, or a broader rewards subsystem with reusable metadata?

## Bottom Line

Profile View delivers a lot, but it is too broad and not fully honest about data semantics. Biggest bug is reset behavior contradicting its warning text. Biggest design issue is that Profile screen has become an orchestration hub instead of a dashboard.

---

## Review

Date reviewed: 2026-04-15

### Verified as accurate

**Finding 1 -- Reset-all contract is false**: Confirmed. `PreferencesView.swift:85` alert message says "Only runs/cardio from HealthKit will be preserved." But `resetAllData()` calls:
- `WorkoutStorage.shared.wipeAllData()` which deletes `runsFileURL` explicitly (`WorkoutStorage.swift:810`)
- `store.clearAllRuns()` in `resetHealthKitState()` (`PreferencesView.swift:600`)

Runs are wiped despite the copy saying otherwise.

**Finding 2 -- Apple Health disconnect is mostly an app-side state change**: Confirmed. `ConnectionsView.swift:90-98` sets `connectionState = .disconnected` and calls an internal `disconnect()` method. No OS-level HealthKit permission revocation is possible on iOS; the code correctly notes this in a comment but the UI does not surface it. The framing of "disconnect" still implies more than what occurs.

**Finding 6 -- Empty NavigationLink in PR Collection**: Confirmed. `ProfileView.swift:336-338` has `NavigationLink(destination: AchievementsDexView()) { }` with an empty label block. The link is invisible to the user, making the navigation affordance unreachable.

### One wording adjustment already applied

**Finding 2 wording**: The main document now avoids "only cosmetic" and instead describes disconnect as mostly an app-side state change, which is a more accurate framing.

### File references

All file paths and types referenced exist and are valid.
