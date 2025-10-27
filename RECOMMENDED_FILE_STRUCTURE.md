# WRKT App - Optimal File Structure

## Overview
This structure follows **feature-based organization** with clear separation of concerns. Each feature module is self-contained with its own models, views, and logic.

---

## 📁 Recommended Structure

```
WRKT/
├── App/
│   ├── WRKTApp.swift                    ← Main app entry point
│   ├── AppShellView.swift               ← Root navigation/tab container
│   ├── WRKT.entitlements
│   └── Info.plist
│
├── Core/
│   ├── Dependencies/
│   │   └── AppDependencies.swift        ← FROM: Utilities/AppDependencies.swift (KEEP THIS ONE)
│   │
│   ├── Persistence/
│   │   ├── WorkoutStorage.swift         ← Main persistence layer (KEEP)
│   │   └── ModelContainer+Extensions.swift
│   │
│   ├── Models/                          ← Shared models used across features
│   │   ├── CompletedWorkout.swift       ← FROM: AppModels/Models.swift (extract)
│   │   ├── CurrentWorkout.swift         ← FROM: AppModels/Models.swift (extract)
│   │   ├── WorkoutEntry.swift           ← FROM: AppModels/Models.swift (extract)
│   │   ├── ExerciseDefinition.swift     ← FROM: AppModels/Models.swift (extract)
│   │   ├── ExercisePR.swift             ← FROM: AppModels/ExercisePR.swift
│   │   ├── ExerciseMapping.swift        ← FROM: AppModels/ExerciseMapping.swift
│   │   └── DS.swift                     ← FROM: AppModels/DS.swift (design system)
│   │
│   ├── Utilities/
│   │   ├── Haptics.swift                ← FROM: Haptics/Haptics.swift
│   │   ├── AppEvents.swift              ← FROM: Utilities/AppEvents.swift
│   │   ├── Notifications.swift          ← FROM: Utilities/Notifications.swift
│   │   ├── Utilities.swift              ← FROM: Utilities/Utilities.swift
│   │   ├── WeightSuggestionHelper.swift ← FROM: Utilities/WeightSuggestionHelper.swift
│   │   └── OnboardingManager.swift      ← FROM: Utilities/OnboardingManager.swift
│   │
│   └── Extensions/
│       └── (common Swift extensions)
│
├── Features/
│   │
│   ├── Onboarding/
│   │   ├── OnboardingCarousel.swift     ← FROM: Views/OnboardingCarousel.swift
│   │   ├── WeeklyGoalSetupView.swift    ← FROM: AppModels/WeeklyGoalSetupView.swift
│   │   └── NotificationPermissionView.swift ← FROM: Views/NotificationPermissionView.swift (DELETE the "2" version)
│   │
│   ├── Home/
│   │   ├── HomeView.swift               ← FROM: HomeView.swift
│   │   └── CurrentWorkoutBar.swift      ← FROM: CurrentWorkoutBar.swift
│   │
│   ├── ExerciseRepository/
│   │   ├── Models/
│   │   │   ├── ExerciseCache.swift      ← FROM: ExcerciseRepository/ExerciseCache.swift (DELETE "2" version)
│   │   │   ├── ExerciseFilters.swift    ← FROM: ExcerciseRepository/ExerciseFilters.swift
│   │   │   └── FavoritesStore.swift     ← FROM: WorkoutStore/FavoritesStore.swift
│   │   │
│   │   ├── Views/
│   │   │   ├── ExerciseBrowserView.swift    ← FROM: ExcerciseRepository/ExerciseBrowserView.swift
│   │   │   ├── BodyBrowse.swift             ← FROM: ExcerciseRepository/BodyBrowse.swift
│   │   │   ├── EmptyExercisesView.swift     ← FROM: ExcerciseRepository/EmptyExercisesView.swift
│   │   │   ├── ExerciseMedia.swift          ← FROM: ExcerciseRepository/ExerciseMedia.swift
│   │   │   ├── YouTubeInlinePlayer.swift    ← FROM: ExcerciseRepository/YouTubeInlinePlayer.swift
│   │   │   └── SearchView.swift             ← FROM: SearchView/SearchView.swift
│   │   │
│   │   ├── Services/
│   │   │   ├── ExerciseRepository.swift     ← FROM: ExcerciseRepository/ExerciseRepository.swift
│   │   │   └── ExerciseTagRepository.swift  ← FROM: Sources/ExerciseTagRepository.swift (DELETE duplicate)
│   │   │
│   │   └── Components/
│   │       └── FavoritesFirst.swift         ← FROM: ExcerciseRepository/FavoritesFirst.swift
│   │
│   ├── WorkoutSession/
│   │   ├── Models/
│   │   │   ├── ExerciseSessionModels.swift  ← FROM: ExcerciseRepository/ExerciseSessionModels.swift
│   │   │   ├── PlannerModels.swift          ← FROM: AppModels/PlannerModels.swift
│   │   │   └── SplitTemplates.swift         ← FROM: AppModels/SplitTemplates.swift
│   │   │
│   │   ├── Views/
│   │   │   ├── LiveWorkout/
│   │   │   │   ├── LiveWorkoutView.swift        ← FROM: Live Workout/LiveWorkoutView.swift
│   │   │   │   ├── LiveWorkoutGrabTab.swift     ← FROM: Live Workout/LiveWorkoutGrabTab.swift
│   │   │   │   └── LiveWorkoutOverlayCard.swift ← FROM: LiveWorkoutOverlayCard.swift
│   │   │   │
│   │   │   ├── ExerciseSession/
│   │   │   │   ├── ExerciseSessionView.swift    ← FROM: ExcerciseRepository/ExcerciseSessionView.swift (DELETE backup/refactored)
│   │   │   │   ├── ExerciseSessionComponents.swift ← FROM: ExcerciseRepository/ExerciseSessionComponents.swift
│   │   │   │   ├── SetRowViews.swift            ← FROM: ExcerciseRepository/SetRowViews.swift (DELETE _Old)
│   │   │   │   ├── OverviewComponents.swift     ← FROM: ExcerciseRepository/OverviewComponents.swift
│   │   │   │   ├── CarouselSteppers.swift       ← FROM: ExcerciseRepository/CarouselSteppers.swift
│   │   │   │   └── MuscleVisualizationViews.swift ← FROM: ExcerciseRepository/MuscleVisualizationViews.swift
│   │   │   │
│   │   │   ├── WorkoutDetail/
│   │   │   │   ├── WorkoutDetailView.swift      ← FROM: WorkoutDetailView.swift (root)
│   │   │   │   └── WorkoutDetail.swift          ← FROM: ExcerciseRepository/WorkoutDetail.swift
│   │   │   │
│   │   │   └── RestTimer/
│   │   │       ├── RestTimerView.swift          ← FROM: ExcerciseRepository/RestTimerView.swift
│   │   │       ├── RestTimerState.swift         ← FROM: ExcerciseRepository/RestTimerState.swift
│   │   │       ├── RestTimerPreferences.swift   ← FROM: ExcerciseRepository/RestTimerPreferences.swift
│   │   │       └── RestTimerComponents.swift    ← FROM: ExcerciseRepository/RestTimerComponents.swift
│   │   │
│   │   └── Services/
│   │       ├── WorkoutStoreV2.swift         ← FROM: WorkoutStore/WorkoutStoreV2.swift (PRIMARY)
│   │       ├── WorkoutStoreRecent.swift     ← FROM: ExcerciseRepository/WorkoutStoreRecent.swift
│   │       ├── PlannerStore.swift           ← FROM: WorkoutStore/PlannerStore.swift
│   │       └── WorkoutStorage.swift         ← FROM: Persistence/WorkoutStorage.swift
│   │
│   ├── Planner/
│   │   ├── PlannerSetupCarouselView.swift   ← FROM: Views/PlannerSetupCarouselView.swift
│   │   ├── PlannerDebugView.swift           ← FROM: Views/PlannerDebugView.swift
│   │   └── CalendarMonthView.swift          ← FROM: CalendarMonthView.swift
│   │
│   ├── Health/
│   │   ├── Models/
│   │   │   ├── RouteModels.swift            ← FROM: Runs/RouteModels.swift
│   │   │   └── HealthSyncAnchor.swift       ← FROM: Runs/HealthSyncAnchor.swift
│   │   │
│   │   ├── Views/
│   │   │   ├── CardioView.swift             ← FROM: Runs/CardioView.swift
│   │   │   ├── CardioDetailView.swift       ← FROM: Runs/CardioDetailView.swift (DELETE root duplicate)
│   │   │   ├── HealthAuthSheet.swift        ← FROM: Runs/HealthAuthSheet.swift
│   │   │   ├── HealthKitSyncProgress.swift  ← FROM: Runs/HealthKitSyncProgress.swift (DELETE Views/ duplicate)
│   │   │   ├── InteractiveRouteMap.swift    ← FROM: InteractiveRouteMap.swift
│   │   │   ├── InteractiveRouteMapHeat.swift ← FROM: InteractiveRouteMapHeat.swift
│   │   │   └── MapRouteView.swift           ← FROM: MapRouteView.swift
│   │   │
│   │   └── Services/
│   │       └── HealthKitManager.swift       ← FROM: Runs/HealthKitManager.swift
│   │
│   ├── Profile/
│   │   ├── Views/
│   │   │   ├── ProfileView.swift            ← FROM: Profile/ProfileView.swift
│   │   │   ├── PreferencesView.swift        ← FROM: Profile/PreferencesView.swift
│   │   │   ├── ConnectionsView.swift        ← FROM: Profile/ConnectionsView.swift
│   │   │   ├── WeeklyGoalCard.swift         ← FROM: Profile/WeeklyGoalCard.swift
│   │   │   └── GoalOnboardingCard.swift     ← FROM: Profile/GoalOnboardingCard.swift
│   │   │
│   │   ├── Models/
│   │   │   ├── WeeklyGoal.swift             ← FROM: Profile/WeeklyGoal.swift
│   │   │   └── WeeklyProgressTypes.swift    ← FROM: Profile/WeeklyProgressTypes.swift
│   │   │
│   │   └── Components/
│   │       └── (any reusable profile components)
│   │
│   ├── Statistics/
│   │   ├── Views/
│   │   │   ├── ProfileStatsSection.swift    ← FROM: Statistics/ProfileStatsSection.swift
│   │   │   └── TrainingBalanceSection.swift ← FROM: Statistics/TrainingBalanceSection.swift
│   │   │
│   │   ├── Models/
│   │   │   ├── StatModels.swift             ← FROM: Statistics/StatModels.swift
│   │   │   └── StatsTokens.swift            ← FROM: Statistics/StatsTokens.swift
│   │   │
│   │   └── Services/
│   │       ├── StatsAggregator.swift        ← FROM: Statistics/StatsAggregator.swift
│   │       └── ExerciseClassifier.swift     ← FROM: Statistics/ExerciseClassifier.swift
│   │
│   ├── Rewards/
│   │   ├── Views/
│   │   │   ├── RewardsHubView.swift         ← FROM: Rewards/RewardsHubView.swift
│   │   │   ├── WinScreen.swift              ← FROM: Rewards/WinScreen.swift
│   │   │   ├── RewardSummary.swift          ← FROM: Rewards/RewardSummary.swift
│   │   │   └── RewardProgress.swift         ← FROM: Rewards/RewardProgress.swift
│   │   │
│   │   ├── Models/
│   │   │   ├── RewardsRules.swift           ← FROM: Rewards/RewardsRules.swift
│   │   │   └── StreakResult.swift           ← FROM: Rewards/StreakResult.swift
│   │   │
│   │   └── Services/
│   │       ├── RewardEngine.swift           ← FROM: Rewards/RewardEngine.swift
│   │       └── WinScreenCoordinator.swift   ← FROM: Rewards/WinScreenCoordinator.swift
│   │
│   ├── Achievements/
│   │   ├── Views/
│   │   │   ├── AchievementsView.swift       ← FROM: Profile/AchievementsView.swift
│   │   │   ├── AchievementsDexView.swift    ← FROM: Profile/AchievementsDexView.swift
│   │   │   ├── DexDetailView.swift          ← FROM: Profile/DexDetailView.swift
│   │   │   └── DexTile.swift                ← FROM: Profile/DexTile.swift
│   │   │
│   │   └── Models/
│   │       └── DexKeying.swift              ← FROM: Profile/DexKeying.swift
│   │
│   └── Muscles/
│       ├── Views/
│       │   ├── MuscleGroupView.swift        ← FROM: MuscleGroup/MuscleGroupView.swift
│       │   ├── SubregionDetailScreen.swift  ← FROM: Views/SubregionDetailScreen.swift
│       │   ├── ExerciseMusclesSection.swift ← FROM: Muscles/ExerciseMusclesSection.swift
│       │   └── SVGHumanBodyView.swift       ← FROM: Muscles/SVGHumanBodyView.swift
│       │
│       ├── Models/
│       │   ├── MuscleTaxonomy.swift         ← FROM: MuscleTaxonomy.swift
│       │   ├── MuscleRegion.swift           ← FROM: Muscles/MuscleRegion.swift
│       │   ├── MuscleRegion+Mapper.swift    ← FROM: Models/MuscleRegion+Mapper.swift
│       │   ├── MuscleIndex.swift            ← FROM: Muscles/MuscleIndex.swift
│       │   ├── MusclePictogram.swift        ← FROM: AppModels/MusclePictogram.swift
│       │   ├── MuscleIconMapper.swift       ← FROM: AppModels/MuscleIconMapper.swift
│       │   └── SVGMuscleIDMapper.swift      ← FROM: Muscles/SVGMuscleIDMapper.swift
│       │
│       └── Resources/
│           └── (SVG files if needed)
│
├── DesignSystem/
│   ├── Components/
│   │   ├── SwipeToConfirm.swift             ← FROM: AppModels/SwipeToConfirm.swift
│   │   └── SpotlightOverlay.swift           ← FROM: Views/SpotlightOverlay.swift
│   │
│   └── Theme/
│       └── DS.swift                         ← FROM: AppModels/DS.swift
│
├── Resources/
│   ├── Assets.xcassets/
│   │   ├── AppIcon.appiconset/
│   │   ├── body_back.imageset/
│   │   ├── body_front.imageset/
│   │   └── ...
│   │
│   ├── Data/                                ← JSON data files
│   │   ├── exercises_clean.json             ← KEEP (primary, 3.8MB)
│   │   ├── exercise_media_final.json        ← KEEP (choose this or exercise_media.json)
│   │   ├── exercise_tags.json
│   │   ├── muscle_id_map.json
│   │   └── rewards_rules_v1.json
│   │
│   └── SVG/                                 ← SVG assets
│       ├── muscles.svg
│       ├── muscles_back.svg
│       └── torso_back.svg
│
├── Tools/                                   ← Build scripts, utilities
│   ├── make_media_json.py
│   └── xlsx_links_to_json.py
│
└── Documentation/
    ├── STORAGE_MIGRATION_GUIDE.md
    ├── PAGINATION_NOTES.md
    ├── SEARCH_DEBOUNCING_NOTES.md
    └── RECOMMENDED_FILE_STRUCTURE.md (this file)
```

