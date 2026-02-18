//
//  PostDetailView.swift
//  WRKT
//
//  Detailed view of a workout post with comments
//

import SwiftUI
import Kingfisher
import Charts

// MARK: - Cardio Tab Enum
private enum CardioTab: String, CaseIterable {
    case overview = "Overview"
    case splits = "Splits"
    case heartRate = "Heart Rate"
}

struct PostDetailView: View {
    @Environment(\.dependencies) private var deps

    let post: PostWithAuthor

    @State private var viewModel: PostDetailViewModel?
    @FocusState private var isCommentFieldFocused: Bool
    @State private var displayImageURLs: [URL] = []
    @State private var selectedCardioTab: CardioTab = .overview

    private let imageUploadService = ImageUploadService()

    var body: some View {
        Group {
            if let viewModel = viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                let vm = PostDetailViewModel(
                    post: post,
                    postRepository: deps.postRepository,
                    authService: deps.authService
                )
                viewModel = vm
                await vm.loadComments()
            }
            await loadImageURLs()
        }
    }

    @ViewBuilder
    private func content(viewModel: PostDetailViewModel) -> some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Post Header
                    postHeader(viewModel: viewModel)

                    // Caption (skip for cardio — the card is the content)
                    if !viewModel.post.post.workoutData.isCardioWorkout,
                       let caption = viewModel.post.post.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.body)
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .padding(.horizontal)
                    }

                    // Images (skip for cardio — map is shown in workout details section)
                    if !displayImageURLs.isEmpty && !viewModel.post.post.workoutData.isCardioWorkout {
                        imageCarousel(imageUrls: displayImageURLs.map { $0.absoluteString })
                    }

                    // Workout Details
                    workoutDetails(viewModel: viewModel)

                    // Like/Comment counts
                    statsSection(viewModel: viewModel)

                    Divider()

                    // Comments Section
                    commentsSection(viewModel: viewModel)
                }
                .padding(.bottom, 100) // Space for comment input
            }
            .scrollDismissesKeyboard(.interactively)

            // Comment Input (sticky at bottom)
            commentInput(viewModel: viewModel)
        }
    }

    private func postHeader(viewModel: PostDetailViewModel) -> some View {
        HStack(spacing: 12) {
            // Avatar (chamfered logo style)
            KFImage(URL(string: viewModel.post.author.avatarUrl ?? ""))
                .placeholder {
                    ChamferedRectangleAlt(.small)
                        .fill(DS.Semantic.brandSoft)
                        .overlay(
                            Text(viewModel.post.author.username.prefix(1).uppercased())
                                .font(.title3.bold())
                                .foregroundStyle(DS.Semantic.brand)
                        )
                }
                .fade(duration: 0.25)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(ChamferedRectangleAlt(.small))

            // Username + Time
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.post.author.displayName ?? viewModel.post.author.username)
                    .font(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                HStack(spacing: 4) {
                    Text(viewModel.post.relativeTime)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Image(systemName: viewModel.post.post.visibility.icon)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    private func imageCarousel(imageUrls: [String]) -> some View {
        TabView {
            ForEach(imageUrls, id: \.self) { urlString in
                KFImage(URL(string: urlString))
                    .placeholder {
                        Rectangle()
                            .fill(DS.Semantic.fillSubtle)
                            .overlay(ProgressView())
                    }
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(height: 350)
        .tabViewStyle(.page(indexDisplayMode: imageUrls.count > 1 ? .always : .never))
    }

    private func workoutDetails(viewModel: PostDetailViewModel) -> some View {
        let workout = viewModel.post.post.workoutData

        return VStack(alignment: .leading, spacing: 16) {
            Text("Workout Details")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)
                .padding(.horizontal)

            // Map image for cardio posts
            if workout.isCardioWorkout, !displayImageURLs.isEmpty {
                KFImage(displayImageURLs.first)
                    .placeholder {
                        Rectangle()
                            .fill(DS.Semantic.fillSubtle)
                            .overlay(ProgressView())
                    }
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 260)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
            }

            // Different stats for cardio vs strength
            if workout.isCardioWorkout {
                // Cardio tabbed interface
                cardioTabbedContent(workout: workout, viewModel: viewModel)
            } else {
                // Strength Stats
                HStack(spacing: 16) {
                    statCard(
                        icon: "dumbbell.fill",
                        value: "\(viewModel.post.post.exerciseCount)",
                        label: "Exercises"
                    )

                    statCard(
                        icon: "list.bullet",
                        value: "\(viewModel.post.post.totalSets)",
                        label: "Sets"
                    )

                    if viewModel.post.post.totalVolume > 0 {
                        statCard(
                            icon: "scalemass.fill",
                            value: formatVolume(viewModel.post.post.totalVolume),
                            label: "Volume"
                        )
                    }

                    if viewModel.post.post.duration != nil {
                        statCard(
                            icon: "clock.fill",
                            value: viewModel.post.post.durationFormatted,
                            label: "Duration"
                        )
                    }
                }
                .padding(.horizontal)

                // Exercise List (only for strength)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.post.post.workoutData.entries) { entry in
                        exerciseRow(entry: entry)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
        .background(DS.Semantic.fillSubtle.opacity(0.5))
    }

    // MARK: - Cardio Tabbed Content
    private func cardioTabbedContent(workout: CompletedWorkout, viewModel: PostDetailViewModel) -> some View {
        VStack(spacing: 16) {
            // Tab picker
            Picker("", selection: $selectedCardioTab) {
                ForEach(CardioTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Tab content
            switch selectedCardioTab {
            case .overview:
                cardioOverviewTab(workout: workout)
            case .splits:
                cardioSplitsTab(workout: viewModel.post.post.workoutData, viewModel: viewModel)
            case .heartRate:
                cardioHeartRateTab(workout: viewModel.post.post.workoutData, viewModel: viewModel)
            }
        }
    }

    // MARK: - Cardio Overview Tab
    private func cardioOverviewTab(workout: CompletedWorkout) -> some View {
        VStack(spacing: 12) {
            // Distance and Time (hero row)
            if let distanceMeters = workout.matchedHealthKitDistance, distanceMeters > 0 {
                HStack(spacing: 16) {
                    // Distance
                    VStack(spacing: 4) {
                        Text(String(format: "%.2f", distanceMeters / 1000))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.Palette.marone)
                        Text("KILOMETERS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Semantic.textSecondary)
                            .tracking(0.5)
                    }
                    .frame(maxWidth: .infinity)

                    // Divider
                    Rectangle()
                        .fill(DS.Semantic.border)
                        .frame(width: 1, height: 50)

                    // Duration
                    VStack(spacing: 4) {
                        if let durationSec = workout.matchedHealthKitDuration {
                            Text(formatCardioDuration(durationSec))
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Semantic.textPrimary)
                        } else {
                            Text("--:--")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Semantic.textPrimary)
                        }
                        Text("TIME")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Semantic.textSecondary)
                            .tracking(0.5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 16)
                .padding(.horizontal)
                .background(DS.Semantic.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }

            // Pace (if distance and duration available)
            if let distanceMeters = workout.matchedHealthKitDistance,
               let durationSec = workout.matchedHealthKitDuration,
               distanceMeters > 0 {
                let paceSecPerKm = Double(durationSec) / (distanceMeters / 1000)
                HStack(spacing: 12) {
                    statCard(icon: "figure.run", value: formatPace(paceSecPerKm), label: "Pace/km")

                    if let calories = workout.matchedHealthKitCalories {
                        statCard(icon: "flame.fill", value: String(format: "%.0f", calories), label: "Calories")
                    }
                }
                .padding(.horizontal)
            }

            // Running Dynamics
            RunningDynamicsGrid(
                avgPower: workout.cardioAvgPower,
                avgCadence: workout.cardioAvgCadence,
                avgStrideLength: workout.cardioAvgStrideLength,
                avgGroundContactTime: workout.cardioAvgGroundContactTime,
                avgVerticalOscillation: workout.cardioAvgVerticalOscillation
            )
            .padding(.horizontal)
        }
    }

    // MARK: - Cardio Splits Tab
    private func cardioSplitsTab(workout: CompletedWorkout, viewModel: PostDetailViewModel) -> some View {
        VStack(spacing: 12) {
            // Refresh button if available
            if viewModel.canRefreshCardioData {
                HStack {
                    Spacer()
                    if viewModel.isRefreshingCardioData {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button {
                            Task {
                                await viewModel.refreshCardioData()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text(workout.cardioSplits == nil ? "Load" : "Refresh")
                            }
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.brand)
                        }
                    }
                }
                .padding(.horizontal)
            }

            SplitsChart(splits: workout.cardioSplits ?? [])
                .padding(.horizontal)
        }
    }

    // MARK: - Cardio Heart Rate Tab
    private func cardioHeartRateTab(workout: CompletedWorkout, viewModel: PostDetailViewModel) -> some View {
        VStack(spacing: 12) {
            // HR Stats row
            HStack(spacing: 12) {
                if let avgHR = workout.matchedHealthKitHeartRate {
                    statCard(icon: "heart.fill", value: String(format: "%.0f", avgHR), label: "Avg BPM")
                }
                if let maxHR = workout.matchedHealthKitMaxHeartRate {
                    statCard(icon: "bolt.heart.fill", value: String(format: "%.0f", maxHR), label: "Max BPM")
                }
                if let minHR = workout.matchedHealthKitMinHeartRate {
                    statCard(icon: "heart", value: String(format: "%.0f", minHR), label: "Min BPM")
                }
            }
            .padding(.horizontal)

            // Refresh button
            if viewModel.canRefreshCardioData {
                HStack {
                    Spacer()
                    if viewModel.isRefreshingCardioData {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button {
                            Task {
                                await viewModel.refreshCardioData()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text(workout.cardioHRZones == nil ? "Load" : "Refresh")
                            }
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.brand)
                        }
                    }
                }
                .padding(.horizontal)
            }

            HRZoneChart(
                zones: workout.cardioHRZones ?? [],
                samples: workout.matchedHealthKitHeartRateSamples
            )
            .padding(.horizontal)
        }
    }

    private func formatPace(_ secPerKm: Double) -> String {
        let minutes = Int(secPerKm) / 60
        let seconds = Int(secPerKm) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatCardioDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    private func statCard(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DS.Semantic.brand)

            Text(value)
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text(label)
                .font(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func exerciseRow(entry: WorkoutEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.exerciseName)
                .font(.subheadline.bold())
                .foregroundStyle(DS.Semantic.textPrimary)

            ForEach(Array(entry.sets.enumerated()), id: \.offset) { index, set in
                HStack {
                    Text("Set \(index + 1):")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    if set.weight > 0 {
                        Text("\(set.weight.safeInt) kg × \(set.reps) reps")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textPrimary)
                    } else {
                        Text("\(set.reps) reps")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textPrimary)
                    }

                    Spacer()

                    if set.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(DS.Status.success)
                    }
                }
            }
        }
        .padding(12)
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statsSection(viewModel: PostDetailViewModel) -> some View {
        HStack(spacing: 20) {
            // Like button
            Button {
                Task {
                    await viewModel.toggleLike()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.post.isLikedByCurrentUser ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(viewModel.post.isLikedByCurrentUser ? DS.Semantic.brand : DS.Semantic.textSecondary)
                        .symbolEffect(.bounce, value: viewModel.post.isLikedByCurrentUser)

                    Text("\(viewModel.post.post.likesCount)")
                        .font(.subheadline.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)
                }
            }

            // Comment count
            HStack(spacing: 6) {
                Image(systemName: "bubble.right.fill")
                    .font(.title3)
                    .foregroundStyle(DS.Semantic.textSecondary)

                Text("\(viewModel.post.post.commentsCount)")
                    .font(.subheadline.bold())
                    .foregroundStyle(DS.Semantic.textPrimary)
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    private func commentsSection(viewModel: PostDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)
                .padding(.horizontal)

            if viewModel.isLoadingComments {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if viewModel.comments.isEmpty {
                Text("No comments yet. Be the first to comment!")
                    .font(.subheadline)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(viewModel.comments) { comment in
                    CommentRow(
                        comment: comment,
                        isReply: false,
                        canDelete: comment.userId == deps.authService.currentUser?.id,
                        onDelete: {
                            Task {
                                await viewModel.deleteComment(comment)
                            }
                        },
                        onReply: {
                            viewModel.startReply(to: comment)
                            isCommentFieldFocused = true
                        }
                    )
                    .padding(.horizontal)
                }
            }
        }
    }

    private func commentInput(viewModel: PostDetailViewModel) -> some View {
        VStack(spacing: 0) {
            // Mention autocomplete (above comment input)
            if !viewModel.mentionSuggestions.isEmpty {
                MentionAutocomplete(
                    suggestions: viewModel.mentionSuggestions,
                    onSelect: { user in
                        viewModel.insertMention(user)
                    }
                )
                .padding(.bottom, 8)
            }

            // Reply indicator (if replying to a comment)
            if let replyingTo = viewModel.replyingTo {
                HStack {
                    Text("Replying to @\(replyingTo.author?.username ?? "unknown")")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Spacer()

                    Button {
                        viewModel.cancelReply()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(DS.Semantic.fillSubtle.opacity(0.5))
            }

            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Add a comment...", text: Binding(
                    get: { viewModel.commentText },
                    set: { newValue in
                        viewModel.commentText = newValue
                        viewModel.detectMentionQuery(in: newValue)
                    }
                ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isCommentFieldFocused)
                    .disabled(viewModel.isPostingComment)
                    .submitLabel(.return)

                Button {
                    Task {
                        await viewModel.postComment()
                        isCommentFieldFocused = false
                    }
                } label: {
                    if viewModel.isPostingComment {
                        ProgressView()
                            .tint(DS.Semantic.brand)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(
                                viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? DS.Semantic.textSecondary
                                    : DS.Semantic.brand
                            )
                    }
                }
                .disabled(viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isPostingComment)
            }
            .padding()
            .background(DS.Semantic.card)
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return String(format: "%.0f", volume)
    }

    // MARK: - Load Image URLs

    private func loadImageURLs() async {
        guard let userId = deps.authService.currentUser?.id else { return }
        guard let images = post.post.images, !images.isEmpty else { return }

        do {
            let urls = try await imageUploadService.getImageURLs(
                for: images,
                currentUserId: userId,
                postOwnerId: post.post.userId
            )
            await MainActor.run {
                displayImageURLs = urls
            }
        } catch {
            print("⚠️ Failed to load image URLs: \(error)")
        }
    }
}

// MARK: - Comment Row Component

struct CommentRow: View {
    let comment: PostComment
    let isReply: Bool
    let canDelete: Bool
    let onDelete: () -> Void
    let onReply: () -> Void

    @State private var showingDeleteAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main comment
            HStack(alignment: .top, spacing: 12) {
                // Indent for replies
                if isReply {
                    // Connecting line
                    Rectangle()
                        .fill(DS.Semantic.textSecondary.opacity(0.3))
                        .frame(width: 2)
                        .padding(.leading, 20)

                    // Horizontal line to avatar
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(DS.Semantic.textSecondary.opacity(0.3))
                            .frame(width: 20, height: 2)
                        Spacer()
                    }
                    .frame(height: 20)
                }

                // Avatar (chamfered logo style)
                if let author = comment.author {
                    KFImage(URL(string: author.avatarUrl ?? ""))
                        .placeholder {
                            ChamferedRectangleAlt(chamferSize: isReply ? 6 : 8)
                                .fill(DS.Semantic.brandSoft)
                                .overlay(
                                    Text(author.username.prefix(1).uppercased())
                                        .font(isReply ? .system(size: 10, weight: .bold) : .caption.bold())
                                        .foregroundStyle(DS.Semantic.brand)
                                )
                        }
                        .fade(duration: 0.25)
                        .resizable()
                        .scaledToFill()
                        .frame(width: isReply ? 28 : 32, height: isReply ? 28 : 32)
                        .clipShape(ChamferedRectangleAlt(chamferSize: isReply ? 6 : 8))
                }

                // Comment content
                VStack(alignment: .leading, spacing: 4) {
                    // Username and time
                    HStack(spacing: 6) {
                        if let author = comment.author {
                            Text("@\(author.username)")
                                .font(.subheadline.bold())
                                .foregroundStyle(DS.Semantic.textPrimary)
                        }

                        Text(relativeTime(for: comment.createdAt))
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)

                        Spacer()

                        if canDelete {
                            Button {
                                showingDeleteAlert = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(DS.Status.error)
                            }
                        }
                    }

                    // Comment text with mentions highlighted
                    MentionText(text: comment.content, mentions: comment.mentions)
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Reply button (only for top-level comments)
                    if !isReply {
                        Button {
                            onReply()
                        } label: {
                            Text("Reply")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                        .padding(.top, 4)
                    }
                }
            }

            // Nested replies
            if let replies = comment.replies, !replies.isEmpty, !isReply {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(replies) { reply in
                        CommentRow(
                            comment: reply,
                            isReply: true,
                            canDelete: false,  // Simplified: only allow deleting own top-level comments for now
                            onDelete: {},
                            onReply: {}
                        )
                    }
                }
                .padding(.top, 12)
            }
        }
        .alert("Delete Comment", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete this comment?")
        }
    }

    private func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

