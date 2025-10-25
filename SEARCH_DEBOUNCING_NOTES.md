# Search Debouncing Implementation

## Overview
Implemented 300ms search debouncing across all searchable views to prevent CPU spikes from filtering on every keystroke.

## Changes

### 1. AchievementsDexView.swift
**Problem:** Typing in search field caused CPU spikes due to filtering 1000+ exercises on every keystroke.

**Solution:**
- Added `@Published var isSearching: Bool` to track search state
- Implemented two Combine pipelines:
  1. Immediate pipeline: Sets `isSearching = true` on any search/scope change
  2. Debounced pipeline: Waits 300ms, then applies filter and sets `isSearching = false`
- Added loading UI with ProgressView and "Searching..." text
- Smooth fade transition between loading and results

**Code Pattern:**
```swift
@Published var isSearching: Bool = false

init() {
    // Immediate response to show loading
    Publishers.CombineLatest($search, $scope)
        .sink { [weak self] _, _ in
            self?.isSearching = true
        }
        .store(in: &bag)

    // Debounced filter application
    Publishers.CombineLatest($search, $scope)
        .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
        .sink { [weak self] q, scope in
            self?.applyFilter(query: q, scope: scope)
            self?.isSearching = false
        }
        .store(in: &bag)
}
```

**UI Changes:**
```swift
if vm.isSearching {
    ProgressView()
    Text("Searching...")
} else {
    LazyVGrid(...) { /* results */ }
}
```

### 2. ExerciseBrowserView.swift
**Problem:** Search triggers pagination reset on every keystroke, causing unnecessary network/cache queries.

**Solution:**
- Added `@State var debouncedSearch: String` to store debounced value
- Added `@State var searchDebounceTask: Task<Void, Never>?` for task management
- Immediate search input updates UI (searchable field)
- After 300ms delay, debounced value updates and triggers pagination reset
- Uses Task-based debouncing (simpler than Combine for simple debounce)

**Code Pattern:**
```swift
@State private var search = ""
@State private var debouncedSearch = ""
@State private var searchDebounceTask: Task<Void, Never>?

private var currentFilters: ExerciseFilters {
    ExerciseFilters(
        // ... other filters
        searchQuery: debouncedSearch  // Use debounced, not immediate
    )
}

.onChange(of: search) { _, newSearch in
    // Cancel previous debounce task
    searchDebounceTask?.cancel()

    // Start new debounce task
    searchDebounceTask = Task {
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        guard !Task.isCancelled else { return }
        debouncedSearch = newSearch
    }
}
```

### 3. AchievementsView.swift
**Problem:** Smaller dataset but still filters on every keystroke for consistency.

**Solution:**
- Same Task-based debouncing as ExerciseBrowserView
- Uses `debouncedSearch` in filtered computed property
- No loading spinner needed (dataset is small, filter is fast)

**Code Pattern:**
```swift
@State private var search = ""
@State private var debouncedSearch = ""
@State private var searchDebounceTask: Task<Void, Never>?

private var filtered: [Achievement] {
    achievements.filter { a in
        guard !debouncedSearch.isEmpty else { return true }
        return a.title.localizedCaseInsensitiveContains(debouncedSearch)
            || a.desc.localizedCaseInsensitiveContains(debouncedSearch)
    }
}
```

## Two Debouncing Approaches

### Approach 1: Combine Publishers (AchievementsDexView)
**Pros:**
- Can track loading state easily with separate pipelines
- Reactive and declarative
- Good for complex state management

**Cons:**
- Requires Combine framework
- More boilerplate code
- Slightly more complex

**Use when:**
- You need to show loading state
- You have multiple publishers to combine
- You want reactive data flow

### Approach 2: Task-based (ExerciseBrowserView, AchievementsView)
**Pros:**
- Simple and straightforward
- Uses async/await (modern Swift)
- Easy to cancel and restart
- No additional framework needed

**Cons:**
- Manual task management required
- Harder to track intermediate states

**Use when:**
- Simple debounce is all you need
- You don't need loading indicators
- You prefer async/await over Combine

## Performance Benefits

### Before Debouncing:
- **Typing "bench press" (11 characters)**: 11 filter operations
- **Each filter**: O(n) scan through 1000+ exercises
- **CPU usage**: Spikes with each keystroke
- **UI**: Can feel laggy during typing

### After Debouncing (300ms):
- **Typing "bench press"**: 1 filter operation (after 300ms pause)
- **Intermediate typing**: No CPU overhead
- **CPU usage**: Single spike after user stops typing
- **UI**: Smooth typing experience, results appear after brief delay

### Timing Choice (300ms):
- **< 200ms**: Might trigger too early while user is still typing
- **200-350ms**: Sweet spot - feels instant but saves CPU
- **> 400ms**: Feels sluggish, user notices delay

## Testing

To verify debouncing is working:

1. **Open AchievementsDexView**
2. **Type quickly**: "barbell bench press"
3. **Expected behavior**:
   - Search field updates immediately
   - "Searching..." spinner appears briefly
   - Results appear ~300ms after you stop typing
   - No lag while typing

4. **Monitor CPU** (Xcode Instruments):
   - Should see single spike after typing stops
   - No spikes during typing

## Future Improvements

1. **Adaptive debounce**: Shorter delay for small datasets, longer for large
2. **Progressive results**: Show first 10 results immediately, rest debounced
3. **Cancel in-flight searches**: If user types again before 300ms, cancel previous search
4. **Search analytics**: Track average query length to optimize debounce timing
