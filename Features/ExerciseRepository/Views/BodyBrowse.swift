//
//  BodyBrowse.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//

import SwiftUI
import Combine

// MARK: - Root picker used by SearchView's browseState flow (kept for compatibility)
struct BodyBrowseRootView: View {
    @Binding var state: BrowseState
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                RegionCard(title: "Upper Body", systemImage: "figure.strengthtraining.traditional") {
                    state = .region(.upper)
                }
                RegionCard(title: "Lower Body", systemImage: "figure.step.training") {
                    state = .region(.lower)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
    }
}

struct RegionCard: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 28, weight: .semibold))
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            //.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .background(DS.Semantic.surface)
            .shadow(radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
    }
}

enum BodyRegion: String, CaseIterable, Hashable { case upper, lower }

// Legacy state enum (still used by SearchView and deep lists)
enum BrowseState: Hashable {
    case root
    case region(BodyRegion)
    case subregion(String)                    // e.g., "Chest"
    case deep(parent: String, child: String)  // e.g., ("Chest", "Upper Chest")
}

struct SubregionGridView: View {
    @Binding var state: BrowseState
    let region: BodyRegion
    var useNavigationLinks: Bool = false   // <–– new

    private var items: [String] { MuscleTaxonomy.subregions(for: region) }
    private let cols = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        ZStack{
            Color(DS.Semantic.surface)
                .ignoresSafeArea(edges: .all)
            ScrollView {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(items, id: \.self) { name in
                        if useNavigationLinks {
                            // Push onto the NavigationStack
                            NavigationLink(value: BrowseRoute.subregion(name)) {
                                //SubregionTile(title: name)
                            }
                        } else {
                            // Mutate local browse state (legacy flow)
                            Button { state = .subregion(name) } label: {
                                //SubregionTile(title: name)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            
            .navigationTitle(region == .upper ? "Upper Body" : "Lower Body")
        }
    }
}

/// Small reusable tile for subregions
//struct SubregionTile: View {
  //  let title: String
    //var body: some View {
      //  Text(title)
        //    .font(.headline)
          //  .frame(maxWidth: .infinity, minHeight: 80)
            //.background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    //}
//}
// MARK: - Sheet context used when starting a logging session
struct SessionSheetContext: Identifiable, Hashable {
    /// Use the entryID as the identity
    let id: UUID
    let exercise: Exercise
}

// BodyBrowse.swift — Difficulty palette + badge
private enum DifficultyTheme {
    // Dark-mode friendly hues, distinct from your main accent yellow (#F4E409)
    static let novice       = Color(hex: "#22C55E") // green-500
    static let beginner     = Color(hex: "#2DD4BF") // teal-400
    static let intermediate = Color(hex: "#F59E0B") // amber-500 (distinct from your brighter CTA yellow)
    static let advanced     = Color(hex: "#EF4444") // red-500

    static func color(for level: DifficultyLevel) -> Color {
        switch level {
        case .novice:       return novice
        case .beginner:     return beginner
        case .intermediate: return intermediate
        case .advanced:     return advanced
        }
    }
}

private struct DifficultyBadge: View {
    let level: DifficultyLevel
    var body: some View {
        let c = DifficultyTheme.color(for: level)
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(level.label)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(.white.opacity(0.9))
        .background(c.opacity(0.16), in: Capsule())
        .overlay(Capsule().stroke(c.opacity(0.35), lineWidth: 1))
        .accessibilityLabel("Difficulty: \(level.label)")
    }
}

// MARK: - Flat exercise list for a subregion (legacy browseState flow)
struct MuscleExerciseListView: View {
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var store: WorkoutStoreV2
    @State private var showingSessionFor: SessionSheetContext? = nil
    @Binding var state: BrowseState
    let subregion: String
    @EnvironmentObject var favs: FavoritesStore
    @AppStorage("equipFilter") private var equip: EquipBucket = .all
    @AppStorage("moveFilter")  private var move:  MoveBucket  = .all

    // Tutorial state
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var showTutorial = false
    @State private var currentTutorialStep = 0
    @State private var equipmentFilterFrame: CGRect = .zero
    @State private var movementFilterFrame: CGRect = .zero
    @State private var exerciseListFrame: CGRect = .zero
    @State private var framesReady = false

    // Debug: Set to true to visualize captured frames
    private let debugFrames = true

    private let stripeWidth: CGFloat = 3
    private let stripeGutter: CGFloat = 10

    var body: some View {
        ZStack {
            Group {
                if rows.isEmpty {
                    ScrollView {
                        EmptyExercisesView(
                            title: "No exercises found",
                            message: "Try loosening the equipment/movement filters or pick a different muscle.",
                            onClear: { equip = .all; move = .all }
                        )
                        .padding(.top, 16)
                    }
                    .background(DS.Semantic.surface)
                } else {
                    List(rows, id: \.id) { ex in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(ex.name).font(.body)
                                HStack(spacing: 6) {
                                    MetaPill(icon: EquipmentIcon.symbol(for: ex.equipment ?? ""),
                                             label: EquipmentIcon.label(for: ex.equipment ?? ""),
                                             tint: EquipmentIcon.color(for: ex.equipment ?? ""))
                                    MetaPill(icon: CategoryIcon.symbol(for: ex.category),
                                             label: ex.category.capitalized,
                                             tint: CategoryIcon.color(for: ex.category))
                                }
                            }
                            Spacer(minLength: 8)
                            //if let lvl = ex.difficultyLevel { DifficultyBadge(level: lvl) }
                            FavoriteHeartButton(exerciseID: ex.id)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { openSession(for: ex) }
                        .listRowSeparator(.hidden)
                        .listRowBackground(DS.Semantic.surface)
                        .padding(.leading, stripeWidth + stripeGutter)
                        .overlay(alignment: .leading) {
                            if let lvl = ex.difficultyLevel {
                                Rectangle()
                                    .fill(DifficultyTheme.color(for: lvl))
                                    .frame(width: stripeWidth)
                                    .allowsHitTesting(false)
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    .captureFrame(in: .global) { frame in
                        exerciseListFrame = frame
                        print("📍 Exercise list frame captured: \(frame)")
                        checkFramesReady()
                    }
                    .listStyle(.plain)
                    .background(DS.Semantic.surface)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: rows.map { $0.id })
                }
            }
            .safeAreaInset(edge: .top) {
                FiltersBar(
                    equip: $equip,
                    move: $move,
                    coordinateSpace: .global,
                    onEquipmentFrameCaptured: { frame in
                        equipmentFilterFrame = frame
                        print("📍 Equipment filter frame captured: \(frame)")
                        checkFramesReady()
                    },
                    onMovementFrameCaptured: { frame in
                        movementFilterFrame = frame
                        print("📍 Movement filter frame captured: \(frame)")
                        checkFramesReady()
                    }
                )
            }
            .sheet(item: $showingSessionFor) { ctx in
                ExerciseSessionView(
                    exercise: ctx.exercise,
                    initialEntryID: store.existingEntry(for: ctx.exercise.id)?.id,
                    returnToHomeOnSave: true
                )
                .environmentObject(store)
            }
            .navigationTitle(subregion)
            .toolbarBackground(DS.Semantic.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(DS.Semantic.surface.ignoresSafeArea())
            .onAppear {
                print("🎬 MuscleExerciseListView appeared")

                // Reset for testing
               // OnboardingManager.shared.hasSeenBodyBrowse = false

                // Fallback: if frames haven't loaded after 2.5 seconds, show tutorial anyway
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if !framesReady && !onboardingManager.hasSeenBodyBrowse && !showTutorial {
                        print("⚠️ Frames not ready after 2.5s, showing tutorial without spotlights")
                        print("   Equipment: \(equipmentFilterFrame)")
                        print("   Movement: \(movementFilterFrame)")
                        print("   List: \(exerciseListFrame)")
                        showTutorial = true
                    }
                }
            }
            .onChange(of: framesReady) { _, ready in
                // Show tutorial once frames are captured
                if ready && !onboardingManager.hasSeenBodyBrowse && !showTutorial {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        print("🎓 Showing tutorial with frames:")
                        print("   Equipment: \(equipmentFilterFrame)")
                        print("   Movement: \(movementFilterFrame)")
                        print("   List: \(exerciseListFrame)")
                        showTutorial = true
                    }
                }
            }

            // Tutorial overlay
            if showTutorial {
                SpotlightOverlay(
                    currentStep: tutorialSteps[currentTutorialStep],
                    currentIndex: currentTutorialStep,
                    totalSteps: tutorialSteps.count,
                    onNext: advanceTutorial,
                    onSkip: skipTutorial
                )
                .transition(.opacity)
                .zIndex(1000)
            }

           
        }
    }

    private var rows: [Exercise] {
        // 1) by primary muscle - use byID index (contains all exercises)
        let keys = MuscleMapper.synonyms(for: subregion)
        let primary = repo.byID.values.filter { ex in
            let prim = ex.primaryMuscles.map { $0.lowercased() }
            return prim.contains { m in keys.contains { key in m.contains(key) } }
        }

        // 2) filters via normalized buckets (robust)
        let byEquip = (equip == .all) ? primary : primary.filter { $0.equipBucket == equip }
        let byMove  = (move  == .all) ? byEquip  : byEquip.filter  { $0.moveBucket  == move  }

        // 3) sort
        let base = byMove.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
           return favoritesFirst(base, favIDs: favs.ids)
    }

    private func openSession(for ex: Exercise) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showingSessionFor = SessionSheetContext(id: UUID(), exercise: ex)
    }

    // MARK: - Tutorial Logic

    private func checkFramesReady() {
        // Check if all frames have been captured and are valid
        let equipReady = equipmentFilterFrame != .zero && equipmentFilterFrame.width > 0
        let moveReady = movementFilterFrame != .zero && movementFilterFrame.width > 0
        let listReady = exerciseListFrame != .zero && exerciseListFrame.height > 0

        print("🔍 Frame readiness check:")
        print("   Equipment ready: \(equipReady) - \(equipmentFilterFrame)")
        print("   Movement ready: \(moveReady) - \(movementFilterFrame)")
        print("   List ready: \(listReady) - \(exerciseListFrame)")

        if equipReady && moveReady && listReady && !framesReady {
            print("✅ All frames ready for tutorial!")
            framesReady = true
        } else if !framesReady {
            print("⏳ Still waiting for frames...")
        }
    }

    private var tutorialSteps: [TutorialStep] {
        [
            TutorialStep(
                title: "Equipment Filters",
                message: "Tap any equipment type to filter exercises. Double-tap a chip to reset the filter.",
                spotlightFrame: CGRect(
                    x: equipmentFilterFrame.origin.x,
                    y: equipmentFilterFrame.origin.y,
                    width: equipmentFilterFrame.width,
                    height: equipmentFilterFrame.height + 8
                ),  // Only expand downward to avoid cutoff at top
                tooltipPosition: .bottom,
                highlightCornerRadius: 16
            ),
            TutorialStep(
                title: "Movement Filters",
                message: "Filter exercises by movement pattern. Combine with equipment filters for precise results.",
                spotlightFrame: CGRect(
                    x: movementFilterFrame.origin.x,
                    y: movementFilterFrame.origin.y,
                    width: movementFilterFrame.width,
                    height: movementFilterFrame.height + 8
                ),  // Only expand downward to avoid cutoff
                tooltipPosition: .bottom,
                highlightCornerRadius: 16
            ),
            TutorialStep(
                title: "Exercise List",
                message: "Each exercise shows equipment and category tags. The colored stripe indicates difficulty level. Tap the heart to favorite, tap the exercise to start a workout.",
                spotlightFrame: CGRect(
                    x: exerciseListFrame.origin.x,
                    y: max(0, exerciseListFrame.origin.y - 8),  // Expand upward but not beyond screen bounds
                    width: exerciseListFrame.width,
                    height: exerciseListFrame.height + 16  // Expand both up and down
                ),
                tooltipPosition: .bottom,
                highlightCornerRadius: 20
            )
        ]
    }

    private func advanceTutorial() {
        if currentTutorialStep < tutorialSteps.count - 1 {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentTutorialStep += 1
            }
        } else {
            completeTutorial()
        }
    }

    private func skipTutorial() {
        completeTutorial()
    }

    private func completeTutorial() {
        withAnimation(.easeOut(duration: 0.2)) {
            showTutorial = false
        }
        onboardingManager.complete(.bodyBrowse)
    }
}

struct FiltersBar: View {
    @Binding var equip: EquipBucket
    @Binding var move:  MoveBucket
    var coordinateSpace: CoordinateSpace = .global
    var onEquipmentFrameCaptured: ((CGRect) -> Void)? = nil
    var onMovementFrameCaptured: ((CGRect) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Equipment Row
            VStack(alignment: .leading, spacing: 6) {
                Text("EQUIPMENT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(DS.Semantic.textSecondary.opacity(0.7))
                    .padding(.horizontal, 16)

                ChipRow(all: EquipBucket.allCases, selected: $equip) { tapped in
                    equip = (tapped == equip ? .all : tapped)
                } onClear: {
                    equip = .all
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 10)
            .captureFrame(in: coordinateSpace) { frame in
                onEquipmentFrameCaptured?(frame)
            }

            // Subtle divider
            Rectangle()
                .fill(DS.Semantic.border.opacity(0.3))
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            // Movement Row
            VStack(alignment: .leading, spacing: 6) {
                Text("MOVEMENT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(DS.Semantic.textSecondary.opacity(0.7))
                    .padding(.horizontal, 16)

                ChipRow(all: MoveBucket.allCases, selected: $move) { tapped in
                    move = (tapped == move ? .all : tapped)
                } onClear: {
                    move = .all
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 12)
            .captureFrame(in: coordinateSpace) { frame in
                onMovementFrameCaptured?(frame)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(DS.Semantic.surface)
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }
}

private struct ChipRow<T: CaseIterable & Hashable & RawRepresentable>: View where T.AllCases: RandomAccessCollection, T.RawValue == String {
    let all: T.AllCases
    @Binding var selected: T
    let onTap: (T) -> Void
    let onClear: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(all), id: \.self) { bucket in
                        SelectChip(
                            title: bucket.rawValue,
                            selected: bucket == selected,
                            tap: {
                                onTap(bucket)
                            },
                            clear: onClear
                        )
                        .id(bucket)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
            .onAppear {
                // Scroll to initial selection without animation
                proxy.scrollTo(selected, anchor: .center)
            }
            .onChange(of: selected) { _, newValue in
                // Smoothly scroll to newly selected chip
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}

private struct SelectChip: View {
    let title: String
    let selected: Bool
    let tap: () -> Void
    let clear: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                tap()
            }
        }) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .medium))
                .foregroundStyle(selected ? DS.Palette.marone : DS.Semantic.textPrimary.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if selected {
                            Capsule()
                                .fill(DS.Palette.marone.opacity(0.15))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(DS.Palette.marone.opacity(0.5), lineWidth: 1.5)
                                )
                        } else {
                            Capsule()
                                .fill(DS.Semantic.surface50.opacity(0.3))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(DS.Semantic.border.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
        // Double-tap anywhere on the chip clears the current filter row
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    clear()
                }
            }
        )
        .onLongPressGesture(minimumDuration: 0.0, maximumDistance: 50) {
            // On release
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selected ? "Double tap to clear filter" : "Tap to select")
    }
}

