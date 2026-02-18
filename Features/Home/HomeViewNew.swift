//
//  HomeViewNew.swift
//  WRKT
//
//  Redesigned Home screen with focused hub structure
//  TODO: Rename to HomeViewNew.swift after testing
//

import SwiftUI
import SwiftData
import Supabase

struct HomeViewNew: View {
    @EnvironmentObject var store: WorkoutStoreV2
    @State private var path = NavigationPath()

    @Query private var goals: [WeeklyGoal]

    @Environment(\.modelContext) private var context
    @Environment(\.dependencies) private var deps

    // ViewModel for data fetching and card management
    @State private var viewModel: HomeViewModel?

    // Observe rest timer to trigger hero updates
    @ObservedObject private var restTimerManager = RestTimerManager.shared

    // Split animation state (preserved for ExpandedRegionPanel)
    @Namespace private var regionNS
    @State private var expandedRegion: BodyRegion? = nil
    @State private var showTiles = false

    // Workout selector sheet
    @State private var showWorkoutSelector = false

    // Sheet states for card taps
    @State private var selectedWorkoutForDetail: CompletedWorkout? = nil
    @State private var selectedCardioForDetail: Run? = nil


    // Communicate browse state to app level to hide LiveWorkoutGrabTab
    @AppStorage("is_browsing_exercises") private var isBrowsingExercises = false

    private var hasActiveWorkout: Bool {
        guard let current = store.currentWorkout else { return false }
        return !current.entries.isEmpty
    }

    private func collapsePanel(animated: Bool = true) {
        let anim = Animation.spring(response: 0.45, dampingFraction: 0.85)
        if animated {
            withAnimation(anim) { showTiles = false; expandedRegion = nil }
        } else {
            showTiles = false; expandedRegion = nil
        }
    }

    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Header (compact)
            if let vm = viewModel {
                HomeHeaderView(
                    greeting: vm.getGreeting(userName: vm.getUserDisplayName()),
                    currentStreak: vm.getCurrentStreak()
                )
                .padding(.top, 8)
            }

            // Hero Button (28% screen - THE MAIN COMPONENT)
            if let vm = viewModel {
                HeroStartWorkoutButton(
                    content: vm.getHeroButtonContent(),
                    onTap: {
                        if hasActiveWorkout {
                            // When workout is active, onTap means "Add Exercise"
                            // TODO: Open exercise browser or show quick add
                            showWorkoutSelector = true
                        } else {
                            // No workout - show workout type selector
                            showWorkoutSelector = true
                        }
                    },
                    showLiveWorkoutSheet: {
                        NotificationCenter.default.post(name: .openLiveOverlay, object: nil)
                    },
                    skipRest: {
                        RestTimerManager.shared.skipTimer()
                    },
                    addExercise: {
                        // Open workout type selector to add exercises
                        showWorkoutSelector = true
                    },
                    extendRest: {
                        RestTimerManager.shared.adjustTime(by: 15)
                    }
                )
                .padding(.top, 1)
            }

