import SwiftUI
import SwiftData
import HealthKit
import OSLog

// MARK: - Shell types & animation
private enum AppTab: Int { case train = 0, plan = 1, social = 2, cardio = 3, profile = 4 }
private enum ShellAnim { static let spring = Animation.spring(response: 0.42, dampingFraction: 0.85) }

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext

    // Centralized dependencies - single source of truth
    @StateObject private var dependencies = AppDependencies.shared
    @StateObject private var settings = AppSettings.shared

    // Direct references to ensure proper observation
    private var repo: ExerciseRepository { dependencies.exerciseRepository }
    private var healthKit: HealthKitManager { dependencies.healthKitManager }
    private var favs: FavoritesStore { dependencies.favoritesStore }

    // Observed object to ensure state changes are detected
    @ObservedObject private var store: WorkoutStoreV2 = AppDependencies.shared.workoutStore
    @ObservedObject private var authService: SupabaseAuthService = AppDependencies.shared.authService

    // Badge manager for social notifications
    @State private var badgeManager = NotificationBadgeManager.shared

    // Shell UI state
    @State private var selectedTab: AppTab = .train
    @State private var showLiveOverlay = false
    @State private var showContent = false
    @AppStorage("is_browsing_exercises") private var isBrowsingExercises = false

    // Notification navigation
    @State private var pendingNotificationNavigation: AppNotification?

    // Onboarding state
    @AppStorage("has_completed_onboarding") private var hasCompletedOnboarding = false
    @State private var onboardingStep: OnboardingStep = .notStarted

    enum OnboardingStep {
        case notStarted
        case carousel
        case healthKit
        case completed
    }

    @Query private var goals: [WeeklyGoal]
    @State private var showGoalSetupSheet = false

    // Exercise navigation from rest timer toast
    @State private var selectedExerciseID: String?

    private var needsGoalSetup: Bool {
        guard let g = goals.first else { return true }
        return !g.isSet
    }

    @Namespace private var liveNS
    @Environment(\.scenePhase) private var scenePhase

    // Convenience
    private var current: CurrentWorkout? { store.currentWorkout }
    private var hasActiveWorkout: Bool { (current?.entries.isEmpty == false) }

    /// Cached workout token to avoid recomputation on every render
    @State private var workoutToken: String = "none"

    // Statistics tracking
    @State private var repoIsBootstrapped = false
    @State private var workoutsLoaded = false

    // Virtual run invite coordinator
    @State private var inviteCoordinator = VirtualRunInviteCoordinator.shared

    // Convenience accessor for stats
    private var stats: StatsAggregator? { dependencies.statsAggregator }

    var body: some View {
        Group {
            if authService.isCheckingSession && !settings.isLocalMode {
                // Show splash screen while checking session (unless in local mode)
                splashScreen
            } else if authService.currentUser != nil || settings.isLocalMode {
                // User is logged in OR in local mode - show main app
                contentWithModifiers
            } else {
                // User is not logged in and not in local mode - show auth
                LoginView()
            }
        }
        .background(DS.Semantic.surface.ignoresSafeArea())
        .withDependencies(dependencies)
        .fullScreenCover(isPresented: $authService.needsPasswordReset) {
            SetNewPasswordView()
                .environmentObject(authService)
        }
    }

    // MARK: - Splash Screen

    @ViewBuilder
    private var splashScreen: some View {
        ZStack {
            DS.Semantic.surface.ignoresSafeArea()

            VStack(spacing: 20) {
                // App logo or icon
                if let logo = UIImage(named: "LaunchLogo") {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                } else {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(DS.Palette.marone)
                }

                // Optional: Loading indicator
                ProgressView()
                    .tint(DS.Palette.marone)
            }
        }
    }

    // MARK: - Content Assembly

    @ViewBuilder
    private var contentWithModifiers: some View {
        mainContentWithOverlays
            .overlay(alignment: .bottom) { liveOverlayCard }
            .overlay(alignment: .top) {
                RestTimerCompletionToast(onTap: { exerciseID in
                    selectedExerciseID = exerciseID
                })
                .zIndex(1000)
            }
            .overlay(alignment: .top) { virtualRunInviteBanner }
            .sheet(item: Binding(
                get: { selectedExerciseID.flatMap { id in repo.exercises.first(where: { $0.id == id }) } },
                set: { _ in selectedExerciseID = nil }
            )) { exercise in
                NavigationStack {
                    ExerciseSessionView(exercise: exercise)
                        .environmentObject(store)
                }
            }
    }

    @ViewBuilder
    private var mainContentWithOverlays: some View {
        mainContent
            .overlay(WinScreenOverlay())
            .overlay(VirtualRunSummaryOverlay())
            .overlay { NotificationOverlay() }
            .overlay { UndoToastOverlay() }
    }

    @ViewBuilder
    private var mainContent: some View {
        baseContent
            .modifier(OnboardingModifiers(
                scenePhase: scenePhase,
                selectedTab: $selectedTab,
                onboardingStep: $onboardingStep,
                showGoalSetupSheet: $showGoalSetupSheet,
                goals: goals,
                healthKit: healthKit,
                handleScenePhaseChange: handleScenePhaseChange,
                handleTabChange: handleTabChange,
                handleInitialAppear: handleInitialAppear,
                completeOnboarding: completeOnboarding
            ))
            .modifier(NotificationModifiers(
                showLiveOverlay: $showLiveOverlay,
                showContent: $showContent,
                handleResetHomeToRoot: handleResetHomeToRoot
            ))
            .modifier(WorkoutChangeModifiers(
                currentWorkoutId: store.currentWorkout?.id,
                entriesCount: store.currentWorkout?.entries.count,
                completedCount: store.completedWorkouts.count,
                workoutToken: workoutToken,
                updateWorkoutToken: updateWorkoutToken,
                handleWorkoutsCountChange: handleWorkoutsCountChange,
                handleNewWorkoutCompleted: handleNewWorkoutCompleted,
                handleWorkoutTokenChange: handleWorkoutTokenChange
            ))
            .modifier(LifecycleModifiers(
                repoIsBootstrapped: repoIsBootstrapped,
                workoutsLoaded: workoutsLoaded,
                repoIsEmpty: repo.exercises.isEmpty,
                handleInitialStatsLoad: handleInitialStatsLoad,
                handleAppLaunch: handleAppLaunch,
                handleRepoReady: handleRepoReady
            ))
            .onReceive(NotificationCenter.default.publisher(for: .init("NavigateToNotification"))) { notification in
                if let appNotification = notification.object as? AppNotification {
                    handleNotificationNavigation(appNotification)
                }
            }
    }

    @ViewBuilder
    private var baseContent: some View {
        ZStack {
            mainTabView
                .overlay(tabBarDetector)
        }
    }

    // MARK: - Main Tab View

    @ViewBuilder
    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            // TRAIN (was Home)
            HomeViewNew()
                .background(DS.Semantic.surface.ignoresSafeArea())
                .tabItem { Label("Train", systemImage: "dumbbell.fill") }
                .tag(AppTab.train)

            // PLAN (was Calendar)
            PlanView()
                .background(DS.Semantic.surface.ignoresSafeArea())
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(AppTab.plan)

            // SOCIAL (new - combines Feed, Compete, Friends)
            // Only show if not in local mode
            if !settings.isLocalMode {
                SocialView(pendingNotification: $pendingNotificationNavigation)
                    .background(DS.Semantic.surface.ignoresSafeArea())
                    .tabItem { Label("Social", systemImage: "person.2.fill") }
                    .tag(AppTab.social)
            }

            // CARDIO
            NavigationStack {
                CardioView()
                    .background(DS.Semantic.surface)
                    .scrollContentBackground(.hidden)
            }
            .tabItem { Label("Cardio", systemImage: "heart.fill") }
            .tag(AppTab.cardio)

            // PROFILE (simplified - settings and account)
            NavigationStack {
                ProfileView()
                    .background(DS.Semantic.surface)
                    .scrollContentBackground(.hidden)
                    .navigationBarHidden(true)
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }
            .tag(AppTab.profile)
        }
        .tint(DS.Palette.marone)
    }

    // MARK: - Tab Bar Detector

    @ViewBuilder
    private var tabBarDetector: some View {
        TabBarReselectionDetector(
            selectedTab: $selectedTab,
            onReselect: { [settings] index in
                // Map visual index to AppTab (handles hidden Social tab in local mode)
                let tabCount = settings.isLocalMode ? 4 : 5
                let tab = TabBarReselectionDetector.Coordinator.mapIndexToTab(index: index, tabCount: tabCount)

                switch tab {
                case .train:
                    NotificationCenter.default.post(name: .homeTabReselected, object: nil)
                case .plan:
                    NotificationCenter.default.post(name: .calendarTabReselected, object: nil)
                case .social:
                    break // TODO: Add social tab reselection notification if needed
                case .cardio:
                    NotificationCenter.default.post(name: .cardioTabReselected, object: nil)
                case .profile:
                    break // TODO: Add profile tab reselection notification if needed
                }
            }
        )
        .allowsHitTesting(false)
    }

    // MARK: - Bindings

    private var onboardingCarouselBinding: Binding<Bool> {
        Binding(
            get: { onboardingStep == .carousel },
            set: { _ in }
        )
    }

    private var onboardingHealthKitBinding: Binding<Bool> {
        Binding(
            get: { onboardingStep == .healthKit },
            set: { _ in }
        )
    }

    // MARK: - Event Handlers

    private func handleScenePhaseChange(_ oldPhase: ScenePhase, _ newPhase: ScenePhase) {
        // Close live overlay when app backgrounds
        if newPhase != .active, showLiveOverlay {
            withAnimation(ShellAnim.spring) { showLiveOverlay = false; showContent = false }
        }

        // Track app lifecycle to detect force quit
        // When backgrounding, store timestamp + active workout status
        // When activating, mark as running
        if newPhase == .background {
            UserDefaults.standard.markBackgrounded(hasActiveWorkout: hasActiveWorkout)
            AppLogger.debug("App backgrounded - hasActiveWorkout: \(hasActiveWorkout)", category: AppLogger.app)

            // Keep real-time subscriptions alive in background for notifications
            // iOS will manage WebSocket suspension automatically after a few minutes
            // For true push when app is terminated, we'll need APNs server-side push
            AppLogger.info("📱 App backgrounded - keeping realtime subscriptions alive for notifications", category: AppLogger.app)
        } else if newPhase == .active {
            UserDefaults.standard.markActive()
            AppLogger.debug("App activated - marked as running", category: AppLogger.app)

            // Ensure real-time subscriptions are active (will skip if already subscribed)
            Task {
                AppLogger.info("🚀 App became active - ensuring realtime subscriptions are running", category: AppLogger.app)
                await badgeManager.startRealtimeSubscriptions()

                // Sync HealthKit workouts when app comes to foreground (catches Apple Watch workouts)
                if healthKit.connectionState == .connected {
                    AppLogger.info("📊 App became active - syncing HealthKit workouts", category: AppLogger.health)
                    try? await healthKit.syncWorkoutsIncremental()
                }
            }
        }
    }

    private func handleTabChange(_ newTab: AppTab) {
        NotificationCenter.default.post(name: .tabSelectionChanged, object: nil)
        NotificationCenter.default.post(name: .tabDidChange, object: nil)

        if showLiveOverlay {
            withAnimation(ShellAnim.spring) { showContent = false; showLiveOverlay = false }
        }

        if needsGoalSetup && (newTab == .profile) {
            showGoalSetupSheet = true
        }
    }

    private func handleInitialAppear() {
        if !hasCompletedOnboarding {
            onboardingStep = .carousel
        } else if needsGoalSetup && (selectedTab == .profile) {
            showGoalSetupSheet = true
        }

        // Validate weekly streak ONCE on cold start - not in individual views
        // This ensures the streak is recalculated once from historical data,
        // without each view recalculating and potentially corrupting the value.
        RewardsEngine.shared.validateWeeklyStreakOnAppear(store: store)
    }

    private func handleResetHomeToRoot(_ note: Notification) {
        let reason = (note.userInfo?["reason"] as? String) ?? (note.object as? String)
        guard reason == "user_intent" else { return }

        NotificationCenter.default.post(name: .openHomeRoot, object: nil)
        selectedTab = .train
    }

    private func handleWorkoutsCountChange(_ newCount: Int) {
        if newCount > 0 && !workoutsLoaded {
            workoutsLoaded = true
        }
    }

    private func handleInitialStatsLoad(_ bothReady: Bool) {
        // Note: Initial stats reindex is now handled in AppDependencies.bootstrap()
        // to ensure it happens AFTER exercises are fully loaded
        // This prevents the race condition where stats would be computed before exercises exist
        guard bothReady, let _ = stats else { return }
        guard store.completedWorkouts.count > 0 else { return }

        // Stats reindex is now handled in bootstrap - no action needed here
        AppLogger.debug("Stats and workouts ready - reindex handled in bootstrap", category: AppLogger.statistics)
    }

    private func handleNewWorkoutCompleted(_ oldCount: Int, _ newCount: Int) {
        guard workoutsLoaded, repoIsBootstrapped, let agg = stats else { return }
        guard newCount > oldCount else { return }
        guard let latest = store.completedWorkouts.last else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await agg.apply(latest, allWorkouts: store.completedWorkouts)
        }
    }

    private func handleWorkoutTokenChange(_ oldValue: String, _ newValue: String) {
        if !hasActiveWorkout {
            withAnimation(ShellAnim.spring) {
                showLiveOverlay = false
                showContent = false
            }
        }
    }

    private func handleAppLaunch() async {
        AppLogger.info("📱 handleAppLaunch() called", category: AppLogger.app)

        dependencies.configure(with: modelContext)
        await dependencies.bootstrap()

        // Initialize Watch Connectivity
        WatchConnectivityManager.shared.connectToWorkoutStore(store)

        // Start real-time subscriptions for notifications
        // Only if not in local mode and user is authenticated
        AppLogger.info("🔍 Checking if should start real-time: isLocalMode=\(settings.isLocalMode), currentUser=\(authService.currentUser != nil)", category: AppLogger.app)

        if !settings.isLocalMode && authService.currentUser != nil {
            AppLogger.info("🚀 Calling badgeManager.startRealtimeSubscriptions() from handleAppLaunch", category: AppLogger.app)
            await badgeManager.startRealtimeSubscriptions()

            // Start listening for virtual run invites (Realtime + 30s fallback poll)
            inviteCoordinator.startListening()
        } else {
            AppLogger.warning("⚠️ Not starting real-time subscriptions in handleAppLaunch", category: AppLogger.app)
        }

        // Run initial pattern analysis if never done before
        if await WorkoutPatternAnalyzer.shared.needsInitialAnalysis() {
            AppLogger.info("📊 Running initial workout pattern analysis...", category: AppLogger.app)
            await WorkoutPatternAnalyzer.shared.forceAnalyzePattern(workouts: store.completedWorkouts)
        }

        // Schedule daily streak check at learned workout time
        await SmartNudgeManager.shared.scheduleDailyStreakCheck()

        // Perform immediate streak check
        if let weeklyGoal = try? modelContext.fetch(FetchDescriptor<WeeklyGoal>()).first {
            await SmartNudgeManager.shared.performStreakCheck(
                weeklyGoal: weeklyGoal,
                completedWorkouts: store.completedWorkouts,
                runs: store.validRuns
            )
        }

        #if DEBUG
        dependencies.logMemoryFootprint()
        #endif
    }

    private func handleRepoReady(_ isEmpty: Bool) {
        if !isEmpty && !repoIsBootstrapped {
            repoIsBootstrapped = true
        }
    }

    // MARK: - Notification Navigation

    private func handleNotificationNavigation(_ notification: AppNotification) {
        AppLogger.info("🧭 Handling notification navigation: type=\(notification.type.rawValue)", category: AppLogger.app)

        // Switch to social tab
        selectedTab = .social

        // Set pending notification for SocialView to handle
        pendingNotificationNavigation = notification

        // Clear after a delay to allow SocialView to process
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            pendingNotificationNavigation = nil
        }
    }

    // MARK: - Overlay Views

    @ViewBuilder
    private var liveOverlayCard: some View {
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
                subtitle: current.startedAt.formatted(date: .abbreviated, time: .shortened),
                showContent: showContent,
                onClose: {
                    withAnimation(ShellAnim.spring) { showContent = false; showLiveOverlay = false }
                },
                startDate: current.startedAt
            )
            .id("overlay-\(workoutToken)")
            .padding(.horizontal, 12)
            .padding(.bottom, 62)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(11)
        }
    }

    // MARK: - Virtual Run Invite Banner

    @ViewBuilder
    private var virtualRunInviteBanner: some View {
        if let invite = inviteCoordinator.pendingInvite,
           let profile = inviteCoordinator.inviterProfile {
            VirtualRunInviteBanner(
                invite: invite,
                inviterProfile: profile,
                onAccept: { inviteCoordinator.acceptInvite() },
                onDecline: { inviteCoordinator.declineInvite() }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: inviteCoordinator.pendingInvite?.id)
            .padding(.top, 8)
            .zIndex(999)
        }
    }

    // MARK: - Helpers

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        onboardingStep = .completed

        // Show goal setup after onboarding if needed
        if needsGoalSetup {
            showGoalSetupSheet = true
        }
    }

    private func updateWorkoutToken() {
        let newToken: String
        if let c = store.currentWorkout {
            newToken = "\(c.id.uuidString)-\(c.entries.count)"
        } else {
            newToken = "none"
        }

        if newToken != workoutToken {
            workoutToken = newToken
        }
    }
}

