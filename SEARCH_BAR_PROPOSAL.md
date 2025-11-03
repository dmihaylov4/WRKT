# BodyBrowse Search Bar - Implementation Proposal

## Problem
- Need search functionality without sacrificing vertical space
- Current filters (EQUIPMENT + MOVEMENT) already take significant space
- Want to preserve quick-tap filter workflow after completing sets

## Recommended Solution: Collapsible Search

### Implementation Plan

#### 1. Add State Variables
```swift
@State private var isSearching = false
@State private var searchText = ""
```

#### 2. Add Search Bar Component
```swift
private struct SearchBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search exercises...", text: $text)
                    .focused($isFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            Button("Cancel") {
                onCancel()
            }
            .foregroundStyle(DS.Palette.marone)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DS.Semantic.surface)
    }
}
```

#### 3. Update Toolbar
```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        if !isSearching {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isSearching = true
                    searchFocused = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
            }
        }
    }
}
```

#### 4. Update safeAreaInset
```swift
.safeAreaInset(edge: .top) {
    VStack(spacing: 0) {
        // Search bar (slides in when active)
        if isSearching {
            SearchBar(
                text: $searchText,
                isFocused: $searchFocused,
                onCancel: {
                    withAnimation(.spring(response: 0.3)) {
                        isSearching = false
                        searchText = ""
                        searchFocused = false
                    }
                }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        } else {
            // Filters (hidden when searching)
            FiltersBar(equip: $equip, move: $move)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    .animation(.spring(response: 0.3), value: isSearching)
}
```

#### 5. Update Filter Logic
```swift
private var rows: [Exercise] {
    // 1) Primary muscle filter
    let keys = MuscleMapper.synonyms(for: subregion)
    let primary = repo.byID.values.filter { ex in
        let prim = ex.primaryMuscles.map { $0.lowercased() }
        return prim.contains { m in keys.contains { key in m.contains(key) } }
    }

    // 2) Search filter (if searching)
    let searchFiltered = isSearching && !searchText.isEmpty
        ? primary.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        : primary

    // 3) Equipment/Movement filters (only when not searching)
    let byEquip = (isSearching || equip == .all)
        ? searchFiltered
        : searchFiltered.filter { $0.equipBucket == equip }

    let byMove = (isSearching || move == .all)
        ? byEquip
        : byEquip.filter { $0.moveBucket == move }

    // 4) Sort
    let base = byMove.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    return favoritesFirst(base, favIDs: favs.ids)
}
```

---

## Alternative Options

### Option 2: Persistent Mini Search
- Thin search bar always visible above filters
- **Pros:** Always accessible
- **Cons:** Takes permanent vertical space (~44pt)

### Option 3: Tab Toggle (Browse/Search)
- Segmented control to switch modes
- **Pros:** Clean separation
- **Cons:** Requires extra tap to access search

### Option 4: Search as Filter Chip
- "Search" chip in equipment row
- **Pros:** Minimal UI change
- **Cons:** Non-standard pattern, confusing UX

---

## Recommendation

**Implement Option 1 (Collapsible Search)** because:
1. ✅ Zero space impact when not needed
2. ✅ Preserves muscle-based browsing workflow
3. ✅ Familiar iOS pattern
4. ✅ Smooth animations provide context
5. ✅ Can be dismissed quickly with "Cancel"

### User Flow
1. **After a set:** User navigates to BodyBrowse → Taps muscle group → Sees filters → Taps equipment/movement chips → Picks exercise (current workflow preserved!)
2. **When searching:** User taps 🔍 → Search slides in, filters hide → Types → Sees filtered results → Taps Cancel → Back to filters

---

## Implementation Effort
- **Low:** ~1 hour
- **Files to modify:** 1 (BodyBrowse.swift)
- **Lines added:** ~80
- **Risk:** Low (additive feature, doesn't break existing flow)
