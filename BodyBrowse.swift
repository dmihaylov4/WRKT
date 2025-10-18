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

// MARK: - Flat exercise list for a subregion (legacy browseState flow)
struct MuscleExerciseListView: View {
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var store: WorkoutStore
    @State private var showingSessionFor: SessionSheetContext? = nil
    @Binding var state: BrowseState
    let subregion: String

    var body: some View {
        List(filtered) { ex in
            VStack(alignment: .leading, spacing: 4) {
                Text(ex.name).font(.body)
                Text("\(ex.category.capitalized) • \(ex.equipment ?? "Bodyweight")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { addAndLog(ex) }
            .contextMenu {
                Button("Add & Log") { addAndLog(ex) }
                Button("Add Only") { addOnly(ex) }
            }
        }
        .sheet(item: $showingSessionFor) { ctx in
            ExerciseSessionView(exercise: ctx.exercise, currentEntryID: ctx.id)
                .environmentObject(store)
        }
        .navigationTitle(subregion)
    }

    private var filtered: [Exercise] {
        let keys = MuscleMapper.synonyms(for: subregion)
        return repo.exercises.filter { ex in
            let muscles = (ex.primaryMuscles + ex.secondaryMuscles).map { $0.lowercased() }
            let name = ex.name.lowercased()
            let hitMuscle = muscles.contains(where: { m in keys.contains(where: { m.contains($0) }) })
            let hitName = keys.contains(where: { name.contains($0) })
            return hitMuscle || hitName
        }.sorted { $0.name < $1.name }
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