// MARK: - View Modifier Groups

private struct OnboardingModifiers: ViewModifier {
    let scenePhase: ScenePhase
    @Binding var selectedTab: AppTab
    @Binding var onboardingStep: AppShellView.OnboardingStep
    @Binding var showGoalSetupSheet: Bool
    let goals: [WeeklyGoal]
    let healthKit: HealthKitManager
    let handleScenePhaseChange: (ScenePhase, ScenePhase) -> Void
    let handleTabChange: (AppTab) -> Void
    let handleInitialAppear: () -> Void
    let completeOnboarding: () -> Void

    private var onboardingCarouselBinding: Binding<Bool> {
        Binding(
            get: { onboardingStep == .carousel },
            set: { _ in }
        )
    }

    private var onboardingHealthKitBinding: Binding<Bool> {
        Binding(
            get: { onboardingStep == .healthKit },
            set: { _ in }
        )
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(oldPhase, newPhase)
            }
            .onChange(of: selectedTab) { _, newTab in
                handleTabChange(newTab)
            }
            .onAppear(perform: handleInitialAppear)
            .fullScreenCover(isPresented: onboardingCarouselBinding) {
                OnboardingCarouselView {
                    onboardingStep = .healthKit
                }
            }
            .fullScreenCover(isPresented: onboardingHealthKitBinding) {
                HealthAuthSheet(onDismiss: {
                    completeOnboarding()
                })
                .environmentObject(healthKit)
            }
            .sheet(isPresented: $showGoalSetupSheet) {
                NavigationStack {
                    WeeklyGoalSetupView(goal: goals.first)
                        .interactiveDismissDisabled()
                }
            }
    }
}

