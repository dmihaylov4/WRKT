import SwiftUI
import SwiftData
import HealthKit
import OSLog

// MARK: - Shell types & animation
enum AppTab: Int { case train = 0, plan = 1, social = 2, cardio = 3, profile = 4 }
private enum ShellAnim { static let spring = Animation.spring(response: 0.42, dampingFraction: 0.85) }
private enum TabBarLayout {
    static let contentHeight: CGFloat = 49  // matches UITabBar content zone
    // System shell: gap between the live workout card and the top of the system tab bar.
    // Matches the legacy gap (card 62pt above the safe area, custom bar top 20pt above it).
    static let systemCardGap: CGFloat = 42
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

// MARK: - Tab selection resolver
/// Decides whether a tab bar tap selects a new tab or reselects the current one.
/// Used by the system tab bar path, where taps arrive through the selection binding.
enum ShellTabSelection: Equatable {
    case select(AppTab)
    case reselect(Notification.Name?)

    static func resolve(current: AppTab, tapped: AppTab) -> ShellTabSelection {
        guard current == tapped else { return .select(tapped) }
        return .reselect(reselectNotification(for: tapped))
    }

    static func reselectNotification(for tab: AppTab) -> Notification.Name? {
        switch tab {
        case .train:   .homeTabReselected
        case .plan:    .calendarTabReselected
        case .social:  .socialTabReselected
        case .cardio:  .cardioTabReselected
        case .profile: nil
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
    @ObservedObject private var restTimer = RestTimerManager.shared
    @ObservedObject private var authService: SupabaseAuthService = AppDependencies.shared.authService

    // Badge manager for social notifications
    @State private var badgeManager = NotificationBadgeManager.shared

    // Shell UI state
    @State private var selectedTab: AppTab = .train
    @State private var showLiveOverlay = false
    @State private var showContent = false
    @State private var isShellTabBarHidden = false
    /// System shell only: bottom safe area inside tab content (the system tab bar's height).
    @State private var systemTabBarInset: CGFloat = 0
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
        .alert("Rest Timer Unavailable", isPresented: Binding(
            get: { restTimer.persistenceError != nil },
            set: { if !$0 { restTimer.dismissPersistenceError() } }
        )) {
            Button("OK", role: .cancel) { restTimer.dismissPersistenceError() }
        } message: {
            Text(restTimer.persistenceError ?? "")
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCompeteTab)) { _ in
            selectedTab = .social
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
                set: { if !$0 {
                    dependencies.barbellProgressService.needsWelcomeScreen = false
                    BattleShareCoordinator.shared.clear()
                }}
            )) {
                BarbellWelcomeView()
            }
    }

