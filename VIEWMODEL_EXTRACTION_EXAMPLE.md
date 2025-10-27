# ViewModel Extraction Example

This document explains what "Extract view logic to ViewModels" means using a **real example** from your codebase.

## 📋 Table of Contents

1. [What We Created](#what-we-created)
2. [The Problem (Before)](#the-problem-before)
3. [The Solution (After)](#the-solution-after)
4. [How to Use It](#how-to-use-it)
5. [Benefits](#benefits)
6. [Next Steps](#next-steps)

---

## What We Created

We created a **reference implementation** showing how to extract view logic from `ExerciseSessionView` into a ViewModel:

### New Files Created:

1. **`Features/WorkoutSession/ViewModels/ExerciseSessionViewModel.swift`**
   - Contains all business logic and state management
   - 220 lines of testable code
   - Properly uses your actual API (WorkoutStoreV2, OnboardingManager)

2. **`WRKTTests/FeaturesTests/WorkoutSession/ExerciseSessionViewModelTests.swift`**
   - 15 unit tests covering the ViewModel logic
   - Tests run in milliseconds (no UI rendering)
   - Demonstrates testability

---

## The Problem (Before)

### Current `ExerciseSessionView.swift` Issues:

```swift
struct ExerciseSessionView: View {
    @EnvironmentObject var store: WorkoutStoreV2        // ❌ Singleton dependency
    @EnvironmentObject var repo: ExerciseRepository

    // ❌ 20+ @State properties scattered in the view
    @State private var currentEntryID: UUID? = nil
    @State private var sets: [SetInput] = [SetInput(reps: 10, weight: 0)]
    @State private var activeSetIndex: Int = 0
    @State private var didPreloadExisting = false
    @State private var showEmptyAlert = false
    // ... 15+ more @State properties

    var body: some View {
        VStack {
            // ❌ 700+ lines of UI mixed with business logic
            Button("Save") {
                handleSave()  // Business logic in view
            }
        }
    }

    // ❌ Business logic embedded in view functions
    private func handleSave() {
        let validSets = sets.filter { $0.reps > 0 && $0.weight >= 0 }
        guard !validSets.isEmpty else {
            showEmptyAlert = true
            return
        }

        if let entryID = currentEntryID {
            store.updateEntrySetsAndActiveIndex(...)
        } else {
            let entryID = store.addExerciseToCurrent(exercise)
            store.updateEntrySets(...)
        }
        // More logic...
    }
}
```

### Problems:
- ❌ **700+ lines** - impossible to navigate
- ❌ **Not testable** - can't test logic without rendering UI
- ❌ **Tightly coupled** - view depends directly on singletons
- ❌ **Mixed concerns** - UI + business logic in same file
- ❌ **Hard to maintain** - finding bugs requires reading hundreds of lines

---

## The Solution (After)

### Architecture with ViewModel:

```
┌─────────────────────────────────────────┐
│  ExerciseSessionView (SwiftUI)          │
│  - Just UI rendering                    │
│  - Binds to ViewModel @Published vars   │
│  - ~200 lines (clean & focused)         │
└─────────────┬───────────────────────────┘
              │ @StateObject
              ▼
┌─────────────────────────────────────────┐
│  ExerciseSessionViewModel                │
│  - All business logic                    │
│  - State management                      │
│  - Calls WorkoutStoreV2 methods          │
│  - ~300 lines (testable)                 │
└─────────────┬───────────────────────────┘
              │ Dependencies injected
              ▼
┌─────────────────────────────────────────┐
│  WorkoutStoreV2, ExerciseRepository     │
│  OnboardingManager                       │
└─────────────────────────────────────────┘
```

### 1. ViewModel (Business Logic)

**File**: `Features/WorkoutSession/ViewModels/ExerciseSessionViewModel.swift`

```swift
@MainActor
class ExerciseSessionViewModel: ObservableObject {
    // ✅ Dependencies injected (testable!)
    private var workoutStore: WorkoutStoreV2
    private let exerciseRepo: ExerciseRepository
    private let onboardingManager: OnboardingManager

    // ✅ Published state (UI binds to these)
    @Published var currentEntryID: UUID?
    @Published var sets: [SetInput] = [SetInput(reps: 10, weight: 0)]
    @Published var activeSetIndex: Int = 0
    @Published var showEmptyAlert = false
    // ... more state

    // ✅ Computed properties
    var totalReps: Int {
        sets.reduce(0) { $0 + max(0, $1.reps) }
    }

    var saveButtonTitle: String {
        currentEntryID != nil ? "Update Exercise" : "Save Exercise"
    }

    // ✅ Initialization with dependency injection
    init(
        exercise: Exercise,
        initialEntryID: UUID? = nil,
        returnToHomeOnSave: Bool = false,
        workoutStore: WorkoutStoreV2  // Injected!
    ) {
        self.exercise = exercise
        self.workoutStore = workoutStore
        // ...
    }

    // ✅ Testable business logic methods
    func handleSave(dismiss: DismissAction) {
        let validSets = sets.filter { $0.reps > 0 && $0.weight >= 0 }

        guard !validSets.isEmpty else {
            showEmptyAlert = true
            return
        }

        if let entryID = currentEntryID {
            workoutStore.updateEntrySetsAndActiveIndex(
                entryID: entryID,
                sets: validSets,
                activeSetIndex: activeSetIndex
            )
        } else {
            let entryID = workoutStore.addExerciseToCurrent(exercise)
            workoutStore.updateEntrySets(entryID: entryID, sets: validSets)
        }

        if showTutorial {
            onboardingManager.complete(.exerciseSession)
        }

        dismiss()
    }

    func addSet() { /* ... */ }
    func deleteSet(at index: Int) { /* ... */ }
    func updateSet(at index: Int, _ updatedSet: SetInput) { /* ... */ }
}
```

### 2. Simplified View (UI Only)

**Future state of** `ExerciseSessionView.swift`:

```swift
struct ExerciseSessionView: View {
    @EnvironmentObject var store: WorkoutStoreV2
    @StateObject private var viewModel: ExerciseSessionViewModel
    @Environment(\.dismiss) private var dismiss

    // ✅ Clean initialization
    init(exercise: Exercise, initialEntryID: UUID? = nil) {
        // Pass store from environment to ViewModel
        let store = /* get from environment */
        _viewModel = StateObject(wrappedValue: ExerciseSessionViewModel(
            exercise: exercise,
            initialEntryID: initialEntryID,
            workoutStore: store
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // ✅ Just UI - clean and readable
            modernHeader

            List {
                ForEach(viewModel.sets.indices, id: \.self) { index in
                    SetRowView(
                        set: $viewModel.sets[index],
                        onDelete: { viewModel.deleteSet(at: index) }
                    )
                }
            }

            // ✅ Simple binding to ViewModel
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

    // ✅ Just UI components - no business logic!
    private var modernHeader: some View {
        HStack {
            Text(viewModel.exercise.name)
            Text("Set \(viewModel.activeSetIndex + 1)/\(viewModel.sets.count)")
        }
    }
}
```

### 3. Unit Tests (Fast & Comprehensive)

**File**: `WRKTTests/FeaturesTests/WorkoutSession/ExerciseSessionViewModelTests.swift`

```swift
@MainActor
final class ExerciseSessionViewModelTests: WRKTTestCase {

    // ✅ Can now test business logic directly!
    func testAddSet() {
        let store = WorkoutStoreV2(repo: .shared)
        let viewModel = ExerciseSessionViewModel(
            exercise: TestFixtures.benchPress,
            workoutStore: store
        )

        let initialCount = viewModel.sets.count
        viewModel.addSet()

        XCTAssertEqual(viewModel.sets.count, initialCount + 1)
        XCTAssertTrue(viewModel.sets.last!.autoWeight)
    }

    func testSaveButtonTitle() {
        let store = WorkoutStoreV2(repo: .shared)
        let viewModel = ExerciseSessionViewModel(
            exercise: TestFixtures.benchPress,
            workoutStore: store
        )

        viewModel.currentEntryID = nil
        XCTAssertEqual(viewModel.saveButtonTitle, "Save Exercise")

        viewModel.currentEntryID = UUID()
        XCTAssertEqual(viewModel.saveButtonTitle, "Update Exercise")
    }

    func testTotalRepsCalculation() {
        let store = WorkoutStoreV2(repo: .shared)
        let viewModel = ExerciseSessionViewModel(
            exercise: TestFixtures.benchPress,
            workoutStore: store
        )

        viewModel.sets = [
            SetInput(reps: 10, weight: 60),
            SetInput(reps: 8, weight: 80),
            SetInput(reps: 6, weight: 90)
        ]

        XCTAssertEqual(viewModel.totalReps, 24)
    }

    // ... 12+ more tests covering all business logic
}
```

---

## How to Use It

### Option 1: Reference Implementation (Current State)

The ViewModel is created as a **reference** - you don't have to use it right now:

1. **Learn from it** - See how ViewModels work
2. **Use for new features** - Apply pattern to new screens
3. **Gradually refactor** - When touching ExerciseSessionView, start using it

### Option 2: Gradual Integration (Recommended)

Start using the ViewModel piece by piece:

**Week 1**: Extract simple computed properties
```swift
// Move to ViewModel:
var totalReps: Int { ... }
var workingSets: Int { ... }
var saveButtonTitle: String { ... }
```

**Week 2**: Extract state management
```swift
// Move @State to @Published in ViewModel:
@Published var sets: [SetInput] = []
@Published var activeSetIndex: Int = 0
```

**Week 3**: Extract business logic methods
```swift
// Move to ViewModel:
func handleSave() { ... }
func addSet() { ... }
func deleteSet(at index: Int) { ... }
```

**Week 4**: Complete migration
- View is now < 300 lines
- All logic in testable ViewModel
- 15+ unit tests passing

### Option 3: Use for New Features Only

Keep existing code as-is, but use ViewModels for **all new features**:
- New screens → Start with ViewModel
- New complex views → Extract ViewModel
- Simple views → Can stay without ViewModel

---

## Benefits

### 1. **Testability** ✅

**Before**: Can't test without rendering UI
```swift
// ❌ Can't test this without running the app
private func handleSave() {
    // Complex logic mixed with UI
}
```

**After**: Direct unit tests
```swift
// ✅ Test runs in milliseconds
func testHandleSave() {
    viewModel.sets = [SetInput(reps: 10, weight: 60)]
    viewModel.handleSave(dismiss: mockDismiss)
    XCTAssertEqual(store.entriesAdded.count, 1)
}
```

### 2. **Maintainability** ✅

**Before**: 700+ lines, hard to find bugs
```
ExerciseSessionView.swift (700+ lines)
├─ UI code (500 lines)
├─ Business logic (150 lines)
└─ Helper methods (50 lines)
```

**After**: Clear separation
```
ExerciseSessionView.swift (~200 lines)
└─ Just UI rendering

ExerciseSessionViewModel.swift (~300 lines)
└─ All business logic (testable)
```

### 3. **Reusability** ✅

**Before**: Logic tied to specific view
```swift
// ❌ Can't reuse this logic in iPad/Mac version
struct ExerciseSessionView: View {
    // Logic embedded here
}
```

**After**: Logic is portable
```swift
// ✅ Same ViewModel works on iPad, Mac, watchOS
class ExerciseSessionViewModel {
    // Platform-independent logic
}

// Different views for each platform
struct ExerciseSessionView_iOS: View { }
struct ExerciseSessionView_Mac: View { }
```

### 4. **Debugging** ✅

**Before**: Set breakpoints in 700-line file, hard to isolate
```swift
// ❌ Which of these 20 functions has the bug?
private func handleSave() { }
private func prefillFromHistory() { }
private func autoSelectFirstIncompleteSet() { }
// ... 17 more functions
```

**After**: Clear boundaries
```swift
// ✅ Bug in save logic? Check ViewModel.handleSave()
// ✅ Bug in UI layout? Check View
// ✅ Bug in data? Check WorkoutStoreV2
```

### 5. **Parallel Development** ✅

**Before**: Team members conflict on same 700-line file
```
Developer A: Working on UI
Developer B: Working on save logic
Result: Merge conflicts 😫
```

**After**: Work independently
```
Developer A: Works on ExerciseSessionView.swift (UI only)
Developer B: Works on ExerciseSessionViewModel.swift (logic only)
Result: No conflicts! 🎉
```

---

## Next Steps

### Immediate (No Code Changes)

1. ✅ **Read the ViewModel** - Understand the pattern
2. ✅ **Run the tests** - See how testing works
   ```bash
   Cmd + U  # Run all tests including ViewModel tests
   ```
3. ✅ **Compare** - Look at current ExerciseSessionView vs ViewModel

### Short Term (1-2 weeks)

1. **Try it on a simple view first**
   - Pick a small view (e.g., preferences screen)
   - Extract its ViewModel
   - See the benefits on smaller scale

2. **Add more ViewModel tests**
   - Test edge cases
   - Test error scenarios
   - Test complex workflows

### Long Term (1-2 months)

1. **Gradually refactor ExerciseSessionView**
   - Start using the ViewModel we created
   - Move logic piece by piece
   - Keep app working throughout

2. **Apply pattern to other views**
   - WorkoutDetail → WorkoutDetailViewModel
   - PlannerSetup → PlannerSetupViewModel
   - ProfileView → ProfileViewModel

3. **Establish pattern as standard**
   - All new views use ViewModels
   - Document the pattern
   - Code review for ViewModel usage

---

## FAQ

### Q: Do I have to refactor everything now?

**A**: No! This is a reference implementation. Use it:
- As learning material
- For new features
- Gradually when touching old code

### Q: Will this break my existing app?

**A**: No! The ViewModel we created doesn't affect existing code. It's an **addition**, not a replacement (yet).

### Q: How do I actually start using it?

**A**: Two options:
1. **New features**: Start with ViewModel pattern
2. **Existing code**: When you need to modify ExerciseSessionView, gradually move logic to the ViewModel

### Q: What about performance?

**A**: ViewModels are **better** for performance:
- Only UI re-renders when needed
- Business logic runs independently
- Can optimize ViewModel operations

### Q: Do all views need ViewModels?

**A**: No! Simple views don't need them:
- ✅ **Need ViewModel**: Complex views with 5+ @State properties, business logic
- ❌ **Don't need**: Simple display views, < 100 lines, no business logic

---

## Summary

**What "Extract ViewModels" means:**

1. **Move** business logic from View → ViewModel
2. **Move** @State properties → @Published properties
3. **Keep** UI rendering in View
4. **Inject** dependencies for testability
5. **Write** unit tests for ViewModel

**Result:**
- View: < 300 lines, just UI
- ViewModel: ~300 lines, all logic, fully tested
- Tests: 15+ tests, runs in seconds
- Maintenance: Easy to find and fix bugs
- Development: Multiple people can work without conflicts

---

**Files to examine:**
- `Features/WorkoutSession/ViewModels/ExerciseSessionViewModel.swift` (reference implementation)
- `WRKTTests/FeaturesTests/WorkoutSession/ExerciseSessionViewModelTests.swift` (15 tests)
- This document (explanation)

**Don't forget**: This is a **pattern** to learn from, not a requirement to implement immediately!
