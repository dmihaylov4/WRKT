# WRKT Test Infrastructure

This directory contains the test suite for the WRKT workout tracking application.

## 📁 Directory Structure

```
WRKTTests/
├── CoreTests/                      # Tests for Core functionality
│   ├── Models/                     # Model tests (WorkoutEntry, Exercise, etc.)
│   ├── Persistence/                # Storage and persistence tests
│   └── Utilities/                  # Utility function tests
├── FeaturesTests/                  # Tests for Features
│   ├── ExerciseRepository/         # Exercise repository and cache tests
│   ├── WorkoutSession/             # Workout session logic tests
│   └── Health/                     # HealthKit integration tests
└── TestHelpers/                    # Shared test infrastructure
    ├── Extensions/                 # Test-specific extensions
    ├── Mocks/                      # Mock implementations
    └── Stubs/                      # Stub data and fixtures
```

## 🧪 Test Infrastructure

### Base Test Case

**WRKTTestCase** - Base class for all tests providing:
- Async test helpers (`assertAsyncNoThrow`, `assertAsyncThrows`)
- Date creation and comparison utilities
- Temporary directory management
- Codable conformance testing
- XCTest best practices setup

### Test Extensions

**TestExtensions.swift** - Equatable conformance for model types:
- `SetInput`
- `WorkoutEntry`
- `CurrentWorkout`
- `Exercise`

These extensions enable easy comparison in tests.

### Test Fixtures

**TestFixtures** - Pre-configured test data:
- Sample exercises (bench press, squat, deadlift)
- Sample sets (warmup, working, backoff)
- Workout entries and completed workouts
- PR data structures

Usage:
```swift
let workout = TestFixtures.makeCurrentWorkout()
let exercise = TestFixtures.benchPress
```

### Mock Implementations

**MockFileSystem** - Mock file system for testing storage operations without touching disk:
```swift
let mockFS = MockFileSystem()
mockFS.write(data, to: "/test/path")
let loaded = mockFS.read(from: "/test/path")
```

## 📝 Test Files

### Core/Models Tests

1. **WorkoutEntryTests.swift** - Tests for workout entries and sets
   - SetTag functionality (labels, cycling)
   - SetInput creation and defaults
   - Legacy data decoding
   - Codable conformance

2. **CurrentWorkoutTests.swift** - Tests for in-progress workouts
   - Workout creation and state
   - Planned workout linking
   - Codable conformance

3. **CompletedWorkoutTests.swift** - Tests for completed workouts
   - Workout completion flow
   - HealthKit data integration
   - Heart rate samples
   - Legacy data migration

4. **ExerciseDefinitionTests.swift** - Tests for exercise models
   - String extensions (trimming, nil handling)
   - DifficultyLevel enum
   - Exercise DTO mapping
   - Codable conformance

### Core/Persistence Tests

**WorkoutStorageTests.swift** - Tests for storage layer
- Storage metadata and containers
- PR data structures
- Current workout lifecycle
- Error handling
- Storage validation

**Note**: Current implementation tests against singleton instance. For better isolation, consider refactoring to use protocol-based dependency injection.

### Features Tests

**ExerciseRepositoryTests.swift** - Tests for exercise repository
- Repository initialization
- Exercise lookup by ID
- Pagination state management
- Filter application
- Thread safety (MainActor)

**Note**: Tests use shared singleton. Consider protocol-based architecture for better testability.

## 🚀 Running Tests

### From Xcode
1. Open `WRKT.xcodeproj`
2. Select the WRKTTests scheme
3. Press `Cmd + U` to run all tests
4. Or use Test Navigator (`Cmd + 6`) to run individual tests

### From Command Line
```bash
xcodebuild test \
  -project WRKT.xcodeproj \
  -scheme WRKTTests \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Using fastlane (if configured)
```bash
fastlane test
```

## ✅ Test Coverage Goals

Current coverage areas:
- ✅ Core models (WorkoutEntry, CurrentWorkout, CompletedWorkout, Exercise)
- ✅ Persistence layer (WorkoutStorage, StorageError)
- ✅ Exercise repository basic functionality
- ⚠️ ExerciseCache (needs more coverage)
- ❌ UI components (not yet covered)
- ❌ ViewModels (not yet extracted/tested)
- ❌ HealthKit integration (needs mocking)
- ❌ Workout session logic (complex state management)

## 🎯 Best Practices

### Writing New Tests

1. **Inherit from WRKTTestCase**
   ```swift
   final class MyFeatureTests: WRKTTestCase {
       // tests here
   }
   ```

2. **Use TestFixtures for sample data**
   ```swift
   let workout = TestFixtures.makeCurrentWorkout()
   ```

3. **Test async code properly**
   ```swift
   func testAsyncOperation() async {
       let result = await assertAsyncNoThrow(try await myAsyncFunc())
       XCTAssertNotNil(result)
   }
   ```

4. **Use descriptive test names**
   ```swift
   func testWorkoutSavesCorrectlyWithMultipleEntries() { }
   func testExerciseLookupReturnsNilForInvalidID() { }
   ```

5. **Test edge cases**
   - Empty collections
   - Nil values
   - Legacy data formats
   - Error conditions

### Test Organization

- One test file per source file
- Group related tests with `// MARK:` comments
- Keep tests focused and single-purpose
- Use setUp/tearDown for common initialization

### Async Testing

For MainActor-isolated types:
```swift
@MainActor
final class MyTests: WRKTTestCase {
    func testMainActorCode() async {
        // test code here
    }
}
```

## 🔧 Future Improvements

### Architecture Refactoring
1. **Dependency Injection**
   - Create protocol-based interfaces for storage, repository
   - Inject dependencies instead of using singletons
   - Enable true unit testing with mocks

2. **Extract ViewModels**
   - Separate view logic from SwiftUI views
   - Make ViewModels testable
   - Add comprehensive ViewModel tests

3. **Mock Infrastructure**
   - Create proper mock implementations for all services
   - Add test-specific configurations
   - Implement in-memory storage for tests

### Test Coverage
1. Add tests for:
   - ExerciseCache filtering and pagination
   - Workout session state management
   - HealthKit integration (with mocks)
   - PR calculation logic
   - Migration scenarios

2. Add UI tests for:
   - Critical user flows
   - Navigation
   - Form validation

### CI/CD Integration
1. Set up automated test runs on PR
2. Add test coverage reporting
3. Add performance testing
4. Add snapshot testing for UI components

## 📚 Resources

- [XCTest Documentation](https://developer.apple.com/documentation/xctest)
- [Testing Swift with XCTest](https://developer.apple.com/documentation/xctest/testing_swift_code)
- [Swift Testing Best Practices](https://developer.apple.com/videos/play/wwdc2023/10175/)

## 🤝 Contributing

When adding new features:
1. Write tests first (TDD) or alongside implementation
2. Ensure all tests pass before submitting PR
3. Add test coverage for edge cases
4. Update this README if adding new test infrastructure

---

**Last Updated**: October 26, 2025
**Test Count**: 40+ tests across 7 test files
**Coverage**: Core models and basic persistence