---

## 🗑️ Files to DELETE

### Duplicate Files with Spaces in Names (Build Blockers)
- ❌ `ExcerciseRepository/ExerciseCache 2.swift`
- ❌ `Views/NotificationPermissionView 2.swift`

### Backup/Old Versions
- ❌ `ExcerciseRepository/ExcerciseSessionView.swift.backup`
- ❌ `ExcerciseRepository/ExcerciseSessionView_Refactored.swift`
- ❌ `ExcerciseRepository/SetRowViews_Old.swift`

### Duplicate Model Folders (keep AppModels/, delete Models/)
- ❌ `Models/DS.swift` (empty 0 bytes)
- ❌ `Models/ExerciseMapping.swift` (empty 0 bytes)
- ❌ `Models/ExercisePR.swift`
- ❌ `Models/Models.swift`
- ❌ `Models/MuscleIconMapper.swift`
- ❌ `Models/MusclePictogram.swift`
- ❌ `Models/SwipeToConfirm.swift`
- ❌ `Models/MuscleRegion+Mapper.swift` (keep this one, move to Muscles/Models/)

### Duplicate Repositories
- ❌ `ExerciseTagRepository.swift` (root, keep Sources/ version)

### Duplicate Health/Run Views
- ❌ `CardioDetailView.swift` (root, keep Runs/ version)
- ❌ `Views/HealthKitSyncProgress.swift` (keep Runs/ version)

