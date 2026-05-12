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
        ScrollView {
            VStack(spacing: 16) {
                if !settings.isLocalMode && isLoggedIn {
                    settingsCard(title: "Social") {
                        if let currentUser = authService.currentUser {
                            settingsRow {
                                NavigationLink {
                                    SocialProfileView(userId: currentUser.id)
                                } label: {
                                    Label("My Profile", systemImage: "person.circle")
                                }
                            }
                        }

                        settingsRow {
                            NavigationLink {
                                ActivityFeedView()
                            } label: {
                                HStack {
                                    Label("Activity", systemImage: "bell.fill")
                                    Spacer()
                                    if badgeManager.notificationCount > 0 {
                                        badgeCount(badgeManager.notificationCount)
                                    }
                                }
                            }
                        }

                        settingsRow {
                            NavigationLink {
                                FriendsListView()
                            } label: {
                                Label("Friends", systemImage: "person.2.fill")
                            }
                        }

                        settingsRow {
                            NavigationLink {
                                FriendRequestsView()
                            } label: {
                                HStack {
                                    Label("Friend Requests", systemImage: "person.badge.plus")
                                    Spacer()
                                    if badgeManager.friendRequestCount > 0 {
                                        badgeCount(badgeManager.friendRequestCount)
                                    }
                                }
                            }
                        }

                        settingsRow(showsDivider: false) {
                            NavigationLink {
                                UserSearchView()
                            } label: {
                                Label("Find Friends", systemImage: "magnifyingglass")
                            }
                        }
                    }
                }

                settingsCard(title: "Preferences") {
                    settingsRow {
                        NavigationLink("App Preferences") { PreferencesView() }
                    }
                    settingsRow {
                        NavigationLink("Apple Health") { ConnectionsView() }
                    }
                    settingsRow {
                        NavigationLink {
                            BarbellEditorView()
                        } label: {
                            Label("My Barbell", systemImage: "scalemass.fill")
                        }
                    }
                    settingsRow(showsDivider: false) {
                        NavigationLink {
                            DataPortabilityView()
                        } label: {
                            Label("Data Portability", systemImage: "arrow.up.arrow.down.circle")
                        }
                    }
                }

                settingsCard(title: "Support") {
                    settingsRow(showsDivider: false) {
                        NavigationLink {
                            DiagnosticsLogView()
                        } label: {
                            Label("Diagnostics", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                }

                #if DEBUG
                settingsCard(title: "Debug") {
                    settingsRow {
                        NavigationLink("Virtual Run Debug") {
                            VirtualRunDebugView()
                                .environmentObject(authService)
                        }
                    }
                    settingsRow(showsDivider: false) {
                        NavigationLink {
                            BarbellPlaygroundView()
                        } label: {
                            Label("Barbell Playground", systemImage: "barbell")
                        }
                    }
                }
                #endif

                settingsCard {
                    if settings.isLocalMode {
                        settingsRow(showsDivider: false) {
                            Button {
                                showLoginSheet = true
                            } label: {
                                Label("Log In to Enable Social Features", systemImage: "person.crop.circle.badge.plus")
                            }
                        }
                    } else if isLoggedIn {
                        settingsRow(showsDivider: false) {
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 32)
        }
        .background(DS.Semantic.surface.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 24)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
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
            if loggedIn && settings.isLocalMode {
                settings.disableLocalMode()
            }
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .padding(.horizontal, 4)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(DS.Semantic.card, in: ChamferedRectangle(.xl))
            .overlay(
                ChamferedRectangle(.xl)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func settingsRow<Content: View>(
        showsDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            if showsDivider {
                Divider()
                    .overlay(.white.opacity(0.08))
                    .padding(.leading, 16)
            }
        }
        .tint(DS.Semantic.textPrimary)
    }

    private func badgeCount(_ count: Int) -> some View {
        Text("\(count)")
            .dsFont(.caption, weight: .bold)
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DS.Semantic.brand)
            .clipShape(Capsule())
    }
}
