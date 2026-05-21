# Battle Result Screen + Feed Post Design

**Date:** 2026-05-21
**Status:** Approved

---

## Problem

When a battle completes, nothing happens. No result screen, no feed post, no notification. Users discover the outcome only by navigating to the Battles tab and reading final scores. There is no share mechanism.

---

## Scope

1. Fullscreen battle result overlay (both participants)
2. Push notification on battle completion
3. Feed post (`PostType.battle`) with head-to-head stats
4. One-global-share-per-battle lock via `shared_post_id` on the battle row

---

## 1. Result Overlay

### Trigger

**Primary path (in-session):** After `BattleRepository.completeBattle()` succeeds, it returns the completed `BattleWithParticipants`. The caller sets `BattleViewModel.pendingResultBattle` immediately. The Compete tab shows the overlay via a `.fullScreenCover`.

**Fallback path (app open):** `BattleViewModel.loadBattles()` filters for completed battles whose IDs are not in `UserDefaults["seenBattleResultIds"]` (a `[String]` stored as JSON). The first unseen battle is set as `pendingResultBattle`; all unseen IDs are added to the seen set immediately (before the overlay appears, to avoid re-showing on crash recovery — the user can always navigate to Battles tab to see the result again).

### View: `BattleResultOverlay`

- Full-screen dark background (`Color.black.ignoresSafeArea()`)
- Staggered reveal animation sequence (same timing: icon → title → stat rows → buttons)
- All text via `.dsFont()`, all colors via `DS.Semantic.*` / `DS.Theme.*`
- All card shapes via `ChamferedRectangle`

**Layout:**

```
[icon]                        ← challenge-trophy-icon (win) or battle-type icon (loss)
[headline]                    ← "You Won!" or "Battle Complete"
[subtitle]                    ← "vs {opponentName} · {battleType.displayName}"
[score card]                  ← two-column: You | Opponent, winner score in DS.Semantic.accentWarm
[battle type icon + label]    ← custom asset icon per BattleType
[Share Result]                ← primary button, or "Already Shared" grayed
[Continue]                    ← secondary/text button
```

**Icon mapping** (promoted to `BattleType.customIconName: String`):
- `.volume` → `"battle-volume-icon"`
- `.consistency` → `"battle-consistency-icon"`
- `.workoutCount` → `"battle-workout-count-icon"`
- `.pr` → `"battle-flags-icon"`
- `.exercise` → `"battle-opponent-icon"`
- `.runningDistance` → `"battle-flags-icon"`

Header icon:
- Winner → `"challenge-trophy-icon"`
- Loser → `battle.battleType.customIconName`

Winner score highlighted in `DS.Semantic.accentWarm`. Loser score in `DS.Semantic.textPrimary`.

**"Already Shared" check:** `BattleWithParticipants` carries `battle.sharedPostId: UUID?`. If non-nil and `battle.sharedByUserId != currentUserId`, Share button label is "Already Shared", disabled, foreground `DS.Semantic.textSecondary`.

If the current user was the one who shared (i.e., `sharedByUserId == currentUserId`), the button shows "Shared" (past tense, also disabled).

### Dismiss

Tapping "Continue" calls `BattleViewModel.dismissResult()` which nils `pendingResultBattle`. The overlay is not re-shown (ID already in seen set).

---

## 2. Push Notification

### Trigger point

Client calls a new Supabase RPC `send_battle_completed_notifications(p_battle_id UUID)` immediately after the DB update in `completeBattle()` succeeds.

### RPC behavior

- Looks up both participant user IDs
- Sends push to both: "Battle Complete — {winnerName} won the {battleType} battle!"
- Uses the same push infrastructure as `send_battle_ending_soon_notifications`
- Idempotent: checks `battles.status = 'completed'` before sending; stores a flag to avoid double-sending if called twice

### Notification tap

Taps navigate to the Battles tab. The result overlay appears automatically because the app-open fallback in `loadBattles()` catches the unseen completed battle.

---

## 3. Feed Post

### New `PostType` case

```swift
enum PostType: String, Codable, Sendable, Hashable {
    case workout = "workout"
    case weeklyProgress = "weekly_progress"
    case battle = "battle"          // NEW
}
```

### New `BattlePostStats` struct

```swift
struct BattlePostStats: Codable, Sendable, Equatable, Hashable {
    let battleId: UUID
    let battleType: BattleType
    let myScore: Decimal
    let opponentScore: Decimal
    let opponentName: String
    let opponentAvatarUrl: String?
    let scoreUnit: String
    let isWinner: Bool
    let durationDays: Int
    let endDate: Date

    enum CodingKeys: String, CodingKey {
        case battleId = "battle_id"
        case battleType = "battle_type"
        case myScore = "my_score"
        case opponentScore = "opponent_score"
        case opponentName = "opponent_name"
        case opponentAvatarUrl = "opponent_avatar_url"
        case scoreUnit = "score_unit"
        case isWinner = "is_winner"
        case durationDays = "duration_days"
        case endDate = "end_date"
    }
}
```