### Old Storage Systems (After Migration)
- ❌ `Persistence/Persistence.swift` (replace with WorkoutStorage.swift)
- ❌ `WorkoutStore/WorkoutStore.swift` (old V1, keep WorkoutStoreV2.swift)

### Duplicate JSON Files
- ❌ `exercise_media.json` (keep `exercise_media_final.json`)
- ❌ `exercises.json` (old, 978KB)
- ❌ `exercises_catalog.json` (old, 917KB, keep `exercises_clean.json`)

### Moved/Deleted Old Files
- ❌ `BodyBrowse.swift` (root, moved to ExcerciseRepository/)
- ❌ `HealthKitManager.swift` (root, moved to Runs/)
- ❌ `HealthRunImporter.swift` (root, moved to Runs/)
- ❌ `MuscleIndex.swift` (root, moved to Muscles/)
- ❌ `RunDetailView.swift` (root, likely old)
- ❌ `RunView.swift` (root, likely old)
- ❌ `SearchView.swift` (root, moved to SearchView/)
- ❌ `WorkoutDetail.swift` (root, moved to ExcerciseRepository/)
- ❌ `WRKTApp.swift` (root, moved to Views/)
- ❌ `AppDependencies.swift` (root, keep Utilities/ version)

### Experimental/Debug Files (Optional - Review First)
- ⚠️ `Untitled-1.ipynb` (Jupyter notebook)
- ⚠️ Various untracked `.py` scripts if no longer needed

