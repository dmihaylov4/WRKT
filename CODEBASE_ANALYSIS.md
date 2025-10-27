# WRKT iOS Workout Tracking App - Comprehensive Code Analysis

## Executive Summary
This is a feature-rich SwiftUI fitness tracking application with a well-organized architecture using modern Swift practices (actors, SwiftData, Combine). However, there are several architectural, performance, and code quality issues that should be addressed for maintainability and scalability.

---

## 1. ARCHITECTURE & ORGANIZATION

### 1.1 Strengths
- **Clear Separation of Concerns**: Core/, Features/, DesignSystem/ folder structure is logical
- **Dependency Injection Pattern**: AppDependencies.swift properly centralizes and manages services
- **Actor-based Concurrency**: WorkoutStorage, ExerciseCache, StatsAggregator use actor for thread safety
- **Service Layer Pattern**: ExerciseRepository, WorkoutStoreV2, HealthKitManager separate business logic

### 1.2 Critical Issues

#### Issue A1: Singleton Proliferation with Injection Complexity
**Files**: 
- `/Users/dimitarmihaylov/dev/WRKT/Core/Dependencies/AppDependencies.swift` (lines 16-61)
- `/Users/dimitarmihaylov/dev/WRKT/Features/ExerciseRepository/Services/ExerciseRepository.swift` (line 13)
- `/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift` (line 25)
- `/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Services/RewardEngine.swift` (line 55)

**Problem**: 
Multiple singletons (ExerciseRepository.shared, HealthKitManager.shared, RewardsEngine.shared) exist alongside AppDependencies which also holds references to these same singletons. This creates redundant singleton patterns and makes testing difficult.

**Example**:
```swift
// ExerciseRepository creates its own singleton
@MainActor
final class ExerciseRepository: ObservableObject {
    static let shared = ExerciseRepository()
}

// Then AppDependencies creates another reference
let exerciseRepository: ExerciseRepository = ExerciseRepository.shared
```

