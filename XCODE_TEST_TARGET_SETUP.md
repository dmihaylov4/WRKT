# Xcode Test Target Setup Guide

This guide explains how to add the WRKTTests test target to your Xcode project.

## 📋 Prerequisites

- Xcode 15.0 or later
- WRKT project opened in Xcode
- Test files already created in the `WRKTTests/` directory

## 🎯 Step-by-Step Instructions

### Step 1: Add Test Target to Project

1. Open `WRKT.xcodeproj` in Xcode
2. In the Project Navigator, select the **WRKT** project (the blue icon at the top)
3. In the main editor, you'll see the project settings with TARGETS listed below
4. Click the **+** button at the bottom of the TARGETS list
5. In the template chooser:
   - Select **iOS** tab at the top
   - Scroll to find **Unit Testing Bundle**
   - Select **Unit Testing Bundle**
   - Click **Next**

### Step 2: Configure Test Target

In the configuration sheet:

1. **Product Name**: `WRKTTests`
2. **Team**: Select your development team
3. **Organization Identifier**: Use your organization identifier (e.g., `com.yourname`)
4. **Bundle Identifier**: Should auto-fill as `com.yourname.WRKTTests`
5. **Language**: Swift
6. **Target to be Tested**: Select **WRKT** from the dropdown
7. Click **Finish**

### Step 3: Delete Auto-Generated Test File

Xcode will create a default test file - we don't need it since we already have our tests:

1. In the Project Navigator, find `WRKTTests/WRKTTests.swift` (auto-generated)
2. Right-click on it and select **Delete**
3. Choose **Move to Trash**

### Step 4: Add Test Files to Target

Now we need to add our existing test files to the target:

1. In the Project Navigator, locate the `WRKTTests` folder
2. Select **all files and folders** in the `WRKTTests` directory:
   - TestHelpers/
   - CoreTests/
   - FeaturesTests/
   - Info.plist
   - README.md

3. Right-click the selected files and choose **Get Info** (or press `Cmd + Option + I`)
4. In the Inspector panel (right side), find **Target Membership**
5. Check the box next to **WRKTTests**
6. Close the inspector

**Alternative method (if files are not showing):**

1. Right-click the **WRKTTests** group in Project Navigator
2. Select **Add Files to "WRKT"...**
3. Navigate to your `WRKTTests` folder
4. Select all test files
5. Make sure **"Add to targets: WRKTTests"** is checked
6. Click **Add**

### Step 5: Configure Build Settings

1. Select the **WRKT** project in Project Navigator
2. Select the **WRKTTests** target
3. Go to **Build Settings** tab
4. Search for "Bundle Loader"
5. Set **Bundle Loader** to: `$(TEST_HOST)`
6. Search for "Test Host"
7. Set **Test Host** to: `$(BUILT_PRODUCTS_DIR)/WRKT.app/$(BUNDLE_EXECUTABLE_PATH)`

### Step 6: Link Test Target to Main Target

1. Still in **WRKTTests** target settings
2. Go to **Build Phases** tab
3. Expand **Link Binary With Libraries**
4. Click the **+** button
5. Add:
   - `XCTest.framework`
   - Any other frameworks your main app uses

### Step 7: Configure Info.plist

The Info.plist is already created at `WRKTTests/Info.plist`. Make sure it's set correctly:

1. Select **WRKTTests** target
2. Go to **Build Settings**
3. Search for "Info.plist"
4. Set **Info.plist File** to: `WRKTTests/Info.plist`

### Step 8: Set Test Target Settings

1. Select **WRKTTests** target
2. Go to **General** tab
3. Under **Testing**:
   - **Host Application**: Should show **WRKT**
4. Under **Deployment Info**:
   - **Deployment Target**: Match your main app (iOS 17.0 or your minimum)

### Step 9: Configure Scheme

1. Click on the scheme selector (next to play/stop buttons)
2. Select **Edit Scheme...**
3. Select **Test** on the left
4. Under **Info** tab:
   - Make sure **Build Configuration** is set to **Debug**
5. Click the **+** button under the test list
6. Expand **WRKTTests.xctest**
7. Select all test classes
8. Click **Add**
9. Click **Close**