            // Unified Weekly Stats Card (MOVED UP - priority visibility)
            if let vm = viewModel, let stats = vm.getUnifiedWeeklyStatsWithStreak(context: context) {
                UnifiedWeeklyStatsCard(
                    strengthCompleted: stats.strengthCompleted,
                    strengthTarget: stats.strengthTarget,
                    cardioMinutes: stats.cardioMinutes,
                    cardioTarget: stats.cardioTarget,
                    daysRemaining: stats.daysRemaining,
                    currentStreak: stats.currentStreak,
                    nextMilestone: stats.nextMilestone,
                    milestoneProgress: stats.milestoneProgress,
                    urgencyLevel: stats.urgencyLevel,
                    urgencyMessage: stats.urgencyMessage
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // Smart Carousel (conditional - only if cards exist, max 3 cards)
            if let vm = viewModel, !vm.carouselCards.isEmpty {
                SmartCardCarousel(
                    cards: vm.carouselCards,
                    onCardTap: { card in handleCardTap(card) },
                    onWorkoutTap: { workout in
                        selectedWorkoutForDetail = workout
                    },
                    onCardioTap: { cardio in
                        selectedCardioForDetail = cardio
                    }
                )
                .padding(.top, 8)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var expandedPanelView: some View {
        Group {
            if let region = expandedRegion {
                
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Haptics.light()
                        collapsePanel()
                    }
                    .transition(.opacity)

             
                VStack {
                    Spacer()
                    ExpandedRegionPanel(
                        region: region,
                        namespace: regionNS,
                        matchedID: region == .upper ? "region-upper" : "region-lower",
                        showTiles: showTiles,
                        onCollapse: { collapsePanel() },
                        onSelectSubregion: { name in
                            path.append(BrowseRoute.subregion(name))
                        }
                    )
                    .padding(.horizontal, 16)
                    Spacer()
                }
                .allowsHitTesting(true)
                .transition(.opacity.combined(with: .scale))
            }
        }
    }

    private var navigationContent: some View {
        ZStack(alignment: .top) {
            // MAIN CONTENT: Focused hub layout
            if expandedRegion == nil {
                mainContentView
                    .transition(.opacity.combined(with: .scale))
            }

            // EXPANDED: ExpandedRegionPanel (preserved for compatibility)
            expandedPanelView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 56)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 90)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: BrowseRoute.self) { route in
            navigationDestination(for: route)
        }
        .sheet(isPresented: $showWorkoutSelector) {
            QuickWorkoutTypeSelector(
                date: .now,
                title: hasActiveWorkout ? "Add Exercise" : "Start Workout"
            ) { workoutType in
                // Close sheet first
                showWorkoutSelector = false

                // Small delay to let sheet animation complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // Handle workout type selection
                    switch workoutType {
                    case .upperBody:
                        // Navigate directly to all upper body exercises with filters
                        path.append(BrowseRoute.regionAll(.upper))
                    case .lowerBody:
                        // Navigate directly to all lower body exercises with filters
                        path.append(BrowseRoute.regionAll(.lower))
                    case .custom:
                        // Navigate to all exercises (no muscle group filtering)
                        path.append(BrowseRoute.allExercises)
                    }
                }
            }
        }
        .sheet(item: $selectedWorkoutForDetail) { workout in
            WorkoutDetailView(workout: workout)
                .environmentObject(store)
                .environmentObject(ExerciseRepository.shared)
        }
        .sheet(item: $selectedCardioForDetail) { run in
            CardioDetailView(run: run)
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetHomeToRoot)) { _ in
            resetToRoot()
        }
        .background(DS.Semantic.surface)
    }

    @ViewBuilder
    private func navigationDestination(for route: BrowseRoute) -> some View {
        switch route {
        case .region(let r):
            SubregionGridView(state: .constant(.region(r)), region: r, useNavigationLinks: true)
        case .regionAll(let region):
            // Show all exercises for a specific region (upper/lower body)
            MuscleExerciseListView(
                state: .constant(.region(region)),
                subregion: nil,
                muscleFilter: region == .upper ? .upperBody : .lowerBody,
                navigationPath: $path
            )
        case .allExercises:
            // Show all exercises (no region filter)
            MuscleExerciseListView(
                state: .constant(.root),
                subregion: nil,
                muscleFilter: .fullBody,
                navigationPath: $path
            )
        case .subregion(let name):
            MuscleExerciseListView(
                state: .constant(.subregion(name)),
                subregion: name,
                navigationPath: $path
            )
        case .deep(let parent, let child):
            SubregionDetailScreen(subregion: parent, preselectedDeep: child)
        }
    }

    private func resetToRoot() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            path = NavigationPath()
            expandedRegion = nil
            showTiles = false
        }
    }

    // MARK: - Navigation Stack View

    private var navigationStackView: some View {
        NavigationStack(path: $path) {
            navigationContent
        }
    }

    private func handleCardTap(_ card: HomeCardType) {
        switch card {
        case .lastWorkout(let workout):
            // Show workout detail sheet
            selectedWorkoutForDetail = workout

        case .friendActivity:
            // No action for now - card is informational
            // Future: Could navigate to Social tab or show friend list
            break

        case .lastCardio(let run):
            // Show cardio detail sheet
            selectedCardioForDetail = run

        case .recentActivity:
            // Individual sections have their own tap handlers
            // No action needed here - handled by onWorkoutTap/onCardioTap callbacks
            break

        case .recommendation(let recommendation):
            // Determine target region from recommendation text
            let reason = recommendation.reason.lowercased()
            if reason.contains("leg") || reason.contains("lower body") {
                // Navigate to lower body exercises
                path.append(BrowseRoute.regionAll(.lower))
            } else if reason.contains("upper body") {
                // Navigate to upper body exercises
                path.append(BrowseRoute.regionAll(.upper))
            } else {
                // Default: show workout selector
                showWorkoutSelector = true
            }

        case .weeklyProgress, .activeCompetition, .recentPR, .comparativeStats:
            // These cards don't have specific actions yet
            break
        }
    }

    var body: some View {
        navigationStackView
            .onReceive(NotificationCenter.default.publisher(for: .openHomeRoot)) { _ in
            expandedRegion = nil
            showTiles = false
            path = .init()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabSelectionChanged)) { _ in
            collapsePanel()
        }
        .onDisappear {
            collapsePanel(animated: false)
        }
        .onChange(of: expandedRegion) { _, newValue in
            isBrowsingExercises = (newValue != nil) || !path.isEmpty
        }
        .onChange(of: path) { _, newValue in
            isBrowsingExercises = (expandedRegion != nil) || !newValue.isEmpty
        }
        .onAppear {
            // NOTE: Don't validate streak here - validation should only happen on app cold start
            // to avoid recalculating and potentially corrupting the correct stored value.

            // Initialize ViewModel if needed
            if viewModel == nil {
                let vm = HomeViewModel(
                    workoutStore: store,
                    plannerStore: PlannerStore.shared,
                    weeklyGoal: goals.first
                )
                // Inject social dependencies
                vm.postRepository = deps.postRepository
                vm.authService = deps.authService
                viewModel = vm
            }

            // Refresh data (async)
            Task {
                await viewModel?.refresh()
            }

            // Initialize browsing state
            isBrowsingExercises = (expandedRegion != nil) || !path.isEmpty
        }
        .onChange(of: goals.first) { _, newGoal in
            // Update ViewModel when goal changes
            viewModel?.setWeeklyGoal(newGoal)
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeTabReselected)) { _ in
            // Reset to root state when Home tab is re-tapped
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                path = NavigationPath()
                expandedRegion = nil
                showTiles = false
            }
        }
    }
}

