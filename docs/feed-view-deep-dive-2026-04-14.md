# Feed View Deep Dive

Date: 2026-04-14
Scope: `SocialView`, `FeedView`, `FeedViewModel`, `PostRepository`, `PostCard`, `PostDetailViewModel`, `EditPostView`, realtime ownership around feed

## Executive Summary

Feed View works, but the implementation has several structural correctness problems:

1. Deleting a post is reversible in UI only; "undo" recreates a different post instead of restoring the original one.
2. Feed pagination is built from two separately paginated queries that are merged client-side, so cursors and `hasMore` are not trustworthy.
3. Feed cards perform hidden network/storage mutations during render, which makes scrolling capable of mutating backend state.
4. Comment-count consistency is patched through `NotificationCenter` and local cache edits rather than maintained by one durable source of truth.
5. Cardio refresh in post detail updates only in-memory state, so refreshed data is lost when leaving the screen.
6. Realtime ownership is fragmented across social root and feed-specific view models, which makes lifecycle behavior harder to reason about.

The dominant theme is ownership drift: repository, view model, and view all mutate social state directly.

## Findings

### 1. "Undo Delete" is not a real undo

Severity: High

`FeedViewModel.deletePost(_:)` optimistically removes the post and then shows an undo callback after backend deletion succeeds ([Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift:257)). But `undoDeletePost(_:at:)` does not restore the deleted record. It recreates a new post via `postRepository.createPost(...)` ([Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift:287), [Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift:302)).

Implications:

- restored post gets a new post id
- restored post gets a new `createdAt` / ordering position
- likes/comments/shares tied to old post are gone
- any foreign keys or notifications targeting the old post now point at a deleted entity
- UI claims "undo", but behavior is actually "repost similar content"

Recommendation:

- Either remove undo for destructive delete and use a confirm-only flow, or implement soft delete with a reversible `deleted_at` / tombstone model.
- If product requires undo, the invariant should be: undo restores the same logical post identity, not a reconstructed approximation.

### 2. Feed pagination is structurally unreliable

Severity: High

`PostRepository.fetchFeed(...)` runs one query for own posts and another for everyone else, each with its own `created_at < cursor` filter, then merges the arrays, sorts client-side, and truncates to `limit` ([Features/Social/Services/PostRepository.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Services/PostRepository.swift:71), [Features/Social/Services/PostRepository.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Services/PostRepository.swift:91), [Features/Social/Services/PostRepository.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Services/PostRepository.swift:110), [Features/Social/Services/PostRepository.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Services/PostRepository.swift:135)). `FeedViewModel` then uses the merged page's last post timestamp as the next cursor and treats `posts.count == limit` as `hasMore` ([Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift:94), [Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift:183)).

Why this is wrong:

- each source query paginates independently, but only one merged cursor is carried forward
- `hasMore = posts.count == limit` is not evidence that either underlying source still has more rows beyond the merged boundary
- a dense own-post stream can crowd out friend posts from one page, then a later page can still surface older friend posts in surprising order
- equal timestamps are not handled with a stable tiebreaker, so duplicates/skips remain possible even with `< cursor`
- `loadMore()` appends blindly with no dedupe ([Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift:165), [Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift:180))

Recommendation:

- Move feed ranking/pagination into one backend query or RPC that returns one globally ordered stream.
- Cursor should be based on a stable composite ordering key, typically `(created_at, id)`.
- `hasMore` should be derived from overfetching one extra row from that single ordered stream.
- Client should still dedupe by `post.id` before append as a defensive guard.

### 3. Feed cards mutate backend state during rendering

Severity: High

`PostCard` launches a `.task` on render, loads image URLs, and for the current user's cardio post with no display image it starts a route-map backfill flow ([Features/Social/Views/Components/PostCard.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/Components/PostCard.swift:116)). That flow fetches HealthKit data, generates a snapshot, uploads the image, instantiates a fresh `PostRepository`, patches the post record, then reloads image URLs ([Features/Social/Views/Components/PostCard.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/Components/PostCard.swift:171), [Features/Social/Views/Components/PostCard.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/Components/PostCard.swift:218)).

This is the wrong layer. A scroll surface should not silently:

- read HealthKit
- generate assets
- upload files
- mutate backend post records

Risks:

- scrolling into view can trigger writes
- repeated mounts can retry the same write work
- hard to test because render lifecycle now owns persistence side effects
- bypasses dependency injection by creating `PostRepository()` directly

Recommendation:

- Backfill should be an explicit command owned by a coordinator/use-case/service, not a view `.task`.
- The feed card should render state only.
- If lazy backfill is required, trigger it from a write-aware orchestration layer with idempotency protection and observable status.

### 4. Edit flow repeats the same ownership mistake

Severity: Medium-High

`EditPostView` also contains route rebuild logic inside the view itself. It fetches HealthKit route data, builds a map, uploads it, creates `PostRepository()` directly, and updates post images ([Features/Social/Views/EditPostView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/EditPostView.swift:154), [Features/Social/Views/EditPostView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/EditPostView.swift:206)). At the same time, the actual "save" button only calls `onSave(finalCaption, currentVisibility)` ([Features/Social/Views/EditPostView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/EditPostView.swift:224)).

This creates split persistence semantics:

- caption/visibility save goes through parent closure
- route backfill writes immediately from inside the sheet
- `hasChanges` becomes true when route backfill succeeded, even if text/visibility never changed ([Features/Social/Views/EditPostView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/EditPostView.swift:216))

Recommendation:

- Make edit screen state-only.
- Route rebuild should be exposed as an explicit async action on a view model/use case.
- Save semantics should be coherent: one screen, one owner, one persistence contract.

### 5. Comment-count sync is patched, not modeled

Severity: Medium-High

`PostDetailViewModel.loadComments()` fetches comments, recalculates the count from the loaded tree, patches `CacheManager`, and then broadcasts `.postCommentCountDidChange` via `NotificationCenter` so feed rows can patch their local post copy ([Features/Social/ViewModels/PostDetailViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/PostDetailViewModel.swift:40), [Features/Social/ViewModels/PostDetailViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/PostDetailViewModel.swift:56), [Features/Social/ViewModels/PostDetailViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/PostDetailViewModel.swift:58)). `FeedViewModel` subscribes to that notification in `init` and mutates local feed state when it arrives ([Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift:45)).

Problems:

- feed correctness depends on a detail screen side effect
- comment counts can differ until someone opens the post detail
- there is no visible observer teardown for the `NotificationCenter` observer token
- count repair is local and opportunistic, not systemic

Recommendation:

- Choose one authority for comment counts.
- Best options:
  - maintain durable counts at write time in backend/database
  - or treat counts as derived, stop storing them redundantly, and compute them in feed fetches / materialized views
- Avoid `NotificationCenter` patch relays for core data correctness.

### 6. Cardio refresh in post detail is ephemeral

Severity: Medium

`PostDetailViewModel.refreshCardioData()` fetches fresh splits/HR zones from HealthKit and updates only the in-memory `post` state ([Features/Social/ViewModels/PostDetailViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/PostDetailViewModel.swift:265)). It does not persist the updated `workoutData` back through `PostRepository`, invalidate caches, or inform the feed.

Result:

- user can refresh data and see updated numbers
- leaving and reopening can drop the change
- feed and detail can disagree permanently until some other write path updates the post

Recommendation:

- Either make cardio refresh a real persistence operation or label it clearly as temporary/local preview.
- Given app semantics, persistence is probably the intended behavior.

### 7. Realtime ownership is fragmented

Severity: Medium

`SocialView` starts global notification badge realtime in its `.task` ([Features/Social/Views/SocialView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/SocialView.swift:95)). Separately, `FeedView` creates a `FeedViewModel` in `.task`, subscribes it to feed-post inserts, and relies on `.onDisappear` for cleanup ([Features/Social/Views/FeedView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/FeedView.swift:171), [Features/Social/Views/FeedView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/FeedView.swift:186)).

The subscription itself listens to all inserts on `workout_posts` with no server-side user/friend filter in the realtime subscription ([Features/Social/Services/RealtimeService.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Services/RealtimeService.swift:39), [Features/Social/Services/RealtimeService.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Services/RealtimeService.swift:53)). `FeedViewModel.handleNewPost(_:)` then just increments a banner counter for any non-self post ([Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift:404)). The banner appears in `FeedView` and simply triggers a full refresh ([Features/Social/Views/FeedView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/FeedView.swift:250), [Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift:417)).

This is workable, but ownership is muddy:

- social root owns one realtime family
- feed VM owns another
- cleanup depends on view disappearance timing
- insert handling does not verify whether the new post actually belongs in the current feed slice before incrementing the banner

Recommendation:

- Centralize social realtime ownership per domain:
  - app/session-level owner for notification badges
  - feed-specific owner for feed inserts with explicit lifecycle
