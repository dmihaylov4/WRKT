import SwiftUI
import SwiftData
import HealthKit
import UserNotifications
import OSLog

// MARK: - Shell types & animation
private enum AppTab: Int { case home = 0, calendar = 1, runs = 2, profile = 3 }
private enum ShellAnim { static let spring = Animation.spring(response: 0.42, dampingFraction: 0.85) }
private enum GrabTabMetrics { static let height: CGFloat = 55; static let bottomMargin: CGFloat = 57 }

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext

    // Centralized dependencies - single source of truth
    @StateObject private var dependencies = AppDependencies.shared

    // Direct references to ensure proper observation
    private var repo: ExerciseRepository { dependencies.exerciseRepository }
    private var healthKit: HealthKitManager { dependencies.healthKitManager }
    private var favs: FavoritesStore { dependencies.favoritesStore }

    // Observed object to ensure state changes are detected
    @ObservedObject private var store: WorkoutStoreV2 = AppDependencies.shared.workoutStore

    // Shell UI state
    @State private var selectedTab: AppTab = .home {
        didSet {
            AppLogger.debug("selectedTab changed: \(oldValue) → \(selectedTab)", category: AppLogger.ui)
        }
    }
    @State private var grabCollapsed = false
    @State private var showLiveOverlay = false
    @State private var showContent = false
    @AppStorage("is_browsing_exercises") private var isBrowsingExercises = false

    // Onboarding state
    @AppStorage("has_completed_onboarding") private var hasCompletedOnboarding = false
    @State private var onboardingStep: OnboardingStep = .notStarted

    enum OnboardingStep {
        case notStarted
        case carousel
        case healthKit
        case notifications
        case completed
    }

    @Query private var goals: [WeeklyGoal]
    @State private var showGoalSetupSheet = false {
        didSet {
            AppLogger.debug("showGoalSetupSheet changed: \(oldValue) → \(showGoalSetupSheet)", category: AppLogger.ui)
        }
    }

    private var needsGoalSetup: Bool {
        guard let g = goals.first else { return true }
        return !g.isSet
    }

    @Namespace private var liveNS
    @Environment(\.scenePhase) private var scenePhase

    // Convenience
    private var current: CurrentWorkout? { store.currentWorkout }
    private var hasActiveWorkout: Bool { (current?.entries.isEmpty == false) }

    /// Changes whenever a workout is created/ended OR entries change.
    private var workoutToken: String {
        guard let c = store.currentWorkout else { return "none" }
        return "\(c.id.uuidString)-\(c.entries.count)"
    }

    /// Centralized "should the pill reserve space" logic
    private var pillShouldReserveSpace: Bool {
        hasActiveWorkout && !showLiveOverlay && !grabCollapsed && !isBrowsingExercises
    }

    // Statistics tracking
    @State private var repoIsBootstrapped = false
    @State private var workoutsLoaded = false

    // Convenience accessor for stats
    private var stats: StatsAggregator? { dependencies.statsAggregator }

    var body: some View {
        ZStack {
            // MAIN TABS
            TabView(selection: $selectedTab) {
                // HOME
                HomeView()
                    .background(DS.Semantic.surface.ignoresSafeArea())
                    .tabItem { Label("Home", systemImage: "dumbbell.fill") }
                    .tag(AppTab.home)

                // CALENDAR
                NavigationStack {
                    CalendarMonthView()
                        .background(DS.Semantic.surface)
                        .scrollContentBackground(.hidden)
                }
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)

                // CARDIO
                NavigationStack {
                    CardioView()
                        .background(DS.Semantic.surface)
                        .scrollContentBackground(.hidden)
                }
                .tabItem { Label("Cardio", systemImage: "heart.fill") }
                .tag(AppTab.runs)

                // PROFILE
                NavigationStack {
                    ProfileView()
                        .background(DS.Semantic.surface)
                        .scrollContentBackground(.hidden)
                        .navigationTitle("Profile")
                        .navigationBarTitleDisplayMode(.inline)
                        .onAppear {
                            AppLogger.debug("Profile NavigationStack appeared - selectedTab: \(selectedTab), needsGoalSetup: \(needsGoalSetup)", category: AppLogger.ui)
                        }
                        .onDisappear {
                            AppLogger.debug("Profile NavigationStack disappeared - selectedTab: \(selectedTab)", category: AppLogger.ui)
                        }
                }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
            }
           // .sensoryFeedback(.selection, trigger: selectedTab)
            .tint(DS.Palette.marone)

            .overlay(
                TabBarReselectionDetector(
                    selectedTab: $selectedTab,
                    onReselect: { index in
                        AppLogger.debug("Tab reselected: \(index)", category: AppLogger.ui)
                        if index == AppTab.home.rawValue {
                            AppLogger.debug("Posting homeTabReselected notification", category: AppLogger.ui)
                            NotificationCenter.default.post(name: .homeTabReselected, object: nil)
                        } else if index == AppTab.calendar.rawValue {
                            AppLogger.debug("Posting calendarTabReselected notification", category: AppLogger.ui)
                            NotificationCenter.default.post(name: .calendarTabReselected, object: nil)
                        } else if index == AppTab.runs.rawValue {
                            AppLogger.debug("Posting cardioTabReselected notification", category: AppLogger.ui)
                            NotificationCenter.default.post(name: .cardioTabReselected, object: nil)
                        }
                    }
                )
                .allowsHitTesting(false)
            )


            // Close overlay if backgrounded & track clean shutdown
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // Close live overlay when app backgrounds
                if newPhase != .active, showLiveOverlay {
                    withAnimation(ShellAnim.spring) { showLiveOverlay = false; showContent = false }
                }

                // Track app lifecycle for force quit detection
                if newPhase == .background {
                    // Only mark clean shutdown if there's NO active workout
                    // This prevents the app switcher force quit from preserving the workout
                    if !hasActiveWorkout {
                        UserDefaults.standard.didExitCleanly = true
                        AppLogger.debug("App backgrounded (no active workout) - marked clean shutdown", category: AppLogger.app)
                    } else {
                        // Keep didExitCleanly = false so force quit will discard the workout
                        AppLogger.debug("App backgrounded (WITH active workout) - keeping didExitCleanly = false", category: AppLogger.app)
                    }
                } else if newPhase == .active {
                    // App became active - mark as running only if there's an active workout
                    if hasActiveWorkout {
                        UserDefaults.standard.didExitCleanly = false
                        AppLogger.debug("App became active (with active workout) - marked as running", category: AppLogger.app)
                    }
                }
            }

            // Sync shell state with tab selection
            .onChange(of: selectedTab) { newTab in
                AppLogger.debug("Tab changed to: \(newTab) (rawValue: \(newTab.rawValue)) - needsGoalSetup: \(needsGoalSetup), showGoalSetupSheet: \(showGoalSetupSheet)", category: AppLogger.ui)

                NotificationCenter.default.post(name: .tabSelectionChanged, object: nil)
                // Also post tabDidChange to dismiss detail views
                NotificationCenter.default.post(name: .tabDidChange, object: nil)

                // Keep your current behavior (pill shows only on Home).
                if newTab != .home {
                    grabCollapsed = true
                } else if hasActiveWorkout {
                    grabCollapsed = false
                }

                if showLiveOverlay {
                    withAnimation(ShellAnim.spring) { showContent = false; showLiveOverlay = false }
                }

                // Check if weekly goal setup is needed when navigating to Home or Profile
                if needsGoalSetup && (newTab == .home || newTab == .profile) {
                    AppLogger.debug("Showing goal setup sheet", category: AppLogger.ui)
                    showGoalSetupSheet = true
                }
            }
            // NEW
            .onAppear {
                // Check onboarding on first launch
                if !hasCompletedOnboarding {
                    onboardingStep = .carousel
                } else if needsGoalSetup && (selectedTab == .home || selectedTab == .profile) {
                    // present goal setup if onboarding is done but goal not set
                    showGoalSetupSheet = true
                }
            }

            // Onboarding carousel (step 1)
            .fullScreenCover(isPresented: Binding(
                get: { onboardingStep == .carousel },
                set: { _ in }  // Don't reset on dismiss - callbacks handle navigation
            )) {
                OnboardingCarouselView {
                    onboardingStep = .healthKit
                }
            }

            // HealthKit permission (step 2)
            .fullScreenCover(isPresented: Binding(
                get: { onboardingStep == .healthKit },
                set: { _ in }  // Don't reset on dismiss - callbacks handle navigation
            )) {
                HealthAuthSheet(onDismiss: {
                    onboardingStep = .notifications
                })
                .environmentObject(healthKit)
            }

            // Notification permission (step 3)
            .fullScreenCover(isPresented: Binding(
                get: { onboardingStep == .notifications },
                set: { _ in }  // Don't reset on dismiss - callbacks handle navigation
            )) {
                NotificationPermissionView {
                    completeOnboarding()
                }
            }

            .sheet(isPresented: $showGoalSetupSheet) {
                NavigationStack {
                    WeeklyGoalSetupView(goal: goals.first)
                        .interactiveDismissDisabled() // keep your requirement
                        .onAppear {
                            AppLogger.debug("Goal setup sheet appeared", category: AppLogger.ui)
                        }
                        .onDisappear {
                            AppLogger.debug("Goal setup sheet dismissed", category: AppLogger.ui)
                        }
                }
            }

            //

            // External overlay close
            .onReceive(NotificationCenter.default.publisher(for: .dismissLiveOverlay)) { _ in
                withAnimation(ShellAnim.spring) { showLiveOverlay = false; showContent = false }
            }

            // Global "return to Home"
            .onReceive(NotificationCenter.default.publisher(for: .resetHomeToRoot)) { note in
                let reason = (note.userInfo?["reason"] as? String) ?? (note.object as? String)
                // Only honor intentional, user-driven resets.
                guard reason == "user_intent" else {
                    AppLogger.debug("Ignoring resetHomeToRoot (reason=\(reason ?? "nil"))", category: AppLogger.ui)
                    return
                }

                AppLogger.info("resetHomeToRoot (reason=\(reason ?? "unknown")) - forcing tab to Home (current tab: \(selectedTab))", category: AppLogger.ui)
                NotificationCenter.default.post(name: .openHomeRoot, object: nil)
                selectedTab = .home
            }

            // Reward summary → win screen queue
            .onReceive(NotificationCenter.default.publisher(for: .rewardsDidSummarize)) { note in
                guard let s = note.object as? RewardSummary else { return }
                WinScreenCoordinator.shared.enqueue(s)
            }

            .overlay(WinScreenOverlay())

            // Global rest timer completion toast
            .overlay(alignment: .top) {
                RestTimerCompletionToast()
                    .zIndex(999)
            }

            // Global undo toast for destructive actions
            .overlay {
                UndoToastOverlay()
            }

        } // ZStack

        // Mark workouts as loaded when they're ready
        .onChange(of: store.completedWorkouts.count) { newCount in
            if newCount > 0 && !workoutsLoaded {
                workoutsLoaded = true
            }
        }

        // Trigger stats aggregation when BOTH repo and workouts are ready (initial load)
        .onChange(of: repoIsBootstrapped && workoutsLoaded) { bothReady in
            guard bothReady, let agg = stats else { return }
            guard store.completedWorkouts.count > 0 else { return }

            Task {
                if let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now) {
                    AppLogger.info("Repo and workouts ready, triggering stats aggregation", category: AppLogger.performance)
                    await agg.reindex(all: store.completedWorkouts, cutoff: cutoff)
                }
            }
        }

        // Also reindex when new workouts are completed (after initial load)
        .onChange(of: store.completedWorkouts) { workouts in
            guard workoutsLoaded, repoIsBootstrapped, let agg = stats else { return }
            guard let latest = workouts.last else { return }

            Task {
                AppLogger.info("New workout completed, updating stats", category: AppLogger.workout)
                await agg.apply(latest, allWorkouts: store.completedWorkouts)
            }
        }

        // Live overlay (full card)
        .overlay(alignment: .bottom) {
            if hasActiveWorkout, showLiveOverlay, let current {
                Color.black.opacity(0.20)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(ShellAnim.spring) { showContent = false; showLiveOverlay = false }
                    }
                    .zIndex(10)

                LiveWorkoutOverlayCard(
                    namespace: liveNS,
                    title: "Live workout",
                    subtitle: grabSubtitle(for: current),
                    showContent: showContent,
                    onClose: {
                        withAnimation(ShellAnim.spring) { showContent = false; showLiveOverlay = false }
                    },
                    startDate: current.startedAt
                )
                .id("overlay-\(workoutToken)") // 🔐 force refresh on workout change
                .padding(.horizontal, 12)
                .padding(.bottom, 62)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(11)
            }
        }

        // React to workout lifecycle regardless of tab changes
        .onChange(of: workoutToken) { oldValue, newValue in
            AppLogger.debug("workoutToken changed: '\(oldValue)' → '\(newValue)' - hasActiveWorkout: \(hasActiveWorkout), grabCollapsed: \(grabCollapsed), currentTab: \(selectedTab)", category: AppLogger.workout)

            if hasActiveWorkout {
                withAnimation(ShellAnim.spring) {
                    grabCollapsed = false
                    AppLogger.debug("Showing grab tab", category: AppLogger.ui)
                }
            } else {
                withAnimation(ShellAnim.spring) {
                    showLiveOverlay = false
                    showContent = false
                    grabCollapsed = true
                    AppLogger.debug("Hiding workout UI", category: AppLogger.ui)
                }
            }
        }

        // Mini "now playing" pill (global drawing; your policy hides it on non-Home via grabCollapsed)
        .overlay(alignment: .bottom) {
            if hasActiveWorkout && !showLiveOverlay && !grabCollapsed && !isBrowsingExercises,
               let current = store.currentWorkout {
                LiveWorkoutGrabTab(
                    namespace: liveNS,
                    title: "Live workout",
                    subtitle: grabSubtitle(for: current),
                    startDate: current.startedAt,
                    onOpen: {
                        withAnimation(ShellAnim.spring) { showLiveOverlay = true; showContent = true }
                    },
                    onCollapse: { grabCollapsed = true }
                )
                .id("pill-\(workoutToken)") // 🔐 force refresh on workout change
                .padding(.horizontal, 25)
                .padding(.bottom, GrabTabMetrics.bottomMargin)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }

        // One-time startup work - configure and bootstrap dependencies
        .task {
            // Configure dependencies with model context
            dependencies.configure(with: modelContext)

            // Bootstrap async services
            await dependencies.bootstrap()

            // Log memory footprint in debug builds
            #if DEBUG
            dependencies.logMemoryFootprint()
            #endif
        }

        // Watch for when exercises are ACTUALLY loaded (not just bootstrap called)
        .onChange(of: repo.exercises.isEmpty) { isEmpty in
            if !isEmpty && !repoIsBootstrapped {
                repoIsBootstrapped = true
                AppLogger.success("Exercise repository ready with \(repo.exercises.count) exercises", category: AppLogger.app)
            }
        }

        .background(DS.Semantic.surface.ignoresSafeArea())
        .withDependencies(dependencies)
    }

    // MARK: - Helpers
    private func grabSubtitle(for current: CurrentWorkout) -> String {
        let when = current.startedAt.formatted(date: .abbreviated, time: .shortened)
        return when
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        onboardingStep = .completed

        // Show goal setup after onboarding if needed
        if needsGoalSetup {
            showGoalSetupSheet = true
        }
    }
}

