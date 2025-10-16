//
//  MuscleTaxonomy.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//

import Foundation
import SwiftUI
private enum Theme {
    static let bg        = Color.black                 // app background
    static let surface   = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let surface2  = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border    = Color.white.opacity(0.10)
    static let text      = Color.white
    static let secondary = Color.white.opacity(0.65)
    static let accent    = Color(hex: "#F4E409")
}


enum MuscleTaxonomy {

    static func subregions(for region: BodyRegion) -> [String] {
        switch region {
        case .upper:
            return ["Chest","Back","Shoulders","Biceps","Triceps","Forearms","Abs","Obliques"]
        case .lower:
            return ["Glutes","Quads","Hamstrings","Calves","Adductors","Abductors"]
        }
    }

    /// Optional deeper layer for a given subregion (no JSON changes required).
    static func deepSubregions(for subregion: String) -> [String]? {
        switch subregion.lowercased() {
        case "chest":
            return ["Upper Chest","Mid Chest","Lower Chest"]
        case "back":
            return ["Lats","Mid-Back","Lower Back","Traps/Rear Delts"]
        default:
            return nil
        }
    }
    
    
    
    /// Keyword rules to classify into deep subregions (heuristics).
    // MuscleTaxonomy.swift — add this full implementation
    static func deepRules(parent: String, child: String) -> (include: [String], exclude: [String]) {
        let p = parent.lowercased()
        let c = child.lowercased()

        if p == "chest" {
            if c.contains("upper") {
                // e.g., incline bench/press/fly, clavicular head
                return (["incline", "upper", "clavicular"], ["decline", "lower"])
            }
            if c.contains("mid") || c.contains("middle") {
                // avoid incline/decline bias
                return (["flat", "press", "bench", "fly"], ["incline", "decline"])
            }
            if c.contains("lower") {
                return (["decline", "dip", "lower"], ["incline", "upper"])
            }
        }

        if p == "back" {
            if c.contains("lat") {
                return (["lat", "pulldown", "pull-up", "pullup", "chin-up", "row"], ["hyperextension", "good morning"])
            }
            if c.contains("mid") {
                return (["row", "rhomboid", "retraction", "seated row", "t-bar"], [])
            }
            if c.contains("lower") {
                return (["hyperextension", "roman chair", "back extension", "good morning"], [])
            }
            if c.contains("trap") || c.contains("rear") || c.contains("delt") {
                return (["shrug", "face pull", "upright row", "rear delt"], [])
            }
        }

        // Generic fallback: look for the child phrase in name or muscles
        return ([c], [])
    }
}
struct MuscleRouterView: View {
    @Binding var state: BrowseState
    let subregion: String
    var useNavigationLinks: Bool = false    // << NEW

    var body: some View {
        if let deep = MuscleTaxonomy.deepSubregions(for: subregion), !deep.isEmpty {
            DeepSubregionGridView(state: $state, parent: subregion, items: deep, useNavigationLinks: useNavigationLinks)
        } else {
            MuscleExerciseListView(state: $state, subregion: subregion)
        }
    }
}
struct DeepSubregionGridView: View {
    @Binding var state: BrowseState
    let parent: String
    let items: [String]
    var useNavigationLinks: Bool = false
    private let cols = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(items, id: \.self) { name in
                    let chip = Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.border, lineWidth: 1)
                        )

                    if useNavigationLinks {
                        NavigationLink(value: BrowseRoute.deep(parent: parent, child: name)) { chip }
                            .buttonStyle(.plain)
                    } else {
                        Button { state = .deep(parent: parent, child: name) } label: { chip }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(parent)
        .navigationBarTitleDisplayMode(.inline)
    }
}
private struct ExerciseRowCompact: View {
    let ex: Exercise
    let onPrimary: () -> Void     // Add & Log (row tap)
    let onAddOnly: () -> Void     // quick action

    private var meta: String {
        "\(ex.category.capitalized) • \(ex.equipment ?? "Bodyweight")"
    }
    
    private var highlights: MuscleIconMapper.Highlights { MuscleIconMapper.highlights(for: ex) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            MusclePictogram(primary: highlights.primary, secondary: highlights.secondary, size: 42)
                       .frame(width: 90, alignment: .leading) // a bit wider so it breathes
            
           
            
            VStack(alignment: .leading, spacing: 4) {
                Text(ex.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }

            Spacer(minLength: 12)

            // Small accent pill for quick "Add Only"
            Button("Add") { onAddOnly() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.accent, in: Capsule())
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onPrimary() } // Add & Log
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Add Only") { onAddOnly() }
                .tint(.gray)
            Button("Add & Log") { onPrimary() }
                .tint(Theme.accent)
        }
        .contextMenu {
            Button("Add & Log", action: onPrimary)
            Button("Add Only", action: onAddOnly)
        }
    }
}

struct MuscleExerciseListDeepView: View {
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var store: WorkoutStore
    @Binding var state: BrowseState
    let parent: String
    let child: String

    @State private var showingSessionFor: SessionSheetContext? = nil

    // Match the grab tab height (you’re using ~65px in AppShellView)
    private let grabTabHeight: CGFloat = 65

    private var hasActiveWorkout: Bool {
        guard let current = store.currentWorkout else { return false }
        return !current.entries.isEmpty
    }

    var body: some View {
        List(filtered) { ex in
            ExerciseRowCompact(ex: ex) {
                addAndLog(ex)
            } onAddOnly: {
                addOnly(ex)
            }
            .listRowInsets(.init(top: 0, leading: 0, bottom: 8, trailing: 0)) // full-bleed + 16 inner
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.surface)
            .padding(.horizontal, 16) // keep rows aligned with the global 16pt grid
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(child)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $showingSessionFor) { ctx in
            ExerciseSessionView(exercise: ctx.exercise, currentEntryID: ctx.id)
                .environmentObject(store)
        }
        // keep content above the live grab tab
        .safeAreaInset(edge: .bottom) {
            if hasActiveWorkout {
                Color.clear
                    .frame(height: grabTabHeight + 8) // a little breathing room
            }
        }
    }

    private var filtered: [Exercise] {
        repo.deepExercises(parent: parent, child: child)
    }

    private func addAndLog(_ ex: Exercise) {
        let entryID = store.addExerciseToCurrent(ex)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        state = .root
        showingSessionFor = SessionSheetContext(id: entryID, exercise: ex)
    }

    private func addOnly(_ ex: Exercise) {
        _ = store.addExerciseToCurrent(ex)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        state = .root
    }
}
