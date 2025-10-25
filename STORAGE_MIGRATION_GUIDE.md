# Storage System Migration Guide

## Overview

The workout storage system has been completely refactored to provide a unified, robust, and efficient storage solution. This replaces the previous dual-storage system that wrote to both Application Support and Documents directories.

## What Changed

### Before (Old System)
- **Dual Storage**: Every save wrote to BOTH locations
  - Application Support: `WRKT/completed_workouts.json`, `pr_index.json`, etc.
  - Documents: `workouts.json`, `runs.json`, etc.
- **Complex Migration Logic**: Init method had ~60 lines of merge logic
- **No Error Handling**: Silent failures, no recovery strategies
- **Scattered PR Management**: Separate file, separate load/save logic
- **No Backups**: No automatic backup system
- **No Validation**: No data integrity checks

### After (New System)
- **Single Source of Truth**: Documents/WRKT_Storage directory
- **Unified Storage**: One file contains workouts + PR index atomically
- **Proper Error Handling**: Custom error types, detailed messages
- **Automatic Backups**: Last 5 backups retained automatically
- **Data Validation**: Metadata tracking and integrity checks
- **Thread-Safe**: Actor-based storage for safe concurrent access
- **Enhanced PR Tracking**: New fields (allTimeBest, firstRecorded)

## New Architecture

### Storage Structure
```
Documents/
└── WRKT_Storage/
    ├── workouts_v2.json          # Workouts + PR index (atomic)
    ├── current_workout_v2.json   # Current in-progress workout
    ├── runs_v2.json              # Cardio/HealthKit data
    ├── .migrated                 # Migration flag
    └── Backups/
        ├── workouts_backup_2025-10-22T10-30-00.json
        ├── workouts_backup_2025-10-22T09-15-00.json
        └── ... (last 5 backups)
```

### Key Components

#### 1. WorkoutStorage Actor
- **Thread-safe**: All operations through actor isolation
- **Atomic operations**: Workouts and PR index saved together
- **Error handling**: Throws detailed errors for debugging
- **Backup system**: Automatic backups before writes
- **Migration**: One-time migration from legacy storage

#### 2. Enhanced Data Models
- **StorageMetadata**: Version, lastModified, itemCount
- **WorkoutStorageContainer**: Workouts + PR index + metadata
- **ExercisePRsV2**: Enhanced PR tracking with new fields
  - `bestPerReps`: Best weight for each rep count
  - `bestE1RM`: Best estimated 1-rep max
  - `lastWorking`: Most recent working set
  - `allTimeBest`: Best weight ever lifted (NEW)
  - `firstRecorded`: First time exercise was performed (NEW)

#### 3. WorkoutStoreV2
- Clean separation of concerns
- No disk I/O logic (delegated to WorkoutStorage)
- Simplified initialization
- All business logic preserved
- Stats integration maintained

## Migration Process

### Automatic Migration
The system performs automatic migration on first launch:

1. **Detection**: Checks for `.migrated` flag
2. **Data Collection**: Loads from ALL old locations:
   - Application Support/WRKT/
   - Documents/ (old Persistence location)
3. **Deduplication**: Merges by UUID, keeps newest
4. **PR Index**: Converts old format or recomputes from workouts
5. **Save**: Writes to new unified storage
6. **Flag**: Marks migration complete
7. **Preserve**: Old files kept for safety

### Migration Output
```
🔄 Starting migration from legacy storage...
   📦 Found 150 workouts in legacy Application Support
   📦 Found 25 PR entries in legacy storage
   📦 Found 45 runs in legacy storage
   📦 Found current workout in legacy storage
   📦 Found 148 workouts in old Persistence location
✅ Migration complete:
   Workouts: 150 (deduplicated)
   Runs: 45
   PR entries: 25
   Current workout: Yes
⚠️ Old storage files retained for safety
```

## How to Switch to New System

### Step 1: Add Files to Xcode Project
1. Add `WorkoutStorage.swift` to Persistence folder
2. Add `WorkoutStoreV2.swift` to WorkoutStore folder
3. Build to ensure no compilation errors

### Step 2: Update Dependencies
Replace all instances where WorkoutStore is created:

**Before:**
```swift
@StateObject private var workoutStore = WorkoutStore()
```

**After:**
```swift
@StateObject private var workoutStore = WorkoutStoreV2()
```

### Step 3: Update Type References
If you have explicit type annotations, update them:

**Before:**
```swift
let store: WorkoutStore
```

**After:**
```swift
let store: WorkoutStoreV2
```

### Step 4: Test Migration
1. **With Existing Data**: Launch app with existing data
   - Check console for migration messages
   - Verify all workouts loaded
   - Check PR suggestions still work
2. **Fresh Install**: Test on simulator/device without data
   - Should initialize cleanly
   - Create test workout
   - Verify persistence

### Step 5: Verify Data
Run validation to ensure data integrity:
```swift
Task {
    let isValid = try await WorkoutStorage.shared.validateStorage()
    print("Storage valid: \(isValid)")

    let stats = await WorkoutStorage.shared.getStorageStats()
    print("Stats: \(stats)")
}
```

### Step 6: Clean Up (Optional)
After verifying data is correct, clean up old files:
```swift
Task {
    try await WorkoutStorage.shared.cleanupLegacyStorage()
    print("✅ Legacy files removed")
}
```

## API Compatibility

### Maintained APIs (No Changes Required)
All public APIs of WorkoutStore are preserved in WorkoutStoreV2:

- `currentWorkout`, `completedWorkouts`, `runs` - @Published properties
- `startWorkoutIfNeeded()`, `finishCurrentWorkout()` - Workout lifecycle
- `addExerciseToCurrent()`, `updateEntrySets()` - Entry management
- `addWorkout()`, `updateWorkout()`, `deleteWorkouts()` - CRUD operations
- `addRun()`, `updateRun()`, `importRunsFromHealth()` - Run management
- `lastWorkingSet()`, `suggestedWorkingWeight()` - Weight suggestions
- `matchWithHealthKit()` - HealthKit integration

### Changed Internal Implementation
These are now handled by WorkoutStorage (transparent to callers):
- Persistence operations (async + error handling)
- PR index management (now atomic with workouts)
- Backup creation (automatic)
- Migration (one-time automatic)

## Benefits

### 1. Performance
- **50% fewer disk writes**: Single location instead of dual writes
- **Atomic operations**: No risk of partial writes
- **Background persistence**: Non-blocking saves

### 2. Reliability
- **Error handling**: Proper error types and recovery
- **Data validation**: Integrity checks on load
- **Automatic backups**: Last 5 backups always available
- **Transaction safety**: All-or-nothing writes

### 3. Maintainability
- **Single source of truth**: No merge logic needed
- **Clean separation**: Storage vs business logic
- **Type safety**: Strong typing for all storage operations
- **Testability**: Actor isolation makes testing easier

### 4. Features
- **Enhanced PR tracking**: New metrics (allTimeBest, firstRecorded)
- **Storage stats**: Query storage size, counts, dates
- **Backup management**: List and restore from backups
- **Storage validation**: Verify data integrity

## Error Handling

### Storage Errors
```swift
enum StorageError: LocalizedError {
    case fileNotFound(String)
    case encodingFailed(String, underlying: Error)
    case decodingFailed(String, underlying: Error)
    case writeFailed(String, underlying: Error)
    case migrationFailed(String)
    case validationFailed(String)
    case backupFailed(String)
}
```

### Handling Errors
```swift
Task {
    do {
        let (workouts, prIndex) = try await storage.loadWorkouts()
        // Use data
    } catch StorageError.decodingFailed(let type, let error) {
        print("Failed to decode \(type): \(error)")
        // Handle gracefully
    } catch {
        print("Storage error: \(error)")
    }
}
```

## Backup & Recovery

### Automatic Backups
- Created before every write operation
- Last 5 backups retained (configurable)
- Named with ISO8601 timestamp
- Stored in `WRKT_Storage/Backups/`

### Manual Backup Management
```swift
// List available backups
let backups = try await WorkoutStorage.shared.listBackups()
for backup in backups {
    print("Backup: \(backup.lastPathComponent)")
}

// Restore from backup
try await WorkoutStorage.shared.restoreFromBackup(at: backupURL)
```

## Statistics Integration

The new storage system maintains full integration with StatsAggregator:

- Workout completion triggers stats update
- Edit/delete operations invalidate affected weeks
- All existing statistics functionality preserved
- No changes needed to StatsAggregator code

## Testing Checklist

- [ ] Migration runs successfully with existing data
- [ ] All workouts visible after migration
- [ ] PR suggestions work correctly
- [ ] Weight suggestions accurate
- [ ] Current workout persists across app restarts
- [ ] Workout completion saves correctly
- [ ] Runs sync from HealthKit
- [ ] Statistics display correctly
- [ ] Calendar view shows workouts
- [ ] Fresh install works (no migration)
- [ ] Storage validation passes
- [ ] Backups created on writes
- [ ] Old files can be cleaned up safely

## Rollback Plan

If issues occur, you can rollback:

1. **Revert code changes**: Switch back to old WorkoutStore
2. **Data is safe**: Old files preserved during migration
3. **Re-migrate if needed**: Delete `.migrated` flag to re-run

## Advanced Features

### Storage Stats
```swift
let stats = await WorkoutStorage.shared.getStorageStats()
print("Workouts: \(stats["workoutCount"])")
print("File size: \(stats["workoutsFileSize"])")
print("Oldest: \(stats["oldestWorkout"])")
```

### Validation
```swift
let isValid = try await WorkoutStorage.shared.validateStorage()
if !isValid {
    // Handle invalid data
}
```

### Development: Wipe All Data
```swift
#if DEBUG
try await WorkoutStorage.shared.wipeAllData()
#endif
```

## Support

If you encounter issues:

1. **Check Console**: Look for migration and storage log messages
2. **Validate Storage**: Run `validateStorage()` to check integrity
3. **Check Backups**: List backups to verify they exist
4. **Review Errors**: Storage errors include detailed context

## Next Steps

1. ✅ Add files to Xcode project
2. ✅ Update WorkoutStore references to WorkoutStoreV2
3. ✅ Test migration with existing data
4. ✅ Verify all features work
5. ✅ Run validation
6. ⚠️ Clean up legacy storage (after verification)
7. 🗑️ Remove old WorkoutStore.swift (optional, keep for reference)

## Summary

This migration provides a modern, robust storage system that:
- Eliminates complexity (dual writes, merge logic)
- Improves reliability (error handling, backups, validation)
- Enhances performance (single write path, atomic operations)
- Maintains compatibility (same public API)
- Adds new features (enhanced PR tracking, backup management)

The migration is automatic and safe, with old data preserved as a fallback.
