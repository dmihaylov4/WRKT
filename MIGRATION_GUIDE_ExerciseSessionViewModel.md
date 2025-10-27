# Safe Migration Guide: ExerciseSessionView → ExerciseSessionViewModel

This guide shows you **exactly how** to integrate the ViewModel into your existing `ExerciseSessionView` without breaking functionality.

## 🎯 Goal

Gradually move logic from `ExerciseSessionView` to `ExerciseSessionViewModel` while keeping the app working at every step.

## ⚠️ Before You Start

1. **Commit your current code** to git
2. **Run the app** - make sure everything works
3. **Test the exercise session flow** manually
4. **Create a backup branch**: `git checkout -b feature/exercise-session-viewmodel`

## 📋 Migration Phases

We'll do this in **5 safe phases**:

### Phase 1: Add ViewModel (No Changes to View Yet) ✅
### Phase 2: Move Simple Properties
### Phase 3: Move Business Logic Methods
### Phase 4: Simplify View Code
### Phase 5: Clean Up and Test

---

## Phase 1: Add ViewModel (Already Done) ✅

The ViewModel file already exists:
- ✅ `Features/WorkoutSession/ViewModels/ExerciseSessionViewModel.swift`
- ✅ `WRKTTests/FeaturesTests/WorkoutSession/ExerciseSessionViewModelTests.swift`

**Test it**: Run tests with `Cmd + U` - all ViewModel tests should pass.

---

## Phase 2: Move Simple Properties (30 minutes)

### Step 2.1: Add ViewModel to ExerciseSessionView

**File**: `Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift`

Find the struct declaration (around line 16):

```swift
struct ExerciseSessionView: View {
    @EnvironmentObject var store: WorkoutStoreV2
    @EnvironmentObject var repo: ExerciseRepository

    let exercise: Exercise
    let initialEntryID: UUID?
    var returnToHomeOnSave: Bool = false
```

**Add this right after the struct declaration:**

```swift
struct ExerciseSessionView: View {
    @EnvironmentObject var store: WorkoutStoreV2
    @EnvironmentObject var repo: ExerciseRepository

    let exercise: Exercise
    let initialEntryID: UUID?
    var returnToHomeOnSave: Bool = false

    // ✅ ADD THIS: ViewModel
    @StateObject private var viewModel: ExerciseSessionViewModel

    // Keep all existing @State properties for now (don't delete anything!)
    @State private var currentEntryID: UUID? = nil
    @State private var sets: [SetInput] = [SetInput(reps: 10, weight: 0)]
    // ... all other @State properties stay
```

### Step 2.2: Add Custom Initializer

