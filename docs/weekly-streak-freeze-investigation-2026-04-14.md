# Weekly Streak And Freeze Investigation

Date: April 14, 2026

## Summary

Observed behavior:
- The planner shows a `13-week goal streak` on Tuesday, April 14, 2026.
- The prior week shown is `Apr 6 - Apr 12`.
- Reported weekly progress for that week is `144/183 min` and `1/3 days`.
- The user did not complete either target, so the weekly streak should have broken.

Confirmed outcome:
- The current codebase contains logic that would reset the weekly streak after a missed week.
- Freeze auto-use is not implemented.
- Weekly freeze support already exists separately in the model/engine/UI.
- The reported stale `13-week` display is therefore more likely caused by validation logic or silent freeze behavior than by missing lifecycle triggers alone.

## Root Cause

### 1. Weekly streak invalidation does not appear to be cold-start-only

The weekly streak rebuild/reset logic exists in:
- [Features/Rewards/Models/StreakResult.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/StreakResult.swift:766)

That function rebuilds the streak from historical weekly data and stops at the first incomplete week:
- [Features/Rewards/Models/StreakResult.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/StreakResult.swift:803)
- [Features/Rewards/Models/StreakResult.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/StreakResult.swift:821)
- [Features/Rewards/Models/StreakResult.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/StreakResult.swift:826)
- [Features/Rewards/Models/StreakResult.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/StreakResult.swift:833)

The earlier hypothesis in this document was that validation only ran on cold start. That is not correct.

Current trigger points in `AppShellView` include:
- foreground / `scenePhase == .active`
- post-foreground HealthKit sync
- cold-start initial appear
- launch bootstrap path

So the observed stale streak is **not** well explained by "validation only runs on cold start."

More likely causes now are:
- validation/rebuild logic itself is producing an unexpected result
- a weekly freeze was already active or silently consumed
- the historical weekly completion inputs were not what the UI appeared to show

### 2. The reported missed week should break the streak

The helper that evaluates historical weekly completion checks:
- strength target
- MVPA target
- overall week completion

Relevant code:
- [Features/Rewards/Models/StreakResult.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/StreakResult.swift:736)
- [Features/Rewards/Models/StreakResult.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/StreakResult.swift:737)
- [Features/Rewards/Models/StreakResult.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/StreakResult.swift:738)
- [Features/Rewards/Models/StreakResult.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/StreakResult.swift:739)

The current implementation defines normal weekly streak completion as:
- `strengthMet || mvpaMet`

So:
- if a user misses one target but completes the other, the regular weekly streak continues
- if a user misses both targets, the regular weekly streak should break

In the reported case, the week shows `144/183 min` and `1/3 days`, so neither target was met. That means the streak should have reset during rebuild.

## Freeze Investigation

### 1. Auto-use of freeze is not implemented

There is no control flow that automatically activates a freeze when a weekly streak is about to break.

What exists:
- manual daily freeze activation:
  [Features/Rewards/Services/RewardEngine.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Services/RewardEngine.swift:228)
- manual weekly freeze activation:
  [Features/Rewards/Services/RewardEngine.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Services/RewardEngine.swift:279)

The weekly streak update logic only checks whether `prog.streakFrozen` is already active:
- [Features/Rewards/Models/StreakResult.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/StreakResult.swift:566)
- [Features/Rewards/Models/StreakResult.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/StreakResult.swift:570)

So current behavior is:
- freeze must be manually armed in advance
- if it is not already active, nothing auto-saves the weekly streak

### 2. Weekly freeze UI is already wired separately from the daily path

The visible profile freeze button already branches on `hasWeeklyGoal` and calls the weekly path when a weekly goal is active. The alert copy also branches between weekly and daily wording.

So the real remaining issue is not "button targets wrong API." It is:
- whether the weekly freeze behavior matches product intent
- whether validation consumes/clears weekly freeze correctly
- whether cadence and auto-use behavior are implemented as intended

### 3. Freeze policy does not match "1 freeze per month"

Current code:
- daily freeze path uses a `7 day` reuse cooldown
  [Features/Rewards/Services/RewardEngine.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Services/RewardEngine.swift:240)
- weekly freeze path uses a `4 week` reuse cooldown
  [Features/Rewards/Services/RewardEngine.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Services/RewardEngine.swift:291)

There is no implementation for:
- one freeze per calendar month

### 4. Daily and weekly freeze state are already split in the model

The model already contains separate weekly fields:
- `weeklyStreakFrozen`
- `weeklyFreezeUsedAt`

So a schema split is **not** required for weekly freeze support.

The real question is whether runtime logic and validation behavior are using those fields consistently and according to product intent.

## Impact

User-facing impact:
- weekly streak can display an incorrect value after a missed week
- users may believe they preserved a streak they actually lost
- freeze expectations are not met
- the app suggests weekly streak importance but exposes daily freeze semantics

Product impact:
- trust in streak mechanics is weakened
- the displayed streak can diverge from actual historical completion
- the freeze feature is underspecified and inconsistently implemented

## Determined Causes

Primary issue:
- the displayed weekly streak does not match the apparent historical completion state
- current evidence no longer supports "cold-start-only validation" as the primary cause
- the next investigation target should be validation behavior and weekly-freeze interaction during rebuild

Related freeze issues:
- no auto-freeze behavior exists
- freeze cadence does not match "1 per month"
- weekly freeze support exists, but product behavior is still not fully encoded/documented

## Recommended Fix Direction

This document does not implement changes, but the required direction is clear:

1. Verify weekly streak rebuild behavior against real historical inputs and active freeze state before changing lifecycle triggers.
   Existing lifecycle triggers already include foreground and bootstrap paths.