**Impact**: 
- Hard to test (can't inject mocks)
- Multiple entry points for same service
- Confusing for developers which pattern to use

**Recommendation**: Either use only AppDependencies for injection OR use dependency injection container for all services. Remove redundant singletons.

---

#### Issue A2: Incomplete Dependency Injection in Views
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift` (lines 14-23)
- `/Users/dimitarmihaylov/dev/WRKT/Features/Home/HomeView.swift` (lines 16-19)

**Problem**:
Some views inject dependencies via EnvironmentObject while AppShellView manually references singleton. Inconsistent patterns.

```swift
// AppShellView gets dependencies but still manually accesses singletons
@StateObject private var dependencies = AppDependencies.shared
private var repo: ExerciseRepository { dependencies.exerciseRepository }

// Yet still uses direct singleton access in some places
healthKitManager: HealthKitManager { dependencies.healthKitManager }
```

**Impact**: Mixed patterns across codebase, harder to maintain

---

#### Issue A3: Missing AppEvents/Notifications Abstraction
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift` (lines 143-172, 254-266)
- `/Users/dimitarmihaylov/dev/WRKT/Core/Utilities/AppEvents.swift`

**Problem**:
Excessive use of NotificationCenter for inter-screen communication. Currently using raw notification names scattered throughout:
- `.homeTabReselected`, `.calendarTabReselected`, `.cardioTabReselected`
- `.tabSelectionChanged`, `.tabDidChange`
- `.dismissLiveOverlay`, `.resetHomeToRoot`
- `.rewardsDidSummarize`

**Impact**:
- No centralized event system, hard to discover all events
- Prone to typos and runtime errors
- Harder to track event flow

**Recommendation**: Create typed event enum instead of raw strings

---

### 1.4 Architectural Pattern Issues

#### Issue A4: Layer Violation - Views with Heavy Business Logic
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift` (700+ lines)

**Problem**:
ExerciseSessionView is 700+ lines containing:
- Set management logic
- Prefill algorithms
- Tutorial state management  
- Multiple onAppear/onChange handlers with complex logic

Views should be thin presentation layers, not contain business logic.

---

## 2. CODE QUALITY & BEST PRACTICES

### 2.1 SwiftUI Issues

#### Issue Q1: Improper State Management Pattern
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift` (line 15)
- `/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift` (line 44)

**Problem**:
```swift
// AppShellView.swift line 15
@StateObject private var dependencies = AppDependencies.shared

// This recreates the object on each view initialization!
// Should be:
@Environment(\.dependencies) private var dependencies
// or injected as @EnvironmentObject

// ExerciseSessionView.swift line 44
@StateObject private var onboardingManager = OnboardingManager.shared

// Creates new instance instead of using shared singleton
```

**Impact**: Potential multiple instances, memory waste, state inconsistency

---

#### Issue Q2: Excessive @State Usage
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Features/ExerciseSession/ExcerciseSessionView.swift` (lines 30-55)

**Problem**:
Over 20 @State properties in a single view:
```swift
@State private var currentEntryID: UUID? = nil
@State private var sets: [SetInput] = [...]
@State private var activeSetIndex: Int = 0
@State private var didPreloadExisting = false
@State private var didPrefillFromHistory = false
@State private var showEmptyAlert = false
@State private var showUnsavedSetsAlert = false
@State private var showInfo = false
@State private var showDemo = false
// ... more state
```

**Impact**: 
- Difficult to manage state
- Hard to trace state dependencies
- Difficult to test
- Views become god objects

**Recommendation**: Extract state into a view model or @StateObject

---

#### Issue Q3: Missing Accessibility
**Files**: Multiple view files
- `/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Views/RestTimer/RestTimerView.swift` (no .accessibilityLabel detected)
- `/Users/dimitarmihaylov/dev/WRKT/DesignSystem/Components/SwipeToConfirm.swift` (no .accessibilityElement or .accessibilityLabel)

**Problem**:
No comprehensive accessibility implementation. SwipeToConfirm and many interactive components lack:
- `.accessibilityLabel`
- `.accessibilityHint`  
- `.accessibilityAction`
- Voice Control support

**Impact**: App is inaccessible to users with visual impairments or motor disabilities

---

### 2.2 Error Handling Issues

#### Issue Q4: Silent Error Swallowing
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Core/Persistence/WorkoutStorage.swift` (lines 196-199, 208, 214)
- `/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/WorkoutStoreV2.swift` (line 67)

**Problem**:
```swift
// Line 196-199 - silently fails on decode errors
} catch let error as DecodingError {
    print("⚠️ Failed to decode current workout: \(error)")
    return nil  // ← silent failure, data lost
}

// Line 208 - try? silently fails
try? fileManager.removeItem(at: currentWorkoutFileURL)

// WorkoutStoreV2 line 67
} catch {
    print("❌ Failed to load from storage: \(error)")
    // No recovery mechanism, just silences error
}
```

**Impact**:
- User doesn't know their data failed to load
- No error reporting/telemetry
- Difficult to debug in production

**Recommendation**: Implement proper error handling with user-facing feedback and logging

---

#### Issue Q5: Force Unwraps
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Core/Models/WorkoutEntry.swift` (line 44)
- `/Users/dimitarmihaylov/dev/WRKT/Features/ExerciseRepository/Services/ExerciseRepository.swift` (line 68)

**Problem**:
```swift
// Line 44
let i = all.firstIndex(of: self)!  // Force unwrap

// Line 68
self.byID = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0) })
// No error handling if IDs aren't unique
```

**Impact**: Crashes if assumptions are violated

---

### 2.3 Memory Management

#### Issue Q6: Potential Memory Leaks in Closures
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Features/ExerciseRepository/Services/ExerciseRepository.swift` (lines 158, 251)
- `/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift` (line 145)

**Problem**:
Most Task.detached calls use `[weak self]` properly, but some don't:
```swift
// Line 158 - good:
Task.detached(priority: .userInitiated) { [weak self] in
    guard let self else { return }
    // ...
}

// But some could be optimized to avoid capturing self at all
```

**Also identified**: ExerciseRepository uses singletons extensively, which prevents proper memory cleanup

---

## 3. PERFORMANCE ISSUES

### 3.1 Critical Performance Bottlenecks

#### Issue P1: Synchronous Data Loading on Main Thread
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Features/ExerciseRepository/Services/ExerciseRepository.swift` (lines 62-87)

**Problem**:
```swift
func bootstrap(useSlimPreload: Bool = true) {
    Task {
        do {
            // This loads ALL exercises into memory at once
            try await cache.loadAllExercises()
            
            // Then builds full indexes synchronously
            let allExercises = await cache.getAllExercises()
            self.byID = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0) })
        }
    }
}
```

**Issues**:
- Loads entire exercise database into memory (potentially thousands of records)
- Builds 3 indexes (byID, bySlug, bySubregion) all at once
- No pagination during loading

**Impact**:
- High memory usage
- Slow app startup
- No incremental loading

---

#### Issue P2: Inefficient Filtering and Search
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Features/ExerciseRepository/Models/ExerciseCache.swift` (lines 88-127)

