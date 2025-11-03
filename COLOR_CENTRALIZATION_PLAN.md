# 🎨 Color Centralization Plan - DS.swift Migration

## 📊 Current State Analysis

### Findings
- **101 hardcoded `Color(hex:)` instances** across Features/
- **33 files** using system colors (.blue, .green, .red, etc.)
- **45 files** with foregroundStyle/background color definitions
- Colors are scattered across:
  - View files (inline definitions)
  - Theme enums (per-feature themes)
  - Models (color mappings)

### Existing DS.swift Structure
✅ Already has:
- `DS.Palette` - Base colors (brand, spice, apricot, saffron, grays)
- `DS.Semantic` - Semantic tokens (brand, surfaces, text, borders)
- `DS.FontType` - Typography system
- `DS.Space`, `DS.Radius` - Layout tokens
- Button styles, Card modifier, Chip component

❌ Missing:
- Status colors (success, warning, error, info)
- State colors (active, inactive, disabled, selected)
- Chart/visualization colors
- Calendar-specific colors
- Workout/exercise state colors

---

## 🎯 Proposed Color System Architecture

### 1. **DS.Colors.Status** (Feedback States)
```swift
public enum Status {
    static let success     = Color.green      // or custom
    static let successBg   = Color.green.opacity(0.12)
    static let warning     = Color.orange
    static let warningBg   = Color.orange.opacity(0.12)
    static let error       = Color.red
    static let errorBg     = Color.red.opacity(0.12)
    static let info        = Color.blue
    static let infoBg      = Color.blue.opacity(0.12)
}
```

**Usage:** Error messages, success toasts, warning badges, info banners

### 2. **DS.Colors.State** (UI States)
```swift
public enum State {
    static let active      = Color(hex: "#F4E409")  // brand yellow
    static let inactive    = Color.gray
    static let disabled    = Color.gray.opacity(0.4)
    static let selected    = Color(hex: "#F4E409")
    static let hover       = Color(hex: "#F4E409").opacity(0.1)
}
```

**Usage:** Buttons, tabs, selections, interactive elements

### 3. **DS.Colors.Charts** (Data Visualization)
```swift
public enum Charts {
    static let push        = Color.purple
    static let pull        = Color.orange
    static let legs        = Color.blue
    static let core        = Color.green

    static let positive    = Color.green.opacity(0.7)
    static let negative    = Color.red.opacity(0.7)
    static let neutral     = Color.gray.opacity(0.7)

    static let gradient1   = [Color.purple, Color.blue]
    static let gradient2   = [Color.orange, Color.yellow]
}
```

**Usage:** Training balance charts, stats graphs, progress visualizations

### 4. **DS.Colors.Calendar** (Workout Calendar)
```swift
public enum Calendar {
    static let workout     = Color(hex: "#F4E409")  // yellow dot
    static let run         = Color.white            // white dot
    static let planned     = Color(hex: "#F4E409").opacity(0.5)
    static let streak      = Color(hex: "#F4E409")  // border
    static let today       = Color(hex: "#F4E409")

    // Planner states
    static let completed   = Color.green
    static let partial     = Color.yellow
    static let skipped     = Color.gray
    static let rescheduled = Color.orange
}
```

**Usage:** CalendarMonthView, PlannerView, workout history

### 5. **DS.Colors.Exercise** (Workout Session)
```swift
public enum Exercise {
    static let current     = Color(hex: "#F4E409")
    static let upNext      = Color.blue
    static let finished    = Color.green
    static let rest        = Color.orange

    // Set types
    static let warmup      = Color.blue.opacity(0.6)
    static let working     = Color(hex: "#F4E409")
    static let backoff     = Color.orange.opacity(0.6)
}
```

**Usage:** ExerciseSessionView, LiveWorkoutOverlay, SetRowViews

### 6. **DS.Colors.Theme** (Dark Mode Variants)
```swift
public enum Theme {
    static let cardTop     = Color(hex: "#121212")
    static let cardBottom  = Color(hex: "#333333")
    static let track       = Color(hex: "#151515")
    static let overlay     = Color.black.opacity(0.85)
}
```

**Usage:** LiveWorkoutOverlay, dark mode surfaces

---

## 📋 File-by-File Migration Plan

### High Priority (Core UI)
1. **LiveWorkoutOverlayCard.swift** (101 lines)
   - Custom theme enum → DS.Colors.Exercise + DS.Colors.Theme
   - System colors (.blue) → DS.Colors.State/Status

2. **CalendarMonthView.swift** (1143 lines)
   - Custom accent → DS.Colors.Calendar.workout
   - .yellow, .orange → DS.Colors.Calendar states

3. **SetRowViews.swift** (complex workout UI)
   - Inline colors → DS.Colors.Exercise