// MARK: - TabBarReselectionDetector

// Robust UITabBar re-tap detector
private struct TabBarReselectionDetector: UIViewRepresentable {
    @Binding var selectedTab: AppTab
    let onReselect: (_ index: Int) -> Void

    func makeCoordinator() -> Coordinator {
        AppLogger.debug("TabBarReselectionDetector: makeCoordinator called", category: AppLogger.ui)
        return Coordinator(selectedTab: $selectedTab, onReselect: onReselect)
    }

    func makeUIView(context: Context) -> UIView {
        AppLogger.debug("TabBarReselectionDetector: makeUIView called", category: AppLogger.ui)
        let v = DetectorView()
        v.coordinator = context.coordinator
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? DetectorView)?.attachDelegateIfNeeded()
    }

    final class DetectorView: UIView {
        weak var coordinator: Coordinator?
        private var retryCount = 0
        private var hasAttached = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            AppLogger.debug("DetectorView: didMoveToWindow called", category: AppLogger.ui)

            // Give SwiftUI time to set up the UITabBarController
            // Initial attempt after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.attachDelegateIfNeeded()

                if !(self?.hasAttached ?? true) {
                    self?.retryWithDelay(0.2)
                }
            }
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            AppLogger.debug("DetectorView: didMoveToSuperview called", category: AppLogger.ui)
        }

        private func retryWithDelay(_ delay: TimeInterval) {
            guard retryCount < 10 else {
                AppLogger.warning("DetectorView: Gave up after \(retryCount) retries", category: AppLogger.ui)
                return
            }

            retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, !self.hasAttached else { return }
                AppLogger.debug("DetectorView: Retry #\(self.retryCount)", category: AppLogger.ui)
                self.attachDelegateIfNeeded()

                if !self.hasAttached {
                    self.retryWithDelay(delay * 2) // Exponential backoff
                }
            }
        }

        func attachDelegateIfNeeded() {
            guard !hasAttached else { return }

            guard let coord = coordinator else {
                AppLogger.warning("DetectorView: No coordinator", category: AppLogger.ui)
                return
            }

            AppLogger.debug("DetectorView: Looking for UITabBarController...", category: AppLogger.ui)

            // Find the real UITabBarController SwiftUI created
            if let tbc = findTabBarControllerInResponderChain(from: self) ?? findTabBarControllerInActiveWindow() {
                AppLogger.success("DetectorView: Found UITabBarController - Selected index: \(tbc.selectedIndex), View controllers: \(tbc.viewControllers?.count ?? 0)", category: AppLogger.ui)

                // Set only the tab bar controller delegate (NOT tabBar.delegate - UIKit doesn't allow that)
                tbc.delegate = coord

                hasAttached = true
                AppLogger.success("DetectorView: Delegates attached successfully", category: AppLogger.ui)
            } else {
                AppLogger.debug("DetectorView: UITabBarController NOT FOUND (will retry)", category: AppLogger.ui)
            }
        }

        private func findTabBarControllerInResponderChain(from view: UIView) -> UITabBarController? {
            var r: UIResponder? = view
            while let cur = r {
                if let tbc = (cur as? UIViewController)?.tabBarController
                    ?? cur as? UITabBarController
                    ?? (cur as? UIViewController)?.parent as? UITabBarController {
                    return tbc
                }
                r = cur.next
            }
            return nil
        }

        private func findTabBarControllerInActiveWindow() -> UITabBarController? {
            // Try all connected scenes, not just foregroundActive
            let scenes = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })

            // First try foreground active scene
            if let scene = scenes.first(where: { $0.activationState == .foregroundActive }),
               let root = (scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first)?.rootViewController {
                if let tbc = dfs(root) { return tbc }
            }

            // Fallback: try all scenes
            for scene in scenes {
                for window in scene.windows {
                    if let root = window.rootViewController,
                       let tbc = dfs(root) {
                        return tbc
                    }
                }
            }

            return nil

            func dfs(_ vc: UIViewController) -> UITabBarController? {
                if let tbc = vc as? UITabBarController { return tbc }
                for child in vc.children { if let t = dfs(child) { return t } }
                if let presented = vc.presentedViewController { return dfs(presented) }
                return nil
            }
        }
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        @Binding var selectedTab: AppTab
        private let onReselect: (_ index: Int) -> Void

        init(selectedTab: Binding<AppTab>, onReselect: @escaping (_ index: Int) -> Void) {
            self._selectedTab = selectedTab
            self.onReselect = onReselect
            AppLogger.debug("Coordinator: Initialized", category: AppLogger.ui)
        }

        // Called when any tab is selected, including re-tapping the current tab
        func tabBarController(_ tabBarController: UITabBarController,
                              shouldSelect viewController: UIViewController) -> Bool {
            let isReselect = viewController == tabBarController.selectedViewController
            AppLogger.debug("Coordinator: tabBarController shouldSelect - Current index: \(tabBarController.selectedIndex), Is reselect: \(isReselect)", category: AppLogger.ui)

            // Haptic feedback on tab tap
            Haptics.light()

            if isReselect {
                // Definite re-tap - stronger haptic
                Haptics.soft()
                AppLogger.debug("Coordinator: Calling onReselect(\(tabBarController.selectedIndex))", category: AppLogger.ui)
                onReselect(tabBarController.selectedIndex)
            } else {
                // Regular tab switch - update SwiftUI state
                if let newIndex = tabBarController.viewControllers?.firstIndex(of: viewController),
                   let newTab = AppTab(rawValue: newIndex) {
                    AppLogger.debug("Coordinator: Updating selectedTab to \(newTab)", category: AppLogger.ui)
                    DispatchQueue.main.async {
                        self.selectedTab = newTab
                    }
                }
            }
            return true
        }
    }
}