**Problem**:
```swift
func getPage(_ page: Int, matching filters: ExerciseFilters? = nil) -> [Exercise] {
    // Filters ALL exercises every time
    let filtered: [Exercise]
    if let filters = filters {
        filtered = allExercises.filter { ex in
            // Multiple nested conditions evaluated for each exercise
            if let muscleGroup = filters.muscleGroup, !muscleGroup.isEmpty {
                guard ex.contains(muscleGroup: muscleGroup) else { return false }
            }
            if filters.equipment != .all {
                guard ex.equipBucket == filters.equipment else { return false }
            }
            if filters.moveType != .all {
                guard ex.moveBucket == filters.moveType else { return false }
            }
            if !filters.searchQuery.isEmpty {
                guard ex.matches(filters.searchQuery) else { return false }
            }
            return true
        }
    }
    // Then paginates
    let startIndex = page * pageSize
    return Array(filtered[startIndex..<endIndex])
}
```

**Issues**:
- Re-filters entire dataset on each page load
- String matching with `.matches()` is called for every record on every search
- No caching of filtered results

**Impact**:
- O(n) operations on every page load
- Search feels sluggish
- Inefficient CPU/battery usage

**Recommendation**: Implement caching, memoization, or indexed search

---

#### Issue P3: StatsAggregator Heavy Computation
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Features/Statistics/Services/StatsAggregator.swift` (lines 143-150+)

**Problem**:
StatsAggregator does heavy computation in `reindex()` and `apply()` methods. Currently runs on background thread but operations aren't clearly documented. Missing granular progress reporting.

---

#### Issue P4: Unnecessary View Recomputations
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift` (lines 374-395)

**Problem**:
```swift
// Line 376 - This print evaluation causes recomputation on every render!
let _ = print("🎯 Grab tab overlay evaluation: shouldShow=\(shouldShow)...")
```

This forces SwiftUI to evaluate the entire condition on every render cycle.

---

### 3.2 Secondary Performance Issues

#### Issue P5: DispatchQueue.main.asyncAfter Usage
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift` (lines 132, 135, 148)
- `/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift` (lines 484-498)

**Problem**:
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
    if !framesReady && !onboardingManager.hasSeenExerciseSession && !showTutorial {
        showTutorial = true
    }
}
```

**Issues**:
- Hard-coded delays (2.5 seconds, 0.3 seconds)
- Not integrated with proper async/await pattern
- Difficult to test and cancel

**Recommendation**: Use Task.sleep(nanoseconds:) with proper cancellation

---

## 4. DATA MANAGEMENT

### 4.1 Data Model Issues

#### Issue D1: Custom Decoder Complexity
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Core/Models/CompletedWorkout.swift` (lines 40-60)
- `/Users/dimitarmihaylov/dev/WRKT/Core/Models/WorkoutEntry.swift` (lines 65-76)

**Problem**:
Duplicate custom decoders for backward compatibility. This pattern is repeated across multiple models. Creates maintenance burden.

**Recommendation**: Create a separate migration layer or use a single decoder helper

---

#### Issue D2: Inconsistent ID Generation
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Core/Models/CompletedWorkout.swift` (line 17)
- `/Users/dimitarmihaylov/dev/WRKT/Core/Models/CurrentWorkout.swift` (line 11)
- `/Users/dimitarmihaylov/dev/WRKT/Core/Models/WorkoutEntry.swift` (line 93)

**Problem**:
Default IDs are generated in model initializers instead of at creation point:
```swift
var id = UUID()  // Generated at definition, not at init!
```

**Impact**: 
- Non-deterministic behavior
- Difficult to test
- IDs can be accidentally regenerated

**Better approach**:
```swift
var id: UUID
init(id: UUID = UUID(), ...) {
    self.id = id
}
```

---

### 4.2 Storage Architecture Issues