2. Decide the intended weekly streak rule explicitly.
   Options:
   - regular streak = either target
   - regular streak = both targets

3. Implement explicit weekly freeze behavior.
   Required decisions:
   - manual only or auto-use
   - one per calendar month or rolling 30/31 days
   - whether weekly freeze is separate from daily freeze

4. Keep the existing separate daily/weekly freeze model fields, but audit all runtime reads/writes that consume them.

5. Keep the current profile branching UI, but verify that the surfaced weekly behavior matches product expectations.

## Final Product Decisions

The following product decisions are now fixed for implementation:

1. Weekly streak completion rule: `OR`
   - meeting either the strength target or the MVPA target preserves the normal weekly streak

2. Weekly freeze cadence: `1 per calendar month`

3. Weekly freeze behavior: automatic after validation detects a break
   - run validation first
   - if validation would reduce the weekly streak because continuity was broken
   - check whether a weekly freeze is available for the current calendar month
   - if available, consume the freeze and preserve the prior streak value
   - do not increment the streak when freeze is used

4. User notification: required when weekly freeze is consumed
   - when auto-freeze saves the streak, the user must be notified
   - notification should state that the monthly freeze was used to preserve the streak

## Suggested Fix Plan

### Fix 1 (primary): Audit validation/rebuild behavior using real historical inputs and weekly-freeze state

Do this first:
- log or inspect the weekly rows used during rebuild
- inspect whether `weeklyStreakFrozen` / `weeklyFreezeUsedAt` were active for the reported period
- verify what streak result the rebuild function actually computes for the reported week

Lifecycle expansion is no longer the primary fix because foreground triggers already exist.

### Fix 2 (required before shipping): Decide and document the weekly streak completion rule

Current code: `strengthMet || mvpaMet` (either target sufficient).

Final decision:
- OR: either target met = streak continues

Required implementation detail:
- encode this as a named constant or enum case in `StreakResult.swift` so the rule is explicit rather than implicit

### Fix 3: Audit and normalize existing weekly freeze runtime logic

No schema split is needed because weekly freeze fields already exist.

Required work:
- verify all weekly freeze reads/writes use weekly fields rather than daily ones
- verify consumption/clearing behavior during rebuild/reset paths
- verify eligibility/cooldown behavior matches the intended monthly policy
- verify UI state and copy stay aligned with actual runtime behavior

### Fix 4: Verify surfaced weekly freeze UX against product semantics

The branching UI already exists.

Required work now is to check:
- whether the weekly button should remain manual
- whether its wording matches actual monthly freeze rules
- whether the user is adequately informed when an automatic weekly freeze is consumed

### Fix 5 (deferred, product decision): Auto-freeze behavior

Auto-freeze is now a product requirement.

The rule should be defined in terms of the validation result, not a narrower "previous week failed" check.

Recommended rule:
1. Run weekly streak validation/rebuild from source data.
2. Determine the post-validation streak result.
3. If validation would reduce the weekly streak because continuity was broken:
4. Check whether a weekly freeze is available.
5. If available, consume the weekly freeze and preserve the prior streak value.
6. If not available, keep the reset.

Important behavior:
- auto-freeze should preserve the existing streak
- it should **not** increment the streak
- for example, if validation would drop `13` to `0` or `1`, an available weekly freeze should keep it at `13`

Notification requirement:
- when auto-freeze is consumed, send a notification confirming that the streak was saved
- the notification should clearly state that the monthly freeze was used

Recommended notification copy:
- title: `Streak Saved`
- body: `Your monthly freeze was used to protect your weekly streak.`

### Freeze cadence

Both paths need an explicit cadence decision documented and enforced as a named constant:
- current daily cooldown: `7 days`
- current weekly cooldown: `4 weeks`
- final weekly policy from product: `1 per calendar month`

Once decided, replace the hardcoded values in `RewardEngine.swift:240` and `RewardEngine.swift:291` with a named constant.

### Suggested fix order

1. Fix 1: audit rebuild/validation behavior with real data
2. Fix 2: document and encode completion rule
3. Fix 3: normalize existing weekly freeze runtime logic
4. Fix 4: align surfaced weekly freeze UX with product semantics
5. Fix 5: auto-freeze (deferred until product decisions made)

## Conclusion

For the reported April 14, 2026 case:
- the streak should have broken if neither target was met and no weekly freeze preserved it
- the likely cause is no longer well explained by "cold-start-only validation"
- the next likely root-cause area is rebuild logic and weekly-freeze interaction

For freezes:
- auto-use is not implemented
- the model and UI already contain a weekly path
- remaining work is to verify runtime behavior and align cadence/auto-use with product rules

---

## Review

Date reviewed: 2026-04-15

This review originally identified three significant inaccuracies. The document has now been patched to remove those incorrect claims and to narrow the root-cause diagnosis.

### Verified corrections

**Validation is not cold-start-only**: confirmed. `AppShellView` already triggers weekly streak validation from foreground and bootstrap paths, not just the cold-start path.

**Weekly freeze fields already exist**: confirmed. Separate weekly freeze model fields already exist and are used by the runtime.

**Profile freeze button already branches to weekly behavior**: confirmed. The surfaced weekly/daily UI split already exists.

### What still stands

- The reported observed state can still be real: a streak that appears not to have reset when the visible week looks incomplete.
- Auto-freeze is still not implemented.
- Freeze cadence still does not match the intended calendar-month policy.
- The next correct investigation target is rebuild/validation behavior and weekly-freeze interaction, not lifecycle trigger absence.

### Current status

The patched version is now directionally accurate. It should be used as a narrowed investigation doc, not as a confirmed root-cause report.
