# CalendarMonthView.swift Refactoring Plan

## 📊 Current State
**CalendarMonthView.swift: 1358 lines** (way too large!)

## Problem
The CalendarMonthView.swift file has grown to over 1358 lines, making it difficult to:
- Navigate and find specific components
- Maintain and debug issues
- Test individual components
- Collaborate with multiple developers
- Reuse components in other parts of the app

---

## 🎯 Refactoring Strategy

Break the monolithic file into 6 focused, maintainable files following the Single Responsibility Principle.

---

## 📁 Target File Structure

### 1. **CalendarUtilities.swift** (~80 lines)
**Purpose:** Helper functions and utilities for calendar operations

**Contents:**
- `timeOnly(_ date: Date) -> String` - Format time display
- `hms(_ seconds: Int) -> String` - Hours/minutes/seconds formatter
- Streak calculation helpers
- Weekly goal calculation helpers
- Date manipulation utilities
- Calendar-specific extensions

**Location:** `Features/Planner/Utilities/CalendarUtilities.swift`

---

### 2. **CalendarBanners.swift** (~200 lines)
**Purpose:** Banner components for displaying streaks and progress

**Components:**
- `StreakBanner` - Daily streak display with fire icon
- `WeeklyStreakBanner` - Weekly goal streak indicator
- `CurrentWeekProgressBanner` - Current week progress with strength days and MVPA minutes
- Shared banner styling and themes

**Location:** `Features/Planner/Components/CalendarBanners.swift`

**Features:**
- Displays current streak length
- Shows weekly goal completion status
- Visual indicators for super weeks (both goals met)
- Consistent styling across all banners

---

### 3. **CalendarGrid.swift** (~250 lines)
**Purpose:** Calendar grid display components

**Components:**
- `MonthHeader` - Month navigation with forward/back buttons
- `WeekdayRow` - Day of week labels (Mon, Tue, Wed, Thu, Fri, Sat, Sun)
- `DayCellV2` - Individual day cells with:
  - Activity indicators (workout/run dots)
  - Streak highlighting
  - Weekly goal completion highlighting
  - Super week highlighting
  - Selection state
- Grid layout logic with 7 columns

**Location:** `Features/Planner/Components/CalendarGrid.swift`

**Features:**
- Prevents navigation into future months
- Shows current day indicator
- Visual feedback for completed weeks
- Handles empty cells for month padding

---

### 4. **DayDetailView.swift** (~400 lines)
**Purpose:** Detailed view of a specific day's activities

**Components:**
- `DayDetail` - Main container for day details
- `DailySummaryCard` - Aggregate statistics:
  - Number of workouts
  - Exercise count
  - Total sets
  - Total reps
- `WorkoutRow` - Individual workout item display
- `SectionHeader` - Section titles with counts
- Run display logic

**Location:** `Features/Planner/Components/DayDetailView.swift`

**Features:**
- Fetches and displays workouts for selected day
- Shows cardio/runs data
- Empty state when no activity
- Clean, minimal design

---

### 5. **PlannedWorkoutComponents.swift** (~200 lines)
**Purpose:** Components for planned/scheduled workouts

**Components:**
- `PlannedWorkoutCard` - Displays planned workout details:
  - Split day name
  - Workout status (scheduled/completed/partial/skipped/rescheduled)
  - Exercise preview (first 3 exercises)
  - Start workout button
  - Completion indicator

**Location:** `Features/Planner/Components/PlannedWorkoutComponents.swift`

**Features:**
- Shows planned workouts for selected day
- Status badges with appropriate colors
- "Start Workout" button to begin planned workout
- Date mismatch alert when starting on wrong day
- Visual distinction between completed and planned workouts

---

### 6. **CalendarMonthView.swift** (~250 lines) ✨
**Purpose:** Main calendar view coordination and state management

**Responsibilities:**
- Overall layout and view hierarchy
- State management (`@State` variables)
- Navigation logic
- Tutorial/onboarding integration
- Data fetching coordination
- Environment object management

