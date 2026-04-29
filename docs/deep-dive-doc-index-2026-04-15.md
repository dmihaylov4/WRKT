# Deep Dive Doc Index

Date: 2026-04-15
Purpose: single entry point for the current review set, with guidance on which documents are authoritative for which decisions.

## Recommended Reading Order

1. [master-ranked-issues-by-feature-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/master-ranked-issues-by-feature-2026-04-14.md)
2. [fix-roadmap-by-file-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/fix-roadmap-by-file-2026-04-14.md)
3. feature deep dives as needed
4. [cross-app-deep-dive-summary-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/cross-app-deep-dive-summary-2026-04-14.md)
5. [weekly-streak-freeze-investigation-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/weekly-streak-freeze-investigation-2026-04-14.md) for that specific investigation only

## Which Doc Is Authoritative For What

### Priority / sequencing

Authoritative doc:
- [master-ranked-issues-by-feature-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/master-ranked-issues-by-feature-2026-04-14.md)

Use this when:
- deciding what to fix first
- discussing issues by navigation feature
- explaining what each issue breaks

Notes:
- this is the best planning-level doc
- it intentionally excludes the weekly streak/freeze issue because that problem cuts across Profile, Rewards, app lifecycle, and validation logic rather than fitting one reviewed navigation tab cleanly

### Implementation planning

Authoritative doc:
- [fix-roadmap-by-file-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/fix-roadmap-by-file-2026-04-14.md)

Use this when:
- assigning engineering work
- deciding file touch order
- planning sprint slices

Notes:
- this is the best execution doc
- use it after choosing priorities from the master ranked list

### Cross-feature architecture patterns

Authoritative doc:
- [cross-app-deep-dive-summary-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/cross-app-deep-dive-summary-2026-04-14.md)

Use this when:
- discussing repeated architectural problems
- explaining why the same class of bugs keeps recurring
- deciding domain-boundary cleanup strategy

Notes:
- this is a summary layer, not the primary source for issue ranking or file-level work

### Feature-specific evidence

Authoritative docs:
- [train-view-deep-dive-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/train-view-deep-dive-2026-04-14.md)
- [plan-view-deep-dive-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/plan-view-deep-dive-2026-04-14.md)
- [feed-view-deep-dive-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/feed-view-deep-dive-2026-04-14.md)
- [cardio-view-deep-dive-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/cardio-view-deep-dive-2026-04-14.md)
- [profile-view-deep-dive-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/profile-view-deep-dive-2026-04-14.md)

Use these when:
- verifying evidence for a specific issue
- checking citations and code paths
- understanding feature-local context before implementation

Notes:
- these are the primary evidence docs per feature
- if a summary doc and a feature deep dive differ, trust the feature deep dive first

### Weekly streak / freeze investigation

Authoritative doc:
- [weekly-streak-freeze-investigation-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/weekly-streak-freeze-investigation-2026-04-14.md)

Use this when:
- investigating the specific April 14, 2026 weekly streak case
- discussing weekly freeze behavior, cadence, or rebuild logic

Current status:
- this doc was materially corrected after review
- it should be treated as a narrowed investigation doc, not a final root-cause report

What is currently safe to take from it:
- auto-freeze is not implemented
- monthly freeze cadence is not encoded yet
- weekly freeze model/UI path already exists
- next investigation target is rebuild/validation behavior plus freeze interaction

What not to treat as settled:
- exact root cause of the reported stale `13-week` display

## Current Truth Summary

If you need the shortest possible answer set:

- What should we fix first?
  - use [master-ranked-issues-by-feature-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/master-ranked-issues-by-feature-2026-04-14.md)

- How do we implement it?
  - use [fix-roadmap-by-file-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/fix-roadmap-by-file-2026-04-14.md)

- Why do these bugs keep repeating?
  - use [cross-app-deep-dive-summary-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/cross-app-deep-dive-summary-2026-04-14.md)

- Where is the proof for a specific feature issue?
  - use the corresponding feature deep dive

- What is the status of the weekly streak/freeze issue?
  - use [weekly-streak-freeze-investigation-2026-04-14.md](/Users/dimitarmihaylov/dev/WRKT/docs/weekly-streak-freeze-investigation-2026-04-14.md), but treat it as an investigation-in-progress

## Recommended Next Step

If moving from docs to code:

1. Pick the target from the master ranked list.
2. Open the corresponding feature deep dive for evidence.
3. Use the file roadmap to scope the patch.
4. Ignore the weekly streak doc unless that is the issue being worked.