`WorkoutPost` gains `var battleStats: BattlePostStats?` (optional, nil for all existing post types).

### Feed card: `BattlePostCard`

Displayed inside `PostCard.postContent` when `post.postType == .battle`. Follows the same two-column stat layout used in `WeeklyProgressFeedCard`:

- Header row: battle-type custom icon + `battleType.displayName` + win/loss badge ("Won" in `DS.Semantic.accentWarm`, "Lost" in `DS.Semantic.textSecondary`)
- Stat row: "Your Score" | "Opponent Score" — winner column highlighted
- Footer: `{durationDays}-day battle · ended {endDate formatted relative}`

All fonts `.dsFont()`, all colors `DS.Semantic.*`, card background `DS.Semantic.card`, shape `ChamferedRectangle`.

### Sharing

`BattleRepository.shareResult(battle:, currentUserId:)` async throws:

1. Builds a `WorkoutPost` with `postType: .battle`, `battleStats` populated from the `BattleWithParticipants`, `workoutData` set to a minimal placeholder `CompletedWorkout` (required by the existing schema — battle posts have no strength workout data).
2. Inserts the post via `PostRepository`.
3. Updates `battles SET shared_post_id = {newPostId}, shared_by_user_id = {currentUserId}` for the battle row.
4. Returns the created `WorkoutPost`.

If step 3 fails after step 2 succeeds (network drop), the post exists but the lock is not set — the other user could also share. Acceptable edge case given the low frequency.

---

## 4. Database Changes

### `battles` table

```sql
ALTER TABLE battles
  ADD COLUMN shared_post_id UUID REFERENCES posts(id) NULL,
  ADD COLUMN shared_by_user_id UUID REFERENCES profiles(id) NULL;
```

### `posts` table

```sql
ALTER TABLE posts
  ADD COLUMN battle_stats JSONB NULL;
```

### `post_type` enum (if stored as PG enum; otherwise string column needs no migration)

```sql
ALTER TYPE post_type ADD VALUE IF NOT EXISTS 'battle';
```

### New RPC

```sql
CREATE OR REPLACE FUNCTION send_battle_completed_notifications(p_battle_id UUID)
RETURNS void ...
```

(Implementation mirrors `send_battle_ending_soon_notifications`.)

---

## 5. Unit Tests

### `BattleResultTriggerTests`

- In-session: after `completeBattle()` mock returns, `pendingResultBattle` is set on `BattleViewModel`
- Fallback: `loadBattles()` with a completed battle not in seen set → `pendingResultBattle` set, ID added to seen set
- Fallback: `loadBattles()` with a completed battle already in seen set → `pendingResultBattle` stays nil
- Dismiss: `dismissResult()` nils `pendingResultBattle`
- Multiple unseen completed battles: only the most-recently-ended one is shown (others are also marked seen)

### `BattleShareTests`

- `shareResult()` calls `PostRepository.createPost` then updates battle row with `shared_post_id`
- Second call to `shareResult()` for a battle with `sharedPostId != nil` throws without creating a duplicate post
- `BattleResultOverlay` shows "Already Shared" when `sharedPostId` non-nil and `sharedByUserId != currentUserId`
- `BattleResultOverlay` shows "Shared" when `sharedByUserId == currentUserId`

### `BattlePostStatsTests`

- `BattlePostStats` encodes to expected JSON keys (snake_case)
- `BattlePostStats` round-trips correctly for all `BattleType` variants
- `WorkoutPost` decodes correctly when `battle_stats` is present (postType == .battle)
- `WorkoutPost` decodes correctly when `battle_stats` is absent (postType == .workout, backward compat)

### `BattleResultDisplayTests`

- Winner state: headline = "You Won!", icon = `challenge-trophy-icon`, score color = `DS.Semantic.accentWarm`
- Loser state: headline = "Battle Complete", icon = `battleType.customIconName`
- `BattleType.customIconName` returns correct asset name for each case
- Score formatting: decimal scores formatted per scoreUnit
- Tie state: no winner highlight, share still available

### `BattleCompletionFlowTests` (integration, mockable Supabase)

- `completeBattle()` with user leading → `winnerId == userId`, notification RPC called, `pendingResultBattle` set
- `completeBattle()` with user losing → `winnerId == opponentId`, notification RPC called, `pendingResultBattle` set
- `completeBattle()` with tied score → `winnerId == nil`, overlay shows tie state

### Supabase-assisted manual testing checklist

(For artificially completing battles via Supabase console)

1. Set `battles.status = 'completed'`, `winner_id = {userId}`, `end_date = now() - interval '1 second'`
2. On next app launch: result overlay appears, shows "You Won!"
3. Tap Share: post appears in feed, `shared_post_id` set on battle row
4. Log in as opponent: result overlay appears, Share button shows "Already Shared"
5. Verify feed post card renders correctly for both users

---

## Non-goals

- Push notification when opponent's workout scores points mid-battle (separate feature)
- Comments on battle posts (inherits from PostCard automatically)
- Battle post visibility controls (defaults to public, same as other auto-posts)
- Retroactive result screens for battles that completed before this feature ships
