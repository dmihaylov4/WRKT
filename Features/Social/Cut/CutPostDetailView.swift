//
//  CutPostDetailView.swift
//  WRKT
//
//  One post opened, in the Cut language: the feed's post head, the workout name as the hero,
//  the caption and stat columns, likes, then the workout as hairline sections (workouts,
//  exercises that open to their sets, splits, heart rate, performance), the comments, and a
//  solid composer bar pinned above the keyboard. Takes plain values, a text binding and
//  closures, so every state renders without the app's services (see CutPostDetailHost).
//

import SwiftUI
import Charts

struct CutPostDetailActions {
    var like: () -> Void = {}
    var showLikes: () -> Void = {}
    var refreshCardio: () -> Void = {}
    var retryComments: () -> Void = {}
    var reply: (UUID) -> Void = { _ in }
    var cancelReply: () -> Void = {}
    var deleteComment: (UUID) -> Void = { _ in }
    var commentTextChanged: (String) -> Void = { _ in }
    var selectSuggestion: (UUID) -> Void = { _ in }
    var send: () async -> Void = {}
    var dismissError: () -> Void = {}
    var feedback: () -> Void = {}
    var back: () -> Void = {}
}

struct CutPostDetailView<Media: View>: View {
    let model: CutPostDetailModel
    @Binding var commentText: String
    var actions = CutPostDetailActions()
    /// Photos and route maps under the stats (resolved by the host).
    @ViewBuilder var media: () -> Media

    @FocusState private var isComposerFocused: Bool
    @State private var openExercises: Set<Int>
    @State private var selectedSplitID: Int?
    @State private var selectedSection: CutPostDetailModel.Section

