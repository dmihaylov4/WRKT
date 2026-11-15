import SwiftUI

struct CutExerciseInfoHost<Stats: View>: View {
    let exercise: Exercise
    let meta: ExerciseGuideMeta
    let progression: ProgressionSuggestion?
    let unit: WeightUnit
    let done: () -> Void
    @ViewBuilder var stats: () -> Stats
    @Environment(\.cutSheetDepth) private var sheetDepth
    @EnvironmentObject private var repo: ExerciseRepository
    @ObservedObject private var preferences = RestTimerPreferences.shared
    @State private var tab = CutExerciseInfoModel.Tab.info
    @State private var editing = false
    @State private var showingTimer = false
    @State private var expandedCues = false

    var body: some View {
        let model = CutExerciseInfoLogic.model(exercise: exercise, meta: meta, videoURL: repo.media(for: exercise)?.youtube,
            progression: progression, unit: unit, restSeconds: preferences.restDuration(for: exercise).safeInt,
            hasOverride: preferences.hasOverride(for: exercise.id))
        NavigationStack {
            CutExerciseInfoView(model: model, tab: tab, expandedCues: expandedCues, actions: .init(tab: { tab = $0 },
                edit: { editing = true }, done: done, timer: { showingTimer = true }, toggleCues: { expandedCues.toggle() }),
                stats: stats, video: {
                    if let url = model.videoURL { YouTubePlayerView(url: url) }
                }, anatomy: {
                    // Keep the existing front/back SVGs and all three muscle layers. In Cut,
                    // neutral intensity carries the highlights instead of extra accent colours.
                    HStack(spacing: 12) {
                        bodySide(.front)
                        bodySide(.back)
                    }
                    .saturation(0)
                })
                .navigationDestination(isPresented: $showingTimer) {
                    CustomTimerEditorView(exercise: exercise).toolbar(.visible, for: .navigationBar)
                }
                .sheet(isPresented: $editing) {
                    CreateExerciseView(preselectedMuscle: exercise.primaryMuscles.first ?? "", editingExercise: exercise)
                        .environmentObject(CustomExerciseStore.shared)
                        .environmentObject(repo)
                        .environment(\.cutSheetDepth, sheetDepth + 1)
                }
        }
    }

    private func bodySide(_ side: SVGHumanBodyView.Side) -> some View {
        SVGHumanBodyView(side: side, focus: .full, primary: Set(exercise.primaryMuscles.map(\.trimmed)),
                         secondary: Set(exercise.secondaryMuscles.map(\.trimmed)),
                         tertiary: Set(exercise.tertiaryMuscles.map(\.trimmed)))
            .frame(maxWidth: .infinity)
            .aspectRatio(0.56, contentMode: .fit)
    }
}
