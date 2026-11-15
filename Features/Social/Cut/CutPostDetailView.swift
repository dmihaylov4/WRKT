//
//  CutPostDetailView.swift
//  WRKT
//
//  One post opened, in the Cut language, read top to bottom: who and when, the title and
//  caption, three headline numbers, media, the reactions (heart with its count, then comments),
//  the workout as quiet labelled sections (workouts when there are several, exercises that
//  open in place to their sets, splits, heart rate, performance), then the comments. The tab
//  bar steps aside on this screen, so the composer sits at the bottom edge above the keyboard. Takes plain values, a text binding and
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

    /// - Parameter openExercises: exercises shown open at first (captures); all closed by
    ///   default, so each reads as one line until it is tapped.
    init(model: CutPostDetailModel, commentText: Binding<String>, actions: CutPostDetailActions = CutPostDetailActions(),
         openExercises: Set<Int> = [], @ViewBuilder media: @escaping () -> Media) {
        self.model = model
        self._commentText = commentText
        self.actions = actions
        self.media = media
        self._openExercises = State(initialValue: openExercises)
    }

    private static var commentsAnchor: String { "comments" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        postSection { withAnimation { proxy.scrollTo(Self.commentsAnchor, anchor: .top) } }
                        workoutSections
                        commentsSection
                            .id(Self.commentsAnchor)
                            .padding(.top, 40)
                    }
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }

            composer
        }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        // A reading screen: the tab bar steps aside so the composer sits at the bottom edge,
        // and the bar keeps content from sliding under the back button.
        .toolbar(.hidden, for: .tabBar)
        .shellNavigationBarBackground(DS.Cut.Colors.background)
        .workoutDetailScrollEdge()
        .onAppear { NotificationCenter.default.post(name: .hideShellTabBar, object: nil) }
        .onDisappear {
            isComposerFocused = false
            NotificationCenter.default.post(name: .showShellTabBar, object: nil)
        }
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

    /// Who and when, what (title, caption), the headline numbers, media, then the reactions.
    private func postSection(showComments: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                head
                Text(model.post.title.uppercased())
                    .font(DS.Cut.Typography.condensed(size: 28, relativeTo: .title2))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 20)
                if let detail = model.battleDetail {
                    Text(detail).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                if let caption = model.post.caption {
                    Text(caption)
                        .cutFont(.body)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                if !model.post.stats.isEmpty {
                    CutPostDetailStats(columns: model.post.stats.map {
                        CutStatColumn(value: $0.value, label: $0.label, isHighlighted: $0.isHighlighted)
                    })
                    .padding(.top, 20)
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)

            if model.showsMedia {
                media()
                    .padding(.top, 20)
            }

            reactions(showComments: showComments)
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 12)
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

    /// The heart and its count as one control (the heart toggles, the count opens who liked
    /// it), then the comment count, which scrolls to the comments. Both share one baseline,
    /// one size and one gap between icon and number.
    private func reactions(showComments: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 28) {
            HStack(spacing: 8) {
                Button {
                    actions.feedback()
                    actions.like()
                } label: {
                    Image(systemName: model.post.isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(model.post.isLiked ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                        .cutReactionHitArea()
                }
                .buttonStyle(.plain)
                .disabled(model.isTogglingLike)
                .accessibilityLabel(Text(CutSocialLogic.likeAccessibility(likes: model.likes, isLiked: model.post.isLiked)))
                if let likesLabel = model.likesLabel {
                    Button(action: actions.showLikes) {
                        Text("\(model.likes)").cutReactionCount()
                            .cutReactionHitArea()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(likesLabel))
                    .accessibilityHint(Text("Shows who liked this post"))
                } else {
                    Text("0").cutReactionCount()
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            Button(action: showComments) {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left")
                    Text("\(model.post.comments)").cutReactionCount()
                }
                .cutReactionHitArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(model.post.comments == 1 ? "1 comment" : "\(model.post.comments) comments"))
            .accessibilityHint(Text("Shows the comments"))
            Spacer(minLength: 0)
        }
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
    }

    // MARK: Workout

    @ViewBuilder
    private var workoutSections: some View {
        if let line = model.overviewLine {
            Text(line).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Cut.Metrics.gutter).padding(.top, 24)
        }
        if !model.workouts.isEmpty {
            section("Workouts") {
                ForEach(model.workouts) { workout in
                    VStack(spacing: 0) {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.title)
                                    .cutFont(.title)
                                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(workout.line)
                                    .cutFont(.secondary, monospacedDigits: true)
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
        if !model.exercises.isEmpty {
            section("Exercises", count: model.exercises.count) {
                ForEach(model.exercises) { exercise in
                    exerciseRow(exercise)
                }
            }
        }
        if !model.splits.isEmpty {
            section("Splits per km") {
                VStack(alignment: .leading, spacing: 4) {
                    if let split = CutPostDetailLogic.selectedSplit(model.splits, id: selectedSplitID) {
                        Text("KM \(split.label) · \(split.pace) /km · \(split.duration)")
                            .cutFont(.body, monospacedDigits: true).foregroundStyle(DS.Cut.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let average = model.splitAverage {
                        Text("Average \(average) /km").cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                            .padding(.bottom, 8)
                    }
                    ForEach(model.splits) { split in
                        Button {
                            selectedSplitID = split.id
                            actions.feedback()
                        } label: {
                            HStack(spacing: 14) {
                                Text(split.label)
                                    .frame(minWidth: 36, alignment: .leading)
                                CutCardioBar(fraction: split.fraction, fill: split.isFastest ? DS.Cut.Colors.lime : DS.Cut.Colors.segmentTrack)
                                Text(split.pace)
                                    .fixedSize()
                            }
                            .font(DS.Cut.Typography.font(.body, monospacedDigits: true).weight(.semibold))
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
        if !model.heartRate.isEmpty || model.refreshTitle != nil {
            heartRateSection
        }
        if !model.performance.isEmpty {
            section("Performance") {
                ForEach(model.performance) { metric in
                    VStack(spacing: 0) {
                        HStack(spacing: 14) {
                            Text(metric.label)
                                .cutFont(.body)
                                .foregroundStyle(DS.Cut.Colors.textPrimary)
                            Spacer(minLength: 8)
                            Text(metric.value)
                                .font(DS.Cut.Typography.font(.body, monospacedDigits: true).weight(.semibold))
                                .foregroundStyle(DS.Cut.Colors.textPrimary)
                        }
                        .frame(minHeight: 44)
                        .padding(.vertical, 2)
                        CutHairline()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func exerciseRow(_ exercise: CutPostDetailModel.Exercise) -> some View {
        let isOpen = openExercises.contains(exercise.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                actions.feedback()
                withAnimation(.easeOut(duration: 0.2)) {
                    if isOpen { openExercises.remove(exercise.id) } else { openExercises.insert(exercise.id) }
                }
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.title)
                            .cutFont(.title)
                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(exercise.line)
                            .cutFont(.secondary, monospacedDigits: true)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
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
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(exercise.sets) { set in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(set.number)
                                .cutFont(.secondary, monospacedDigits: true)
                                .foregroundStyle(DS.Cut.Colors.textSecondary)
                                .frame(minWidth: 18, alignment: .leading)
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
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
                .padding(.leading, 2)
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
                        Text(energy).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary).padding(.top, 4)
                    }
                    if !heart.stats.isEmpty {
                        CutPostDetailStats(columns: heart.stats.map { CutStatColumn(value: $0.value, label: $0.label, unit: "bpm") })
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
                        .frame(height: 140)
                        .padding(.top, 18)
                        .accessibilityLabel(Text("Heart rate in beats per minute over elapsed workout time"))
                    }
                    if !heart.zones.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            if let method = model.zoneMethod {
                                Text(method).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                            }
                            if heart.isEstimated {
                                Text("Zones are estimated from the average heart rate.")
                                    .cutFont(.secondary)
                                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 18)
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                            ForEach(heart.zones) { zone in
                                GridRow {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(zone.label).cutFont(.title)
                                        if !zone.detail.isEmpty { Text(zone.detail).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary).fixedSize(horizontal: false, vertical: true) }
                                    }
                                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                                        .accessibilityLabel(Text("\(zone.label), \(zone.detail), \(zone.time), \(Int((zone.fraction * 100).rounded())) percent"))
                                    CutCardioBar(fraction: zone.fraction,
                                                 fill: DS.Cut.Colors.lime.opacity(0.35 + 0.13 * Double(zone.id)))
                                    Text("\(zone.time) · \(Int((zone.fraction * 100).rounded()))%")
                                        .font(DS.Cut.Typography.font(.body, monospacedDigits: true).weight(.semibold))
                                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                                        .fixedSize()
                                        .gridColumnAlignment(.trailing)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .padding(.top, 14)
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
                .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
                .disabled(model.isRefreshing)
                .padding(.top, 4)
            }
        }
    }

    /// A quiet section label (as Settings labels its sections), then the content. Rows carry
    /// their own hairlines, so the label never reads as a row.
    private func section<Content: View>(_ title: String, count: Int? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CutPostDetailSectionLabel(title: title, count: count)
            content()
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.top, 40)
    }

    // MARK: Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CutPostDetailSectionLabel(title: "Comments", count: model.post.comments)
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
         openExercises: Set<Int> = []) {
        self.init(model: model, commentText: commentText, actions: actions, openExercises: openExercises) { EmptyView() }
    }
}

// MARK: - Pieces

/// The detail's section label: secondary text at 15 pt with an optional count beside it.
private struct CutPostDetailSectionLabel: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(DS.Cut.Typography.font(.secondary).weight(.semibold))
            if let count {
                Text("\(count)")
                    .cutFont(.secondary, monospacedDigits: true)
            }
        }
        .foregroundStyle(DS.Cut.Colors.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Stat columns at a reading size: 26 pt condensed values over a plain label, 1 pt hairlines
/// between equal columns.
private struct CutPostDetailStats: View {
    let columns: [CutStatColumn]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                if index > 0 {
                    Rectangle().fill(DS.Cut.Colors.hairline).frame(width: DS.Cut.Metrics.hairline)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(column.value)
                            .font(DS.Cut.Typography.condensed(size: 26, relativeTo: .title2, monospacedDigits: true))
                            .foregroundStyle(column.isHighlighted ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if let unit = column.unit {
                            Text(unit)
                                .cutFont(.secondary)
                                .foregroundStyle(DS.Cut.Colors.textSecondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    Text(column.label)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, index > 0 ? 14 : 0)
                .padding(.trailing, 8)
                .accessibilityElement(children: .combine)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension View {
    /// The reaction count: the icon's size and weight, tabular digits.
    func cutReactionCount() -> some View {
        font(DS.Typography.custom(size: 18, weight: .semibold, relativeTo: .body, monospacedDigits: true))
    }

    /// A 44 pt tall touch target that does not push its neighbours apart.
    func cutReactionHitArea() -> some View {
        frame(minHeight: DS.Cut.Metrics.minTouchTarget)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .padding(.horizontal, -8)
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