    /// - Parameter openExercises: exercises shown open at first (captures); all open by default, matching the legacy exercise breakdown.
    init(model: CutPostDetailModel, commentText: Binding<String>, actions: CutPostDetailActions = CutPostDetailActions(),
         openExercises: Set<Int>? = nil, initialSection: CutPostDetailModel.Section = .overview, @ViewBuilder media: @escaping () -> Media) {
        self.model = model
        self._commentText = commentText
        self.actions = actions
        self.media = media
        self._openExercises = State(initialValue: openExercises ?? Set(model.exercises.map(\.id)))
        self._selectedSection = State(initialValue: openExercises?.isEmpty == false ? .exercises : initialSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    postSection
                    if !model.availableSections.isEmpty { detailTabs }
                    workoutSections
                    commentsSection
                        .padding(.top, 36)
                }
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            composer
        }
        // Lifts the composer above the custom tab bar, as the legacy screen does.
        .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 56, system: 36))
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .onDisappear { isComposerFocused = false }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left") {
                    isComposerFocused = false
                    // Let focus settle before popping to avoid the legacy keyboard layout jump.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { actions.back() }
                }
                .labelStyle(.iconOnly)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isComposerFocused = false }
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: Post

    private var postSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                head
                Text(model.post.title.uppercased())
                    .font(DS.Cut.Typography.condensed(size: 28, relativeTo: .title2))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 18)
                if let detail = model.battleDetail {
                    Text(detail).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary).padding(.top, 12)
                }
                if let caption = model.post.caption {
                    Text(caption)
                        .cutFont(.body)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }
                if !model.post.stats.isEmpty {
                    CutStatColumns(model.post.stats.map {
                        CutStatColumn(value: $0.value, label: $0.label, isHighlighted: $0.isHighlighted)
                    })
                    .padding(.top, 16)
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)

            if model.showsMedia {
                media()
                    .padding(.top, 18)
            }

            actionRow
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 18)
        }
        .padding(.top, 8)
    }

    private var head: some View {
        HStack(spacing: 12) {
            HStack(spacing: -10) {
                CutSocialAvatar(initials: model.post.author.initials, url: model.post.author.avatarURL, size: 44)
                if let partner = model.post.partner {
                    CutSocialAvatar(initials: partner.initials, url: partner.avatarURL, size: 44)
                        .overlay(Circle().strokeBorder(DS.Cut.Colors.background, lineWidth: 2))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.post.names)
                    .cutFont(.title)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.post.timeLine.localizedCaseInsensitiveContains(model.visibility) ? model.post.timeLine : model.post.timeLine + " · " + model.visibility)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var actionRow: some View {
        HStack(spacing: 16) {
            Button {
                actions.feedback()
                actions.like()
            } label: {
                Image(systemName: model.post.isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(model.post.isLiked ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
            }
            .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
            .disabled(model.isTogglingLike)
            .accessibilityLabel(Text(CutSocialLogic.likeAccessibility(likes: model.likes, isLiked: model.post.isLiked)))
            if let likesLabel = model.likesLabel {
                Button(action: actions.showLikes) {
                    Text("\(model.likes)").cutFont(.title).monospacedDigit()
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .accessibilityLabel(Text(likesLabel))
                .accessibilityHint(Text("Shows who liked this post"))
            } else {
                Text("0").cutFont(.body)
            }
            Label("\(model.post.comments)", systemImage: "bubble.left")
                .cutFont(.body)
                .accessibilityLabel(Text("\(model.post.comments) comments"))
            Spacer(minLength: 0)
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
    }

    // MARK: Workout

    @ViewBuilder
    private var workoutSections: some View {
        if selectedSection == .overview, let line = model.overviewLine {
            Text(line).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Cut.Metrics.gutter).padding(.top, 20)
        }
        if selectedSection == .overview && !model.workouts.isEmpty {
            section("Workout breakdown") {
                ForEach(model.workouts) { workout in
                    VStack(spacing: 0) {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.title)
                                    .cutFont(.title)
                                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                                Text(workout.line)
                                    .cutFont(.secondary)
                                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Text(workout.value)
                                .font(DS.Cut.Typography.font(.secondary, monospacedDigits: true).weight(.semibold))
                                .foregroundStyle(DS.Cut.Colors.textSecondary)
                        }
                        .padding(.vertical, 12)
                        CutHairline()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        if selectedSection == .exercises && !model.exercises.isEmpty {
            section("Exercises") {
                ForEach(model.exercises) { exercise in
                    exerciseRow(exercise)
                }
            }
        }
        if selectedSection == .exercises && model.exercises.isEmpty {
            Text("No logged exercises").cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary)
                .padding(DS.Cut.Metrics.gutter)
        }
        if selectedSection == .watch && !model.splits.isEmpty {
            section("Splits per km") {
                VStack(alignment: .leading, spacing: 12) {
                    if let split = CutPostDetailLogic.selectedSplit(model.splits, id: selectedSplitID) {
                        Text("KM \(split.label) · \(split.pace) /km · \(split.duration)")
                            .cutFont(.body).foregroundStyle(DS.Cut.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let average = model.splitAverage {
                        Text("Average \(average) /km").cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                    }
                    ForEach(model.splits) { split in
                        Button {
                            selectedSplitID = split.id
                            actions.feedback()
                        } label: {
                            HStack(spacing: 14) {
                                Text(split.label)
                                    .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .title3, monospacedDigits: true))
                                    .frame(minWidth: 44, alignment: .leading)
                                CutCardioBar(fraction: split.fraction, fill: split.isFastest ? DS.Cut.Colors.lime : DS.Cut.Colors.segmentTrack)
                                Text(split.pace)
                                    .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .title3, monospacedDigits: true))
                                    .fixedSize()
                            }
                            .foregroundStyle(split.isFastest ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Kilometre \(split.label), \(split.pace) per kilometre, duration \(split.duration)\(split.isFastest ? ", fastest" : "")"))
                        .accessibilityAddTraits(selectedSplitID == split.id || (selectedSplitID == nil && split.id == model.splits.last?.id) ? .isSelected : [])
                    }
                }
                .padding(.top, 14)
            }
        }

        if selectedSection == .watch && (!model.heartRate.isEmpty || model.refreshTitle != nil) {
            heartRateSection
        }
        if selectedSection == .watch && !model.performance.isEmpty {
            section("Performance") {
                ForEach(Array(model.performance.enumerated()), id: \.offset) { _, row in
                    CutStatColumns(row.count == 1 ? row + [CutStatColumn(value: "", label: "")] : row)
                        .padding(.vertical, 14)
                    CutHairline()
                }
            }
        }
    }

    private var detailTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 24) {
                ForEach(model.availableSections, id: \.self) { section in
                    Button { selectedSection = section; actions.feedback() } label: {
                        VStack(spacing: 10) {
                            Text(section.rawValue).cutFont(.title).fixedSize()
                                .foregroundStyle(selectedSection == section ? DS.Cut.Colors.textPrimary : DS.Cut.Colors.textSecondary)
                            SlantedSegmentShape().fill(selectedSection == section ? DS.Cut.Colors.lime : .clear).frame(height: 4)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 24)
    }

    private func exerciseRow(_ exercise: CutPostDetailModel.Exercise) -> some View {
        let isOpen = openExercises.contains(exercise.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                actions.feedback()
                if isOpen { openExercises.remove(exercise.id) } else { openExercises.insert(exercise.id) }
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.title)
                            .cutFont(.title)
                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(exercise.line)
                            .cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 50)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text(isOpen ? "Open" : "Closed"))
            .accessibilityHint(Text(isOpen ? "Hides the sets" : "Shows the sets"))

            if isOpen {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(exercise.sets) { set in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(set.number)
                                .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .title3, monospacedDigits: true))
                                .foregroundStyle(DS.Cut.Colors.textSecondary)
                                .frame(minWidth: 22, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(set.value)
                                    .cutFont(.body, monospacedDigits: true)
                                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                                if let note = set.note {
                                    Text(note)
                                        .cutFont(.secondary)
                                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text("Set \(set.number), \(set.value)\(set.note.map { ", \($0)" } ?? "")"))
                    }
                    if let timing = exercise.timing {
                        Text(timing)
                            .cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                            .padding(.top, 2)
                    }
                }
                .padding(.bottom, 16)
            }
            CutHairline()
        }
    }

    private var heartRateSection: some View {
        section("Heart rate") {
            ForEach(model.heartRate) { heart in
                VStack(alignment: .leading, spacing: 0) {
                    if let title = heart.title {
                        Text(title)
                            .cutFont(.title)
                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                            .padding(.top, 14)
                    }
                    if let energy = heart.energy, model.heartRate.count > 1 {
                        Text(energy).cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary).padding(.top, 10)
                    }
                    if heart.isEstimated {
                        Text("Zones are estimated from the average heart rate.")
                            .cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    }
                    if !heart.stats.isEmpty {
                        CutStatColumns(heart.stats)
                            .padding(.top, 14)
                    }
                    if !heart.points.isEmpty {
                        Chart(heart.points) { point in
                            LineMark(x: .value("Seconds", point.seconds), y: .value("BPM", point.bpm))
                                .foregroundStyle(DS.Cut.Colors.lime)
                                .interpolationMethod(.catmullRom)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                                AxisGridLine().foregroundStyle(DS.Cut.Colors.hairline)
                                AxisValueLabel {
                                    if let seconds = value.as(Double.self) {
                                        Text(CutCardioLogic.duration(Int(seconds))).cutFont(.secondary)
                                    }
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                                AxisGridLine().foregroundStyle(DS.Cut.Colors.hairline)
                                AxisValueLabel {
                                    if let bpm = value.as(Double.self) { Text("\(Int(bpm))").cutFont(.secondary) }
                                }
                            }
                        }
                        .frame(height: 160)
                        .padding(.top, 18)
                        .accessibilityLabel(Text("Heart rate in beats per minute over elapsed workout time"))
                    }
                    if !heart.zones.isEmpty {
                        if let method = model.zoneMethod {
                            Text(method).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary).padding(.top, 14)
                        }
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                            ForEach(heart.zones) { zone in
                                GridRow {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(zone.label).cutFont(.title)
                                        if !zone.detail.isEmpty { Text(zone.detail).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary).fixedSize(horizontal: false, vertical: true) }
                                    }
                                        .cutFont(.title)
                                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                                        .accessibilityLabel(Text("\(zone.label), \(zone.detail), \(zone.time), \(Int((zone.fraction * 100).rounded())) percent"))
                                    CutCardioBar(fraction: zone.fraction,
                                                 fill: DS.Cut.Colors.lime.opacity(0.35 + 0.13 * Double(zone.id)))
                                    Text("\(zone.time) · \(Int((zone.fraction * 100).rounded()))%")
                                        .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .title3, monospacedDigits: true))
                                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                                        .fixedSize()
                                        .gridColumnAlignment(.trailing)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .padding(.top, 18)
                    }
                }
                .padding(.bottom, 16)
            }
            if let title = model.refreshTitle {
                Button(action: actions.refreshCardio) {
                    if model.isRefreshing {
                        HStack(spacing: 10) {
                            ProgressView().tint(DS.Cut.Colors.textPrimary)
                            Text("Loading")
                        }
                    } else {
                        Text(title)
                    }
                }
                .buttonStyle(CutSecondaryButtonStyle(fillsWidth: true))
                .disabled(model.isRefreshing)
                .padding(.top, 4)
            }
        }
    }

    /// A section title, a hairline, then the content: the pattern every section here shares.
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CutSectionTitle(title)
                .padding(.bottom, 10)
            CutHairline()
            content()
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.top, 36)
    }

    // MARK: Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CutSectionTitle("Comments (\(model.post.comments))")
                .padding(.bottom, 10)
            CutHairline()
            switch model.comments {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView().tint(DS.Cut.Colors.textSecondary)
                    Text("Loading comments").cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                }
                .padding(.vertical, 20)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 12) {
                    Text(message)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again", action: actions.retryComments)
                        .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
                }
                .padding(.vertical, 18)
            case .empty:
                Text("No comments yet.")
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .padding(.vertical, 20)
            case .list(let comments):
                ForEach(comments) { comment in
                    commentRow(comment)
                }
            }
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
    }

    private func commentRow(_ comment: CutPostDetailModel.Comment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CutSocialAvatar(initials: comment.initials, url: comment.avatarURL, size: comment.isReply ? 32 : 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(comment.name)
                    .cutFont(.title)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                mentionText(comment.text)
                    .cutFont(.body)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Text(comment.time)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                    if comment.canReply {
                        Button("Reply") { reply(to: comment.id) }
                            .font(DS.Cut.Typography.font(.secondary).weight(.semibold))
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                            .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Reply to \(comment.name)"))
                    }
                }
                .frame(minHeight: DS.Cut.Metrics.minTouchTarget, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if comment.canDelete {
                Menu {
                    Button("Reply", systemImage: "arrowshape.turn.up.left") { reply(to: comment.id) }
                    Button("Delete", systemImage: "trash", role: .destructive) { actions.deleteComment(comment.id) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .frame(width: DS.Cut.Metrics.minTouchTarget, height: DS.Cut.Metrics.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Comment options"))
            }
        }
        .padding(.leading, comment.isReply ? 52 : 0)
        .padding(.top, 14)
        .contentShape(Rectangle())
        .contextMenu {
            if comment.canReply {
                Button("Reply", systemImage: "arrowshape.turn.up.left") { reply(to: comment.id) }
            }
            if comment.canDelete {
                Button("Delete", systemImage: "trash", role: .destructive) { actions.deleteComment(comment.id) }
            }
        }
    }

    private func reply(to id: UUID) {
        actions.reply(id)
        isComposerFocused = true
    }

    private func mentionText(_ text: String) -> Text {
        CutPostDetailLogic.segments(text).reduce(Text(verbatim: "")) { result, segment in
            if segment.isMention {
                return result + Text(verbatim: segment.text).foregroundColor(DS.Cut.Colors.lime).fontWeight(.semibold)
            }
            return result + Text(verbatim: segment.text)
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 0) {
            CutHairline()
            if !model.composer.suggestions.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.composer.suggestions) { person in
                            Button { actions.selectSuggestion(person.id) } label: {
                                HStack(spacing: 12) {
                                    CutSocialAvatar(initials: person.initials, url: person.avatarURL, size: 36)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(person.name)
                                            .cutFont(.title)
                                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(person.handle)
                                            .cutFont(.secondary)
                                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, DS.Cut.Metrics.gutter)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Mention \(person.name), \(person.handle)"))
                            CutHairline()
                        }
                    }
                }
                .frame(maxHeight: 180)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.composer.error {
                HStack(spacing: 10) {
                    Text(error)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Dismiss", systemImage: "xmark", action: actions.dismissError)
                        .buttonStyle(CutIconButtonStyle(tone: .outline, diameter: DS.Cut.Metrics.minTouchTarget))
                }
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 8)
            }
            if let replyingTo = model.composer.replyingTo {
                HStack(spacing: 10) {
                    Text(replyingTo)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Cancel reply", systemImage: "xmark", action: actions.cancelReply)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .frame(width: DS.Cut.Metrics.minTouchTarget, height: DS.Cut.Metrics.minTouchTarget)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                }
                .padding(.leading, DS.Cut.Metrics.gutter)
                .padding(.trailing, DS.Cut.Metrics.gutter - 12)
            }
            HStack(alignment: .bottom, spacing: 12) {
                VStack(spacing: 6) {
                    TextField("Add a comment", text: Binding(
                        get: { commentText },
                        set: { newValue in
                            commentText = newValue
                            actions.commentTextChanged(newValue)
                        }
                    ), prompt: Text("Add a comment").foregroundStyle(DS.Cut.Colors.textSecondary), axis: .vertical)
                    .cutFont(.body)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .tint(DS.Cut.Colors.lime)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .disabled(model.composer.isPosting)
                    .submitLabel(.return)
                    Rectangle()
                        .fill(isComposerFocused ? DS.Cut.Colors.lime : DS.Cut.Colors.hairlineStrong)
                        .frame(height: isComposerFocused ? 2 : 1)
                        .accessibilityHidden(true)
                }
                .padding(.bottom, 4)
                Button {
                    Task {
                        await actions.send()
                        isComposerFocused = false
                    }
                } label: {
                    if model.composer.isPosting {
                        ProgressView().tint(DS.Cut.Colors.ink)
                    } else {
                        Label("Post comment", systemImage: "arrow.up")
                    }
                }
                .buttonStyle(CutIconButtonStyle(tone: .lime, diameter: DS.Cut.Metrics.minTouchTarget))
                .disabled(!model.composer.canSend)
                .accessibilityLabel(Text("Post comment"))
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .background(DS.Cut.Colors.background)
    }
}

extension CutPostDetailView where Media == EmptyView {
    init(model: CutPostDetailModel, commentText: Binding<String>, actions: CutPostDetailActions = CutPostDetailActions(),
         openExercises: Set<Int>? = nil) {
        self.init(model: model, commentText: commentText, actions: actions, openExercises: openExercises) { EmptyView() }
    }
}

// MARK: - Loader

/// The post while it loads by id, or the message when it cannot be found.
struct CutPostLoaderStateView: View {
    enum State: Equatable {
        case loading
        case failed(String)
    }

    let state: State
    var retry: () -> Void = {}

    var body: some View {
        ScrollView {
            switch state {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView().tint(DS.Cut.Colors.textSecondary)
                    Text("Loading post").cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
                .accessibilityElement(children: .combine)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 16) {
                    Text("POST NOT FOUND").font(DS.Cut.Typography.condensed(size: 28, relativeTo: .title2))
                    Text(message).cutFont(.body).foregroundStyle(DS.Cut.Colors.textSecondary)
                    Button("Try again", action: retry).buttonStyle(CutPrimaryButtonStyle(fillsWidth: false))
                }.padding(DS.Cut.Metrics.gutter)
            }
        }
        .scrollIndicators(.hidden)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }
}

/// Full-screen route presentation. The host supplies the resolved image.
struct CutPostDetailMapView<Map: View>: View {
    let close: () -> Void
    @ViewBuilder var map: () -> Map
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            map().frame(maxWidth: .infinity, maxHeight: .infinity)
            Button("Close map", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DS.Cut.Colors.textPrimary).frame(width: 44, height: 44).padding()
        }
    }
}
