# Master Plan: Accountability-Driven Social Profile

Date: 2026-04-16
Owner: Product / Social / Profile
Primary surfaces: `Features/Social/Views/SocialProfileView.swift`, `Features/Social/ViewModels/ProfileViewModel.swift`
Supporting systems: battles, challenges, virtual runs, smart nudges, activity feed, friend activity

## Why This Exists

The current social profile is structurally correct but product-weak for a workout app.

Today, when a user opens a friend's profile, the most prominent signals are:

- number of shared workouts
- number of friends
- standard profile bio/avatar
- feed posts

That is fine for a generic social app, but weak for WRKT's actual goal: helping friends push each other, stay consistent, and feel accountable.

The profile should answer:

- Is this person active right now?
- Are they ahead of me, behind me, or at risk of falling off?
- What can I do with them right now?
- What promise, streak, challenge, or rivalry is currently alive between us?

The profile should feel less like a static identity page and more like an accountability dashboard for one relationship.

## Current State

The current implementation has now moved beyond the original flat social layout.

### Current implementation status in app

Friend profile currently includes:

- richer profile header card
- relationship badge
- last-active chip
- top accountability insight banner
- accountability snapshot cards
- `You vs Them` comparison card
- reworked friend action area
- recent activity feed
- cardio-aware activity cards instead of fake strength stats for runs

Own profile currently includes:

- profile header card
- stats row
- activity link
- barbell showcase
- edit profile action
- recent activity feed

### Important limitation in current implementation

Streak is still not properly visible on friend profiles.

Right now:

- own profile can still surface streak from local reward progress
- friend profile does not yet expose streak as a primary visible metric
- the redesign language already assumes streak matters, but the current screen does not yet deliver that clearly

That means one of the highest-value accountability signals is still missing from the friend-profile experience.

Relevant reusable systems already exist elsewhere in the app:

- friend activity summaries in `Features/Home/ViewModels/HomeViewModel.swift`
- comparative "You vs. Friends" logic in `HomeViewModel.getComparativeStats()`
- battles
- challenges
- virtual run invites
- smart nudges
- notifications / activity feed

This means the gap is not missing social infrastructure. The gap is poor packaging of it on the profile surface.

## What Is Still Missing

Even after the current redesign pass, the profile is still missing several important accountability signals.

### 1. Visible streak on profiles

This should be added explicitly.

Recommended behavior:

- own profile should show current streak prominently
- friend profile should show current streak if privacy rules allow it
- head-to-head should eventually include streak comparison, not just weekly session count

Good placements:

- inside the accountability snapshot
- as a chip in the header context area
- inside `You vs Them`

Why it matters:

- streak is one of the strongest habit/accountability signals in the app
- users immediately understand it
- it creates both pride and pressure

This is the highest-priority missing data point.

### 2. Weekly goal progress

The current friend profile shows momentum proxies, but not the clearest weekly accountability contract.

Add:

- `3 / 4 workouts this week`
- `1 workout left`
- `goal complete`

This matters because weekly goal progress is more actionable than raw post count.

### 3. Streak risk / urgency

The profile should not only show streak count. It should show whether the streak is safe or in danger.

Examples:

- `Needs 1 workout by Sunday to keep streak alive`
- `Streak safe this week`
- `Missed this week, streak at risk`

This is one of the strongest missing emotional triggers.

### 4. Shared history

The current redesign improves comparison, but the relationship still lacks depth.

Still missing:

- friends since
- battles completed together
- challenges completed together
- recent winner between the two of you

This matters because accountability works better when the relationship feels ongoing.

### 5. Goal-aware recommendation

The top insight banner is better now, but it is still heuristic and mostly activity-based.

It should become aware of:

- their weekly goal state
- your weekly goal state
- streak danger
- active battle/challenge state

That would make the banner feel much smarter and more specific.

### 6. Better action options

The friend action area is improved, but still incomplete relative to the product direction.

Still missing:

