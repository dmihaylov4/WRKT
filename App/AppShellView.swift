import SwiftUI
import SwiftData
import HealthKit
import UserNotifications

// MARK: - Shell types & animation
private enum AppTab: Int { case home = 0, calendar = 1, runs = 2, profile = 3 }
private enum ShellAnim { static let spring = Animation.spring(response: 0.42, dampingFraction: 0.85) }
private enum GrabTabMetrics { static let height: CGFloat = 64; static let bottomMargin: CGFloat = 53 }

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
            print("📍 selectedTab changed: \(oldValue) → \(selectedTab)")
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
            print("🎯 showGoalSetupSheet changed: \(oldValue) → \(showGoalSetupSheet)")
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
                            print("🟢 Profile NavigationStack appeared")
                            print("   selectedTab = \(selectedTab)")
                            print("   needsGoalSetup = \(needsGoalSetup)")
                        }
                        .onDisappear {
                            print("🔴 Profile NavigationStack disappeared")
                            print("   selectedTab = \(selectedTab)")
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
                        print("🔄 Tab reselected: \(index)")
                        if index == AppTab.home.rawValue {
                            print("🏠 Posting homeTabReselected notification")
                            NotificationCenter.default.post(name: .homeTabReselected, object: nil)
                        } else if index == AppTab.calendar.rawValue {
                            print("📅 Posting calendarTabReselected notification")
                            NotificationCenter.default.post(name: .calendarTabReselected, object: nil)
                        } else if index == AppTab.runs.rawValue {
                            print("🏃 Posting cardioTabReselected notification")
                            NotificationCenter.default.post(name: .cardioTabReselected, object: nil)
                        }
                    }
                )
                .allowsHitTesting(false)
            )


            // Close overlay if backgrounded
            .onChange(of: scenePhase) { phase in
                if phase != .active, showLiveOverlay {
                    withAnimation(ShellAnim.spring) { showLiveOverlay = false; showContent = false }
                }
            }

            // Sync shell state with tab selection
            .onChange(of: selectedTab) { newTab in
                print("🔄 Tab changed to: \(newTab) (rawValue: \(newTab.rawValue))")
                print("   needsGoalSetup: \(needsGoalSetup)")
                print("   showGoalSetupSheet: \(showGoalSetupSheet)")

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
                    print("   → Showing goal setup sheet")
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
                            print("📋 Goal setup sheet appeared")
                        }
                        .onDisappear {
                            print("📋 Goal setup sheet dismissed")
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
                    print("⚠️ Ignoring resetHomeToRoot (reason=\(reason ?? "nil"))")
                    return
                }

                print("⚠️ resetHomeToRoot (reason=\(reason!)) - forcing tab to Home")
                print("   Current tab: \(selectedTab)")
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
                    print("🔄 Repo and workouts ready, triggering stats aggregation...")
                    await agg.reindex(all: store.completedWorkouts, cutoff: cutoff)
                }
            }
        }

        // Also reindex when new workouts are completed (after initial load)
        .onChange(of: store.completedWorkouts) { workouts in
            guard workoutsLoaded, repoIsBootstrapped, let agg = stats else { return }
            guard let latest = workouts.last else { return }

            Task {
                print("🔄 New workout completed, updating stats...")
                await agg.apply(latest, allWorkouts: store.completedWorkouts)
            }
        }

        // Reserve space for the GrabTab in ONE place (shell)
        .safeAreaInset(edge: .bottom) {
            if pillShouldReserveSpace {
                Color.clear.frame(height: GrabTabMetrics.height + GrabTabMetrics.bottomMargin)
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
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(11)
            }
        }

        // React to workout lifecycle regardless of tab changes
        .onChange(of: workoutToken) { oldValue, newValue in
            print("🔄 workoutToken changed: '\(oldValue)' → '\(newValue)'")
            print("   hasActiveWorkout: \(hasActiveWorkout)")
            print("   grabCollapsed: \(grabCollapsed)")
            print("   currentTab: \(selectedTab)")

            if hasActiveWorkout {
                withAnimation(ShellAnim.spring) {
                    grabCollapsed = false
                    print("   ✅ Showing grab tab")
                }
            } else {
                withAnimation(ShellAnim.spring) {
                    showLiveOverlay = false
                    showContent = false
                    grabCollapsed = true
                    print("   ❌ Hiding workout UI")
                }
            }
        }

        // Mini "now playing" pill (global drawing; your policy hides it on non-Home via grabCollapsed)
        .overlay(alignment: .bottom) {
            let shouldShow = hasActiveWorkout && !showLiveOverlay && !grabCollapsed && !isBrowsingExercises
            let _ = print("🎯 Grab tab overlay evaluation: shouldShow=\(shouldShow), hasActiveWorkout=\(hasActiveWorkout), showLiveOverlay=\(showLiveOverlay), grabCollapsed=\(grabCollapsed), isBrowsingExercises=\(isBrowsingExercises)")

            if shouldShow, let current = store.currentWorkout {
                let _ = print("✅ Rendering LiveWorkoutGrabTab with \(current.entries.count) exercises")
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
                .padding(.horizontal, 22)
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
                print("✅ Exercise repository ready with \(repo.exercises.count) exercises")
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
        print("🔧 TabBarReselectionDetector: makeCoordinator called")
        return Coordinator(selectedTab: $selectedTab, onReselect: onReselect)
    }

    func makeUIView(context: Context) -> UIView {
        print("🔧 TabBarReselectionDetector: makeUIView called")
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
            print("🔍 DetectorView: didMoveToWindow called")
            attachDelegateIfNeeded()

            // Retry after a delay if not found immediately
            if !hasAttached {
                retryWithDelay(0.1)
            }
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            print("🔍 DetectorView: didMoveToSuperview called")
        }

        private func retryWithDelay(_ delay: TimeInterval) {
            guard retryCount < 5 else {
                print("❌ DetectorView: Gave up after \(retryCount) retries")
                return
            }

            retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, !self.hasAttached else { return }
                print("🔄 DetectorView: Retry #\(self.retryCount)")
                self.attachDelegateIfNeeded()

                if !self.hasAttached {
                    self.retryWithDelay(delay * 2) // Exponential backoff
                }
            }
        }

        func attachDelegateIfNeeded() {
            guard !hasAttached else { return }

            guard let coord = coordinator else {
                print("⚠️ DetectorView: No coordinator")
                return
            }

            print("🔍 DetectorView: Looking for UITabBarController...")

            // Find the real UITabBarController SwiftUI created
            if let tbc = findTabBarControllerInResponderChain(from: self) ?? findTabBarControllerInActiveWindow() {
                print("✅ DetectorView: Found UITabBarController!")
                print("   Selected index: \(tbc.selectedIndex)")
                print("   View controllers: \(tbc.viewControllers?.count ?? 0)")

                // Set only the tab bar controller delegate (NOT tabBar.delegate - UIKit doesn't allow that)
                tbc.delegate = coord

                hasAttached = true
                print("✅ DetectorView: Delegates attached successfully")
            } else {
                print("❌ DetectorView: UITabBarController NOT FOUND (will retry)")
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
            guard
                let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }),
                let root = (scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first)?.rootViewController
            else { return nil }

            func dfs(_ vc: UIViewController) -> UITabBarController? {
                if let tbc = vc as? UITabBarController { return tbc }
                for child in vc.children { if let t = dfs(child) { return t } }
                if let presented = vc.presentedViewController { return dfs(presented) }
                return nil
            }
            return dfs(root)
        }
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        @Binding var selectedTab: AppTab
        private let onReselect: (_ index: Int) -> Void

        init(selectedTab: Binding<AppTab>, onReselect: @escaping (_ index: Int) -> Void) {
            self._selectedTab = selectedTab
            self.onReselect = onReselect
            print("🎯 Coordinator: Initialized")
        }

        // Called when any tab is selected, including re-tapping the current tab
        func tabBarController(_ tabBarController: UITabBarController,
                              shouldSelect viewController: UIViewController) -> Bool {
            print("🎯 Coordinator: tabBarController shouldSelect called")
            print("   Current index: \(tabBarController.selectedIndex)")
            print("   Is reselect: \(viewController == tabBarController.selectedViewController)")

            // Haptic feedback on tab tap
            Haptics.light()

            if viewController == tabBarController.selectedViewController {
                // Definite re-tap - stronger haptic
                Haptics.soft()
                print("🎯 Coordinator: Calling onReselect(\(tabBarController.selectedIndex))")
                onReselect(tabBarController.selectedIndex)
            } else {
                // Regular tab switch - update SwiftUI state
                if let newIndex = tabBarController.viewControllers?.firstIndex(of: viewController),
                   let newTab = AppTab(rawValue: newIndex) {
                    print("🎯 Coordinator: Updating selectedTab to \(newTab)")
                    DispatchQueue.main.async {
                        self.selectedTab = newTab
                    }
                }
            }
            return true
        }
    }
}
