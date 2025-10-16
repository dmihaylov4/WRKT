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

    // Shell UI state
    @State private var selectedTab: AppTab = .home
    @State private var grabCollapsed = false
    @State private var showLiveOverlay = false
    @State private var showContent = false

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

                // RUNS
                NavigationStack {
                    RunsView()
                        .background(DS.Semantic.surface)
                        .scrollContentBackground(.hidden)
                }
                .tabItem { Label("Run", systemImage: "figure.run") }
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
            .tint(DS.Palette.marone)
            .overlay(
                TabBarReselectionDetector { index in
                    if index == AppTab.home.rawValue {
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

            // External overlay close
            .onReceive(NotificationCenter.default.publisher(for: .dismissLiveOverlay)) { _ in
                withAnimation(ShellAnim.spring) { showLiveOverlay = false; showContent = false }
            }

            // Global “return to Home”
            .onReceive(NotificationCenter.default.publisher(for: .resetHomeToRoot)) { _ in
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
                stats = agg
                store.installStats(agg)

                if let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now) {
                    await agg.reindex(all: store.completedWorkouts, cutoff: cutoff)
                }
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
            repo.bootstrap(useSlimPreload: true) // or false if you don’t want the slim prepaint
            RewardsEngine.shared.configure(context: modelContext)
            print("⚙️ Rewards configured:", RewardsEngine.shared.debugRulesSummary())
        }

        .background(DS.Semantic.surface.ignoresSafeArea())
        .environmentObject(repo)
        .environmentObject(store)
        .environmentObject(favs)
    }

    // MARK: - Helpers
    private func grabSubtitle(for current: CurrentWorkout) -> String {
        let c = current.entries.count
        let count = "\(c) exercise" + (c == 1 ? "" : "s")
        let when = current.startedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(count) • \(when)"
    }
}

@main
struct WRKTApp: App {
    var body: some Scene {
        WindowGroup {
            AppShellView()
                .modelContainer(for: [
                    RewardProgress.self,
                      Achievement.self,
                      ChallengeAssignment.self,
                      RewardLedgerEntry.self,
                      Wallet.self,
                      ExercisePR.self,
                      DexStamp.self,
                      WeeklyTrainingSummary.self,
                      ExerciseVolumeSummary.self
                ])
        }
    }
}

// Robust UITabBar re-tap detector
private struct TabBarReselectionDetector: UIViewRepresentable {
    let onReselect: (_ index: Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onReselect: onReselect) }

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

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachDelegateIfNeeded()
        }
        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            attachDelegateIfNeeded()
        }

        func attachDelegateIfNeeded() {
            guard let coord = coordinator else { return }

            // Find the real UITabBarController SwiftUI created
            if let tbc = findTabBarControllerInResponderChain(from: self) ?? findTabBarControllerInActiveWindow() {
                // Set both delegates; safe to set repeatedly
                tbc.delegate = coord
                tbc.tabBar.delegate = coord
                coord.lastIndex = tbc.selectedIndex
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

    final class Coordinator: NSObject, UITabBarControllerDelegate, UITabBarDelegate {
        private let onReselect: (_ index: Int) -> Void
        var lastIndex: Int? = nil

        init(onReselect: @escaping (_ index: Int) -> Void) { self.onReselect = onReselect }

        // Called even when tapping the already-selected tab (pre-selection state)
        func tabBarController(_ tabBarController: UITabBarController,
                              shouldSelect viewController: UIViewController) -> Bool {
            if viewController == tabBarController.selectedViewController {
                // Definite re-tap
                onReselect(tabBarController.selectedIndex)
            }
            return true
        }

        // Extra safety: compare against the last index on didSelect
        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard
                let tbc = tabBar.delegate as? UITabBarController ?? (tabBar.next as? UITabBarController),
                let items = tbc.tabBar.items,
                let tapped = items.firstIndex(of: item)
            else { return }

            if let last = lastIndex, last == tapped {
                onReselect(tapped)
            }
            lastIndex = tapped
        }
    }
}