- direct challenge CTA
- direct battle CTA
- direct nudge CTA
- dynamic primary action based on state

Right now the profile is more structured, but still not yet the full accountability launcher it should become.

## Product Goal

Turn the social profile into the best place in the app to:

- read a friend's momentum
- compare consistency
- start an accountability action
- reinforce shared progress and friendly pressure

## Product Principles

1. Show momentum, not vanity.
The profile should prioritize recent consistency, streak risk, weekly goal progress, and head-to-head movement over generic counts.

2. Make action obvious.
Every friend profile should present the next best action: nudge, battle, challenge, invite to run, or react to a recent workout.

3. Build around the relationship, not just the person.
The most important data is not "this user has 42 workouts." It is "you are 2 workouts behind them this week" or "both of you are on 3-week streaks."

4. Reward honesty and urgency.
The UI should surface when someone is slipping, when they just trained, or when a challenge is close to ending.

5. Preserve privacy boundaries.
If a metric is not allowed for non-friends or private profiles, the UI must degrade gracefully without feeling broken.

## Proposed Profile Model

The friend profile should be reorganized into five stacked sections.

### 1. Identity + Relationship Context

Keep:

- avatar
- display name / username
- bio

Add:

- friendship state
- "friends since" date if available
- last active signal like `Worked out 3h ago`
- optional accountability label:
  - `On a streak`
  - `Ahead this week`
  - `Needs one more workout for weekly goal`

This section should immediately explain why this friend matters today.

### 2. Accountability Snapshot

Replace the current generic stats row with three high-signal cards.

Recommended metrics:

- This week: workouts completed this week
- Goal progress: `3 / 4 workouts`
- Recent consistency: active days in last 7 or 14 days

For friend profiles, if data is available, also show:

- current weekly streak
- time since last workout
- head-to-head weekly delta: `+2 vs you` or `-1 vs you`

Important note:
Streak should not be treated as optional in the long run. It should become a first-class profile metric.

Do not lead with:

- total friends
- lifetime post count

Those can still exist in secondary surfaces, but they should not dominate the page.

### 3. Head-to-Head Section

This is the core new module.

Show the relationship between current user and the viewed friend:

- `You: 2 workouts this week`
- `Alex: 4 workouts this week`
- delta and motivational framing:
  - `Alex is ahead by 2`
  - `You’re tied`
  - `One workout puts you ahead`

Secondary signals:

- streak comparison
- last 14 day active-day comparison
- recent battle or challenge status
- personal rivalry summary:
  - `You’ve beaten Alex in 3 of the last 5 battles`

This section should reuse logic patterns from `HomeViewModel.getComparativeStats()` but scoped to a single friend rather than the friend group average.

### 4. Quick Accountability Actions

This must become the highest-conversion area on the profile.

Primary actions:

- `Challenge`
- `Start Battle`
- `Invite to Run`
- `Nudge`

Secondary actions:

- mute / unmute
- remove friend

Rules:

- if there is already an active battle, replace `Start Battle` with `View Battle`
- if there is already an active challenge together, replace `Challenge` with `View Challenge`
- if the friend worked out recently and the user did not, show `Catch Up`
- if the friend is at risk of missing a streak/goal, show `Nudge`

`Nudge` should be framed carefully. Good copy examples:

- `Push Them`
- `Check In`
- `Don’t Let Them Fold`

The exact tone can be tuned later, but the action should exist.

### 5. Activity and Proof

Posts remain useful, but they should become evidence of momentum, not the whole profile.

Enhance the activity section with:

- recent workout timeline
- lightweight workout tags:
  - `Leg Day`
  - `5.2 km run`
  - `PR hit`
  - `45 min`
- reactions or lightweight comments
- pinned recent achievement if one exists

Potential top module before the post feed:

- `Recent Wins`
  - last PR
  - streak milestone
  - challenge placement
  - battle win

## Concrete Feature Modules

### Module A: Friend Momentum Card

Purpose:
Summarize whether this friend is hot, cold, or slipping.

