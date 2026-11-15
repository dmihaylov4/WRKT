import SwiftUI

struct CutExerciseInfoActions {
    var tab: (CutExerciseInfoModel.Tab) -> Void = { _ in }
    var edit: () -> Void = {}
    var done: () -> Void = {}
    var timer: () -> Void = {}
    var toggleCues: () -> Void = {}
}

struct CutExerciseInfoView<Stats: View, Video: View, Muscles: View>: View {
    let model: CutExerciseInfoModel
    var tab = CutExerciseInfoModel.Tab.info
    var expandedCues = false
    var actions = CutExerciseInfoActions()
    @ViewBuilder var stats: () -> Stats
    @ViewBuilder var video: () -> Video
    @ViewBuilder var anatomy: () -> Muscles

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        CutSheet("Exercise details", kind: .browser, scrollsContent: tab != .stats || dynamicTypeSize.isAccessibilitySize, close: actions.done) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.title.uppercased())
                        .font(DS.Cut.Typography.condensed(size: 26, relativeTo: .title2))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if !model.metadata.isEmpty {
                        Text(model.metadata).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.vertical, 16)
                ViewThatFits(in: .horizontal) {
                    tabButtons(vertical: false)
                    tabButtons(vertical: true)
                }.padding(.horizontal, DS.Cut.Metrics.gutter).padding(.bottom, 16)
                if model.canEdit {
                    Button("Edit exercise", action: actions.edit).buttonStyle(CutPillButtonStyle(.outline))
                        .padding(.horizontal, DS.Cut.Metrics.gutter).padding(.bottom, 12)
                }
                switch tab {
                case .info: information
                case .timer:
                    Group {
                        VStack(alignment: .leading, spacing: 0) {
                            CutHairline()
                            Button(action: actions.timer) {
                                CutHairlineRow("Rest Timer", value: model.restTime, subtitle: model.restSource, showsChevron: true)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(DS.Cut.Metrics.gutter)
                    }
                case .stats:
                    stats().frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 400 : nil)
                }
            }
        }
    }

    private func tabButtons(vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ForEach(CutExerciseInfoModel.Tab.allCases, id: \.self) { item in
                Button(item.rawValue) { actions.tab(item) }
                    .buttonStyle(CutPillButtonStyle(item == tab ? .white : .outline))
                    .accessibilityAddTraits(item == tab ? .isSelected : [])
            }
        }
    }

    private var information: some View {
        Group {
            VStack(alignment: .leading, spacing: 24) {
                if model.videoURL != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tutorial").cutFont(.title)
                        video().frame(height: 220).clipped()
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Muscles Worked").cutFont(.title)
                    anatomy()
                    VStack(spacing: 0) {
                        CutHairline()
                        ForEach(model.muscles) { line in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(line.title).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                                Text(line.value).cutFont(.body).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                            CutHairline()
                        }
                    }
                }
                if !model.progression.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Progression").cutFont(.title)
                        if let reason = model.progressionReason {
                            Text(reason).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(spacing: 0) {
                            CutHairline()
                            ForEach(model.progression) { line in CutHairlineRow(line.title, value: line.value) }
                        }
                    }
                }
                if !model.cues.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Technique Tips").cutFont(.title)
                        CutHairline()
                        ForEach(Array(CutExerciseInfoLogic.visibleCues(model.cues, expanded: expandedCues).enumerated()), id: \.offset) { _, cue in
                            Text(cue).cutFont(.body).fixedSize(horizontal: false, vertical: true)
                        }
                        if model.cues.count > 3 {
                            Button(expandedCues ? "Show less" : "Show more", action: actions.toggleCues)
                                .cutFont(.title).foregroundStyle(DS.Cut.Colors.textPrimary).frame(minHeight: 44)
                        }
                    }
                }
            }
            .padding(DS.Cut.Metrics.gutter)
        }
    }
}
