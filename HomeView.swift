//
//  HomeView.swift
//  WRKT
//

import SwiftUI
import SwiftData

// MARK: - Routes the Home stack can push to
enum BrowseRoute: Hashable {
    case region(BodyRegion)
    case subregion(String)                    // e.g. "Chest"
    case deep(parent: String, child: String)  // e.g. ("Chest","Upper Chest")
}

struct HomeView: View {
    @EnvironmentObject var store: WorkoutStore
    @State private var path = NavigationPath()

    @Query private var goals: [WeeklyGoal]
    
    @Environment(\.modelContext) private var context
    //DELETED BECAUSE ONBOARDING
    //@State private var showGoalSetup = false

    // Split animation state
    @Namespace private var regionNS
    @State private var expandedRegion: BodyRegion? = nil
    @State private var showTiles = false

    private var hasActiveWorkout: Bool {
        guard let current = store.currentWorkout else { return false }
        return !current.entries.isEmpty
    }
    
    
    private func collapsePanel(animated: Bool = true) {
        let anim = Animation.spring(response: 0.45, dampingFraction: 0.85)
        if animated {
            withAnimation(anim) { showTiles = false; expandedRegion = nil }
        } else {
            showTiles = false; expandedRegion = nil
        }
    }
    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                // ROOT: two big, styled cards
                if expandedRegion == nil {
                    VStack(spacing: 8) {
                        RegionSquareLarge(
                            title: "Upper Body",
                            systemImage: "figure.strengthtraining.traditional",
                            matchedID: "region-upper",
                            namespace: regionNS,
                            tint: DS.Palette.marone
                        ) {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                expandedRegion = .upper
                                showTiles = true
                            }
                        }

                        RegionSquareLarge(
                            title: "Lower Body",
                            systemImage: "figure.step.training",
                            matchedID: "region-lower",
                            namespace: regionNS,
                            tint: DS.Palette.marone
                        ) {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                expandedRegion = .lower
                                showTiles = true
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .scale))
                }

                // EXPANDED: the selected card morphs into a panel with subregion tiles
                if let region = expandedRegion {
                    ExpandedRegionPanel(
                        region: region,
                        namespace: regionNS,
                        matchedID: region == .upper ? "region-upper" : "region-lower",
                        showTiles: showTiles,
                        onCollapse: {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                showTiles = false
                                expandedRegion = nil
                            }
                        },
                        onSelectSubregion: { name in
                            path.append(BrowseRoute.subregion(name))
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .navigationTitle("Pick your poison")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: BrowseRoute.self) { route in
                switch route {
                case .region(let r):
                    SubregionGridView(state: .constant(.region(r)), region: r, useNavigationLinks: true)
                case .subregion(let name):
                    MuscleExerciseListView(
                          state: .constant(.subregion(name)),
                          subregion: name
                      )
                case .deep(let parent, let child):
                    SubregionDetailScreen(subregion: parent, preselectedDeep: child)
                }
            }
    
            .onReceive(NotificationCenter.default.publisher(for: .resetHomeToRoot)) { _ in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    path = NavigationPath()
                    expandedRegion = nil
                    showTiles = false
                }
            }
            // Reserve room for the grab tab ONLY when a workout is active
            .safeAreaInset(edge: .bottom) {
                if hasActiveWorkout { Color.clear.frame(height: 65) }
            }
            .background(DS.Semantic.surface)                               // ← keep it local
            .toolbarBackground(DS.Semantic.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openHomeRoot)) { _ in
            expandedRegion = nil
            showTiles = false
            path = .init()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabSelectionChanged)) { _ in
            collapsePanel()
        }
        .onDisappear {            // if TabView swaps away from Home
            collapsePanel(animated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeTabReselected)) { _ in
            print("🏠 HomeView: Received homeTabReselected notification")
            // Reset to root state when Home tab is re-tapped
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                path = NavigationPath()
                expandedRegion = nil
                showTiles = false
            }
        }
       // .onAppear {
            // Check if weekly goal is set, show setup if not
            //if let goal = goals.first, !goal.isSet {
              //  showGoalSetup = true
            //} else if goals.isEmpty {
            //    showGoalSetup = true
          //  }
        //}
       // .sheet(isPresented: $showGoalSetup) {
         //   NavigationStack {
           //     WeeklyGoalSetupView(goal: goals.first)
             //       .interactiveDismissDisabled() // Require user to set goal
           // }
       // }
        //.tint(DS.Semantic.brand)

    }
}

// MARK: - Big tappable “region” cards

private struct RegionSquareLarge: View {
    let title: String
    let systemImage: String
    let matchedID: String
    let namespace: Namespace.ID
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            ZStack {
                let bg = RoundedRectangle(cornerRadius: 20, style: .continuous)
                bg
                    .fill(
                        LinearGradient(
                            colors: [tint.lighten(0.10), tint.darken(0.06)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .matchedGeometryEffect(id: matchedID, in: namespace)
                    .overlay(bg.stroke(tint.darken(0.12).opacity(0.25), lineWidth: 1))

                VStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 36, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(DS.Semantic.surface)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(DS.Semantic.surface)
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 12)
            }
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PressCardStyle()) // ← feedback
        .frame(maxWidth: .infinity, minHeight: 140)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
    }
}

// MARK: - Expanded panel + tiles

private struct ExpandedRegionPanel: View {
    let region: BodyRegion
    let namespace: Namespace.ID
    let matchedID: String
    let showTiles: Bool
    let onCollapse: () -> Void
    let onSelectSubregion: (String) -> Void

    private var title: String {
        region == .upper ? "Upper Body" : "Lower Body"
    }
    private var accent: Color {
        region == .upper ? DS.Palette.marone : DS.Palette.marone
    }
    private var items: [String] {
        MuscleTaxonomy.subregions(for: region)
    }

    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: region == .upper ? "figure.strengthtraining.traditional" : "figure.step.training")
                    .font(.headline)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    Haptics.soft()
                    onCollapse()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DS.Palette.marone)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
            .padding(.horizontal, 14)

            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(items, id: \.self) { name in
                    Button {
                        Haptics.light()
                        onSelectSubregion(name)
                    } label: {
                        SubregionTile(title: name, accent: accent)
                    }
                    .buttonStyle(PressTileStyle()) // ← feedback
                    .transition(.opacity.combined(with: .scale))
                }
            }
            
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .opacity(showTiles ? 1 : 0)
            .scaleEffect(showTiles ? 1 : 0.98, anchor: .top)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showTiles)
        }
        .background(
            // Use your card surface for consistency (not .thinMaterial)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DS.Semantic.surface)
                .matchedGeometryEffect(id: matchedID, in: namespace)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}



private struct SubregionTile: View {
    let title: String
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            // tiny accent dot for hierarchy
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .font(.footnote)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(DS.Semantic.fillSubtle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
        .foregroundStyle(DS.Semantic.textPrimary)
        .contentShape(Rectangle())
    }
}





private extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >>  8) & 0xFF) / 255.0
        let b = Double( v        & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