private struct NotificationModifiers: ViewModifier {
    @Binding var showLiveOverlay: Bool
    @Binding var showContent: Bool
    let handleResetHomeToRoot: (Notification) -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openLiveOverlay)) { _ in
                withAnimation(ShellAnim.spring) { showLiveOverlay = true; showContent = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dismissLiveOverlay)) { _ in
                withAnimation(ShellAnim.spring) { showLiveOverlay = false; showContent = false }
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetHomeToRoot)) { note in
                handleResetHomeToRoot(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .rewardsDidSummarize)) { note in
                guard let s = note.object as? RewardSummary else { return }
                WinScreenCoordinator.shared.enqueue(s)
            }
    }
}

private struct WorkoutChangeModifiers: ViewModifier {
    let currentWorkoutId: UUID?
    let entriesCount: Int?
    let completedCount: Int
    let workoutToken: String
    let updateWorkoutToken: () -> Void
    let handleWorkoutsCountChange: (Int) -> Void
    let handleNewWorkoutCompleted: (Int, Int) -> Void
    let handleWorkoutTokenChange: (String, String) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: currentWorkoutId) { _ in
                updateWorkoutToken()
            }
            .onChange(of: entriesCount) { _ in
                updateWorkoutToken()
            }
            .onChange(of: completedCount) { _, newCount in
                handleWorkoutsCountChange(newCount)
            }
            .onChange(of: completedCount) { oldCount, newCount in
                handleNewWorkoutCompleted(oldCount, newCount)
            }
            .onChange(of: workoutToken) { oldValue, newValue in
                handleWorkoutTokenChange(oldValue, newValue)
            }
    }
}