#### Issue D3: Potential Data Corruption with Atomic Writes
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Core/Persistence/WorkoutStorage.swift` (lines 175, 205, 238)

**Problem**:
Uses atomic writes but doesn't implement proper crash recovery:
```swift
let data = try encoder.encode(container)
try data.write(to: workoutsFileURL, options: [.atomic])
```

While `.atomic` is good, there's no:
- Verification after write
- Transaction logging
- Crash recovery mechanism

---

#### Issue D4: Duplicate Storage Systems
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Core/Persistence/WorkoutStorage.swift`
- `/Users/dimitarmihaylov/dev/WRKT/Persistence/Persistence.swift`

**Problem**: 
There appear to be two separate persistence implementations. The git status shows both files exist, suggesting potential duplication or incomplete migration.

---

## 5. DEPENDENCY MANAGEMENT

### 5.1 Issues

#### Issue M1: Lazy Initialization Complexity
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Core/Dependencies/AppDependencies.swift` (lines 70-96)

**Problem**:
Some dependencies require configuration after initialization:
```swift
@Published private(set) var statsAggregator: StatsAggregator?

// Must be set later
func configure(with modelContext: ModelContext) {
    let aggregator = StatsAggregator(container: modelContext.container)
    Task {
        await aggregator.setExerciseRepository(exerciseRepository)
        self.statsAggregator = aggregator
    }
}
```

**Issues**:
- statsAggregator is nil until configuration
- Async configuration not guaranteed
- Views must handle nil case

**Better approach**: Use @MainActor initialization with proper async setup

---

#### Issue M2: Missing Lifecycle Management
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Core/Dependencies/AppDependencies.swift`

**Problem**:
No cleanup/teardown for dependencies. In particular:
- HealthKitManager observers never cleaned up
- Background tasks not cancelled
- Database connections not closed

**Recommendation**: Implement `deinit` and proper lifecycle hooks

---

## 6. TESTING INFRASTRUCTURE

### 6.1 Critical Gap

#### Issue T1: No Test Coverage
**Findings**:
- No test files found in repository
- No test targets in Xcode project
- No TestPlans configured

**Impact**:
- High risk of regressions
- Refactoring is dangerous
- Quality gates missing

**Recommendation**:
Immediate priority to add:
1. Unit tests for models and business logic
2. Integration tests for storage layer
3. Snapshot tests for complex views
4. Performance tests for critical paths

---

## 7. CODE DUPLICATION

### 7.1 Identified Duplications

#### Issue C1: Filter Logic Duplication
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Features/ExerciseRepository/Models/ExerciseCache.swift` (lines 88-127)
- `/Users/dimitarmihaylov/dev/WRKT/Features/ExerciseRepository/Models/ExerciseCache.swift` (lines 130-150)

**Problem**:
`getPage()` and `getTotalCount()` both contain identical filtering logic:
```swift
if let muscleGroup = filters.muscleGroup, !muscleGroup.isEmpty {
    guard ex.contains(muscleGroup: muscleGroup) else { return false }
}
if filters.equipment != .all {
    guard ex.equipBucket == filters.equipment else { return false }
}
// ... repeated twice
```

**Recommendation**: Extract to private `applyFilters()` method

---

#### Issue C2: Debug Print Statements
**Files**: 325 occurrences across 31 files

**Problem**:
Excessive debug prints throughout codebase:
```swift
print("📦 Loaded \(container.workouts.count) workouts...")
print("✅ AppDependencies initialized")
print("⚠️ HealthKit not authorized")
// etc.
```

**Issues**:
- Emoji-prefixed logs are non-standard
- No log levels (warning/error/info)
- Should use os_log or Logger framework
- Makes production builds noisy

**Recommendation**: Replace with os.log or Swift.Logger with proper levels

---

## 8. ERROR HANDLING

### 8.1 Issues

#### Issue E1: Missing Error Propagation
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/WorkoutStoreV2.swift` (lines 39-75)

**Problem**:
```swift
Task {
    do {
        // Load data
        let (workouts, prIndex) = try await storage.loadWorkouts()
    } catch {
        print("❌ Failed to load from storage: \(error)")
        // Silently initializes empty state - user doesn't know data failed
        self.completedWorkouts = []
        self.prIndex = [:]
    }
}
```

**Impact**: Users don't know data load failed; potential data loss

---

