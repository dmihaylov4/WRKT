//
//  CutPostDetailView.swift
//  WRKT
//
//  One post opened, in the Cut language ("Post B"), read top to bottom. The navigation bar is
//  the top row: the system back button (so the back swipe works), the author with the time and
//  visibility, and the like pill (plus the menu on your own post). Then a compact lime block with
//  the title and the three headline numbers, the caption, media, and bold condensed sections:
//  Exercises (rows open in place to their sets), Heart rate, Splits, Performance, Comments. The
//  tab bar steps aside, so the composer sits at the bottom edge above the keyboard. Takes plain
//  values, a text binding and closures, so every state renders without the app's services (see
//  CutPostDetailHost).
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
    /// Your own post: open the editor, or ask to delete it.
    var editPost: () -> Void = {}
    var deletePost: () -> Void = {}
}

struct CutPostDetailView<Media: View>: View {
    let model: CutPostDetailModel
    @Binding var commentText: String
    var actions = CutPostDetailActions()
    /// Photos and route maps under the caption (resolved by the host).
    @ViewBuilder var media: () -> Media

    @FocusState private var isComposerFocused: Bool
    @State private var openExercises: Set<Int>
    @State private var selectedSplitID: Int?
    /// A reply focuses the composer without moving the list away from the comment.
    @State private var focusIsFromReply = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The screen and like pill widths: a leading bar item is sized to its content, so the
    /// author gets the width the bar leaves between the back button and the trailing items.
    @State private var screenWidth: CGFloat = 0
    @State private var likeWidth: CGFloat = 88

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