---

## ✅ Critical Consolidations

### 1. AppDependencies
**KEEP:** `Utilities/AppDependencies.swift`
**DELETE:** `AppDependencies.swift` (root)
**REASON:** Utilities version has PlannerStore and uses WorkoutStoreV2

### 2. Persistence Layer
**KEEP:** `Persistence/WorkoutStorage.swift`
**DELETE:** `Persistence/Persistence.swift` (after data migration)
**REASON:** WorkoutStorage is the unified v2 system

### 3. WorkoutStore
**KEEP:** `WorkoutStore/WorkoutStoreV2.swift`
**DEPRECATE:** `WorkoutStore/WorkoutStore.swift`
**REASON:** V2 is the active version, V1 should be migrated

### 4. Exercise Data
**KEEP:** `exercises_clean.json` (3.8MB - most complete)
**DELETE:** `exercises.json`, `exercises_catalog.json`
**REASON:** exercises_clean.json is referenced in ExerciseRepository.swift:64

### 5. Exercise Media
**KEEP:** `exercise_media_final.json`
**DELETE:** `exercise_media.json`
**REASON:** "final" suggests it's the production version

---

## 🎯 Migration Benefits

### Before (Current Issues)
- 170+ files scattered across root and subdirectories
- Duplicate files causing build failures
- Multiple persistence systems causing data conflicts
- Unclear dependencies and circular references
- Hard to onboard new developers