### Step 10: Verify Setup

1. Select the **WRKTTests** scheme from the scheme selector
2. Press `Cmd + U` to run tests
3. You should see tests executing in the Test Navigator (`Cmd + 6`)

If tests don't compile:
- Check that all test files have WRKTTests as their target membership
- Verify that `@testable import WRKT` is in your test files
- Make sure the main WRKT target builds successfully first

## 🧪 Running Tests

### Run All Tests
- **Keyboard**: `Cmd + U`
- **Menu**: Product → Test
- **Test Navigator**: Click the play icon next to "WRKTTests"

### Run Individual Test Class
- In Test Navigator, click the play icon next to the test class name

### Run Single Test Method
- Click in the gutter next to the test method (diamond icon)
- Or use Test Navigator and click the play icon next to the test method

### Run Tests from File
- Open a test file in the editor
- Click the play icon in the gutter next to the class declaration
- Or click the play icon next to any test method

## 🔍 Troubleshooting

### Tests Don't Appear in Test Navigator

**Solution:**
1. Clean build folder: `Cmd + Shift + K`
2. Delete derived data: `Cmd + Option + Shift + K`
3. Restart Xcode
4. Rebuild: `Cmd + B`

### "No such module 'WRKT'" Error

**Solution:**
1. Make sure main app builds successfully first
2. Check that Test Host is set correctly in build settings
3. Verify `@testable import WRKT` is used (not just `import WRKT`)

### Tests Won't Compile - "Cannot find type 'Exercise' in scope"

**Solution:**
1. Make sure the types are defined in the main app target, not test target
2. Verify `@testable import WRKT` is at the top of test files
3. Check that main app files have proper access control (internal or public)
4. If types are in frameworks, import those frameworks too

### "Host Application Not Set" Error

**Solution:**
1. Select WRKTTests target
2. Go to General tab
3. Under Testing section, set Host Application to WRKT

### Tests Pass but Code Coverage Shows 0%

**Solution:**
1. Edit Scheme → Test
2. Under Options tab
3. Check "Gather coverage for: WRKT"
4. Re-run tests

## 📊 Viewing Test Results

### Test Navigator (`Cmd + 6`)
- Shows all test classes and methods
- Green checkmark = passed
- Red X = failed
- Click any test to see details

### Report Navigator (`Cmd + 9`)
- Shows test run history
- Click any run to see detailed results
- Expandable tree view of all tests

### Code Coverage
1. After running tests with coverage enabled
2. Go to Report Navigator
3. Select latest test run
4. Click **Coverage** tab
5. See percentage coverage per file

## 🎨 Customizing Test Scheme

### Add Pre/Post-Actions
1. Edit Scheme → Test
2. Click **Pre-Actions** or **Post-Actions**
3. Add shell scripts to run before/after tests

### Add Environment Variables
1. Edit Scheme → Test → Arguments
2. Add environment variables for tests
3. Example: `IS_RUNNING_TESTS = 1`

### Set Test Region/Language
1. Edit Scheme → Test → Options
2. Set Application Language
3. Set Application Region

## ✅ Verification Checklist

After setup, verify:

- [ ] Test target appears in scheme selector
- [ ] All test files show in Test Navigator
- [ ] Tests compile without errors (`Cmd + B`)
- [ ] Tests can be run (`Cmd + U`)
- [ ] Test results appear in Test Navigator
- [ ] Code coverage works (if enabled)
- [ ] Tests can be run individually
- [ ] Tests can be run from command line

## 🚀 Next Steps

After successful setup:

1. **Run all tests**: `Cmd + U` - Should see 40+ tests pass
2. **Enable code coverage**: Edit Scheme → Test → Options → Gather coverage
3. **Set up CI/CD**: Configure automated test runs on pull requests
4. **Write more tests**: Add tests for remaining features
5. **Refactor for testability**: Extract ViewModels, use dependency injection

## 📝 Notes

- Tests use the singleton pattern currently - consider refactoring for better isolation
- Some integration tests may affect app state - this is documented in test files
- For better test isolation, implement protocol-based dependency injection
- Consider using a separate test bundle for UI tests vs unit tests