    /// The author fits the bar up to xLarge text; above that it leads the page instead, where it
    /// can wrap.
    private var authorInBar: Bool { dynamicTypeSize <= .xLarge }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !authorInBar {
                            author
                                .padding(.horizontal, DS.Cut.Metrics.gutter)
                                .padding(.top, 8)
                        }
                        summary
                            .padding(.top, authorInBar ? 12 : 20)
                        workoutSections
                        commentsSection
                            .id(Self.commentsAnchor)
                    }
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                // Tapping "Add a comment" brings the comments into view, so the count in the
                // header and the thread are one tap away from anywhere on the page.
                .onChange(of: isComposerFocused) { _, focused in
                    if focused, !focusIsFromReply {
                        withAnimation { proxy.scrollTo(Self.commentsAnchor, anchor: .top) }
                    }
                    focusIsFromReply = false
                }
            }

            composer
        }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        // A reading screen: the tab bar steps aside so the composer sits at the bottom edge.
        .toolbar(.hidden, for: .tabBar)
        .shellNavigationBarBackground(DS.Cut.Colors.background)
        .workoutDetailScrollEdge()
        .onAppear { NotificationCenter.default.post(name: .hideShellTabBar, object: nil) }
        .onDisappear {
            isComposerFocused = false
            NotificationCenter.default.post(name: .showShellTabBar, object: nil)
        }
        .modifier(CutPostDetailBarItems(showsAuthor: authorInBar, showsMenu: !model.ownerActions.isEmpty) {
            author
        } like: {
            likePill
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { likeWidth = $0 }
        } menu: {
            ownerMenu
        })
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isComposerFocused = false }
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: Top row

    /// The bar's room for the author: the screen less its 16 pt margins, the back button, the
    /// like pill, the menu on your own post, and the bar's gaps between items.
    private var authorWidth: CGFloat? {
        guard authorInBar, screenWidth > 0 else { return nil }
        let menu: CGFloat = model.ownerActions.isEmpty ? 0 : 44 + 12
        return max(120, screenWidth - 32 - 44 - 24 - likeWidth - menu)
    }

    /// Who and when: the avatar, the name, then "42 min. ago, public" under it.
    private var author: some View {
        (authorInBar ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))) {
            HStack(spacing: -10) {
                CutSocialAvatar(initials: model.post.author.initials, url: model.post.author.avatarURL, size: 40)
                if let partner = model.post.partner {
                    CutSocialAvatar(initials: partner.initials, url: partner.avatarURL, size: 40)
                        .overlay(Circle().strokeBorder(DS.Cut.Colors.background, lineWidth: 2))
                }
            }
            // Initials fill a fixed circle; they cannot follow the text size.
            .dynamicTypeSize(...DynamicTypeSize.large)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.post.names)
                    .font(DS.Typography.custom(size: 17, weight: .bold, relativeTo: .headline))
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .lineLimit(authorInBar ? 1 : nil)
                    .fixedSize(horizontal: false, vertical: !authorInBar)
                Text(model.timeLine)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .lineLimit(authorInBar ? 1 : nil)
                    .fixedSize(horizontal: false, vertical: !authorInBar)
            }
        }
        .frame(width: authorWidth, alignment: .leading)
        .frame(maxWidth: authorWidth == nil ? .infinity : nil, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The like control as one outlined pill with two parts: the heart toggles your like, the
    /// number opens who liked it. Each part is a full 44 pt target and its own VoiceOver button.
    private var likePill: some View {
        HStack(spacing: 0) {
            Button {
                actions.feedback()
                actions.like()
            } label: {
                Image(systemName: model.post.isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(model.post.isLiked ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                    .padding(.leading, 14)
                    .padding(.trailing, 6)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isTogglingLike)
            .accessibilityLabel(Text(CutSocialLogic.likeAccessibility(likes: model.likes, isLiked: model.post.isLiked)))

            Button(action: actions.showLikes) {
                Text("\(model.likes)")
                    .font(DS.Typography.custom(size: 17, weight: .semibold, relativeTo: .body, monospacedDigits: true))
                    .foregroundStyle(model.likesLabel == nil ? DS.Cut.Colors.textSecondary : DS.Cut.Colors.textPrimary)
                    .padding(.trailing, 14)
                    .frame(minWidth: 40, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.likesLabel == nil)
            .accessibilityLabel(Text(model.likesLabel ?? "No likes yet"))
            .accessibilityHint(model.likesLabel == nil ? Text("") : Text("Shows who liked this post"))
        }
        .overlay(Capsule().strokeBorder(DS.Cut.Colors.hairlineStrong, lineWidth: 1.5))
        .fixedSize()
    }

    /// Edit and delete for your own post, in the bar beside the like pill.
    private var ownerMenu: some View {
        Menu {
            ForEach(model.ownerActions, id: \.self) { action in
                Button(CutSocialLogic.menuLabel(action), systemImage: action == .edit ? "pencil" : "trash",
                       role: CutSocialLogic.isDestructive(action) ? .destructive : nil) {
                    action == .edit ? actions.editPost() : actions.deletePost()
                }
            }
        } label: {
            Label("Post options", systemImage: "ellipsis")
        }
        .tint(DS.Cut.Colors.textPrimary)
    }

    // MARK: Summary

    /// The lime block (title and headline numbers), then the battle line, caption, week totals
    /// and media, in that order.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            CutPostDetailSummaryBlock(title: model.post.title, stats: model.headline)
                .padding(.horizontal, DS.Cut.Metrics.gutter)
            if hasLeadText {
            VStack(alignment: .leading, spacing: 8) {
                if let detail = model.battleDetail {
                    Text(detail).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let caption = model.post.caption {
                    Text(caption)
                        .font(DS.Typography.custom(size: 17, weight: .medium, relativeTo: .body))
                        .lineSpacing(3)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let line = model.overviewLine {
                    Text(line).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 16)
            }

            if model.showsMedia {
                media()
                    .padding(.top, 20)
            }
        }
    }

    private var hasLeadText: Bool {
        model.battleDetail != nil || model.post.caption != nil || model.overviewLine != nil
    }

    // MARK: Workout

    @ViewBuilder
    private var workoutSections: some View {
        if !model.workouts.isEmpty {
            section("Workouts") {
                ForEach(model.workouts) { workout in
                    VStack(spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.title)
                                    .font(CutPostDetailType.rowTitle)
                                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(workout.line)
                                    .cutFont(.secondary, monospacedDigits: true)
                                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Text(workout.value)
                                .font(CutPostDetailType.rowValue)
                                .foregroundStyle(DS.Cut.Colors.textSecondary)
                        }
                        .padding(.vertical, 12)
                        .frame(minHeight: 50)
                        CutHairline()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        if !model.exercises.isEmpty {
            section("Exercises") {
                ForEach(model.exercises) { exercise in
                    exerciseRow(exercise)
                }
            }
        }
        if !model.heartRate.isEmpty || model.refreshTitle != nil {
            heartRateSection
        }
        if !model.splits.isEmpty {
            section("Splits") {
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
        if !model.performance.isEmpty {
            section("Performance") {
                ForEach(model.performance) { metric in
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Text(metric.label)
                                .font(CutPostDetailType.rowTitle)
                                .foregroundStyle(DS.Cut.Colors.textPrimary)
                            Spacer(minLength: 8)
                            Text(metric.value)
                                .font(CutPostDetailType.rowValue)
                                .foregroundStyle(DS.Cut.Colors.textSecondary)
                        }
                        .padding(.vertical, 8)
                        .frame(minHeight: 50)
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
                CutPostDetailRowLayout(stacks: dynamicTypeSize.isAccessibilitySize) {
                    Text(exercise.title)
                        .font(CutPostDetailType.rowTitle)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } value: {
                    Text(exercise.line)
                        .font(CutPostDetailType.rowValue)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                }
                .padding(.vertical, 12)
                .frame(minHeight: 50)
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

    /// A bold condensed title over a strong hairline, then the content. Rows carry their own
    /// lighter hairlines, so the title never reads as a row.
    private func section<Content: View>(_ title: String, count: Int? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CutPostDetailSectionTitle(title: title, count: count)
            content()
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.top, 28)
    }

    // MARK: Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CutPostDetailSectionTitle(title: "Comments", count: model.post.comments)
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
                    .font(CutPostDetailType.rowValue)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .padding(.vertical, 16)
            case .list(let comments):
                ForEach(comments) { comment in
                    commentRow(comment)
                }
            }
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.top, 28)
    }

    /// Avatar, the name with the time beside it, the text, a hairline under. Reply sits at the
    /// end of the name line; on your own comment the menu there holds Reply and Delete.
    private func commentRow(_ comment: CutPostDetailModel.Comment) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                CutSocialAvatar(initials: comment.initials, url: comment.avatarURL, size: comment.isReply ? 30 : 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        (Text(comment.name)
                            .font(DS.Typography.custom(size: 16, weight: .bold, relativeTo: .subheadline))
                            .foregroundColor(DS.Cut.Colors.textPrimary)
                         + Text(verbatim: "  ")
                         + Text(comment.time)
                            .font(DS.Cut.Typography.font(.secondary))
                            .foregroundColor(DS.Cut.Colors.textSecondary))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        commentAction(comment)
                    }
                    mentionText(comment.text)
                        .font(DS.Typography.custom(size: 17, weight: .medium, relativeTo: .body))
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, comment.isReply ? 48 : 0)
            .padding(.vertical, 12)
            CutHairline()
        }
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

    /// One trailing control per comment, a full 44 pt target that does not grow the row.
    @ViewBuilder
    private func commentAction(_ comment: CutPostDetailModel.Comment) -> some View {
        if comment.canDelete {
            Menu {
                Button("Reply", systemImage: "arrowshape.turn.up.left") { reply(to: comment.id) }
                Button("Delete", systemImage: "trash", role: .destructive) { actions.deleteComment(comment.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .cutCommentHitArea()
            }
            .accessibilityLabel(Text("Comment options"))
        } else if comment.canReply {
            Button { reply(to: comment.id) } label: {
                Text("Reply")
                    .font(DS.Typography.custom(size: 15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .cutCommentHitArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Reply to \(comment.name)"))
        }
    }

    private func reply(to id: UUID) {
        actions.reply(id)
        focusIsFromReply = true
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
                TextField("Add a comment", text: Binding(
                    get: { commentText },
                    set: { newValue in
                        commentText = newValue
                        actions.commentTextChanged(newValue)
                    }
                ), prompt: Text("Add a comment").foregroundStyle(DS.Cut.Colors.textSecondary), axis: .vertical)
                .font(DS.Typography.custom(size: 17, weight: .medium, relativeTo: .body))
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .tint(DS.Cut.Colors.lime)
                .lineLimit(1...4)
                .focused($isComposerFocused)
                .disabled(model.composer.isPosting)
                .submitLabel(.return)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS.Cut.Colors.controlFill))
                .overlay {
                    if isComposerFocused {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(DS.Cut.Colors.hairlineStrong, lineWidth: 1)
                    }
                }
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
            .padding(.top, 12)
            .padding(.bottom, 8)
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

/// The detail's type: 18 pt semibold row names, 17 pt medium summaries.
enum CutPostDetailType {
    static var rowTitle: Font { DS.Typography.custom(size: 18, weight: .semibold, relativeTo: .body) }
    static var rowValue: Font { DS.Typography.custom(size: 17, weight: .medium, relativeTo: .body, monospacedDigits: true) }
}

/// The summary: a compact lime block, cut 28 pt at 45 degrees on its bottom trailing corner,
/// with the title in condensed capitals and the headline numbers as columns split by ink hairlines.
struct CutPostDetailSummaryBlock: View {
    let title: String
    let stats: [CutSocialStat]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .cutHero(.exercise, lines: 2, minimumScaleFactor: 0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !stats.isEmpty, dynamicTypeSize.isAccessibilitySize {
                // Columns cannot hold accessibility sizes: one number per line, label beside it.
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                        if index > 0 {
                            Rectangle().fill(DS.Cut.Colors.inkHairline).frame(height: DS.Cut.Metrics.hairline)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(stat.value)
                                .font(DS.Cut.Typography.condensed(size: 26, relativeTo: .title2, monospacedDigits: true))
                            Text(stat.label)
                                .font(DS.Typography.custom(size: 15, weight: .semibold, relativeTo: .subheadline))
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                    }
                }
            } else if !stats.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                        if index > 0 {
                            Rectangle().fill(DS.Cut.Colors.inkHairline).frame(width: DS.Cut.Metrics.hairline)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(stat.value)
                                .font(DS.Cut.Typography.condensed(size: 26, relativeTo: .title2, monospacedDigits: true))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(stat.label)
                                .font(DS.Typography.custom(size: 15, weight: .semibold, relativeTo: .subheadline))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, index > 0 ? 12 : 0)
                        .padding(.trailing, 6)
                        .accessibilityElement(children: .combine)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(DS.Cut.Colors.ink)
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 20, trailing: 20))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CutCornerShape(corner: .bottomTrailing, cut: .points(28)).fill(DS.Cut.Colors.lime))
        .environment(\.cutSurface, .lime)
    }
}

/// A section title: condensed capitals at 24 pt over a white hairline at 40 percent, with an
/// optional count at the trailing end.
private struct CutPostDetailSectionTitle: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(DS.Cut.Typography.condensed(size: 24, relativeTo: .title3))
                .textCase(.uppercase)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let count {
                Text("\(count)")
                    .font(CutPostDetailType.rowValue)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
            }
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Cut.Colors.hairlineStrong).frame(height: DS.Cut.Metrics.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A one line row: the name on the left, the summary on the right; at accessibility sizes the
/// summary drops under the name instead of squeezing it.
private struct CutPostDetailRowLayout<Title: View, Value: View>: View {
    let stacks: Bool
    @ViewBuilder var title: () -> Title
    @ViewBuilder var value: () -> Value

    var body: some View {
        if stacks {
            VStack(alignment: .leading, spacing: 4) {
                title()
                value().fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                title()
                    .frame(maxWidth: .infinity, alignment: .leading)
                value()
                    .multilineTextAlignment(.trailing)
                    .fixedSize()
            }
        }
    }
}

/// Stat columns at a reading size (the heart rate numbers): 26 pt condensed values over a plain
/// label, 1 pt hairlines between equal columns.
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

/// The top row's bar items: the author right after the system back button, then the
/// like pill and, on your own post, the menu at the trailing end. On iOS 26 the author and the
/// pill draw without the bar's glass, so the pill keeps its own outline.
private struct CutPostDetailBarItems<Author: View, Like: View, Menu: View>: ViewModifier {
    let showsAuthor: Bool
    let showsMenu: Bool
    @ViewBuilder var author: () -> Author
    @ViewBuilder var like: () -> Like
    @ViewBuilder var menu: () -> Menu

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.toolbar {
                if showsAuthor {
                    ToolbarItem(placement: .topBarLeading) { author() }
                        .sharedBackgroundVisibility(.hidden)
                }
                ToolbarItem(placement: .topBarTrailing) { like() }
                    .sharedBackgroundVisibility(.hidden)
                if showsMenu {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) { menu() }
                }
            }
        } else {
            content.toolbar {
                if showsAuthor {
                    ToolbarItem(placement: .topBarLeading) { author() }
                }
                ToolbarItem(placement: .topBarTrailing) { like() }
                if showsMenu {
                    ToolbarItem(placement: .topBarTrailing) { menu() }
                }
            }
        }
    }
}

private extension View {
    /// A 44 pt touch target around a small glyph or word that does not push the row apart.
    func cutCommentHitArea() -> some View {
        frame(minWidth: DS.Cut.Metrics.minTouchTarget, minHeight: DS.Cut.Metrics.minTouchTarget, alignment: .trailing)
            .contentShape(Rectangle())
            .padding(.vertical, -12)
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
