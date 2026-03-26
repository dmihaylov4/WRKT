# HIG Fix Plan — Home Screen

Derived from HIG audit of the home screen screenshot (2026-03-07).

---

## Fix 1 — Grammar: "1 days left"

**File:** `Features/Home/Components/UnifiedWeeklyStatsCard.swift:59`

**Problem:** Hardcoded plural "days" is always used regardless of the count.

**Current:**
```swift
Text(daysRemaining == 0 ? "Last day!" : "\(daysRemaining) days left")
```

**Fix:**
```swift
Text(daysRemaining == 0 ? "Last day!" : "\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left")
```

**Effort:** 1 line.

---

## Fix 2 — Tab bar label font size: 10pt → 11pt

**File:** `App/AppShellView.swift:800` (`CustomTabBarButton`)

**Problem:** `size: 10` is below the HIG/SF minimum practical label size of 11pt. It won't scale
proportionally at large Dynamic Type sizes.

**Current:**
```swift
.font(.system(size: 10, weight: .medium))
```

**Fix:**
```swift
.font(.system(size: 11, weight: .medium))
```

**Effort:** 1 line.

---

## Fix 3 — Carousel pill indicator breathing room

**File:** `Features/Home/Components/SmartCardCarousel.swift`

**Problem:** The pill indicators sit with `.padding(.vertical, 12)` directly above the tab bar separator.
At the reduced carousel height (160pt) and stats card size, the visual gap feels compressed.

**Current:**
```swift
.padding(.vertical, 12)
```

**Fix:** Increase bottom padding while keeping top padding the same to push indicators away from
the tab bar without adding height above them.

```swift
.padding(.top, 10)
.padding(.bottom, 16)
```

Replace the single `.padding(.vertical, 12)` with the two-line version above.

**Effort:** 2 lines.

---

## Fix 4 — FriendActivityCard content clipping

**File:** `Features/Home/Components/Cards/FriendActivityCard.swift:72`

**Problem:** The card uses `.padding(14)` inside a fixed-height carousel frame (160pt). When 4
activities are present (4 recent → 2 shown + "+ 2 more"), the content exactly fills the frame,
leaving no visual bottom padding. The card feels cut off.

**Root cause:** `title3.weight(.bold)` title + `padding(.top, 2)` + 2 × activity rows (≈36pt each)
+ "+ N more" line totals ~145pt of content inside 14+14=28pt of padding = 173pt > 160pt frame.

**Fix — two options:**

### Option A (preferred): Reduce internal top padding on the title
```swift
// Current line 44/49/54:
.padding(.top, 2)

// Change to:
.padding(.top, 0)
```
Saves 2pt — enough to prevent clipping at the "+ N more" row.

### Option B: Reduce card padding to 12pt (matches UnifiedWeeklyStatsCard)
```swift
// Current line 72:
.padding(14)

// Change to:
.padding(12)
```
Saves 4pt total — gives the content room and visually aligns with the stats card.

**Recommendation:** Option B is cleaner — consistent padding across all carousel cards.

**Effort:** 1 line.

---

## Fix 5 — "9 weeks" streak pill touch target (investigate)

**File:** `Features/Home/Components/HomeHeaderView.swift:27–38`

**Problem:** The streak pill in the header has no tap action and no accessibility label. This is
fine if it's purely decorative/informational, but:
- VoiceOver will either skip it or read it with no context
- If it's ever made tappable, the current 32×28pt size fails the 44×44pt minimum

**Current state:** The pill is non-interactive (no `onTapGesture`, no `Button`). It's a label.

**Fix — accessibility label only (no behavior change):**
```swift
HStack(spacing: 6) {
    Text("\(currentStreak) week\(currentStreak == 1 ? "" : "s")")
        ...
}
.padding(...)
.background(...)
.cornerRadius(12)
.fixedSize()
.accessibilityLabel("\(currentStreak)-week streak")
.accessibilityAddTraits(.isStaticText)
```

This ensures VoiceOver reads it with context instead of just "9 weeks" without a noun.

**Effort:** 2 lines.

---

## Summary

| # | File | Change | Lines |
|---|------|--------|-------|
| 1 | `UnifiedWeeklyStatsCard.swift:59` | Fix "1 days left" plural | 1 |
| 2 | `AppShellView.swift:800` | Tab bar label 10pt → 11pt | 1 |
| 3 | `SmartCardCarousel.swift` | Pill indicator vertical padding | 2 |
| 4 | `FriendActivityCard.swift:72` | Card padding 14 → 12 | 1 |
| 5 | `HomeHeaderView.swift:27` | Streak pill accessibility label | 2 |

**Total:** 7 lines across 5 files. All changes are isolated with no architectural impact.
