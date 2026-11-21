//
//  CutSettingsHost.swift
//  WRKT
//
//  SettingsView's state and flows behind the Cut hub: the same auth service, local mode
//  settings, badge refresh, login sheet, sign out, local mode hand-off on sign in, and the same
//  pushed screens (the Social pages, Preferences, Apple Health, Data portability, Diagnostics).
//  In DEBUG builds the same Debug switches and buttons: rounded shapes, Cut design, launch
//  replay, barbell playground, the three year in review triggers and the Cut gallery.
//

import SwiftUI

struct CutSettingsHost: View {
    @EnvironmentObject private var authService: SupabaseAuthService
    @StateObject private var settings = AppSettings.shared
    @State private var badgeManager = NotificationBadgeManager.shared
    @State private var showLoginSheet = false
    @State private var destination: Destination?
    @ObservedObject private var workoutStore: WorkoutStoreV2 = AppDependencies.shared.workoutStore
    /// TestFlight tester switch: the latest choice, applied at the next launch.
    @State private var testerChoice = CutTesterSwitch.chosen()
    #if DEBUG
    @State private var showLaunchReplay = false
    @AppStorage(DS.Redesign.roundedShapesPreferenceKey)
    private var useRoundedShapes = DS.Redesign.roundedShapesDefault
    @AppStorage(DS.Redesign.cutPreferenceKey)
    private var useCut = DS.Redesign.cutDefault
    @AppStorage(CutYearAwardRendering.objectKey)
    private var yearAward3D = true
    @AppStorage(RunHistoryConfiguration.debugOptInKey)
    private var runHistoryMigrationOptIn = false
    @Environment(\.dependencies) private var dependencies
    #endif

    private enum Destination: Hashable {
        case myProfile(UUID)
        case activity, friends, friendRequests, findFriends
        case preferences, health, dataPortability, diagnostics
        #if DEBUG
        case barbellPlayground, cutGallery
        #endif
    }

    private var isLoggedIn: Bool {
        authService.currentUser != nil
    }

    private var model: CutSettingsModel {
        CutSettingsLogic.model(CutSettingsFacts(
            isLocalMode: settings.isLocalMode,
            isLoggedIn: isLoggedIn,
            activityCount: badgeManager.notificationCount,
            friendRequestCount: badgeManager.friendRequestCount,
            showsTesterSwitch: CutTesterSwitch.showsSwitch,
            testerChoice: testerChoice,
            runningNewDesign: DS.Redesign.cutEnabled,
            workoutActive: workoutStore.currentWorkout != nil
        ))
    }

    private var testerDesign: Binding<Bool> {
        Binding(
            get: { testerChoice },
            set: { on in
                testerChoice = on
                CutTesterSwitch.choose(on, workoutActive: workoutStore.currentWorkout != nil)
            }
        )
    }

    var body: some View {
        content
            .navigationDestination(item: $destination) { destination in
                destinationView(destination)
            }
            .task {
                if CutSettingsLogic.refreshesBadges(isLocalMode: settings.isLocalMode) {
                    await badgeManager.refreshBadges()
                }
            }
            .sheet(isPresented: $showLoginSheet) {
                NavigationStack {
                    LoginView()
                        .environmentObject(authService)
                }
            }
            #if DEBUG
            .fullScreenCover(isPresented: $showLaunchReplay) {
                LaunchClapView(sessionReady: true) {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { showLaunchReplay = false }
                }
                .presentationBackground(.clear)
            }
            #endif
            .onChange(of: isLoggedIn) { _, loggedIn in
                if CutSettingsLogic.leavesLocalMode(loggedIn: loggedIn, isLocalMode: settings.isLocalMode) {
                    settings.disableLocalMode()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        CutSettingsView(model: model, roundedShapes: $useRoundedShapes, cutDesign: $useCut,
                        yearAward3D: $yearAward3D, runHistoryMigration: $runHistoryMigrationOptIn,
                        runHistoryMigrationStatus: runHistoryMigrationStatus, testerDesign: testerDesign,
                        actions: actions)
        #else
        CutSettingsView(model: model, testerDesign: testerDesign, actions: actions)
        #endif
    }

    private var actions: CutSettingsActions {
        CutSettingsActions(
            openMyProfile: {
                if let id = authService.currentUser?.id { destination = .myProfile(id) }
            },
            openActivity: { destination = .activity },
            openFriends: { destination = .friends },
            openFriendRequests: { destination = .friendRequests },
            openFindFriends: { destination = .findFriends },
            openPreferences: { destination = .preferences },
            openHealth: { destination = .health },
            openDataPortability: { destination = .dataPortability },
            openDiagnostics: { destination = .diagnostics },
            logIn: { showLoginSheet = true },
            logOut: {
                Task {
                    try? await authService.signOut()
                }
            },
            debug: runDebug
        )
    }

    @ViewBuilder
    private func destinationView(_ destination: Destination) -> some View {
        switch destination {
        // The social rows wait until a made-up name is replaced, as the Social tab does.
        case .myProfile(let id):
            SocialNameGate(.socialSettings, authService: authService) { SocialProfileView(userId: id) }
        case .activity:
            SocialNameGate(.socialSettings, authService: authService) { ActivityFeedView() }
        case .friends:
            SocialNameGate(.socialSettings, authService: authService) { FriendsListView() }
        case .friendRequests:
            SocialNameGate(.socialSettings, authService: authService) { FriendRequestsView() }
        case .findFriends:
            SocialNameGate(.socialSettings, authService: authService) { UserSearchView() }
        case .preferences:
            PreferencesView()
        case .health:
            ConnectionsView()
        case .dataPortability:
            DataPortabilityView()
        case .diagnostics:
            DiagnosticsLogView()
        #if DEBUG
        case .barbellPlayground:
            BarbellPlaygroundView()
        case .cutGallery:
            CutGalleryView()
        #endif
        }
    }

    #if DEBUG
    private var runHistoryMigrationStatus: String {
        let store = dependencies.workoutStore
        return RunHistoryMigrationStatus.describe(
            migrated: store.isOnPerWorkoutHistory, optIn: runHistoryMigrationOptIn,
            argumentPresent: ProcessInfo.processInfo.arguments.contains(RunHistoryConfiguration.debugOptInArgument),
            attempts: store.runHistoryMigrationAttempts, last: store.lastRunHistoryMigration,
            merge: store.lastRunHistoryMerge)
    }
    #endif

    /// The legacy Debug buttons, unchanged.
    private func runDebug(_ row: CutSettingsModel.DebugRow) {
        #if DEBUG
        switch row {
        case .roundedShapes, .cutDesign, .yearAward3D, .runHistoryMigration:
            break
        case .replayLaunch:
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { showLaunchReplay = true }
        case .barbellPlayground:
            destination = .barbellPlayground
        case .yearReviewMine:
            let store = dependencies.workoutStore
            let year = Calendar.current.component(.year, from: .now)
            CutYearReviewCenter.shared.present(
                CutYearReviewLogic.stats(year: year, workouts: store.completedWorkouts, runs: store.runSummaries))
        case .yearReviewSample:
            let year = Calendar.current.component(.year, from: .now)
            CutYearReviewCenter.shared.present(.sample(year: year))
        case .yearReviewNextLaunch:
            UserDefaults.standard.removeObject(forKey: CutYearReviewLogic.seenYearKey)
            UserDefaults.standard.set(true, forKey: CutYearReviewLogic.forceNextLaunchKey)
        case .cutGallery:
            destination = .cutGallery
        }
        #endif
    }
}
