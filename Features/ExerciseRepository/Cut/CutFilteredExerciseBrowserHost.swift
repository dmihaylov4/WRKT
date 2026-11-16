import SwiftUI

struct CutFilteredExerciseBrowserHost: View {
    let muscleFilter: MuscleFilter?
    let title: String
    @Environment(\.cutSheetDepth) private var sheetDepth
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []
    var body: some View {
        NavigationStack(path: $path) {
            CutFilteredExerciseBrowserView(model: CutFilteredExerciseBrowserLogic.model(filter: muscleFilter, title: title),
                select: { path.append($0) }, done: { dismiss() })
                .navigationDestination(for: String.self) { subregion in
                    MuscleExerciseListView(state: .constant(.subregion(subregion)), subregion: subregion)
                        .toolbar(.visible, for: .navigationBar)
                        .environment(\.cutSheetDepth, sheetDepth + 1)
                }
        }
    }
}