Inputs:

- last workout timestamp
- workouts in current week
- active days in last 7 days
- weekly goal progress
- streak state if available

Output examples:

- `Hot: 3 workouts in 4 days`
- `Cooling off: no workout in 5 days`
- `At risk: needs 1 workout by Sunday to keep streak alive`

### Module B: You vs Them Card

Purpose:
Create direct social comparison pressure.

Inputs:

- your current week workouts
- their current week workouts
- your goal progress
- their goal progress
- optional streak comparison

Outputs:

- progress bars
- delta label
- one sentence interpretation

Example messages:

- `You’re 2 behind this week`
- `You pulled ahead today`
- `Both of you are one session away from goal`

### Module C: Accountability Actions Rail

Purpose:
Drive behavior from the profile.

Actions:

- challenge friend
- start battle
- invite to virtual run
- send nudge

Success condition:
The viewed profile should never feel like a dead end.

### Module D: Shared History

Purpose:
Make the relationship feel persistent and meaningful.

Possible items:

- friends since date
- total battles together
- total challenges together
- shared runs completed
- recent winner in head-to-head interactions

This is useful because accountability works better when the relationship feels continuous.

### Module E: Risk + Opportunity Banner

Purpose:
Surface the most important accountability state at top of profile.

Examples:

- `Alex is one workout short of their weekly goal`
- `You haven’t worked out since Alex posted yesterday`
- `Battle with Alex ends in 18h`
- `Alex just hit a PR`

This can be powered by simple heuristics at first.

## Data Requirements

The current `UserProfile` model is too identity-focused. The screen needs a dedicated aggregate payload.

Recommended new read model:

`SocialProfileSummary`

Suggested fields:

- `profile`
- `friendshipStatus`
- `friendCount`
- `sharedWorkoutPostCount`
- `lastWorkoutAt`
- `workoutsThisWeek`
- `goalTarget`
- `goalCompleted`
- `activeDaysLast7`
- `currentWeeklyStreak`
- `sharedBattlesCount`
- `sharedChallengesCount`
- `activeBattle`
- `activeChallenge`
- `headToHeadWeekDelta`
- `headToHeadLast14ActiveDayDelta`
- `topRecentAchievement`
- `recommendedAction`

Important note:
This should be a server- or repository-composed summary, not assembled ad hoc in the view from many sequential calls.

## API / Repository Direction

Add a dedicated profile-summary fetch path instead of continuing to grow `ProfileViewModel` with one-off async loaders.

Recommended repository additions:

- `fetchSocialProfileSummary(userId:viewerId:)`
- `fetchHeadToHeadSummary(friendId:viewerId:)`
- `sendAccountabilityNudge(to:context:)`

If backend work is expensive, phase it:

Phase 1:
- compose on client from existing repositories

Phase 2:
- move to a single Supabase RPC or view-backed summary endpoint

## UX Rules

### Own profile

Own profile can stay more reflective and stats-heavy.

Primary emphasis:

- personal streak
- progress
- achievements
- posts

### Friend profile

Friend profile should be relationship-heavy.

Primary emphasis:

- momentum
- comparison to you
- accountability action
- recent activity

This means `SocialProfileView` should likely branch more intentionally between own-profile and friend-profile layouts instead of sharing nearly the same structure.

## Privacy Rules

We should define visibility tiers explicitly.

Public or non-friend:

- avatar
- name
- bio
- limited recent activity if allowed

Friend:

- weekly progress
- last active
- head-to-head comparison
- accountability actions

Private profile:

- no detailed momentum cards until accepted friendship

If a metric is hidden, replace it with a clear state like:

- `Add friend to see weekly progress`

Do not show empty modules with missing numbers.

## Rollout Plan

### Phase 1: Reframe Existing Profile

Goal:
Make the current screen meaningfully better with minimal backend work.

Changes:

- replace `Friends` stat with `Last active`
- replace `Workouts` stat with `This week`
- add friend-only `You vs Them` card using existing feed/workout data
- move action buttons above the feed and make them primary
- add recent momentum banner based on existing heuristics

Expected outcome:
The profile becomes immediately more useful without schema changes.

### Phase 1 Status

Mostly implemented:

- friend profile now has a stronger structure
- `You vs Them` exists
- action area is more intentional
- top insight banner exists
- cardio posts are rendered more honestly

Still incomplete inside Phase 1:

- streak is not yet clearly visible on friend profiles
- weekly goal progress is not yet surfaced
- stats are still based on available client-side data rather than a proper summary model

### Phase 2: Add Accountability Actions

Goal:
Turn profile views into behavior triggers.

Changes:

- add `Nudge` action
- deep link to create battle
- deep link to challenge creation
- show active battle/challenge state inline

Expected outcome:
Profile becomes a launch point for accountability loops.

### Phase 3: Build Shared Relationship Summary

Goal:
Make the profile about the pair, not just the friend.

Changes:

- shared history module
- battle/challenge record
- friends-since
- trend comparisons across 14 or 30 days

Expected outcome:
The relationship gets continuity and stronger social pressure.

### Phase 4: Server-Composed Summary

Goal:
Reduce latency and complexity.

Changes:

- create `SocialProfileSummary` backend aggregation
- fetch profile in one request
- cache aggressively

Expected outcome:
Cleaner code, faster loads, less state stitching in `ProfileViewModel`.

## Engineering Plan

### UI

Refactor `SocialProfileView` into separate sections/components:

- `SocialProfileHeader`
- `MomentumBanner`
- `AccountabilitySnapshot`
- `HeadToHeadCard`
- `AccountabilityActionsCard`
- `SharedHistoryCard`
- `ProfileActivitySection`

### View model

Replace the current broad `ProfileViewModel` loading pattern with explicit state:

- base profile state
- posts state
- friendship state
- summary state
- action state

### Data

Start by computing these from existing sources:

- post feed
- friendship repository
- local workout store for current user
- challenge repository
- battle repository

Then consolidate.

## Success Metrics

The redesign is successful if it increases:

- profile-to-action conversion
  - battle starts
  - challenge starts
  - run invites
  - nudges sent
- repeat visits to friend profiles
- same-day workout conversion after visiting a friend profile

Secondary metrics:

- friend retention
- streak preservation
- challenge participation

## Risks

1. Data sparsity.
Some users do not share enough workouts for rich profile signals.

Mitigation:
Use recency and weekly progress where possible; degrade cleanly.

2. Privacy mismatch.
Users may not expect detailed momentum visibility.

Mitigation:
Gate sensitive modules behind friendship/privacy settings.

3. Empty action overload.
Too many CTAs can make the profile noisy.

Mitigation:
Promote one primary recommended action, keep others secondary.

4. View-model sprawl.
Adding more async fetches to the existing screen will make it fragile.

Mitigation:
Introduce a summary model early, even if client-composed first.

## Recommended First Build

If we want the highest-value version with the lowest implementation cost, build this first:

1. Replace the current stats row with:
   - `This week`
   - `Last active`
   - `Goal progress`
2. Add a `You vs Them` comparison card.
3. Promote `Start Battle`, `Challenge`, and `Invite to Run` into one action rail.
4. Add a top banner with the single most important accountability insight.

That version alone would make the profile feel like WRKT instead of a generic social page.

## Recommended Next Step From Current State

Given what is already implemented, the next best step is:

1. Add visible streak to both own and friend profile surfaces.
2. Add weekly goal progress to friend profile.
3. Upgrade the top insight banner so it can talk about streak danger and goal danger.
4. Add direct battle / challenge / nudge actions.

If only one thing gets added next, it should be streak visibility.

## Bottom Line

The friend profile should not mainly communicate popularity or posting volume.

It should communicate momentum, pressure, and possibility:

- how this friend is doing
- how they compare to you
- what accountability action should happen next

That is the right social profile for a workout app.