- Realtime payload handling should validate feed eligibility before mutating UI counters.
- If feed uses refresh-on-banner instead of live insertion, document that as the intended product behavior.

### 8. Feed view lifecycle is more fragile than it needs to be

Severity: Medium

`FeedView` stores the view model in `@State` optional, creates it inside `.task`, and cleans it up from `.onDisappear` ([Features/Social/Views/FeedView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/FeedView.swift:14), [Features/Social/Views/FeedView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/FeedView.swift:171), [Features/Social/Views/FeedView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/FeedView.swift:186)).

This works, but it gives lifecycle control to view mount/unmount events rather than a stable owner. In a navigation-heavy area with sheets, tab switching, and custom ids, that makes subscription and cleanup behavior harder to reason about.

Recommendation:

- Give feed state a more explicit owner.
- Options:
  - use a long-lived screen model owned by parent navigation scope
  - or make feed VM lifecycle explicit through dependency container / coordinator creation
- If the current pattern remains, cleanup and subscription behavior should be tested under tab switches, sheet presentation, and repeated social-root entry/exit.

## Efficiency / Simplicity Opportunities

1. Replace dual-query merge pagination with one backend feed query.
2. Remove `NotificationCenter` from feed/detail comment sync path.
3. Move map backfill and cardio refresh into dedicated social-post commands/use cases.
4. Inject repositories/services instead of instantiating `PostRepository()` inside views.
5. Add append-time dedupe by `post.id` in `loadMore()` as a defensive guard.
6. Define a single write model for post editing, route images, and cardio data enrichment.

## Suggested Refactor Order

1. Fix delete/undo semantics first because current behavior is user-visible and misleading.
2. Replace feed pagination/query model because it affects correctness, duplicates, and performance.
3. Extract view-owned write side effects from `PostCard` and `EditPostView`.
4. Normalize post-detail/feed synchronization around one source of truth.
5. Then clean up lifecycle and realtime ownership once data flow is simpler.

## Open Questions

1. Is route-map backfill intended to be silent and automatic, or should users explicitly request it?
2. Should cardio refresh be a local "recompute for display" feature or a persisted post enrichment feature?
3. Is the feed intended to show only friends + self, or is there broader discovery logic hidden in RLS/policies?
4. Is delete supposed to be reversible product-wise, or is current undo just a convenience placeholder?

## Bottom Line

Feed View has solid UI coverage, but its data flow is not clean. The biggest mistakes are mixed ownership and misleading mutation semantics. The code will get simpler and more correct if feed ordering, social mutations, and background enrichment all move out of views and into one explicit social data flow.

---

## Review

Date reviewed: 2026-04-15

### Verified as accurate

**Finding 1 -- "Undo delete" creates a new post**: Confirmed. `FeedViewModel.undoDeletePost` at line 288 calls `postRepository.createPost(...)`, producing a new post with a new ID and timestamp. The original row was hard-deleted. Likes, comments, and identity are permanently gone.

**Finding 2 -- Feed pagination dual-query merge**: Confirmed by the PostRepository structure: two separate cursored queries (own posts + others) are merged and truncated client-side. `FeedViewModel:94` uses the merged page's last timestamp as the next cursor, and `posts.count == limit` as `hasMore`. Both are unreliable across sources with independent densities.

**Finding 3 -- PostCard triggers backend writes during render**: Confirmed. `PostCard.swift:116` launches a `.task` on render; for a matching cardio post it fetches HealthKit data, generates a map snapshot, uploads it, and patches the backend record via a directly instantiated `PostRepository()` at line 218. Scrolling is a write path.

**Finding 5 -- Comment count sync via NotificationCenter**: Confirmed pattern. The description of `PostDetailViewModel` broadcasting `.postCommentCountDidChange` for `FeedViewModel` to patch local state is consistent with the code structure.

**Finding 8 -- FeedView lifecycle tied to mount/unmount**: Confirmed. `FeedView.swift:14` declares `@State private var viewModel: FeedViewModel?`, i.e. an optional created lazily in `.task` and destroyed in `.onDisappear`.

**Finding 7 -- Realtime new-post eligibility is broad**: Confirmed. `RealtimeService.subscribeToNewPosts` subscribes to inserts on `workout_posts` without feed-specific filter, and `FeedViewModel.handleNewPost(_:)` increments `newPostsAvailable` for any non-self post. The banner can therefore announce posts that are not guaranteed to belong in the user’s effective feed.

### No issues found

All file paths reference real files. All line number citations are close to correct within the referenced code areas.