**Find** the current implicit initializer (you won't see it, SwiftUI generates it automatically).

**Add** this initializer right after all the @State properties (around line 60):

```swift
    // All your existing @State properties...
    private let debugFrames = true
    private let frameUpwardAdjustment: CGFloat = 70

    // ✅ ADD THIS: Custom initializer
    init(exercise: Exercise, initialEntryID: UUID? = nil, returnToHomeOnSave: Bool = false) {
        self.exercise = exercise
        self.initialEntryID = initialEntryID
        self.returnToHomeOnSave = returnToHomeOnSave

        // Initialize ViewModel with a temporary store reference
        // We'll pass the actual store from onAppear
        self._viewModel = StateObject(wrappedValue: ExerciseSessionViewModel(
            exercise: exercise,
            initialEntryID: initialEntryID,
            returnToHomeOnSave: returnToHomeOnSave,
            workoutStore: WorkoutStoreV2(repo: .shared) // Temporary
        ))
    }

    // MARK: - Body
    var body: some View {
        // ... existing code
```

### Step 2.3: Pass Store to ViewModel on Appear

**Find** the `.onAppear` block (around line 117):

```swift
.onAppear {
    // Initialize current entry ID from the initial value
    currentEntryID = initialEntryID
    preloadExistingIfNeeded()
```

**Change it to:**

```swift
.onAppear {
    // ✅ ADD THIS: Connect store from environment
    viewModel.workoutStore = store

    // ✅ Keep all existing logic
    currentEntryID = initialEntryID
    preloadExistingIfNeeded()
```

Wait - that won't work because `workoutStore` is private. Let me fix the ViewModel first:

### Step 2.4: Make WorkoutStore Injectable After Init

**File**: `Features/WorkoutSession/ViewModels/ExerciseSessionViewModel.swift`

**Find** the private var (around line 16):

```swift
private var workoutStore: WorkoutStoreV2
```

**Change to** internal with a setter:

```swift
internal var workoutStore: WorkoutStoreV2
```

Now back to the view:

**File**: `Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift`

**Update** `.onAppear`:

```swift
.onAppear {
    // ✅ Connect real store from environment to ViewModel
    viewModel.workoutStore = store

    // Keep all existing code exactly as-is
    currentEntryID = initialEntryID
    preloadExistingIfNeeded()

    if initialEntryID == nil && !didPrefillFromHistory {
        prefillFromWorkoutHistory()
    }

    autoSelectFirstIncompleteSet()
    checkForCompletedTimerAndGenerateSet()

    // ... rest of existing code
```

### Step 2.5: Test Phase 2

**Build and run** the app:

```bash
Cmd + R
```

**Test**:
1. Open the app
2. Start a workout
3. Add an exercise
4. The exercise session view should open
5. Try adding sets, saving, etc.
6. Everything should work exactly as before!

**Why this works**: The ViewModel exists but we're not using it yet. Everything still works through the existing @State properties.

---

## Phase 3: Move Business Logic Methods (1-2 hours)

Now we'll gradually move logic from the view to the ViewModel.

### Step 3.1: Replace `addSet()` Call

**Find** where `addSet()` is called in the view (search for "addSet()").

**Before**:
```swift
Button("Add Set") {
    addSet()  // Calls view's function
}
```

**After**:
```swift
Button("Add Set") {
    viewModel.addSet()  // ✅ Calls ViewModel's function
    sets = viewModel.sets  // ✅ Sync back to view's @State
}
```

### Step 3.2: Test Just This Change

**Build and run**:
```bash
Cmd + R
```

**Test**:
- Can you add sets?
- Do they appear correctly?
- If yes, commit: `git commit -m "Use ViewModel for addSet()"`
- If no, revert and debug

### Step 3.3: Replace Computed Properties

**Find** computed properties in the view (around line 40):

```swift
private var totalReps: Int { sets.reduce(0) { $0 + max(0, $1.reps) } }
private var workingSets: Int { sets.filter { $0.reps > 0 }.count }
```

**Find** where they're used in the view and replace:

**Before**:
```swift
Text("Total: \(totalReps) reps")
Text("\(workingSets) sets")
```

**After**:
```swift
Text("Total: \(viewModel.totalReps) reps")
Text("\(viewModel.workingSets) sets")
```

**Keep the local computed properties** for now (don't delete them yet).

### Step 3.4: Test Computed Properties

**Build and run**:
```bash
Cmd + R
```

**Test**:
- Do rep counts show correctly?
- Do set counts update?
- If yes, commit: `git commit -m "Use ViewModel computed properties"`

### Step 3.5: Replace `saveButtonTitle`

**Find** where save button title is used:

```swift
PrimaryCTA(title: saveButtonTitle) {
    handleSave()
}
```

**Change to**:

```swift
PrimaryCTA(title: viewModel.saveButtonTitle) {
    handleSave()
}
```

### Step 3.6: Sync State Between View and ViewModel

This is the trickiest part. We need to keep the view's @State in sync with ViewModel's @Published.

**Add this helper method** to ExerciseSessionView (around line 900):

```swift
// MARK: - ViewModel Sync Helpers

private func syncStateToViewModel() {
    // Sync view state to ViewModel
    viewModel.sets = sets
    viewModel.currentEntryID = currentEntryID
    viewModel.activeSetIndex = activeSetIndex
    viewModel.showEmptyAlert = showEmptyAlert
    viewModel.showUnsavedSetsAlert = showUnsavedSetsAlert
    viewModel.showInfo = showInfo
    viewModel.showDemo = showDemo
    viewModel.showTutorial = showTutorial
    viewModel.currentTutorialStep = currentTutorialStep
}

private func syncViewModelToState() {
    // Sync ViewModel back to view state
    sets = viewModel.sets
    currentEntryID = viewModel.currentEntryID
    activeSetIndex = viewModel.activeSetIndex
    showEmptyAlert = viewModel.showEmptyAlert
    showUnsavedSetsAlert = viewModel.showUnsavedSetsAlert
    showInfo = viewModel.showInfo
    showDemo = viewModel.showDemo
    showTutorial = viewModel.showTutorial
    currentTutorialStep = viewModel.currentTutorialStep
}
```

**Update `.onAppear`** to sync initially:

```swift
.onAppear {
    viewModel.workoutStore = store

    // ✅ Sync initial state
    syncStateToViewModel()

    // Keep all existing code
    currentEntryID = initialEntryID
    preloadExistingIfNeeded()
    // ... rest
}
```

### Step 3.7: Test Sync

**Build and run**, test everything still works.

---

## Phase 4: Gradually Replace Business Logic (2-3 hours)

Now we'll replace methods one at a time.

### Step 4.1: Replace Simple Methods First

Start with the simplest methods.

**Find `deleteSet(at:)` calls**:

```swift
.onDelete { indexSet in
    for index in indexSet {
        deleteSet(at: index)
    }
}
```

**Change to**:

```swift
.onDelete { indexSet in
    for index in indexSet {
        viewModel.deleteSet(at: index)
        syncViewModelToState()  // ✅ Sync back to view
    }
}
```

**Test**: Can you delete sets? If yes, commit.

### Step 4.2: Replace Tutorial Methods

**Find** calls to tutorial methods:

```swift
Button("Next") {
    advanceTutorial()
}

Button("Skip") {
    skipTutorial()
}
```

**Change to**:

```swift
Button("Next") {
    viewModel.advanceTutorial()
    syncViewModelToState()
}

Button("Skip") {
    viewModel.skipTutorial()
    syncViewModelToState()
}
```

**Test**: Does the tutorial work? If yes, commit.

### Step 4.3: Replace `handleSave()` (Most Important)

This is the biggest change. We'll do it carefully.

**Find** `handleSave()` call (around line 78):

```swift
PrimaryCTA(title: viewModel.saveButtonTitle) {
    handleSave()  // Old function
}
```

**Change to**:

```swift
PrimaryCTA(title: viewModel.saveButtonTitle) {
    syncStateToViewModel()  // ✅ Sync before save
    viewModel.handleSave(dismiss: dismiss)  // ✅ Use ViewModel
}
```

**Test this thoroughly**:
1. Create new exercise session ✅
2. Add sets ✅
3. Save ✅
4. Check if it appears in workout ✅
5. Edit existing entry ✅
6. Save changes ✅
7. Check updates work ✅

If everything works: `git commit -m "Use ViewModel for handleSave()"`

### Step 4.4: Replace Lifecycle Methods

**Find** `preloadExistingIfNeeded()` call:

```swift
.onAppear {
    currentEntryID = initialEntryID
    preloadExistingIfNeeded()
```

**Add ViewModel call BEFORE the existing call**:

```swift
.onAppear {
    viewModel.workoutStore = store
    viewModel.onAppear()  // ✅ Let ViewModel do its lifecycle
    syncViewModelToState()  // ✅ Sync back to view

    // Keep existing calls for now (we'll remove later)
    currentEntryID = initialEntryID
    preloadExistingIfNeeded()
```

**Test**: Does data pre-fill correctly?

---

## Phase 5: Clean Up (1 hour)

Now that everything works through the ViewModel, we can clean up.

### Step 5.1: Remove Duplicate Computed Properties

**Find** and **comment out** (don't delete yet):

```swift
// private var totalReps: Int { sets.reduce(0) { $0 + max(0, $1.reps) } }
// private var workingSets: Int { sets.filter { $0.reps > 0 }.count }
// private var saveButtonTitle: String { currentEntryID != nil ? "Update" : "Save" }
```

**Test**: Does everything still work? If yes, actually delete these lines.

### Step 5.2: Remove Duplicate Methods

**Gradually comment out** and test methods that are now in ViewModel:

```swift
// private func addSet() { ... }  // Now in ViewModel
// private func deleteSet(at index: Int) { ... }  // Now in ViewModel
// private func advanceTutorial() { ... }  // Now in ViewModel
// private func skipTutorial() { ... }  // Now in ViewModel
```

**Test after each one**: App still works? Yes → Delete the commented code.

### Step 5.3: Migrate to ViewModel @Published Properties

Once everything is working, we can gradually replace @State with ViewModel bindings.

**Pick one simple property**, like `showInfo`:

**Before**:
```swift
@State private var showInfo = false

// ... in view:
.sheet(isPresented: $showInfo) {
    InfoView()
}
```

**After**:
```swift
// Remove: @State private var showInfo = false

// ... in view:
.sheet(isPresented: $viewModel.showInfo) {  // ✅ Direct binding
    InfoView()
}
```

**Test**: Does the info sheet still work?

**Repeat** for other properties one at a time:
- `showDemo`
- `showEmptyAlert`
- `showTutorial`
- etc.

### Step 5.4: Final Cleanup

Once all properties are migrated:

1. **Remove** `syncStateToViewModel()` and `syncViewModelToState()` (no longer needed)
2. **Remove** all duplicate `@State` properties
3. **Remove** all duplicate methods
4. **Run all tests**: `Cmd + U`
5. **Test app thoroughly**

---

## ✅ Final Checklist

After migration, verify:

- [ ] App builds without errors
- [ ] Can start a workout
- [ ] Can add exercise to workout
- [ ] Exercise session view opens
- [ ] Can add sets
- [ ] Can delete sets
- [ ] Can edit set values (reps, weight)
- [ ] Can change set tags (warmup, working, backoff)
- [ ] Save button title correct (Save/Update)
- [ ] Can save new exercise
- [ ] Can update existing exercise
- [ ] Tutorial works
- [ ] Can skip tutorial
- [ ] All alerts work (empty sets, unsaved changes)
- [ ] App doesn't crash
- [ ] All unit tests pass: `Cmd + U`

---

## 🔄 If Something Breaks

### Quick Rollback

If anything breaks during migration:

```bash
# Rollback last commit
git reset --hard HEAD~1

# Or rollback to before migration
git checkout main
```

### Debug Steps

1. **Check console** for error messages
2. **Set breakpoints** in ViewModel methods
3. **Verify** sync methods are called
4. **Check** if workoutStore is passed correctly
5. **Compare** with working backup branch

### Common Issues

**Issue**: "Value of type 'ExerciseSessionViewModel' has no member 'workoutStore'"
**Fix**: Make sure you made `workoutStore` internal in Step 2.4

**Issue**: "Sets aren't saving"
**Fix**: Make sure you call `syncStateToViewModel()` before `viewModel.handleSave()`

**Issue**: "UI not updating"
**Fix**: Make sure you call `syncViewModelToState()` after ViewModel methods

**Issue**: "App crashes on save"
**Fix**: Check that `workoutStore` is connected in `.onAppear`

---

## 📊 Progress Tracking

Track your migration progress:

### Phase 2: Add ViewModel
- [ ] Step 2.1: Add ViewModel property
- [ ] Step 2.2: Add custom initializer
- [ ] Step 2.3: Make workoutStore injectable
- [ ] Step 2.4: Pass store on appear
- [ ] Step 2.5: Test - everything works

### Phase 3: Move Business Logic
- [ ] Step 3.1: Replace addSet() call
- [ ] Step 3.2: Test addSet()
- [ ] Step 3.3: Replace computed properties
- [ ] Step 3.4: Test computed properties
- [ ] Step 3.5: Replace saveButtonTitle
- [ ] Step 3.6: Add sync helpers
- [ ] Step 3.7: Test sync

### Phase 4: Replace Methods
- [ ] Step 4.1: Replace deleteSet()
- [ ] Step 4.2: Replace tutorial methods
- [ ] Step 4.3: Replace handleSave()
- [ ] Step 4.4: Replace lifecycle methods
- [ ] Test everything thoroughly

### Phase 5: Clean Up
- [ ] Step 5.1: Remove duplicate computed properties
- [ ] Step 5.2: Remove duplicate methods
- [ ] Step 5.3: Migrate to @Published properties
- [ ] Step 5.4: Final cleanup
- [ ] Run all tests
- [ ] Final verification

---

## 🎯 Expected Timeline

**Total time**: 4-6 hours spread over 2-3 days

- **Day 1** (2-3 hours): Phases 2-3
  - Add ViewModel to view
  - Test basic integration
  - Replace simple methods

- **Day 2** (2 hours): Phase 4
  - Replace business logic
  - Test thoroughly
  - Fix any issues

- **Day 3** (1 hour): Phase 5
  - Clean up duplicate code
  - Final testing
  - Celebrate! 🎉

---

## 💡 Pro Tips

1. **Commit after every step** - Easy to rollback if needed
2. **Test after every change** - Catch issues early
3. **Keep app running** - Don't break main functionality
4. **Ask for help** - If stuck, reference this guide or ask
5. **Take breaks** - Fresh eyes catch bugs better

---

## 🎓 What You'll Learn

By doing this migration, you'll understand:

- ✅ How ViewModels work in practice
- ✅ How to safely refactor large files
- ✅ How to keep app working during migration
- ✅ How to test business logic independently
- ✅ How to organize code better

---

## Next After This Migration

Once `ExerciseSessionView` is migrated:

1. **Apply pattern to other views**:
   - `WorkoutDetailView` → `WorkoutDetailViewModel`
   - `PlannerSetupView` → `PlannerSetupViewModel`

2. **Improve testing**:
   - Add more ViewModel tests
   - Test edge cases
   - Test error scenarios

3. **Refine the pattern**:
   - Extract protocols for testing
   - Add mock implementations
   - Improve dependency injection

---

**Ready to start?** Begin with Phase 2, Step 2.1! 🚀

**Questions?** Refer to `VIEWMODEL_EXTRACTION_EXAMPLE.md` for concepts, this guide for implementation steps.