## 📚 Resources

- [XCTest Documentation](https://developer.apple.com/documentation/xctest)
- [Testing in Xcode](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/)
- [Test Target Setup](https://developer.apple.com/documentation/xcode/testing-your-apps-in-xcode)

---

**Need Help?**
- Check console output for specific error messages
- Clean and rebuild project
- Verify all paths in build settings
- Check the `WRKTTests/README.md` for test-specific documentation


XCTAssertEqual failed: ("WorkoutStorageContainer(metadata: WRKT.StorageMetadata(version: 1, lastModified: 2025-10-26 13:52:21 +0000, itemCount: 2), workouts: [WRKT.CompletedWorkout(id: BFD1C1CA-0D2D-47DE-A139-DCAF9CCB5F38, date: 2025-10-26 13:52:21 +0000, entries: [WRKT.WorkoutEntry(id: 9F54CF36-C4E5-4652-AD13-A5D26F7DB493, exerciseID: "barbell-bench-press", exerciseName: "Barbell Bench Press", muscleGroups: ["chest"], sets: [WRKT.SetInput(reps: 10, weight: 20.0, tag: WRKT.SetTag.warmup, autoWeight: false, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 8, weight: 60.0, tag: WRKT.SetTag.working, autoWeight: false, didSeedFromMemory: true, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 8, weight: 60.0, tag: WRKT.SetTag.working, autoWeight: false, didSeedFromMemory: true, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 12, weight: 50.0, tag: WRKT.SetTag.backoff, autoWeight: false, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false)], activeSetIndex: 0), WRKT.WorkoutEntry(id: 40F89112-FE8D-4108-B440-4F4D38C8F2EA, exerciseID: "barbell-squat", exerciseName: "Barbell Squat", muscleGroups: ["quadriceps"], sets: [WRKT.SetInput(reps: 10, weight: 40.0, tag: WRKT.SetTag.warmup, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 5, weight: 100.0, tag: WRKT.SetTag.working, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 5, weight: 100.0, tag: WRKT.SetTag.working, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false)], activeSetIndex: 0)], plannedWorkoutID: nil, matchedHealthKitUUID: nil, matchedHealthKitCalories: nil, matchedHealthKitHeartRate: nil, matchedHealthKitMaxHeartRate: nil, matchedHealthKitMinHeartRate: nil, matchedHealthKitDuration: nil, matchedHealthKitHeartRateSamples: nil), WRKT.CompletedWorkout(id: 7F9A222B-63C9-4E2E-842B-BB65C61AD5AE, date: 2025-10-26 13:52:21 +0000, entries: [WRKT.WorkoutEntry(id: 9F54CF36-C4E5-4652-AD13-A5D26F7DB493, exerciseID: "barbell-bench-press", exerciseName: "Barbell Bench Press", muscleGroups: ["chest"], sets: [WRKT.SetInput(reps: 10, weight: 20.0, tag: WRKT.SetTag.warmup, autoWeight: false, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 8, weight: 60.0, tag: WRKT.SetTag.working, autoWeight: false, didSeedFromMemory: true, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 8, weight: 60.0, tag: WRKT.SetTag.working, autoWeight: false, didSeedFromMemory: true, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 12, weight: 50.0, tag: WRKT.SetTag.backoff, autoWeight: false, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false)], activeSetIndex: 0), WRKT.WorkoutEntry(id: 40F89112-FE8D-4108-B440-4F4D38C8F2EA, exerciseID: "barbell-squat", exerciseName: "Barbell Squat", muscleGroups: ["quadriceps"], sets: [WRKT.SetInput(reps: 10, weight: 40.0, tag: WRKT.SetTag.warmup, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 5, weight: 100.0, tag: WRKT.SetTag.working, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 5, weight: 100.0, tag: WRKT.SetTag.working, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false)], activeSetIndex: 0)], plannedWorkoutID: nil, matchedHealthKitUUID: nil, matchedHealthKitCalories: nil, matchedHealthKitHeartRate: nil, matchedHealthKitMaxHeartRate: nil, matchedHealthKitMinHeartRate: nil, matchedHealthKitDuration: nil, matchedHealthKitHeartRateSamples: nil)], prIndex: ["bench-press": WRKT.ExercisePRsV2(bestPerReps: [5: 100.0, 8: 85.0, 10: 75.0], bestE1RM: Optional(116.0), lastWorking: Optional(WRKT.LastSetV2(date: 2025-10-26 13:52:21 +0000, reps: 8, weightKg: 85.0)), allTimeBest: Optional(100.0), firstRecorded: Optional(2025-09-26 13:52:21 +0000)), "squat": WRKT.ExercisePRsV2(bestPerReps: [5: 100.0, 8: 85.0, 10: 75.0], bestE1RM: Optional(116.0), lastWorking: Optional(WRKT.LastSetV2(date: 2025-10-26 13:52:21 +0000, reps: 8, weightKg: 85.0)), allTimeBest: Optional(100.0), firstRecorded: Optional(2025-09-26 13:52:21 +0000))])") is not equal to ("WorkoutStorageContainer(metadata: WRKT.StorageMetadata(version: 1, lastModified: 2025-10-26 13:52:21 +0000, itemCount: 2), workouts: [WRKT.CompletedWorkout(id: BFD1C1CA-0D2D-47DE-A139-DCAF9CCB5F38, date: 2025-10-26 13:52:21 +0000, entries: [WRKT.WorkoutEntry(id: 9F54CF36-C4E5-4652-AD13-A5D26F7DB493, exerciseID: "barbell-bench-press", exerciseName: "Barbell Bench Press", muscleGroups: ["chest"], sets: [WRKT.SetInput(reps: 10, weight: 20.0, tag: WRKT.SetTag.warmup, autoWeight: false, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 8, weight: 60.0, tag: WRKT.SetTag.working, autoWeight: false, didSeedFromMemory: true, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 8, weight: 60.0, tag: WRKT.SetTag.working, autoWeight: false, didSeedFromMemory: true, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 12, weight: 50.0, tag: WRKT.SetTag.backoff, autoWeight: false, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false)], activeSetIndex: 0), WRKT.WorkoutEntry(id: 40F89112-FE8D-4108-B440-4F4D38C8F2EA, exerciseID: "barbell-squat", exerciseName: "Barbell Squat", muscleGroups: ["quadriceps"], sets: [WRKT.SetInput(reps: 10, weight: 40.0, tag: WRKT.SetTag.warmup, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 5, weight: 100.0, tag: WRKT.SetTag.working, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 5, weight: 100.0, tag: WRKT.SetTag.working, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false)], activeSetIndex: 0)], plannedWorkoutID: nil, matchedHealthKitUUID: nil, matchedHealthKitCalories: nil, matchedHealthKitHeartRate: nil, matchedHealthKitMaxHeartRate: nil, matchedHealthKitMinHeartRate: nil, matchedHealthKitDuration: nil, matchedHealthKitHeartRateSamples: nil), WRKT.CompletedWorkout(id: 7F9A222B-63C9-4E2E-842B-BB65C61AD5AE, date: 2025-10-26 13:52:21 +0000, entries: [WRKT.WorkoutEntry(id: 9F54CF36-C4E5-4652-AD13-A5D26F7DB493, exerciseID: "barbell-bench-press", exerciseName: "Barbell Bench Press", muscleGroups: ["chest"], sets: [WRKT.SetInput(reps: 10, weight: 20.0, tag: WRKT.SetTag.warmup, autoWeight: false, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 8, weight: 60.0, tag: WRKT.SetTag.working, autoWeight: false, didSeedFromMemory: true, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 8, weight: 60.0, tag: WRKT.SetTag.working, autoWeight: false, didSeedFromMemory: true, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 12, weight: 50.0, tag: WRKT.SetTag.backoff, autoWeight: false, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false)], activeSetIndex: 0), WRKT.WorkoutEntry(id: 40F89112-FE8D-4108-B440-4F4D38C8F2EA, exerciseID: "barbell-squat", exerciseName: "Barbell Squat", muscleGroups: ["quadriceps"], sets: [WRKT.SetInput(reps: 10, weight: 40.0, tag: WRKT.SetTag.warmup, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 5, weight: 100.0, tag: WRKT.SetTag.working, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 5, weight: 100.0, tag: WRKT.SetTag.working, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false)], activeSetIndex: 0)], plannedWorkoutID: nil, matchedHealthKitUUID: nil, matchedHealthKitCalories: nil, matchedHealthKitHeartRate: nil, matchedHealthKitMaxHeartRate: nil, matchedHealthKitMinHeartRate: nil, matchedHealthKitDuration: nil, matchedHealthKitHeartRateSamples: nil)], prIndex: ["squat": WRKT.ExercisePRsV2(bestPerReps: [5: 100.0, 8: 85.0, 10: 75.0], bestE1RM: Optional(116.0), lastWorking: Optional(WRKT.LastSetV2(date: 2025-10-26 13:52:21 +0000, reps: 8, weightKg: 85.0)), allTimeBest: Optional(100.0), firstRecorded: Optional(2025-09-26 13:52:21 +0000)), "bench-press": WRKT.ExercisePRsV2(bestPerReps: [8: 85.0, 5: 100.0, 10: 75.0], bestE1RM: Optional(116.0), lastWorking: Optional(WRKT.LastSetV2(date: 2025-10-26 13:52:21 +0000, reps: 8, weightKg: 85.0)), allTimeBest: Optional(100.0), firstRecorded: Optional(2025-09-26 13:52:21 +0000))])")



XCTAssertEqual failed: ("CurrentWorkout(id: FE2EE6F1-F43C-4E61-AC8F-A6B1C0846CCA, startedAt: 2025-10-26 14:10:18 +0000, entries: [WRKT.WorkoutEntry(id: 7E6BF055-0B34-474B-A45B-F37BF7111ECB, exerciseID: "barbell-bench-press", exerciseName: "Barbell Bench Press", muscleGroups: ["chest"], sets: [WRKT.SetInput(reps: 10, weight: 20.0, tag: WRKT.SetTag.warmup, autoWeight: false, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 8, weight: 60.0, tag: WRKT.SetTag.working, autoWeight: false, didSeedFromMemory: true, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 8, weight: 60.0, tag: WRKT.SetTag.working, autoWeight: false, didSeedFromMemory: true, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 12, weight: 50.0, tag: WRKT.SetTag.backoff, autoWeight: false, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false)], activeSetIndex: 0), WRKT.WorkoutEntry(id: EAC422E8-79B0-484D-AC7D-9E456B6332F6, exerciseID: "barbell-squat", exerciseName: "Barbell Squat", muscleGroups: ["quadriceps"], sets: [WRKT.SetInput(reps: 10, weight: 40.0, tag: WRKT.SetTag.warmup, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 5, weight: 100.0, tag: WRKT.SetTag.working, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 5, weight: 100.0, tag: WRKT.SetTag.working, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false)], activeSetIndex: 0)], plannedWorkoutID: nil)") is not equal to ("CurrentWorkout(id: FE2EE6F1-F43C-4E61-AC8F-A6B1C0846CCA, startedAt: 2025-10-26 14:10:18 +0000, entries: [WRKT.WorkoutEntry(id: 7E6BF055-0B34-474B-A45B-F37BF7111ECB, exerciseID: "barbell-bench-press", exerciseName: "Barbell Bench Press", muscleGroups: ["chest"], sets: [WRKT.SetInput(reps: 10, weight: 20.0, tag: WRKT.SetTag.warmup, autoWeight: false, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 8, weight: 60.0, tag: WRKT.SetTag.working, autoWeight: false, didSeedFromMemory: true, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 8, weight: 60.0, tag: WRKT.SetTag.working, autoWeight: false, didSeedFromMemory: true, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 12, weight: 50.0, tag: WRKT.SetTag.backoff, autoWeight: false, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false)], activeSetIndex: 0), WRKT.WorkoutEntry(id: EAC422E8-79B0-484D-AC7D-9E456B6332F6, exerciseID: "barbell-squat", exerciseName: "Barbell Squat", muscleGroups: ["quadriceps"], sets: [WRKT.SetInput(reps: 10, weight: 40.0, tag: WRKT.SetTag.warmup, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 5, weight: 100.0, tag: WRKT.SetTag.working, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false), WRKT.SetInput(reps: 5, weight: 100.0, tag: WRKT.SetTag.working, autoWeight: true, didSeedFromMemory: false, isCompleted: true, isGhost: false, isAutoGeneratedPlaceholder: false)], activeSetIndex: 0)], plannedWorkoutID: nil)")





 Add accessibility support

  💡 Pro Tips

  1. Write tests first (TDD) when adding new features
  2. Run tests before committing to catch issues early
  3. Keep tests fast - slow tests won't get run
  4. Test edge cases - empty collections, nil values, errors
  5. Use fixtures - TestFixtures makes test data easy

  ---
  Great job! You now have a solid foundation for maintaining code quality. Your future self will thank you when these tests catch bugs! 🙌

  Would you like help with any of the next steps, or shall we move on to something else?

> 2. Extract view logic to ViewModels
What does this entail? 

⏺ Great question! Let me explain what "Extract view logic to ViewModels" means and why it's important for your codebase.

  🎯 What Are ViewModels?

  ViewModels are classes that sit between your Views (UI) and Models (data), handling:
  - Business logic
  - State management
  - Data formatting
  - User interactions
  - Network/storage calls

  The Problem in Your Codebase

  Based on the analysis, you currently have:

  1. 700+ line view files with business logic embedded in SwiftUI views
  2. 20+ @State properties in single views
  3. Singleton usage directly in views (@StateObject var store = WorkoutStoreV2.shared)
  4. Mixed concerns - UI rendering + data manipulation in same file

  📋 Current Architecture (What You Have Now)

  // ❌ Current: Everything in the View
  struct ExerciseSessionView: View {
      @StateObject var store = WorkoutStoreV2.shared  // Singleton in view
      @State private var selectedExercise: Exercise?
      @State private var currentSet: Int = 0
      @State private var weight: Double = 0
      @State private var reps: Int = 0
      @State private var isRestTimerActive: Bool = false
      @State private var restDuration: TimeInterval = 90
      // ... 15+ more @State properties ...

      var body: some View {
          VStack {
              // 700 lines of UI code mixed with business logic
              Button("Complete Set") {
                  // Business logic embedded in view
                  let newSet = SetInput(reps: reps, weight: weight)
                  store.addSet(newSet)
                  calculateNextWeight()  // Complex calculation
                  startRestTimer()       // Side effects
                  updatePRIfNeeded()     // More logic
              }
          }
      }

      private func calculateNextWeight() { /* complex logic */ }
      private func startRestTimer() { /* timer logic */ }
      private func updatePRIfNeeded() { /* PR calculation */ }
  }

  Problems:

  - ❌ Not testable - Can't test logic without rendering UI
  - ❌ Tightly coupled - View depends on singleton
  - ❌ Hard to maintain - 700 lines, difficult to navigate
  - ❌ Mixed concerns - UI and business logic together
  - ❌ Poor reusability - Logic tied to specific view

  ✅ Better Architecture (With ViewModel)

  // ✅ Better: ViewModel handles logic
  @MainActor
  class ExerciseSessionViewModel: ObservableObject {
      // Dependencies injected (testable!)
      private let workoutStore: WorkoutStoreProtocol
      private let prCalculator: PRCalculator

      // Published state
      @Published var selectedExercise: Exercise?
      @Published var currentSet: Int = 0
      @Published var weight: Double = 0
      @Published var reps: Int = 0
      @Published var isRestTimerActive: Bool = false
      @Published var restDuration: TimeInterval = 90

      init(
          workoutStore: WorkoutStoreProtocol = WorkoutStoreV2.shared,
          prCalculator: PRCalculator = PRCalculator()
      ) {
          self.workoutStore = workoutStore
          self.prCalculator = prCalculator
      }

      // Business logic methods
      func completeSet() {
          let newSet = SetInput(reps: reps, weight: weight)
          workoutStore.addSet(newSet)
          calculateNextWeight()
          startRestTimer()
          updatePRIfNeeded()
      }

      func calculateNextWeight() {
          // Complex logic here, fully testable
          weight = prCalculator.suggestNextWeight(
              currentWeight: weight,
              reps: reps
          )
      }

      private func startRestTimer() {
          isRestTimerActive = true
          // Timer logic
      }

      private func updatePRIfNeeded() {
          // PR calculation logic
      }
  }

  // ✅ View is now simple and focused on UI
  struct ExerciseSessionView: View {
      @StateObject private var viewModel: ExerciseSessionViewModel

      init(viewModel: ExerciseSessionViewModel = ExerciseSessionViewModel()) {
          _viewModel = StateObject(wrappedValue: viewModel)
      }

      var body: some View {
          VStack {
              // Just UI code - clean and readable
              TextField("Weight", value: $viewModel.weight, format: .number)
              TextField("Reps", value: $viewModel.reps, format: .number)

              Button("Complete Set") {
                  viewModel.completeSet()  // Simple call to ViewModel
              }
          }
      }
  }

  // ✅ Now you can test the logic!
  class ExerciseSessionViewModelTests: XCTestCase {
      func testCompleteSetCalculatesNextWeight() {
          let mockStore = MockWorkoutStore()
          let viewModel = ExerciseSessionViewModel(workoutStore: mockStore)

          viewModel.weight = 100
          viewModel.reps = 8
          viewModel.completeSet()

          XCTAssertEqual(viewModel.weight, 105) // Next suggested weight
          XCTAssertTrue(mockStore.setWasAdded)
      }
  }

  🔍 Real Example from Your Codebase

  Let me show you a specific file that needs this:

⏺ Read(Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift)
  ⎿  Read 100 lines

⏺ Perfect! Let me show you what needs to be extracted from your actual code:

  📸 Your Current Code: ExerciseSessionView.swift

  Looking at lines 1-100, I can see:

  ❌ Current Problems (Lines 16-56):

  struct ExerciseSessionView: View {
      @EnvironmentObject var store: WorkoutStoreV2        // Singleton dependency
      @EnvironmentObject var repo: ExerciseRepository     // Another singleton

      // 20+ @State properties scattered throughout the view!
      @State private var currentEntryID: UUID? = nil
      @State private var sets: [SetInput] = [...]
      @State private var activeSetIndex: Int = 0
      @State private var didPreloadExisting = false
      @State private var didPrefillFromHistory = false
      @State private var showEmptyAlert = false
      @State private var showUnsavedSetsAlert = false
      @State private var showInfo = false
      @State private var showDemo = false
      @State private var showTutorial = false
      @State private var currentTutorialStep = 0
      @State private var setsSectionFrame: CGRect = .zero
      // ... more state ...

      var body: some View {
          // 700 lines of UI + business logic mixed together
      }
  }

  ✅ What It Should Be:

  Step-by-Step: Extract ViewModel for ExerciseSessionView

  Step 1: Create the ViewModel

⏺ Write(Features/WorkoutSession/ViewModels/ExerciseSessionViewModel.swift)
  ⎿  Wrote 219 lines to Features/WorkoutSession/ViewModels/ExerciseSessionViewModel.swift
     //
     //  ExerciseSessionViewModel.swift
     //  WRKT
     //
     //  ViewModel for ExerciseSessionView - handles business logic and state
     //
     import SwiftUI
     import Combine
     … +209 lines (ctrl+o to expand)

⏺ Step 2: Create Tests for the ViewModel

⏺ Write(WRKTTests/FeaturesTests/WorkoutSession/ExerciseSessionViewModelTests.swift)
  ⎿  Wrote 252 lines to WRKTTests/FeaturesTests/WorkoutSession/ExerciseSessionViewModelTests.swift
     //
     //  ExerciseSessionViewModelTests.swift
     //  WRKTTests
     //
     //  Tests for ExerciseSessionViewModel business logic
     //
     import XCTest
     @testable import WRKT
     … +242 lines (ctrl+o to expand)

⏺ Step 3: Simplified View (Example)

  Here's how your view would be simplified:

  // ✅ AFTER: Clean, focused on UI only
  struct ExerciseSessionView: View {
      @StateObject private var viewModel: ExerciseSessionViewModel
      @Environment(\.dismiss) private var dismiss

      init(exercise: Exercise, initialEntryID: UUID? = nil) {
          _viewModel = StateObject(wrappedValue: ExerciseSessionViewModel(
              exercise: exercise,
              initialEntryID: initialEntryID
          ))
      }

      var body: some View {
          VStack(spacing: 0) {
              // Header
              modernHeader

              // Content
              List {
                  setsSection
                  addSetButton
              }

              // Save button
              PrimaryCTA(title: viewModel.saveButtonTitle) {
                  viewModel.handleSave(dismiss: dismiss)
              }
          }
          .onAppear {
              viewModel.onAppear()
          }
          .alert("Empty Sets", isPresented: $viewModel.showEmptyAlert) {
              Button("OK") { }
          }
      }

      // Just UI components - no business logic!
      private var setsSection: some View {
          ForEach(viewModel.sets.indices, id: \.self) { index in
              SetRowView(
                  set: $viewModel.sets[index],
                  index: index,
                  onDelete: { viewModel.deleteSet(at: index) }
              )
          }
      }
  }

  📊 Summary: What Does This Mean?

  Before (Current State):

  | Aspect           | Current                 |
  |------------------|-------------------------|
  | File size        | 700+ lines              |
  | State properties | 20+ @State vars in view |
  | Testability      | ❌ Can't test without UI |
  | Reusability      | ❌ Logic tied to view    |
  | Maintainability  | ❌ Hard to find/fix bugs |
  | Dependencies     | ❌ Singletons in view    |

  After (With ViewModel):

  | Aspect           | With ViewModel                          |
  |------------------|-----------------------------------------|
  | File size        | View: ~200 lines, ViewModel: ~300 lines |
  | State properties | ViewModel: @Published vars              |
  | Testability      | ✅ 15+ unit tests (see example above)    |
  | Reusability      | ✅ Logic in separate class               |
  | Maintainability  | ✅ Clear separation of concerns          |
  | Dependencies     | ✅ Injected, mockable                    |

  🎯 Key Benefits You Get

  1. Testability ✅

  // Can now test business logic without rendering UI!
  func testAddSet() {
      let viewModel = ExerciseSessionViewModel(exercise: exercise)
      viewModel.addSet()
      XCTAssertEqual(viewModel.sets.count, 2)
  }

  2. Mockable Dependencies ✅

  // For tests, inject mocks
  let mockStore = MockWorkoutStore()
  let viewModel = ExerciseSessionViewModel(
      exercise: exercise,
      workoutStore: mockStore
  )

  3. Cleaner Views ✅

  - Views go from 700 lines → ~200 lines
  - Easy to read and understand
  - Focused only on UI layout

  4. Better Organization ✅

  Features/WorkoutSession/
  ├── Views/              # UI only
  │   └── ExerciseSessionView.swift (200 lines)
  ├── ViewModels/         # Business logic
  │   └── ExerciseSessionViewModel.swift (300 lines)
  └── Models/             # Data structures
      └── ExerciseSessionModels.swift

  5. Easier Debugging ✅

  - Logic bugs → Test ViewModel
  - UI bugs → Check View
  - Clear separation

  🚀 Next Steps (If You Want To Do This)

  Option 1: Start Small
  1. Pick one simple view (like a settings screen)
  2. Extract its ViewModel
  3. Write tests
  4. See the benefits

  Option 2: Full Refactor (Recommended approach)
  1. Start with ExerciseSessionView (most complex)
  2. Use the ViewModel I created above as template
  3. Add the tests I created
  4. Gradually refactor other views

  Option 3: For New Features
  - Start using ViewModels for all new features
  - Gradually refactor old code when you touch it

  📝 Quick Checklist: "Does This Need a ViewModel?"

  ✅ Yes, extract a ViewModel if:
  - View has 5+ @State properties
  - View has business logic (calculations, data manipulation)
  - View directly uses singletons
  - View is 200+ lines
  - You want to test the logic

  ❌ No, keep it simple if:
  - View is just displaying data
  - View has 1-2 @State properties for UI only (like isExpanded)
  - View is <100 lines
  - Pure presentation (no logic)

  ---
  Does this clarify what "Extract view logic to ViewModels" means? Would you like me to help you actually refactor the ExerciseSessionView to use the ViewModel I created?