// MARK: - Helpers

enum MuscleMapper {
    static func synonyms(for name: String) -> [String] {
        switch name.lowercased() {
        case "chest": return ["chest","pectoralis","pec"]
        case "back": return ["back","lat","lats","latissimus","trapezius","trap","rhomboid"]
        case "shoulders": return ["shoulder","deltoid","delts"]
        case "biceps": return ["bicep","biceps"]
        case "triceps": return ["tricep","triceps"]
        case "forearms": return ["forearm","brachioradialis","flexor","extensor"]
        case "abs": return ["abs","abdominals","rectus abdominis"]
        case "obliques": return ["oblique"]
        case "glutes": return ["glute","gluteus","butt"]
        case "quads": return ["quad","quadriceps","vastus","rectus femoris"]
        case "hamstrings": return ["hamstring","biceps femoris","semitendinosus","semimembranosus"]
        case "calves": return ["calf","gastrocnemius","soleus"]
        case "adductors": return ["adductor","adductors","inner thigh"]
        case "abductors": return ["abductor","abductors","outer thigh","glute medius","glute minimus"]
        default: return [name.lowercased()]
        }
    }
}


// BodyBrowse.swift — Difficulty filter model + chip

private enum DifficultyFilter: CaseIterable, Hashable {
    case all, novice, beginner, intermediate, advanced