#### Issue E2: Inconsistent Error Types
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Core/Persistence/WorkoutStorage.swift` (lines 12-39)

**Problem**:
Defined StorageError enum but many places use generic Error. Inconsistent error handling patterns.

---

## 9. SWIFTUI-SPECIFIC ISSUES

### 9.1 View Hierarchy Problems

#### Issue S1: Deep View Nesting
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift` (lines 62-90)

**Problem**:
Multiple levels of nesting without separation:
```swift
ZStack {
    VStack(spacing: 0) {
        modernHeader
        contentList
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // ... 10+ modifiers
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    PrimaryCTA(...)
                }
            }
    }
}
```

**Recommendation**: Extract to separate sub-views

---

#### Issue S2: Missing .id() Stability
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift` (lines 343, 390)

**Problem**:
Views use computed identifiers:
```swift
.id("overlay-\(workoutToken)")
.id("pill-\(workoutToken)")
```

While this works, it can cause unexpected animations/re-renders if workoutToken changes.

---

### 9.2 Animation Issues

#### Issue S3: Over-use of Animation
**Files**:
- `/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift` (multiple withAnimation blocks)
- `/Users/dimitarmihaylov/dev/WRKT/Features/Home/HomeView.swift` (lines 61-77)

**Problem**:
Explicit `.spring()` animations defined in multiple places:
```swift
withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
    expandedRegion = .upper
    showTiles = true
}
```

Same animation constants repeated. Difficult to maintain consistent animation feel.

**Recommendation**: Create animation constants in DesignSystem

---

## 10. CODE ORGANIZATION IMPROVEMENTS

### 10.1 Recommended Refactoring Priority

#### High Priority (Week 1-2)
1. **Add test infrastructure** - Unit tests for models and storage
2. **Fix error handling** - Proper user feedback, logging, error recovery
3. **Consolidate singletons** - Remove redundant singleton patterns
4. **Extract view state** - Move @State from views to @StateObjects/ViewModels

#### Medium Priority (Week 3-4)
5. **Implement logging** - Replace print statements with os.log
6. **Optimize search/filtering** - Implement caching for query results
7. **Add accessibility** - Implement .accessibilityLabel, .accessibilityHint
8. **Extract view components** - Break up 700-line views into smaller components

#### Lower Priority (Week 5+)
9. **Design system consistency** - Centralize animation/color constants
10. **Memory profiling** - Profile exercise loading performance
11. **Background task lifecycle** - Implement proper cleanup and teardown

---

## 11. SUMMARY TABLE

| Category | Issue Count | Severity |
|----------|------------|----------|
| Architecture | 4 | High |
| Code Quality | 3 | High |
| Performance | 5 | High |
| Data Management | 4 | Medium |
| Dependency Management | 2 | Medium |
| Testing | 1 | High |
| Duplication | 2 | Medium |
| Error Handling | 2 | High |
| SwiftUI | 3 | Medium |
| **Total** | **26** | - |

---

## 12. KEY FILES TO REFACTOR

### Critical (50+ lines of changes needed)
1. `/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/WorkoutStoreV2.swift` (718 lines)
2. `/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift` (700+ lines)
3. `/Users/dimitarmihaylov/dev/WRKT/Core/Dependencies/AppDependencies.swift` (reorganize patterns)
4. `/Users/dimitarmihaylov/dev/WRKT/Features/ExerciseRepository/Services/ExerciseRepository.swift` (dedup patterns)

### Important (20-50 lines of changes)
5. `/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift` (598 lines)
6. `/Users/dimitarmihaylov/dev/WRKT/Core/Persistence/WorkoutStorage.swift` (639 lines)
7. `/Users/dimitarmihaylov/dev/WRKT/Features/Statistics/Services/StatsAggregator.swift` (optimization needed)

### Nice to Have (5-20 lines of changes)
8. `/Users/dimitarmihaylov/dev/WRKT/DesignSystem/Theme/DS.swift` (centralize constants)
9. Various view files (add accessibility)

---

## Conclusion

The WRKT app has a solid architectural foundation with proper use of modern Swift concurrency patterns (actors, async/await). However, it would benefit from:

1. **Immediate**: Test coverage and error handling improvements
2. **Short-term**: Consolidating patterns, extracting view state
3. **Medium-term**: Performance optimization of search/filtering
4. **Long-term**: Comprehensive accessibility and refined architecture

The codebase is feature-complete and functional, but needs refinement for production-grade quality, maintainability, and user experience.

