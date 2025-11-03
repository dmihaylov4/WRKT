//
//  BodyBrowse.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//

import SwiftUI
import Combine
import OSLog

// MARK: - Root picker used by SearchView's browseState flow (kept for compatibility)
struct BodyBrowseRootView: View {
    @Binding var state: BrowseState
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                RegionCard(title: "Upper Body", systemImage: "figure.strengthtraining.traditional") {
                    state = .region(.upper)
                }
                RegionCard(title: "Lower Body", systemImage: "figure.step.training") {
                    state = .region(.lower)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
    }
}

struct RegionCard: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 28, weight: .semibold))
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            //.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .background(DS.Semantic.surface)
            .shadow(radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
    }
}

enum BodyRegion: String, CaseIterable, Hashable { case upper, lower }

// Legacy state enum (still used by SearchView and deep lists)
enum BrowseState: Hashable {
    case root
    case region(BodyRegion)
    case subregion(String)                    // e.g., "Chest"
    case deep(parent: String, child: String)  // e.g., ("Chest", "Upper Chest")
}

struct SubregionGridView: View {
    @Binding var state: BrowseState
    let region: BodyRegion
    var useNavigationLinks: Bool = false   // <–– new

    private var items: [String] { MuscleTaxonomy.subregions(for: region) }
    private let cols = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        ZStack{
            Color(DS.Semantic.surface)
                .ignoresSafeArea(edges: .all)
            ScrollView {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(items, id: \.self) { name in
                        if useNavigationLinks {
                            // Push onto the NavigationStack
                            NavigationLink(value: BrowseRoute.subregion(name)) {
                                //SubregionTile(title: name)
                            }
                        } else {
                            // Mutate local browse state (legacy flow)
                            Button { state = .subregion(name) } label: {
                                //SubregionTile(title: name)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            
            .navigationTitle(region == .upper ? "Upper Body" : "Lower Body")
        }
    }
}

/// Small reusable tile for subregions
//struct SubregionTile: View {
  //  let title: String
    //var body: some View {
      //  Text(title)
        //    .font(.headline)
          //  .frame(maxWidth: .infinity, minHeight: 80)
            //.background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    //}
//}
// MARK: - Sheet context used when starting a logging session
struct SessionSheetContext: Identifiable, Hashable {
    /// Use the entryID as the identity
    let id: UUID
    let exercise: Exercise
}

// MARK: - Flat exercise list for a subregion (legacy browseState flow)
struct MuscleExerciseListView: View {
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var store: WorkoutStoreV2
    @State private var showingSessionFor: SessionSheetContext? = nil
    @Binding var state: BrowseState
    let subregion: String

    // Optional navigation path for NavigationStack-based navigation (HomeView)
    var navigationPath: Binding<NavigationPath>? = nil

    @Environment(\.dismiss) private var dismiss

    // Add identity to force recreation when subregion changes
    var viewID: String { subregion }
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var customStore: CustomExerciseStore
    @AppStorage("equipFilter") private var equip: EquipBucket = .all
    @AppStorage("moveFilter")  private var move:  MoveBucket  = .all

    // Custom exercise creation
    @State private var showingCreateExercise = false

    // Tutorial state
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var showTutorial = false
    @State private var currentTutorialStep = 0
    @State private var equipmentFilterFrame: CGRect = .zero
    @State private var movementFilterFrame: CGRect = .zero
    @State private var exerciseListFrame: CGRect = .zero
    @State private var createButtonFrame: CGRect = .zero
    @State private var framesReady = false

    // Search state
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var debouncedSearchText = ""  // Debounced for filtering
    @FocusState private var searchFocused: Bool
    @State private var expandedSuggestions: Set<String> = []  // Track which suggestion groups are expanded

    // Debug: Set to true to visualize captured frames
    private let debugFrames = true

    private let stripeWidth: CGFloat = 3
    private let stripeGutter: CGFloat = 10

    var body: some View {
        ZStack {
            // Keep List in hierarchy even when empty to prevent keyboard dismissal
            List {
                if rows.isEmpty {
                    // Empty state as a list row to maintain view hierarchy
                    Section {
                        EmptyExercisesView(
                            title: "No exercises found",
                            message: isSearching
                                ? "No exercises match '\(searchText)' in \(subregion)."
                                : "Try loosening the equipment/movement filters or pick a different muscle.",
                            onClear: {
                                equip = .all
                                move = .all
                                // Also clear search if active
                                if isSearching {
                                    searchText = ""
                                    debouncedSearchText = ""
                                }
                            }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    // Cross-muscle search suggestions when searching and no results
                    if isSearching && !debouncedSearchText.isEmpty {
                        ForEach(crossMuscleSuggestions, id: \.muscle) { suggestion in
                            CrossMuscleSuggestionSection(
                                suggestion: suggestion,
                                isExpanded: expandedSuggestions.contains(suggestion.muscle),
                                onToggle: {
                                    if expandedSuggestions.contains(suggestion.muscle) {
                                        expandedSuggestions.remove(suggestion.muscle)
                                    } else {
                                        expandedSuggestions.insert(suggestion.muscle)
                                    }
                                },
                                onSelectExercise: { exercise in
                                    openSession(for: exercise)
                                },
                                onShowAll: {
                                    // Navigate to the suggested muscle group
                                    Haptics.light()

                                    // Capture the target muscle name
                                    let targetMuscle = suggestion.muscle

                                    // Dismiss keyboard
                                    searchFocused = false
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

                                    // Clear search state
                                    searchText = ""
                                    debouncedSearchText = ""
                                    isSearching = false

                                    // Wait for keyboard dismissal, then trigger navigation
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        if let navPath = navigationPath {
                                            // NavigationStack mode (HomeView): Replace current route
                                            // Batch both operations in a single transaction to avoid multiple updates per frame
                                            var transaction = Transaction(animation: .spring(response: 0.35, dampingFraction: 0.8))
                                            withTransaction(transaction) {
                                                navPath.wrappedValue.removeLast()
                                                navPath.wrappedValue.append(BrowseRoute.subregion(targetMuscle))
                                            }
                                        } else {
                                            // State-based navigation (SearchView)
                                            state = .subregion(targetMuscle)
                                        }
                                    }
                                }
                            )
                        }
                    }
                } else {
                    ForEach(rows, id: \.id) { ex in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(ex.name).font(.body)
                                    if ex.isCustom {
                                        CustomExerciseBadge()
                                    }
                                }
                                if let mechanic = ex.mechanic {
                                    MechanicPill(mechanic: mechanic)
                                }
                            }
                            Spacer(minLength: 8)
                            FavoriteHeartButton(exerciseID: ex.id)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { openSession(for: ex) }
                        .listRowSeparator(.hidden)
                        .listRowBackground(DS.Semantic.surface)
                        .padding(.leading, stripeWidth + stripeGutter)
                        .overlay(alignment: .leading) {
                            if let lvl = ex.difficultyLevel {
                                Rectangle()
                                    .fill(DifficultyTheme.color(for: lvl))
                                    .frame(width: stripeWidth)
                                    .allowsHitTesting(false)
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .captureFrame(in: .global) { frame in
                exerciseListFrame = frame

                checkFramesReady()
            }
            .listStyle(.plain)
            .background(DS.Semantic.surface)
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    // Search bar (slides in when active)
                    if isSearching {
                        ExerciseSearchBar(
                            text: $searchText,
                            isFocused: $searchFocused,
                            onCancel: {
                                // Dismiss keyboard and clear focus
                                searchFocused = false

                                // Clear search state immediately
                                isSearching = false
                                searchText = ""
                                debouncedSearchText = ""
                                Haptics.light()
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                        .zIndex(1) // Ensure search bar renders on top during transition
                    } else {
                        // Filters (hidden when searching)
                        FiltersBar(
                            equip: $equip,
                            move: $move,
                            coordinateSpace: .global,
                            onEquipmentFrameCaptured: { frame in
                                equipmentFilterFrame = frame
                                checkFramesReady()
                            },
                            onMovementFrameCaptured: { frame in
                                movementFilterFrame = frame
                                checkFramesReady()
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                        .zIndex(0)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSearching)
            }
            .sheet(item: $showingSessionFor) { ctx in
                ExerciseSessionView(
                    exercise: ctx.exercise,
                    initialEntryID: store.existingEntry(for: ctx.exercise.id)?.id,
                    returnToHomeOnSave: true
                )
                .environmentObject(store)
            }
            .sheet(isPresented: $showingCreateExercise) {
                CreateExerciseView(preselectedMuscle: subregion)
                    .environmentObject(customStore)
                    .environmentObject(repo)
            }
            .navigationTitle(subregion)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        // Search icon (hidden when searching)
                        if !isSearching {
                            Button {
                                // Set states immediately for instant response
                                isSearching = true
                                // Focus immediately - the keyboard animation will handle itself
                                searchFocused = true
                                Haptics.light()
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.title3)
                            }
                            .accessibilityLabel("Search exercises")
                        }

                        // Create exercise button
                        Button {
                            showingCreateExercise = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .captureFrame(in: .global) { frame in
                                    createButtonFrame = frame
                                    checkFramesReady()
                                }
                        }
                        .accessibilityLabel("Create custom exercise")
                    }
                    .tint(DS.Palette.marone)  // Apply tint to entire toolbar item group
                }
            }
            .toolbarBackground(DS.Semantic.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(DS.Semantic.surface.ignoresSafeArea())
            .onAppear {

                // Reset for testing
               // OnboardingManager.shared.hasSeenBodyBrowse = false

                // Fallback: if frames haven't loaded after 2.5 seconds, show tutorial anyway
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if !framesReady && !onboardingManager.hasSeenBodyBrowse && !showTutorial {
                        showTutorial = true
                    }
                }
            }
            .onDisappear {
                // Dismiss keyboard when navigating away to prevent RTI warnings
                if searchFocused {
                    searchFocused = false
                }
            }
            .onChange(of: searchText) { oldValue, newValue in
                // Debounce search to prevent keyboard dismissal when typing fast
                // The user sees their typed text immediately, but filtering happens after pause
                Task {
                    try? await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds
                    if searchText == newValue {
                        debouncedSearchText = newValue
                    }
                }
            }
            .onChange(of: framesReady) { _, ready in
                // Show tutorial once frames are captured
                if ready && !onboardingManager.hasSeenBodyBrowse && !showTutorial {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showTutorial = true
                    }
                }
            }

            // Tutorial overlay
            if showTutorial {
                SpotlightOverlay(
                    currentStep: tutorialSteps[currentTutorialStep],
                    currentIndex: currentTutorialStep,
                    totalSteps: tutorialSteps.count,
                    onNext: advanceTutorial,
                    onSkip: skipTutorial
                )
                .transition(.opacity)
                .zIndex(1000)
            }

           
        }
    }

    private var rows: [Exercise] {
        // 1) Primary muscle filter
        let keys = MuscleMapper.synonyms(for: subregion)
        let primary = repo.byID.values.filter { ex in
            let prim = ex.primaryMuscles.map { $0.lowercased() }
            return prim.contains { m in keys.contains { key in m.contains(key) } }
        }

        // 2) Search filter (if searching) - use smart fuzzy search with typo tolerance
        let searchFiltered = isSearching && !debouncedSearchText.isEmpty
            ? primary.filter { SmartSearch.matches(query: debouncedSearchText, in: $0.name) }
                     .sorted { SmartSearch.score(query: debouncedSearchText, in: $0.name) >
                              SmartSearch.score(query: debouncedSearchText, in: $1.name) }
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

    /// Cross-muscle search suggestions - searches other muscles when current muscle has no results
    private var crossMuscleSuggestions: [MuscleSuggestion] {
        // Only compute when searching and no results in current muscle
        guard isSearching, !debouncedSearchText.isEmpty, rows.isEmpty else { return [] }

        // Get current region
        let currentRegion: BodyRegion = MuscleTaxonomy.subregions(for: .upper).contains(subregion) ? .upper : .lower
        let oppositeRegion: BodyRegion = currentRegion == .upper ? .lower : .upper

        // Get all muscles to search (same region first, then opposite)
        let sameRegionMuscles = MuscleTaxonomy.subregions(for: currentRegion).filter { $0 != subregion }
        let oppositeRegionMuscles = MuscleTaxonomy.subregions(for: oppositeRegion)
        let allMuscles = sameRegionMuscles + oppositeRegionMuscles

        // Search each muscle and collect matches
        var suggestions: [MuscleSuggestion] = []
        for muscle in allMuscles {
            let keys = MuscleMapper.synonyms(for: muscle)
            let muscleExercises = repo.byID.values.filter { ex in
                let prim = ex.primaryMuscles.map { $0.lowercased() }
                return prim.contains { m in keys.contains { key in m.contains(key) } }
            }

            let matches = muscleExercises
                .filter { SmartSearch.matches(query: debouncedSearchText, in: $0.name) }
                .sorted { SmartSearch.score(query: debouncedSearchText, in: $0.name) >
                         SmartSearch.score(query: debouncedSearchText, in: $1.name) }

            if !matches.isEmpty {
                let region = MuscleTaxonomy.subregions(for: .upper).contains(muscle) ? "Upper Body" : "Lower Body"
                suggestions.append(MuscleSuggestion(
                    muscle: muscle,
                    region: region,
                    exercises: Array(matches.prefix(5)),  // Limit to 5 per muscle
                    totalCount: matches.count
                ))
            }
        }

        // Return top 5 muscles with most matches
        return Array(suggestions.sorted { $0.totalCount > $1.totalCount }.prefix(5))
    }

    private func openSession(for ex: Exercise) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showingSessionFor = SessionSheetContext(id: UUID(), exercise: ex)
    }

    // MARK: - Tutorial Logic

    private func checkFramesReady() {
        // Check if all frames have been captured and are valid
        let equipReady = equipmentFilterFrame != .zero && equipmentFilterFrame.width > 0
        let moveReady = movementFilterFrame != .zero && movementFilterFrame.width > 0
        let listReady = exerciseListFrame != .zero && exerciseListFrame.height > 0
        let createReady = createButtonFrame != .zero && createButtonFrame.width > 0

        if equipReady && moveReady && listReady && createReady && !framesReady {
            framesReady = true
        } else if !framesReady {
            AppLogger.debug("Still waiting for frames...", category: AppLogger.ui)
        }
    }

    private var tutorialSteps: [TutorialStep] {
        [
            TutorialStep(
                title: "Equipment Filters",
                message: "Tap any equipment type to filter exercises. Double-tap a chip to reset the filter.",
                spotlightFrame: CGRect(
                    x: equipmentFilterFrame.origin.x,
                    y: equipmentFilterFrame.origin.y,
                    width: equipmentFilterFrame.width,
                    height: equipmentFilterFrame.height + 8
                ),  // Only expand downward to avoid cutoff at top
                tooltipPosition: .bottom,
                highlightCornerRadius: 16
            ),
            TutorialStep(
                title: "Movement Filters",
                message: "Filter exercises by movement pattern. Combine with equipment filters for precise results.",
                spotlightFrame: CGRect(
                    x: movementFilterFrame.origin.x,
                    y: movementFilterFrame.origin.y,
                    width: movementFilterFrame.width,
                    height: movementFilterFrame.height + 8
                ),  // Only expand downward to avoid cutoff
                tooltipPosition: .bottom,
                highlightCornerRadius: 16
            ),
            TutorialStep(
                title: "Exercise List",
                message: "Each exercise shows Compound/Isolation type. The colored stripe indicates difficulty. Tap the heart to favorite.",
                spotlightFrame: CGRect(
                    x: exerciseListFrame.origin.x,
                    y: max(0, exerciseListFrame.origin.y - 8),  // Expand upward but not beyond screen bounds
                    width: exerciseListFrame.width,
                    height: exerciseListFrame.height + 16  // Expand both up and down
                ),
                tooltipPosition: .bottom,
                highlightCornerRadius: 20
            ),
            TutorialStep(
                title: "Create Custom Exercise",
                message: "Tap the yellow + button in the top-right corner to create your own custom exercises. They'll be marked with a 'CUSTOM' badge and appear at the top of the list.",
                spotlightFrame: nil,  // No spotlight to avoid toolbar z-index issues
                tooltipPosition: .top,
                highlightCornerRadius: 16
            )
        ]
    }

    private func advanceTutorial() {
        if currentTutorialStep < tutorialSteps.count - 1 {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentTutorialStep += 1
            }
        } else {
            completeTutorial()
        }
    }

    private func skipTutorial() {
        completeTutorial()
    }

    private func completeTutorial() {
        withAnimation(.easeOut(duration: 0.2)) {
            showTutorial = false
        }
        onboardingManager.complete(.bodyBrowse)
    }
}

// MARK: - Helpers

enum MuscleMapper {
    static func synonyms(for name: String) -> [String] {
        switch name.lowercased() {
        case "chest": return ["chest","pectoralis","pec"]
        case "back": return ["back","lat","lats","latissimus","trapezius","trap","rhomboid"]
        case "shoulders": return ["shoulder","deltoid","delts"]
        case "biceps": return ["bicep","biceps"]
        case "triceps": return ["tricep","triceps"]
        case "forearms": return ["forearm","brachioradialis","flexor","extensor"]
        case "abs": return ["abs","abdominals","rectus abdominis"]
        case "obliques": return ["oblique"]
        case "glutes": return ["glute","gluteus","butt"]
        case "quads": return ["quad","quadriceps","vastus","rectus femoris"]
        case "hamstrings": return ["hamstring","biceps femoris","semitendinosus","semimembranosus"]
        case "calves": return ["calf","gastrocnemius","soleus"]
        case "adductors": return ["adductor","adductors","inner thigh"]
        case "abductors": return ["abductor","abductors","outer thigh","glute medius","glute minimus"]
        default: return [name.lowercased()]
        }
    }
}
