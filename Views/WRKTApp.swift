// WRKTApp.swift
import SwiftUI
import SwiftData
import UIKit

// MARK: - Shell types & animation
private enum AppTab: Int { case home = 0, calendar = 1, runs = 2, profile = 3 }
private enum ShellAnim { static let spring = Animation.spring(response: 0.42, dampingFraction: 0.85) }
private enum GrabTabMetrics { static let height: CGFloat = 64; static let bottomMargin: CGFloat = 53 }



struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var favs = FavoritesStore()
    // Shared stores
    @StateObject private var repo  = ExerciseRepository.shared
    @StateObject private var store = WorkoutStore()
    @StateObject private var healthKit = HealthKitManager.shared

    // Shell UI state
    @State private var selectedTab: AppTab = .home
    @State private var grabCollapsed = false
    @State private var showLiveOverlay = false
    @State private var showContent = false
    
    //Onboarding needed
    
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

    /// Changes whenever a workout is created/ended OR entries change.
    private var workoutToken: String {
        guard let c = store.currentWorkout else { return "none" }
        return "\(c.id.uuidString)-\(c.entries.count)"
    }

    /// Centralized “should the pill reserve space” logic
    private var pillShouldReserveSpace: Bool {
        hasActiveWorkout && !showLiveOverlay && !grabCollapsed
    }
    
    //Statistics

    @State private var stats: StatsAggregator?
    @State private var repoIsBootstrapped = false
    @State private var workoutsLoaded = false

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
                }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
            }
           // .sensoryFeedback(.selection, trigger: selectedTab)
            .tint(DS.Palette.marone)

            .overlay(
                TabBarReselectionDetector { index in
                    print("🔄 Tab reselected: \(index)")
                    if index == AppTab.home.rawValue {
                        print("🏠 Posting homeTabReselected notification")
                        NotificationCenter.default.post(name: .homeTabReselected, object: nil)
                    }
                }
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
                NotificationCenter.default.post(name: .tabSelectionChanged, object: nil)

                // Keep your current behavior (pill shows only on Home).
                if newTab != .home {
                    grabCollapsed = true
                } else if hasActiveWorkout {
                    grabCollapsed = false
                }

                if showLiveOverlay {
                    withAnimation(ShellAnim.spring) { showContent = false; showLiveOverlay = false }
                }
            }
            // NEW
            .onAppear {
                // present once on first launch if needed
                if needsGoalSetup && (selectedTab == .home || selectedTab == .profile) {
                    showGoalSetupSheet = true
                }
            }

            .onChange(of: selectedTab) { newTab in
                // re-check when the user navigates — but don’t force a tab swap
                if needsGoalSetup && (newTab == .home || newTab == .profile) {
                    showGoalSetupSheet = true
                }
            }

            .sheet(isPresented: $showGoalSetupSheet) {
                NavigationStack {
                    WeeklyGoalSetupView(goal: goals.first)
                        .interactiveDismissDisabled() // keep your requirement
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

        } // ZStack
        .task {
            if stats == nil {
                let agg = StatsAggregator(container: modelContext.container)
                // IMPORTANT: Configure exercise repository BEFORE setting stats
                // to prevent race condition where reindex is triggered before repo is set
                await agg.setExerciseRepository(repo)
                store.installStats(agg)
                stats = agg  // Only set stats after repo is configured
                // Don't reindex yet - wait for workouts to load
            }
        }

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
        .onChange(of: workoutToken) { _ in
            if hasActiveWorkout {
                withAnimation(ShellAnim.spring) { grabCollapsed = false } // show pill when entries arrive
            } else {
                withAnimation(ShellAnim.spring) {
                    showLiveOverlay = false
                    showContent = false
                    grabCollapsed = true
                }
            }
        }

        // Mini “now playing” pill (global drawing; your policy hides it on non-Home via grabCollapsed)
        .overlay(alignment: .bottom) {
            if hasActiveWorkout, !showLiveOverlay, !grabCollapsed, let current {
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

        // One-time startup work (do not duplicate)
        .task {
            repo.bootstrap(useSlimPreload: true)
            RewardsEngine.shared.configure(context: modelContext)
            print("⚙️ Rewards configured:", RewardsEngine.shared.debugRulesSummary())

            // Configure HealthKit sync
            HealthKitManager.shared.modelContext = modelContext
            HealthKitManager.shared.workoutStore = store
            HealthKitManager.shared.registerBackgroundTasks()

            // Check if already authorized and setup observers
            if HealthKitManager.shared.connectionState == .connected {
                HealthKitManager.shared.setupBackgroundObservers()
            }
        }

        // Watch for when exercises are ACTUALLY loaded (not just bootstrap called)
        .onChange(of: repo.exercises.isEmpty) { isEmpty in
            if !isEmpty && !repoIsBootstrapped {
                repoIsBootstrapped = true
                print("✅ Exercise repository ready with \(repo.exercises.count) exercises")
            }
        }

        .background(DS.Semantic.surface.ignoresSafeArea())
        .environmentObject(repo)
        .environmentObject(store)
        .environmentObject(favs)
        .environmentObject(healthKit)
    }

    // MARK: - Helpers
    private func grabSubtitle(for current: CurrentWorkout) -> String {
        let c = current.entries.count
        let count = "\(c) exercise" + (c == 1 ? "" : "s")
        let when = current.startedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(count) • \(when)"
    }
}

//@main
//struct WRKTApp: App {
  //  var body: some Scene {
    //    WindowGroup {
      //      AppShellView()
        //        .modelContainer(Self.makeContainer())
        //}
   // }

   // static func makeContainer() -> ModelContainer {
     //   let schema = Schema([
       //     RewardProgress.self,
         //   Achievement.self,
         //   ChallengeAssignment.self,
         //   RewardLedgerEntry.self,
          //  Wallet.self,
          //  ExercisePR.self,
          //  DexStamp.self,
          //  WeeklyTrainingSummary.self,
          //  ExerciseVolumeSummary.self,
           // MovingAverage.self,
           // ExerciseProgressionSummary.self,
          //  ExerciseTrend.self,
           // PushPullBalance.self,
           // MuscleGroupFrequency.self,
           // MovementPatternBalance.self,
           // WeeklyGoal.self,
            // Health sync models
           // HealthSyncAnchor.self,
           // RouteFetchTask.self,
           // MapSnapshotCache.self
        //])

//  let config = ModelConfiguration(
  //          schema: schema,
    //        isStoredInMemoryOnly: false,
      //      allowsSave: true,
        //    cloudKitDatabase: .none
       // )

        //do {
          //  return try ModelContainer(for: schema, configurations: config)
        //} catch {
          //  fatalError("Failed to create ModelContainer: \(error)")
       // }
   // }
//}

@main
struct WRKTApp: App {
    // create exactly once
    private let container: ModelContainer

    init() {
        self.container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .modelContainer(container)   // <- reuse the same instance
        }
    }

    static func makeContainer() -> ModelContainer {
        let schema = Schema([
            RewardProgress.self, Achievement.self, ChallengeAssignment.self, RewardLedgerEntry.self,
            Wallet.self, ExercisePR.self, DexStamp.self, WeeklyTrainingSummary.self, ExerciseVolumeSummary.self,
            MovingAverage.self, ExerciseProgressionSummary.self, ExerciseTrend.self, PushPullBalance.self,
            MuscleGroupFrequency.self, MovementPatternBalance.self, WeeklyGoal.self,
            HealthSyncAnchor.self, RouteFetchTask.self, MapSnapshotCache.self
        ])

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        do { return try ModelContainer(for: schema, configurations: config) }
        catch { fatalError("Failed to create ModelContainer: \(error)") }
    }
}

// Robust UITabBar re-tap detector
private struct TabBarReselectionDetector: UIViewRepresentable {
    let onReselect: (_ index: Int) -> Void

    func makeCoordinator() -> Coordinator {
        print("🔧 TabBarReselectionDetector: makeCoordinator called")
        return Coordinator(onReselect: onReselect)
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
        private let onReselect: (_ index: Int) -> Void

        init(onReselect: @escaping (_ index: Int) -> Void) {
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
            }
            return true
        }
    }
}