    @ViewBuilder
    private var mainContentWithOverlays: some View {
        mainContent
            .overlay(WinScreenOverlay())
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
        if #available(iOS 26, *), DS.Redesign.usesSystemShell {
            systemTabView
        } else {
            legacyTabView
        }
    }

    // MARK: - System Tab View (iOS 26 system shell)

    @available(iOS 26, *)
    private var systemTabView: some View {
        TabView(selection: systemTabSelection) {
            // TRAIN
            Tab(value: AppTab.train) {
                HomeViewNew()
                    .background(DS.Semantic.surface.ignoresSafeArea())
                    .modifier(systemTabContent)
            } label: {
                SystemTabLabel(tab: .train, isSelected: selectedTab == .train)
            }

            // PLAN
            Tab(value: AppTab.plan) {
                PlanView(pendingNotification: $pendingNotificationNavigation)
                    .background(DS.Semantic.surface.ignoresSafeArea())
                    .modifier(systemTabContent)
            } label: {
                SystemTabLabel(tab: .plan, isSelected: selectedTab == .plan)
            }

            // SOCIAL: only shown when not in local mode
            if !settings.isLocalMode {
                Tab(value: AppTab.social) {
                    SocialView(pendingNotification: $pendingNotificationNavigation)
                        .background(DS.Semantic.surface.ignoresSafeArea())
                        .modifier(systemTabContent)
                } label: {
                    SystemTabLabel(tab: .social, isSelected: selectedTab == .social)
                }
                .badge(SystemTabBadge.text(for: badgeManager.friendRequestCount + badgeManager.notificationCount))
            }

            // CARDIO
            Tab(value: AppTab.cardio) {
                NavigationStack {
                    CardioView()
                        .background(DS.Semantic.surface)
                        .scrollContentBackground(.hidden)
                }
                .modifier(systemTabContent)
            } label: {
                SystemTabLabel(tab: .cardio, isSelected: selectedTab == .cardio)
            }

            // PROFILE
            Tab(value: AppTab.profile) {
                NavigationStack {
                    ProfileView()
                        .background(DS.Semantic.surface)
                        .scrollContentBackground(.hidden)
                        .toolbar(.hidden, for: .navigationBar)
                }
                .modifier(systemTabContent)
            } label: {
                SystemTabLabel(tab: .profile, isSelected: selectedTab == .profile)
            }
        }
        .tint(DS.Palette.marone)
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    @available(iOS 26, *)
    private var systemTabContent: SystemTabContentModifier {
        SystemTabContentModifier(isTabBarHidden: isShellTabBarHidden, bottomInset: $systemTabBarInset)
    }

    /// Routes system tab bar taps through the reselect resolver.
    /// Programmatic `selectedTab` writes bypass this setter, so they never count as a reselect.
    private var systemTabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { tapped in
                switch ShellTabSelection.resolve(current: selectedTab, tapped: tapped) {
                case .select(let tab):
                    Haptics.light()
                    selectedTab = tab
                case .reselect(let name):
                    Haptics.soft()
                    if let name {
                        NotificationCenter.default.post(name: name, object: nil)
                    }
                }
            }
        )
    }

    // MARK: - Legacy Tab View (custom tab bar)

    @ViewBuilder
    private var legacyTabView: some View {
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

        if newPhase == .background {
            AppLogger.debug("App backgrounded - hasActiveWorkout: \(hasActiveWorkout)", category: AppLogger.app)

        } else if newPhase == .active {
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


                AppLogger.info("🚀 App became active - ensuring realtime subscriptions are running", category: AppLogger.app)
                await badgeManager.startRealtimeSubscriptions()

                // Sync HealthKit workouts when app comes to foreground (catches Apple Watch workouts)
                if healthKit.connectionState == .connected {
                    AppLogger.info("📊 App became active - syncing HealthKit workouts", category: AppLogger.health)
                    await healthKit.catchUpHealthChanges()
                }

                RewardsEngine.shared.validateWeeklyStreakOnAppear(store: store)
                let currentStreak = RewardsEngine.shared.weeklyGoalStreak()
                Task { await dependencies.authService.syncStreak(currentStreak) }

                // Check for battles that completed while the app was backgrounded
                await presentPendingBattleRewardsOnLaunch()
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
            await healthKit.catchUpHealthChanges()
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
            await presentPendingBattleRewardsOnLaunch()
            Task { await prewarmPlateSnapshots() }

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

    private func prewarmPlateSnapshots() async {
        let plates = dependencies.barbellProgressService.allOwnedPlateInfos()
        for plate in plates {
            guard !Task.isCancelled else { return }
            await PlateSnapshotService.shared.renderIfNeeded(
                tierID: plate.tierID,
                weightKg: plate.weightKg,
                engravingText: plate.engravingText
            )
        }
    }

    private func presentPendingBattleRewardsOnLaunch() async {
        guard let userId = authService.currentUser?.id else { return }

        do {
            let battles = try await dependencies.battleRepository.fetchUserBattles()
            for battle in battles where battle.battle.isActive && battle.battle.endDate <= Date() {
                try await dependencies.battleRepository.completeBattle(battle.battle.id)
            }

            let refreshedBattles = try await dependencies.battleRepository.fetchUserBattles()
            for battle in refreshedBattles where battle.battle.isCompleted {
                await dependencies.battleRepository.awardCompletionReward(for: battle.battle, userId: userId)
            }

            // Surface the most recently completed battle for sharing in BarbellWelcomeView
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            if let latest = refreshedBattles
                .filter({ $0.battle.isCompleted && $0.battle.endDate > cutoff })
                .max(by: { $0.battle.endDate < $1.battle.endDate }) {
                var withUser = latest
                withUser.currentUserId = userId
                BattleShareCoordinator.shared.set(battle: withUser, userId: userId)
            }
        } catch {
            AppLogger.warning("Failed to present pending battle rewards on launch: \(error.localizedDescription)", category: AppLogger.battles)
        }
    }

    private func handleRepoReady(_ isEmpty: Bool) {
        if !isEmpty && !repoIsBootstrapped {
            repoIsBootstrapped = true
        }
    }

    // MARK: - Notification Navigation

    private func handleNotificationNavigation(_ notification: AppNotification) {
        guard notification.type.isVisible else { return }
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
            .modifier(LiveOverlayBottomPlacement(systemTabBarInset: systemTabBarInset))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(11)
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

// MARK: - Live overlay placement

/// Places the live workout card above whichever tab bar is in use.
private struct LiveOverlayBottomPlacement: ViewModifier {
    let systemTabBarInset: CGFloat

    func body(content: Content) -> some View {
        if DS.Redesign.usesSystemShell {
            // Measured from the screen bottom so the card clears the system bar by the legacy gap
            content
                .padding(.bottom, systemTabBarInset + TabBarLayout.systemCardGap)
                .ignoresSafeArea(.container, edges: .bottom)
        } else {
            content
                .padding(.bottom, TabBarLayout.contentHeight + 13) // tab bar + gap
        }
    }
}

// MARK: - System tab bar pieces (iOS 26 system shell)

/// Applied to each tab's root content on the system shell: maps the shell hide and show
/// notifications to the system tab bar and reports the tab bar's height to the shell.
@available(iOS 26, *)
private struct SystemTabContentModifier: ViewModifier {
    let isTabBarHidden: Bool
    @Binding var bottomInset: CGFloat

    func body(content: Content) -> some View {
        content
            .toolbarVisibility(isTabBarHidden ? .hidden : .automatic, for: .tabBar)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.safeAreaInsets.bottom
            } action: { inset in
                bottomInset = inset
            }
    }
}

private struct SystemTabLabel: View {
    let tab: AppTab
    let isSelected: Bool

    var body: some View {
        Label {
            Text(tab.label)
        } icon: {
            SystemTabIcon.image(for: tab, isSelected: isSelected)
        }
    }
}

enum SystemTabIcon {
    /// Two-tone original art, swapped on selection like CustomTabBar.
    /// For tint-only template icons, return `Image(tab.inactiveIcon).renderingMode(.template)`.
    static func image(for tab: AppTab, isSelected: Bool) -> Image {
        Image(isSelected ? tab.activeIcon : tab.inactiveIcon).renderingMode(.original)
    }
}

enum SystemTabBadge {
    /// Same text as the CustomTabBar badge: hidden at zero, capped at "99+".
    static func text(for count: Int) -> Text? {
        guard count > 0 else { return nil }
        return Text(count > 99 ? "99+" : "\(count)")
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