**Location:** `Features/Planner/CalendarMonthView.swift` (existing file, cleaned up)

**Contents:**
- Main `CalendarMonthView` struct
- View composition using extracted components
- Navigation helpers
- Tutorial logic
- Data helpers

---

## 📈 Expected Results

### Line Count Comparison:
| File | Lines | Purpose |
|------|-------|---------|
| **Before** |
| CalendarMonthView.swift | 1358 | Everything |
| **After** |
| CalendarUtilities.swift | ~80 | Utilities |
| CalendarBanners.swift | ~200 | Banners |
| CalendarGrid.swift | ~250 | Grid components |
| DayDetailView.swift | ~400 | Day detail |
| PlannedWorkoutComponents.swift | ~200 | Planned workouts |
| CalendarMonthView.swift | ~250 | Main coordination |
| **Total** | **~1380** | Well organized |

### Main File Reduction:
**1358 lines → 250 lines (82% reduction!)**

---

## ✅ Benefits of This Refactoring

### 🎯 Organization
- Each file has a clear, single purpose
- Easy to find specific components
- Logical grouping of related functionality

### 🔧 Maintainability
- Changes are isolated to specific files
- Reduced risk of breaking unrelated features
- Easier to understand component dependencies

### 🧪 Testability
- Components can be tested in isolation
- Easier to write unit tests for individual pieces
- Reduced complexity in each test

### 👥 Collaboration
- Multiple developers can work on different components simultaneously
- Reduced merge conflicts
- Clear ownership of specific features

### 📦 Reusability
- Components can be imported and used elsewhere in the app
- Banner components could be used in other views
- Day detail components could be reused in workout history

### 🚀 Performance
- Smaller files compile faster
- Easier for Xcode to index
- Better code completion performance

---

## 🔄 Implementation Steps

1. **Create CalendarUtilities.swift**
   - Extract utility functions
   - Add proper imports
   - Test functionality

2. **Create CalendarBanners.swift**
   - Extract banner components
   - Ensure proper environment object access
   - Verify styling is preserved

3. **Create CalendarGrid.swift**
   - Extract grid components
   - Maintain calendar layout logic
   - Test month navigation

4. **Create DayDetailView.swift**
   - Extract day detail components
   - Preserve data fetching logic
   - Test workout and run display

5. **Create PlannedWorkoutComponents.swift**
   - Extract planned workout card
   - Maintain start workout functionality
   - Test status indicators

6. **Clean up CalendarMonthView.swift**
   - Remove all extracted components
   - Add imports for new files
   - Maintain same public API
   - Verify view still works correctly

7. **Build and Test**
   - Full compilation test
   - Manual testing of all calendar features
   - Verify no regressions

---

## 🎨 Design Principles Applied

### Single Responsibility Principle
Each file/component has one reason to change:
- Utilities change when calculation logic changes
- Banners change when streak display changes
- Grid changes when calendar layout changes
- Day detail changes when activity display changes
- Planned workouts change when planning features change

### Separation of Concerns
- UI components separated from business logic
- Data fetching separated from display
- Styling separated into focused components

### DRY (Don't Repeat Yourself)
- Shared utilities extracted to single location
- Common styling patterns consolidated
- Reusable components for repeated UI elements

### Composition Over Inheritance
- Small, focused components composed together
- Each component is independently testable
- Easy to swap or modify individual pieces

---

## 📝 Notes

- All extracted files should maintain the same functionality
- Public API of CalendarMonthView should remain unchanged
- Environment objects should be properly passed to child components
- Maintain existing naming conventions
- Preserve all tutorial/onboarding functionality
- Keep all accessibility features intact

---

## ✨ Future Improvements

After this refactoring, consider:
- Creating unit tests for each component
- Adding SwiftUI previews for individual components
- Further breaking down large components if needed
- Extracting shared calendar logic into a view model
- Creating a CalendarTheme file for consistent styling

---

**Created:** 2025-11-03
**Status:** Ready for implementation
**Estimated Time:** 2-3 hours
**Risk Level:** Low (extract and test incrementally)
