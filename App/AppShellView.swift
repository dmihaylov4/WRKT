import SwiftUI
import SwiftData
import HealthKit
import OSLog

// MARK: - Shell types & animation
private enum AppTab: Int { case train = 0, plan = 1, social = 2, cardio = 3, profile = 4 }
private enum ShellAnim { static let spring = Animation.spring(response: 0.42, dampingFraction: 0.85) }
private enum TabBarLayout {
    static let contentHeight: CGFloat = 49  // matches UITabBar content zone
}

extension AppTab {
    var activeIcon: String {
        switch self {
        case .train:   "tab-train"
        case .plan:    "tab-plan"
        case .social:  "tab-social"
        case .cardio:  "tab-cardio"
        case .profile: "tab-profile"
        }
    }
    var inactiveIcon: String { activeIcon + "-inactive" }
    var label: String {
        switch self {
        case .train:   "Train"
        case .plan:    "Plan"
        case .social:  "Social"
        case .cardio:  "Cardio"
        case .profile: "Me"
        }
    }
}

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
    @State private var isShellTabBarHidden = false
    @State private var whatsNewManager = WhatsNewManager.shared
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
    @State private var isPerformingInitialLaunchSync = false
    @State private var didCompleteInitialLaunchSync = false
    @State private var lastForegroundSyncAt: Date?

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
        .font(DS.FontType.body)
        .withDependencies(dependencies)
        .onReceive(NotificationCenter.default.publisher(for: .hideShellTabBar)) { _ in
            isShellTabBarHidden = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showShellTabBar)) { _ in
            isShellTabBarHidden = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .weeklyStreakUpdated)) { note in
            guard let streak = note.object as? Int else { return }
            Task { await dependencies.authService.syncStreak(streak) }
        }
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
            .sheet(isPresented: Binding(
                get: { whatsNewManager.needsWhatsNew },
                set: { if !$0 { whatsNewManager.dismiss() } }
            )) {
                if let release = WhatsNewManager.releases.first(where: { $0.version == whatsNewManager.currentVersion }) {
                    WhatsNewView(
                        release: release,
                        currentVersion: whatsNewManager.currentVersion,
                        onDismiss: { whatsNewManager.dismiss() }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: Binding(
                get: { dependencies.barbellProgressService.needsWelcomeScreen && !whatsNewManager.needsWhatsNew },
                set: { if !$0 { dependencies.barbellProgressService.needsWelcomeScreen = false } }
            )) {
                BarbellWelcomeView()
            }
    }

    @ViewBuilder
    private var mainContentWithOverlays: some View {
        mainContent
            .overlay(WinScreenOverlay())
            .overlay(VirtualRunSummaryOverlay())
            .overlay { NotificationOverlay() }
            .overlay { UndoToastOverlay() }
            .overlay(alignment: .bottom) {
                VirtualRunFlowStatusCard()
                    .padding(.horizontal, 16)
                    .padding(.bottom, TabBarLayout.contentHeight + 25) // tab bar + gap
                    .zIndex(998)
            }
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
            .onReceive(NotificationCenter.default.publisher(for: .didReceivePushNotification)) { notification in
                handlePushNotificationTap(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLiveWorkoutTab)) { _ in
                handleOpenLiveWorkoutTab()
            }
    }

    private var baseContent: some View {
        mainTabView
    }

    // MARK: - Main Tab View

    @ViewBuilder
    private var mainTabView: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                // TRAIN (was Home)
                HomeViewNew()
                    .background(DS.Semantic.surface.ignoresSafeArea())
                    .tabItem { Label("Train", image: "tab-train-inactive") }
                    .tag(AppTab.train)

                // PLAN (was Calendar)
                PlanView(pendingNotification: $pendingNotificationNavigation)
                    .background(DS.Semantic.surface.ignoresSafeArea())
                    .tabItem { Label("Plan", image: "tab-plan-inactive") }
                    .tag(AppTab.plan)

                // SOCIAL (new - combines Feed, Compete, Friends)
                // Only show if not in local mode
                if !settings.isLocalMode {
                    SocialView(pendingNotification: $pendingNotificationNavigation)
                        .background(DS.Semantic.surface.ignoresSafeArea())
                        .tabItem { Label("Social", image: "tab-social-inactive") }
                        .tag(AppTab.social)
                }

                // CARDIO
                NavigationStack {
                    CardioView()
                        .background(DS.Semantic.surface)
                        .scrollContentBackground(.hidden)
                }
                .tabItem { Label("Cardio", image: "tab-cardio-inactive") }
                .tag(AppTab.cardio)

                // PROFILE (simplified - settings and account)
                NavigationStack {
                    ProfileView()
                        .background(DS.Semantic.surface)
                        .scrollContentBackground(.hidden)
                        .toolbar(.hidden, for: .navigationBar)
                }
                .tabItem { Label("Me", image: "tab-profile-inactive") }
                .tag(AppTab.profile)
            }
            .tint(DS.Palette.marone)
            .toolbar(.hidden, for: .tabBar)

            if !isShellTabBarHidden {
                CustomTabBar(
                    selectedTab: $selectedTab,
                    isLocalMode: settings.isLocalMode,
                    friendRequestCount: badgeManager.friendRequestCount,
                    notificationCount: badgeManager.notificationCount
                )
                .ignoresSafeArea(edges: .bottom)
            }
        }
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

            // During active virtual runs, keep all Supabase subscriptions alive.
            // Background execution modes (audio + location) prevent suspension, so the
            // WebSocket stays open. Tearing down + rebuilding on every lock/unlock cycle
            // creates reconnection windows where broadcast messages are silently dropped.
            if inviteCoordinator.isInActiveRun {
                AppLogger.info("📱 App backgrounded during active VR — keeping subscriptions alive", category: AppLogger.app)
            } else {
                // Stop invite coordinator polling and Realtime subscription.
                // iOS kills WebSockets ~5s after suspension anyway — keeping them alive wastes resources.
                // Push notifications handle invite delivery while truly backgrounded.
                inviteCoordinator.stopListening()
                AppLogger.info("📱 App backgrounded - stopped invite coordinator, keeping badge subscriptions", category: AppLogger.app)
            }
        } else if newPhase == .active {
            UserDefaults.standard.markActive()
            AppLogger.debug("App activated - marked as running", category: AppLogger.app)
            guard didCompleteInitialLaunchSync, !isPerformingInitialLaunchSync else {
                AppLogger.info("⏭️ App became active during initial launch - skipping duplicate startup work", category: AppLogger.app)
                return
            }

            // Ensure real-time subscriptions are active (will skip if already subscribed)
            Task {
                if let lastForegroundSyncAt,
                   Date.now.timeIntervalSince(lastForegroundSyncAt) < 5 {
                    AppLogger.info("⏭️ App became active too soon after previous foreground sync - skipping", category: AppLogger.app)
                    return
                }
                lastForegroundSyncAt = .now

                // Restart invite coordinator on true resume.
                inviteCoordinator.startListening()

                AppLogger.info("🚀 App became active - ensuring realtime subscriptions are running", category: AppLogger.app)
                await badgeManager.startRealtimeSubscriptions()

                // Sync HealthKit workouts when app comes to foreground (catches Apple Watch workouts)
                if healthKit.connectionState == .connected {
                    AppLogger.info("📊 App became active - syncing HealthKit workouts", category: AppLogger.health)
                    try? await healthKit.syncWorkoutsIncremental()
                    await healthKit.syncExerciseTimeIncremental()
                }

                RewardsEngine.shared.validateWeeklyStreakOnAppear(store: store)
                let currentStreak = RewardsEngine.shared.weeklyGoalStreak()
                Task { await dependencies.authService.syncStreak(currentStreak) }
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
    }

    private func handleResetHomeToRoot(_ note: Notification) {
        let reason = (note.userInfo?["reason"] as? String) ?? (note.object as? String)
        guard reason == "user_intent" else { return }

        NotificationCenter.default.post(name: .openHomeRoot, object: nil)
        selectedTab = .train
    }

    private func handleOpenLiveWorkoutTab() {
        selectedTab = .train
        NotificationCenter.default.post(name: .openHomeRoot, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard hasActiveWorkout else { return }
            withAnimation(ShellAnim.spring) {
                showLiveOverlay = true
                showContent = true
            }
        }
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
        guard !didCompleteInitialLaunchSync, !isPerformingInitialLaunchSync else {
            AppLogger.info("⏭️ Initial launch already handled or in progress - skipping", category: AppLogger.app)
            return
        }

        isPerformingInitialLaunchSync = true
        defer { isPerformingInitialLaunchSync = false }

        healthKit.beginRouteQueueLaunchProtection()
        dependencies.configure(with: modelContext)
        whatsNewManager.configure(hasCompletedOnboarding: hasCompletedOnboarding)
        NotificationCenter.default.post(name: .appDependenciesDidConfigure, object: nil)
        await dependencies.bootstrap()

        if healthKit.connectionState == .connected {
            AppLogger.info("Running launch HealthKit sync after dependency configuration", category: AppLogger.health)
            await healthKit.syncWorkoutsIncremental()
            await healthKit.syncExerciseTimeIncremental()
        }

        RewardsEngine.shared.validateWeeklyStreakOnAppear(store: store)
        let currentStreak = RewardsEngine.shared.weeklyGoalStreak()
        Task { await dependencies.authService.syncStreak(currentStreak) }
        didCompleteInitialLaunchSync = true
        healthKit.endRouteQueueLaunchProtection(bufferSeconds: 5)

        // Initialize Watch Connectivity
        WatchConnectivityManager.shared.connectToWorkoutStore(store)

        // Seed birth year + resting HR so zones are personalised from first launch
        if let birthYear = authService.currentUser?.profile?.birthYear {
            HRZoneCalculator.shared.setBirthYear(birthYear)
        }
        if let rhr = try? await healthKit.fetchAverageRestingHeartRate() {
            HRZoneCalculator.shared.setRestingHR(rhr)
        }

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

        if let launchNotification = PushNotificationService.shared.consumeLaunchNotification() {
            handleNotificationNavigation(launchNotification)
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

        switch notification.type {
        case .programInvite:
            selectedTab = .plan
        default:
            selectedTab = .social
        }

        pendingNotificationNavigation = notification

        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            pendingNotificationNavigation = nil
        }
    }

    private func handlePushNotificationTap(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let appNotification = PushNotificationService.appNotification(from: userInfo)
        else {
            return
        }

        handleNotificationNavigation(appNotification)
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
            .padding(.bottom, TabBarLayout.contentHeight + 13) // tab bar + gap
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
        whatsNewManager.configure(hasCompletedOnboarding: true, fromOnboardingCompletion: true)

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

// MARK: - CustomTabBar

private struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    let isLocalMode: Bool
    let friendRequestCount: Int
    let notificationCount: Int

    private var tabs: [AppTab] {
        isLocalMode ? [.train, .plan, .cardio, .profile]
                    : [.train, .plan, .social, .cardio, .profile]
    }

    private var socialBadge: Int { friendRequestCount + notificationCount }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                CustomTabBarButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    badge: tab == .social ? socialBadge : 0
                ) {
                    if selectedTab == tab {
                        Haptics.soft()
                        postReselect(for: tab)
                    } else {
                        Haptics.light()
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(.top, 12)
        .background(DS.Semantic.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.primary.opacity(0.12))
        }
    }

    private func postReselect(for tab: AppTab) {
        switch tab {
        case .train:   NotificationCenter.default.post(name: .homeTabReselected, object: nil)
        case .plan:    NotificationCenter.default.post(name: .calendarTabReselected, object: nil)
        case .social:  NotificationCenter.default.post(name: .socialTabReselected, object: nil)
        case .cardio:  NotificationCenter.default.post(name: .cardioTabReselected, object: nil)
        case .profile: break
        }
    }
}

private struct CustomTabBarButton: View {
    let tab: AppTab
    let isSelected: Bool
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(isSelected ? tab.activeIcon : tab.inactiveIcon)
                        .renderingMode(.original)
                        .frame(width: 26, height: 26)

                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 10, y: -6)
                    }
                }
                Text(tab.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? DS.Palette.marone : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