private struct LifecycleModifiers: ViewModifier {
    let repoIsBootstrapped: Bool
    let workoutsLoaded: Bool
    let repoIsEmpty: Bool
    let handleInitialStatsLoad: (Bool) -> Void
    let handleAppLaunch: () async -> Void
    let handleRepoReady: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: repoIsBootstrapped && workoutsLoaded) { _, bothReady in
                handleInitialStatsLoad(bothReady)
            }
            .task {
                await handleAppLaunch()
            }
            .onChange(of: repoIsEmpty) { _, isEmpty in
                handleRepoReady(isEmpty)
            }
    }
}

// MARK: - TabBarReselectionDetector

// Robust UITabBar re-tap detector
private struct TabBarReselectionDetector: UIViewRepresentable {
    @Binding var selectedTab: AppTab
    let onReselect: (_ index: Int) -> Void

    func makeCoordinator() -> Coordinator {
        return Coordinator(selectedTab: $selectedTab, onReselect: onReselect)
    }

    func makeUIView(context: Context) -> UIView {
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

            // Give SwiftUI time to set up the UITabBarController
            // Initial attempt after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.attachDelegateIfNeeded()

                if !(self?.hasAttached ?? true) {
                    self?.retryWithDelay(0.2)
                }
            }
        }

        private func retryWithDelay(_ delay: TimeInterval) {
            guard retryCount < 5 else { return }  // Reduced from 10 to 5 retries

            retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, !self.hasAttached else { return }
                self.attachDelegateIfNeeded()

                if !self.hasAttached {
                    self.retryWithDelay(delay * 1.5) // Reduced exponential backoff
                }
            }
        }

        func attachDelegateIfNeeded() {
            guard !hasAttached, let coord = coordinator else { return }

            // Find the real UITabBarController SwiftUI created
            if let tbc = findTabBarControllerInResponderChain(from: self) ?? findTabBarControllerInActiveWindow() {
                // Set only the tab bar controller delegate (NOT tabBar.delegate - UIKit doesn't allow that)
                tbc.delegate = coord
                hasAttached = true
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
        }

        /// Maps visual tab index to AppTab, handling hidden Social tab in local mode
        static func mapIndexToTab(index: Int, tabCount: Int) -> AppTab {
            // 5 tabs = all tabs shown (train, plan, social, cardio, profile)
            // 4 tabs = social hidden (train, plan, cardio, profile)
            if tabCount == 5 {
                return AppTab(rawValue: index) ?? .train
            } else {
                // Local mode: Social tab is hidden
                // Visual: 0=train, 1=plan, 2=cardio, 3=profile
                // AppTab: 0=train, 1=plan, 3=cardio, 4=profile
                switch index {
                case 0: return .train
                case 1: return .plan
                case 2: return .cardio
                case 3: return .profile
                default: return .train
                }
            }
        }

        // Called when any tab is selected, including re-tapping the current tab
        func tabBarController(_ tabBarController: UITabBarController,
                              shouldSelect viewController: UIViewController) -> Bool {
            let isReselect = viewController == tabBarController.selectedViewController

            // Haptic feedback on tab tap
            Haptics.light()

            if isReselect {
                // Definite re-tap - stronger haptic
                Haptics.soft()
                onReselect(tabBarController.selectedIndex)
            } else {
                // Regular tab switch - update SwiftUI state
                if let newIndex = tabBarController.viewControllers?.firstIndex(of: viewController) {
                    let tabCount = tabBarController.viewControllers?.count ?? 5
                    let newTab = Self.mapIndexToTab(index: newIndex, tabCount: tabCount)
                    DispatchQueue.main.async {
                        self.selectedTab = newTab
                    }
                }
            }
            return true
        }
    }
}