4. **ExerciseSessionView.swift** (large file)
   - Theme colors → DS.Colors.Exercise + DS.Semantic

### Medium Priority (Features)
5. **ProfileStatsSection.swift**
   - .green/.red for trends → DS.Colors.Charts.positive/negative

6. **TrainingBalanceSection.swift**
   - .red/.orange/.green balance → DS.Colors.Charts
   - .purple/.orange muscle groups → DS.Colors.Charts

7. **RestTimerView.swift**
   - Timer colors → DS.Colors.Exercise.rest

8. **WinScreen.swift**
   - Celebration colors → DS.Semantic + new tokens

9. **HomeView.swift + CurrentWorkoutBar.swift**
   - Theme colors → DS.Semantic + DS.Colors.State

### Lower Priority (Supporting)
10. **ProfileView.swift**
    - System colors → DS.Semantic

11. **AchievementsView.swift + DexTile.swift**
    - Badge colors → DS.Colors.Status or custom

12. **Onboarding** (4 files)
    - Brand colors → DS.Semantic.brand
    - Accent colors → DS.Colors.State

13. **HealthKit Views** (5 files)
    - Chart colors → DS.Colors.Charts
    - Status colors → DS.Colors.Status

14. **ExerciseRepository Views** (5 files)
    - Search/filter colors → DS.Colors.State

15. **Remaining hex colors** (~30 files)
    - Map to appropriate DS color category

---

## 🚀 Implementation Strategy

### Phase 1: Setup (1-2 hours)
- [ ] Expand DS.swift with new color enums
- [ ] Add comprehensive inline documentation
- [ ] Create color preview/testing view

### Phase 2: Core UI Migration (3-4 hours)
- [ ] LiveWorkoutOverlayCard
- [ ] CalendarMonthView
- [ ] SetRowViews
- [ ] ExerciseSessionView

### Phase 3: Feature Migration (4-6 hours)
- [ ] Stats & Charts views
- [ ] Timer & Workout views
- [ ] Home & Profile

### Phase 4: Polish (2-3 hours)
- [ ] Onboarding, Achievements, HealthKit
- [ ] ExerciseRepository
- [ ] Remaining files

### Phase 5: Testing & Documentation (2 hours)
- [ ] Visual regression testing
- [ ] Update documentation
- [ ] Create color swapping guide

**Total Estimated Time:** 12-17 hours

---

## ✅ Benefits

1. **Easy Theme Swapping**
   - Change `DS.Palette.brand` from yellow to purple → entire app updates
   - Test different color schemes instantly

2. **Consistency**
   - All "success" states use same green
   - All "current exercise" uses same yellow

3. **Maintainability**
   - Single source of truth for colors
   - Easy to audit which colors are used where

4. **Accessibility**
   - Centralized place to ensure WCAG contrast ratios
   - Easy to add high-contrast theme

5. **Documentation**
   - Self-documenting color system
   - New devs understand color usage instantly

---

## 🎨 Color Testing View (Bonus)

Create `DSColorPreviewView.swift`:
```swift
struct DSColorPreviewView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                colorSection("Status", [
                    ("Success", DS.Colors.Status.success),
                    ("Warning", DS.Colors.Status.warning),
                    ("Error", DS.Colors.Status.error),
                ])

                colorSection("Calendar", [
                    ("Workout", DS.Colors.Calendar.workout),
                    ("Run", DS.Colors.Calendar.run),
                    ("Streak", DS.Colors.Calendar.streak),
                ])

                // ... more sections
            }
        }
    }
}
```

**Usage:** Quick visual check when testing new themes

---

## 📝 Migration Checklist Template

For each file:
- [ ] Identify all hardcoded colors
- [ ] Map to appropriate DS color
- [ ] Replace inline Color(hex:) with DS token
- [ ] Replace system colors (.blue) with DS token
- [ ] Test visual appearance unchanged
- [ ] Commit with descriptive message

---

## 🔄 Rollback Plan

If issues arise:
1. Git revert to pre-migration commit
2. Fix issues in DS.swift
3. Re-run migration script/manually update

---

## 📚 References

- Current DS.swift: `DesignSystem/Theme/DS.swift`
- Color usage audit: See grep results above
- Files with most hex colors:
  - LiveWorkoutOverlayCard.swift
  - CalendarMonthView.swift
  - ProfileStatsSection.swift
  - TrainingBalanceSection.swift

---

## 🎯 Success Criteria

✅ Zero `Color(hex:)` in Features/ (except DS.swift)
✅ All system colors (.blue, .green) mapped to DS tokens
✅ Can swap brand color and see instant app-wide change
✅ No visual regressions in any screen
✅ Documentation updated with color usage guide

---

**Ready to start?** Begin with Phase 1 (Setup) by expanding DS.swift with the new color enums! 🚀
