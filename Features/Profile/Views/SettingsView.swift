//
//  SettingsView.swift
//  WRKT
//
//  Settings view containing social features and app preferences
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authService: SupabaseAuthService
    @StateObject private var settings = AppSettings.shared
    @State private var badgeManager = NotificationBadgeManager.shared
    @State private var showLoginSheet = false

    private var isLoggedIn: Bool {
        authService.currentUser != nil
    }

    var body: some View {
        List {
            // SOCIAL - only show when not in local mode and logged in
            if !settings.isLocalMode && isLoggedIn {
                Section("Social") {
                    if let currentUser = authService.currentUser {
                        NavigationLink {
                            SocialProfileView(userId: currentUser.id)
                        } label: {
                            Label("My Profile", systemImage: "person.circle")
                        }
                    }

                    NavigationLink {
                        ActivityFeedView()
                    } label: {
                        HStack {
                            Label("Activity", systemImage: "bell.fill")

                            Spacer()

                            if badgeManager.notificationCount > 0 {
                                Text("\(badgeManager.notificationCount)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(DS.Semantic.brand)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    NavigationLink {
                        FriendsListView()
                    } label: {
                        Label("Friends", systemImage: "person.2.fill")
                    }

                    NavigationLink {
                        FriendRequestsView()
                    } label: {
                        HStack {
                            Label("Friend Requests", systemImage: "person.badge.plus")

                            Spacer()

                            if badgeManager.friendRequestCount > 0 {
                                Text("\(badgeManager.friendRequestCount)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(DS.Semantic.brand)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    NavigationLink {
                        UserSearchView()
                    } label: {
                        Label("Find Friends", systemImage: "magnifyingglass")
                    }
                }
            }

            // PREFERENCES
            Section("Preferences") {
                NavigationLink("App Preferences") { PreferencesView() }
                NavigationLink("Apple Health") { ConnectionsView() }
            }

            #if DEBUG
            Section("Debug") {
                NavigationLink("Virtual Run Debug") {
                    VirtualRunDebugView()
                        .environmentObject(authService)
                }
            }
            #endif

            // ACCOUNT
            Section {
                if settings.isLocalMode {
                    // Local mode - show Log In option
                    Button {
                        showLoginSheet = true
                    } label: {
                        Label("Log In to Enable Social Features", systemImage: "person.crop.circle.badge.plus")
                    }
                } else if isLoggedIn {
                    // Logged in - show Log Out option
                    Button(role: .destructive) {
                        Task {
                            try? await authService.signOut()
                        }
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Refresh badges when view appears (only if not in local mode)
            if !settings.isLocalMode {
                await badgeManager.refreshBadges()
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            NavigationStack {
                LoginView()
                    .environmentObject(authService)
            }
        }
        .onChange(of: isLoggedIn) { _, loggedIn in
            // When user successfully logs in, disable local mode to show social tab
            if loggedIn && settings.isLocalMode {
                settings.disableLocalMode()
            }
        }
    }
}