    var label: String {
        switch self {
        case .all: "All"
        case .novice: "Novice"
        case .beginner: "Beginner"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        }
    }

    var level: DifficultyLevel? {
        switch self {
        case .all: nil
        case .novice: .novice
        case .beginner: .beginner
        case .intermediate: .intermediate
        case .advanced: .advanced
        }
    }
}

private struct MetaPill: View {
    let icon: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(label)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.18), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
    }
}

private struct DifficultyChip: View {
    let filter: DifficultyFilter
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let c: Color = {
            if let lvl = filter.level { return DifficultyTheme.color(for: lvl) }
            return Color.white.opacity(0.75) // neutral for "All"
        }()

        Button(action: onTap) {
            HStack(spacing: 8) {
                if filter != .all {
                    Circle().fill(c).frame(width: 8, height: 8)
                }
                Text(filter.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                (isSelected ? c.opacity(0.22) : Color.clear),
                in: Capsule()
            )
            
            .overlay(
                Capsule().stroke(c.opacity(isSelected ? 0.55 : 0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter: \(filter.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
enum EquipmentIcon {
    static func symbol(for equipment: String) -> String {
        switch equipment.lowercased() {
        case "kettlebell":                   return "dumbbell.fill"      // use “kettlebell” if your iOS target has it
        case "dumbbell":                     return "dumbbell.fill"
        case "barbell", "ez bar", "trap bar":return "dumbbell.fill"
        case "cable", "cable machine":       return "cable.connector.horizontal" // generic-ish
        case "band", "resistance band":      return "bandage.fill"       // closest neutral icon
        case "machine":                      return "rectangle.compress.vertical"
        case "smith machine":                return "square.3.layers.3d"
        case "bodyweight", "none":           return "figure.walk"
        default:                             return "hammer.fill"         // generic tool fallback
        }
    }

    static func label(for equipment: String) -> String {
        let s = equipment.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "Bodyweight" : s
    }

    static func color(for equipment: String) -> Color {
        switch equipment.lowercased() {
        case "kettlebell": return Color(hex: "#F97316") // orange-ish
        case "dumbbell":   return Color(hex: "#60A5FA") // blue
        case "barbell", "ez bar", "trap bar": return Color(hex: "#A3A3A3")
        case "cable", "cable machine": return Color(hex: "#34D399") // green
        case "band", "resistance band": return Color(hex: "#F59E0B") // amber
        case "machine", "smith machine": return Color(hex: "#A78BFA") // violet
        case "bodyweight", "none": return Color.secondary
        default: return DS.Palette.marone
        }
    }
}

private enum CategoryIcon {
    static func symbol(for category: String) -> String {
        switch category.lowercased() {
        case "bodybuilding", "hypertrophy":
            return "figure.strengthtraining.traditional"
        case "powerlifting", "strength":
            return "scalemass" // if unavailable, fallback below
        case "conditioning", "hiit", "metcon":
            return "flame.fill"
        case "mobility", "rehab", "prehab":
            return "figure.mind.and.body" // fallback below if needed
        case "plyometrics":
            return "arrow.up.forward.circle.fill"
        default:
            return "bolt.heart" // generic training category
        }
    }

    static func color(for category: String) -> Color {
        switch category.lowercased() {
        case "bodybuilding", "hypertrophy": return Color(hex: "#F472B6") // pink-ish
        case "powerlifting", "strength":    return Color(hex: "#FB923C") // orange
        case "conditioning", "hiit":        return Color(hex: "#22D3EE") // cyan
        case "mobility", "rehab", "prehab": return Color(hex: "#4ADE80") // green
        case "plyometrics":                 return Color(hex: "#C084FC") // violet
        default:                            return DS.Palette.marone
        }
    }
}


struct FavoriteHeartButton: View {
    @EnvironmentObject private var favs: FavoritesStore
    let exerciseID: String
    var size: CGFloat = 22
    var filledTint: Color = .red

    var body: some View {
        let isFav = favs.contains(exerciseID)
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                favs.toggle(exerciseID)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: isFav ? "heart.fill" : "heart")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isFav ? filledTint : .secondary)
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
                .symbolEffect(.bounce, value: isFav)
                .scaleEffect(isFav ? 1.0 : 0.95)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFav ? "Remove from favorites" : "Add to favorites")
        .accessibilityAddTraits(isFav ? .isSelected : [])
    }
}
