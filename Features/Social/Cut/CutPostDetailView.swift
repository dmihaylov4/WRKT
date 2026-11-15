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
}

struct CutPostDetailView<Media: View>: View {
    let model: CutPostDetailModel
    @Binding var commentText: String
    var actions = CutPostDetailActions()
    /// Photos and route maps under the stats (resolved by the host).
    @ViewBuilder var media: () -> Media

    @FocusState private var isComposerFocused: Bool
    @State private var openExercises: Set<Int>
    @State private var pendingDelete: UUID?

    /// - Parameter openExercises: exercises shown open at first (captures); all closed by default.
    init(model: CutPostDetailModel, commentText: Binding<String>, actions: CutPostDetailActions = CutPostDetailActions(),
         openExercises: Set<Int> = [], @ViewBuilder media: @escaping () -> Media) {
        self.model = model
        self._commentText = commentText
        self.actions = actions
        self.media = media
        self._openExercises = State(initialValue: openExercises)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    postSection
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isComposerFocused = false }
                    .fontWeight(.semibold)
            }
        }
        .alert("Delete comment?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = pendingDelete { actions.deleteComment(id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: Post

    private var postSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                head
                CutHeroText(CutHeroText.balancedLines(model.post.title), hero: .l, minimumScaleFactor: 0.45)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 18)
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

            if model.post.showsMedia {
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
                    .lineLimit(2)
                Text(model.post.timeLine)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.light()
                actions.like()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.post.isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(model.post.isLiked ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                    if model.likes > 0 { Text("\(model.likes)").monospacedDigit() }
                }
            }
            .disabled(model.isTogglingLike)
            .accessibilityLabel(Text(CutSocialLogic.likeAccessibility(likes: model.likes, isLiked: model.post.isLiked)))
            Button {
                isComposerFocused = true
            } label: {
                Image(systemName: "bubble.left")
            }
            .accessibilityLabel(Text("Add a comment"))
            ShareLink(item: CutSocialLogic.shareText) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel(Text("Share"))
            Spacer(minLength: 8)
            if let likesLabel = model.likesLabel {
                Button(action: actions.showLikes) {
                    Text(likesLabel)
                        .font(DS.Cut.Typography.font(.secondary).weight(.semibold))
                        .foregroundStyle(DS.Cut.Colors.lime)
                        .lineLimit(1)
                        .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows who liked this post"))
            }
        }
        .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
    }

    // MARK: Workout

    @ViewBuilder
    private var workoutSections: some View {
        if !model.workouts.isEmpty {
            section("Workouts") {
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
        if !model.exercises.isEmpty {
            section("Exercises") {
                ForEach(model.exercises) { exercise in
                    exerciseRow(exercise)
                }
            }
        }
        if !model.splits.isEmpty {
            section("Splits per km") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    ForEach(model.splits) { split in
                        GridRow {
                            Text(split.label)
                                .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .title3, monospacedDigits: true))
                                .foregroundStyle(split.isFastest ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                                .fixedSize()
                                .accessibilityLabel(Text("Kilometre \(split.label), \(split.pace) per kilometre\(split.isFastest ? ", fastest" : "")"))
                            CutCardioBar(fraction: split.fraction, fill: split.isFastest ? DS.Cut.Colors.lime : DS.Cut.Colors.segmentTrack)
                            Text(split.pace)
                                .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .title3, monospacedDigits: true))
                                .foregroundStyle(split.isFastest ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                                .fixedSize()
                                .gridColumnAlignment(.trailing)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .padding(.top, 16)
            }
        }
        if !model.heartRate.isEmpty || model.refreshTitle != nil {
            heartRateSection
        }
        if !model.performance.isEmpty {
            section("Performance") {
                ForEach(Array(model.performance.enumerated()), id: \.offset) { _, row in
                    CutStatColumns(row.count == 1 ? row + [CutStatColumn(value: "", label: "")] : row)
                        .padding(.vertical, 14)
                    CutHairline()
                }
            }
        }
    }

    private func exerciseRow(_ exercise: CutPostDetailModel.Exercise) -> some View {
        let isOpen = openExercises.contains(exercise.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.light()
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
                    if !heart.bars.isEmpty {
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(Array(heart.bars.enumerated()), id: \.offset) { _, value in
                                Rectangle()
                                    .fill(DS.Cut.Colors.lime.opacity(0.25 + 0.75 * value))
                                    .frame(height: 72 * value)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 72, alignment: .bottom)
                        .padding(.top, 18)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Heart rate over the workout"))
                    }
                    if !heart.zones.isEmpty {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                            ForEach(heart.zones) { zone in
                                GridRow {
                                    Text(zone.label)
                                        .cutFont(.title)
                                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                                        .fixedSize()
                                        .accessibilityLabel(Text("\(zone.label), \(zone.time)"))
                                    CutCardioBar(fraction: zone.fraction,
                                                 fill: DS.Cut.Colors.lime.opacity(0.35 + 0.13 * Double(zone.id)))
                                    Text(zone.time)
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
            CutSectionTitle("Comments")
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
                    .lineLimit(1)
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
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = comment.id }
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
                Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = comment.id }
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
                                            .lineLimit(1)
                                        Text(person.handle)
                                            .cutFont(.secondary)
                                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                                            .lineLimit(1)
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
                        .lineLimit(1)
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
                    ), axis: .vertical)
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
                CutSocialMessage(title: "Post not found", line: message, button: "Try again", action: retry)
            }
        }
        .scrollIndicators(.hidden)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }
}