### After (Optimized Structure)
✅ **Feature Isolation**: Each feature is self-contained
✅ **Clear Dependencies**: Core → Features (unidirectional)
✅ **Scalability**: Easy to add new features
✅ **Testability**: Features can be tested independently
✅ **Navigation**: Find files instantly (feature/models vs feature/views)
✅ **Build Performance**: No duplicates, clear module boundaries
✅ **Team Collaboration**: Features owned by different developers

---

## 🔄 Migration Strategy

### Phase 1: Critical Cleanup (Do First)
1. Delete all duplicate "2.swift" files
2. Delete all .backup and _Old files
3. Choose one AppDependencies (Utilities/)
4. Remove duplicate JSON files

### Phase 2: Create Feature Folders
1. Create the folder structure above
2. Move files in batches by feature (test after each)
3. Update imports as you go

### Phase 3: Xcode Project Update
1. Remove old file references from .xcodeproj
2. Add new file references in feature groups
3. Ensure all targets include correct files
4. Build and test

### Phase 4: Consolidate Data Layer
1. Migrate all code to use WorkoutStorage
2. Remove Persistence.swift
3. Deprecate WorkoutStore.swift (V1)
4. Test data persistence thoroughly

---

## 📝 Notes

- **SwiftUI Previews**: Keep preview code in same files for convenience
- **Tests**: Create parallel `WRKTTests/Features/` structure mirroring app
- **Shared Components**: If components are used across 3+ features, move to DesignSystem/
- **ViewModels**: If you add ViewModels later, create `feature/ViewModels/` folders
- **Localization**: Add `Resources/Localizable.strings` when needed

---

## 🚀 Next Steps

After moving files:
1. Update all import statements
2. Run `swift build` to verify no missing files
3. Fix any broken references in Xcode project
4. Run tests
5. Archive old branches before deleting legacy files

---

**Last Updated:** 2025-10-25
**App Version:** 1.0 (Initial Restructure)