// MARK: - Preserved Components (ExpandedRegionPanel, SubregionTile)
// These are kept to maintain compatibility with the animation system

private struct ExpandedRegionPanel: View {
    let region: BodyRegion
    let namespace: Namespace.ID
    let matchedID: String
    let showTiles: Bool
    let onCollapse: () -> Void
    let onSelectSubregion: (String) -> Void

    private var title: String {
        region == .upper ? "Upper Body" : "Lower Body"
    }
    private var accent: Color {
        DS.Theme.accent
    }
    private var items: [String] {
        MuscleTaxonomy.subregions(for: region)
    }

    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: region == .upper ? "figure.strengthtraining.traditional" : "figure.step.training")
                    .font(.headline)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    Haptics.soft()
                    onCollapse()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DS.Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
            .padding(.horizontal, 14)

            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(items, id: \.self) { name in
                    Button {
                        Haptics.light()
                        onSelectSubregion(name)
                    } label: {
                        SubregionTile(title: name, accent: accent)
                    }
                    .buttonStyle(PressTileStyle())
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .opacity(showTiles ? 1 : 0)
            .scaleEffect(showTiles ? 1 : 0.98, anchor: .top)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showTiles)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DS.Semantic.surface)
                .matchedGeometryEffect(id: matchedID, in: namespace)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

private struct SubregionTile: View {
    let title: String
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .font(.footnote)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(DS.Semantic.fillSubtle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
        .foregroundStyle(DS.Semantic.textPrimary)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HomeViewNew()
            .environmentObject(WorkoutStoreV2(repo: .shared))
    }
}
