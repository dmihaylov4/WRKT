# Planner Module Structure

## File Organization

```
Features/Planner/
├── PlannerSetupCarouselView.swift (519 lines)
│   └── Main coordinator for split creation workflow
│
├── CalendarMonthView.swift
│   └── Monthly calendar view for workouts
│
├── PlannerDebugView.swift
│   └── Debug utilities for planner
│
├── Models/
│   └── SplitValidation.swift
│       └── Validation rules and warnings for custom splits
│
├── Services/
│   └── CustomSplitStore.swift
│       └── Persistence layer for custom workout splits
│
└── Views/
    ├── Shared/
    │   ├── SplitTemplateCard.swift (78 lines)
    │   ├── CreateCustomSplitCard.swift (67 lines)
    │   └── RestDayOptionCard.swift (52 lines)
    │
    ├── Components/
    │   └── ExerciseEditSheet.swift (74 lines)
    │
    ├── PredefinedSplit/
    │   ├── Step1ChooseSplit.swift (97 lines)
    │   ├── Step2TrainingFrequency.swift (145 lines)
    │   ├── Step3RestDays.swift (77 lines)
    │   ├── Step4CustomizeExercises.swift (638 lines)
    │   ├── Step5ProgramLength.swift (107 lines)
    │   └── Step6Review.swift (62 lines)
    │
    └── CustomSplit/
        ├── CustomSplitSteps.swift (313 lines)
        └── CustomSplitExercisePicker.swift (253 lines)
```

## Component Responsibilities

### Main Coordinator
**PlannerSetupCarouselView.swift**
- Step navigation and progress tracking
- Validation logic for both predefined and custom splits
- Plan generation and persistence
- Conversion from ExerciseTemplate to PlanBlockExercise

### Shared Components
Reusable UI components used across multiple views:
- `SplitTemplateCard`: Displays split template information
- `CreateCustomSplitCard`: Button to create custom splits
- `RestDayOptionCard`: Rest day placement options

### Predefined Split Flow (6 steps)
1. **Step1**: Choose from predefined or custom splits
2. **Step2**: Select training frequency (days per week)
3. **Step3**: Choose rest day placement
4. **Step4**: Customize exercises (optional)
5. **Step5**: Set program length (weeks)
6. **Step6**: Review and confirm

### Custom Split Flow (5 steps)
1. **Step1**: Name split + choose parts + name parts
2. **Step2**: Add exercises to each part (3-10 per part)
3. **Step3**: Set frequency + rest days
4. **Step4**: Program length
5. **Step5**: Review

## Key Fixes Applied

1. ✅ Removed `private` visibility from all view structs
2. ✅ Fixed `Haptics.success()` → `Haptics.soft()`
3. ✅ Added type conversion: `ExerciseTemplate` → `PlanBlockExercise`
4. ✅ Moved files to correct locations
5. ✅ Removed duplicate files

## Import Requirements

All step files import:
```swift
import SwiftUI
import Combine  // For Step4 only
```

Main coordinator imports:
```swift
import SwiftUI
import Combine
import SwiftData
import OSLog
```

## Total Line Count
- **Before Refactor**: 2,256 lines (single file)
- **After Refactor**: 519 lines (main coordinator) + distributed across 14 files
- **Reduction**: 77% in main file size
