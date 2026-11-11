//
//  PostCard.swift
//  WRKT
//
//  Social feed post card component
//

import SwiftUI
import Kingfisher

struct PostCard: View {
    let post: PostWithAuthor
    let currentUserId: UUID?
    let onLike: () -> Void
    let onComment: () -> Void
    let onShowLikes: (() -> Void)?
    let onProfileTap: () -> Void
    let onPostTap: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    let onRemoveMe: (() -> Void)?
    let onBackfillRoute: (() async -> Bool)?
    var onPartnerProfileTap: ((UUID) -> Void)? = nil

    @State private var showingImageViewer = false
    @State private var selectedImageIndex = 0
    @State private var showingDeleteAlert = false
    @State private var showingRemoveMeAlert = false
    @State private var showingReportAlert = false
    @State private var showingMenuSheet = false
    @State private var displayImageURLs: [URL] = []
    @State private var resolvedImages: [ResolvedPostImage] = []
    @State private var isBackfilling = false

    private let imageUploadService = ImageUploadService()

    private var userImageURLs: [URL] {
        resolvedImages.filter { !$0.image.isGeneratedMapImage }.map(\.url)
    }

    private var generatedMapURLs: [URL] {
        resolvedImages.filter { $0.image.isGeneratedMapImage }.map(\.url)
    }

    // For single cardio posts: route map(s) first, then user photos
    private var allCardioImageURLs: [URL] {
        generatedMapURLs + userImageURLs
    }

    private var activePartner: PostParticipant? {
        post.partners.first { $0.removedAt == nil }
    }

    private var shouldShowSharedPostPresentation: Bool {
        post.post.postType == .shared && activePartner != nil
    }

    private var canRemoveCurrentUserFromPost: Bool {
        guard let currentUserId, post.post.userId != currentUserId else { return false }
        return post.partners.contains { $0.userId == currentUserId && $0.removedAt == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Avatar + Username + Time
            header

            postContent

            // Action Buttons (Like, Comment, Share)
            actionButtons

            // Like/Comment Counts
            statsRow
        }
        .padding(16)
        .background(DS.Semantic.card)
        .clipShape(DS.RoleShape(.card, legacy: ChamferedRectangle(.large)))
        .overlay(
            DS.RoleShape(.card, legacy: ChamferedRectangle(.large))
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .sheet(isPresented: $showingImageViewer) {
            let viewerURLs = (!post.post.isMultiWorkout && post.post.workoutData.isCardioWorkout)
                ? allCardioImageURLs.map { $0.absoluteString }
                : userImageURLs.map { $0.absoluteString }
            ImageViewer(imageUrls: viewerURLs, selectedIndex: $selectedImageIndex)
        }
        .sheet(isPresented: $showingMenuSheet) {
            PostMenuSheet(
                post: post,
                isOwnPost: post.post.userId == currentUserId,
                onEdit: {
                    onEdit?()
                },
                onDelete: {
                    showingDeleteAlert = true
                },
                canRemoveMe: canRemoveCurrentUserFromPost,
                onRemoveMe: {
                    showingRemoveMeAlert = true
                },
                onShare: {
                    sharePost()
                },
                onReport: {
                    reportPost()
                }
            )
        }
        .alert("Delete Post", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("Are you sure you want to delete this post? This action cannot be undone.")
        }
        .alert("Remove Me", isPresented: $showingRemoveMeAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                onRemoveMe?()
            }
        } message: {
            Text("This post will no longer appear as one you shared together.")
        }
        .alert("Report Post", isPresented: $showingReportAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Report", role: .destructive) {
                submitReport()
            }
        } message: {
            Text("Report this post for inappropriate content? Our team will review it.")
        }
        .task(id: imageTaskKey) {
            await loadImageURLs()

            // Lazy map backfill: own cardio post with HealthKit UUID but no map image
            if post.post.userId == currentUserId,
               post.post.workoutData.isCardioWorkout,
               !post.post.isMultiWorkout,
               generatedMapURLs.isEmpty,    // backfill only when no route map exists
               post.post.workoutData.matchedHealthKitUUID != nil {
                await runBackfill()
            }
        }
    }

    @ViewBuilder
    private var postContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Caption
            if let caption = post.post.caption, !caption.isEmpty {
                Text(caption)
                    .dsFont(.body)
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Workout Summary
            if post.post.postType == .weeklyProgress, let stats = post.post.weeklyStats {
                WeeklyProgressFeedCard(stats: stats)
            } else if post.post.postType == .battle, let stats = post.post.battleStats {
                BattlePostCard(stats: stats)
            } else if shouldShowSharedPostPresentation, let partner = activePartner {
                sharedPostContent(partner: partner)
            } else if post.post.isMultiWorkout {
                MultiWorkoutCarousel(
                    workouts: post.post.allWorkouts,
                    mapURLs: generatedMapURLs
                )
                if !userImageURLs.isEmpty {
                    PostImageStrip(
                        imageUrls: userImageURLs.map { $0.absoluteString },
                        selectedImageIndex: $selectedImageIndex
                    ) {
                        showingImageViewer = true
                    }
                }
            } else if post.post.workoutData.isCardioWorkout {
                WorkoutPostHeroSummaryCard(
                    summary: .make(for: [post.post.workoutData]),
                    context: .feed
                )
                cardioImagesSection
            } else {
                VStack(spacing: 12) {
                    WorkoutPostHeroSummaryCard(
                        summary: .make(for: [post.post.workoutData]),
                        context: .feed
                    )
                }
                if !userImageURLs.isEmpty {
                    PostImageStrip(
                        imageUrls: userImageURLs.map { $0.absoluteString },
                        selectedImageIndex: $selectedImageIndex
                    ) {
                        showingImageViewer = true
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.light()
            onPostTap()
        }
    }

    // MARK: - Load Image URLs

    private func loadImageURLs() async {
        guard let userId = currentUserId else {
            print("⚠️ [PostCard] No current user ID")
            return
        }

        guard let images = post.post.images, !images.isEmpty else {
            print("ℹ️ [PostCard] No images for post \(post.post.id)")
            return
        }

        print("📸 [PostCard] Loading \(images.count) images for post \(post.post.id)")
        print("  Images: \(images.map { "\($0.storagePath) (public: \($0.isPublic))" })")

        do {
            var pairs: [ResolvedPostImage] = []
            for image in images {
                if let url = try await imageUploadService.getImageURL(
                    for: image,
                    currentUserId: userId,
                    postOwnerId: post.post.userId
                ) {
                    pairs.append(ResolvedPostImage(image: image, url: url))
                }
            }
            print("✅ [PostCard] Loaded \(pairs.count) URLs")
            await MainActor.run {
                resolvedImages = pairs
                displayImageURLs = pairs.map(\.url)
            }
        } catch {
            print("❌ [PostCard] Failed to load image URLs: \(error)")
        }
    }

    // MARK: - Lazy Map Backfill

    private var imageTaskKey: String {
        let imageCount = post.post.images?.count ?? 0
        return "\(post.post.id.uuidString)-\(imageCount)-\(post.post.updatedAt.timeIntervalSince1970)"
    }

    private func runBackfill() async {
        guard !isBackfilling,
              let onBackfillRoute else { return }
        isBackfilling = true
        let success = await onBackfillRoute()
        if success {
            await loadImageURLs()
        }
        isBackfilling = false
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if let partner = activePartner, shouldShowSharedPostPresentation {
            sharedHeader(partner: partner)
        } else {
            standardHeader
        }
    }

    private var standardHeader: some View {
        HStack(spacing: 12) {
            PostAvatar(
                avatarUrl: post.author.avatarUrl,
                fallbackName: post.author.displayName ?? post.author.username,
                size: 40
            )
                .onTapGesture {
                    onProfileTap()
                }

            // Username + Time + spacer — taps open the post
            Button {
                onPostTap()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.author.displayName ?? post.author.username)
                            .dsFont(.subheadline, weight: .bold)
                            .foregroundStyle(DS.Semantic.textPrimary)

                        HStack(spacing: 4) {
                            Text(post.relativeTime)
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)

                            Text("•")
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)

                            Image(systemName: post.post.visibility.icon)
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // More menu button
            Button {
                showingMenuSheet = true
            } label: {
                Image(systemName: "ellipsis")
                    .dsFont(.body)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .padding(8)
            }
        }
    }

    private func sharedHeader(partner: PostParticipant) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                PostAvatar(
                    avatarUrl: post.author.avatarUrl,
                    fallbackName: post.author.displayName ?? post.author.username,
                    size: 40
                )
                .onTapGesture {
                    onProfileTap()
                }

                PostAvatar(
                    avatarUrl: partner.profile?.avatarUrl,
                    fallbackName: partnerDisplayName(partner),
                    size: 40
                )
                .overlay(
                    ChamferedRectangleAlt(.small)
                        .stroke(DS.Semantic.card, lineWidth: 2)
                )
                .offset(x: 28)
                .onTapGesture {
                    onPartnerProfileTap?(partner.userId)
                }
            }
            .frame(width: 68, height: 40, alignment: .leading)

            Button {
                onPostTap()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(post.author.displayName ?? post.author.username) and \(partnerDisplayName(partner))")
                            .dsFont(.subheadline, weight: .bold)
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Text(post.relativeTime)
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)

                            Text("•")
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)

                            Image(systemName: post.post.visibility.icon)
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                showingMenuSheet = true
            } label: {
                Image(systemName: "ellipsis")
                    .dsFont(.body)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .padding(8)
            }
        }
    }

    // MARK: - Shared Post Content

    @ViewBuilder
    private func sharedPostContent(partner: PostParticipant) -> some View {
        if let stats = partner.vrStats {
            if post.post.workoutData.isCardioWorkout {
                cardioImagesSection
            }
            sharedRunComparison(partner: partner, stats: stats)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                WorkoutPostHeroSummaryCard(
                    summary: .make(for: [post.post.workoutData]),
                    context: .feed
                )

                if post.post.workoutData.isCardioWorkout {
                    cardioImagesSection
                } else if !userImageURLs.isEmpty {
                    PostImageStrip(
                        imageUrls: userImageURLs.map { $0.absoluteString },
                        selectedImageIndex: $selectedImageIndex
                    ) {
                        showingImageViewer = true
                    }
                }

                sharedPartnerStrip(partner: partner)
            }
        }
    }

    private func sharedPartnerStrip(partner: PostParticipant) -> some View {
        HStack(spacing: 10) {
            PostAvatar(
                avatarUrl: partner.profile?.avatarUrl,
                fallbackName: partnerDisplayName(partner),
                size: 28
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Worked out with")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
                Text(partnerDisplayName(partner))
                    .dsFont(.caption, weight: .bold)
                    .foregroundStyle(DS.Semantic.textPrimary)
            }

            Spacer()

            Image(systemName: "person.2.fill")
                .dsFont(.caption)
                .foregroundStyle(DS.Semantic.brand)
        }
        .padding(12)
        .background(DS.Semantic.fillSubtle)
        .clipShape(DS.RoleShape(.nested, legacy: ChamferedRectangle(.small)))
        .overlay(
            DS.RoleShape(.nested, legacy: ChamferedRectangle(.small))
                .stroke(DS.Semantic.border.opacity(0.8), lineWidth: 1)
        )
    }

    private func sharedRunComparison(partner: PostParticipant, stats: VRPartnerSummary) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label("Shared Run", systemImage: "figure.run")
                    .dsFont(.caption, weight: .bold)
                    .foregroundStyle(DS.Semantic.brand)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Rectangle().fill(DS.Semantic.border.opacity(0.6)).frame(height: 1)

            sharedRunMetricRow(
                label: "DISTANCE",
                leftValue: distanceText(post.post.workoutData.matchedHealthKitDistance),
                rightValue: distanceText(stats.distanceM),
                partner: partner
            )

            Rectangle().fill(DS.Semantic.border.opacity(0.6)).frame(height: 1)

            sharedRunMetricRow(
                label: "PACE",
                leftValue: paceText(for: post.post.workoutData),
                rightValue: stats.paceSecPerKm.map { "\(WorkoutPostStatsViews.formatPace(Double($0))) /km" } ?? "--",
                partner: partner
            )

            Rectangle().fill(DS.Semantic.border.opacity(0.6)).frame(height: 1)

            sharedRunMetricRow(
                label: "DURATION",
                leftValue: durationText(post.post.workoutData.matchedHealthKitDuration),
                rightValue: durationText(stats.durationS),
                partner: partner
            )
        }
        .background(DS.Semantic.card)
        .clipShape(DS.RoleShape(.nested, legacy: ChamferedRectangle(.medium)))
        .overlay(
            DS.RoleShape(.nested, legacy: ChamferedRectangle(.medium))
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }

    private func sharedRunMetricRow(
        label: String,
        leftValue: String,
        rightValue: String,
        partner: PostParticipant
    ) -> some View {
        HStack(spacing: 0) {
            SharedMetricColumn(
                name: post.author.displayName ?? post.author.username,
                value: leftValue,
                label: label
            )

            Rectangle()
                .fill(DS.Semantic.border)
                .frame(width: 1, height: 44)

            SharedMetricColumn(
                name: partnerDisplayName(partner),
                value: rightValue,
                label: label
            )
        }
        .padding(.vertical, 12)
    }

    // MARK: - Cardio Images Section

    @ViewBuilder
    private var cardioImagesSection: some View {
        if !allCardioImageURLs.isEmpty {
            cardioImageCarousel
        } else if post.post.userId == currentUserId,
                  post.post.workoutData.matchedHealthKitUUID != nil {
            Button {
                Task { await runBackfill() }
            } label: {
                HStack(spacing: 6) {
                    if isBackfilling {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(DS.Semantic.brand)
                    } else {
                        Image(systemName: "map.fill")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.brand)
                    }
                    Text(isBackfilling ? "Building route..." : "Get Route Map")
                        .dsFont(.caption, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(DS.Semantic.fillSubtle, in: DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 8)))
            }
            .disabled(isBackfilling)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Cardio Image Carousel (map first, user photos after)

    private var cardioImageCarousel: some View {
        VStack(spacing: 6) {
            TabView(selection: $selectedImageIndex) {
                ForEach(Array(allCardioImageURLs.enumerated()), id: \.offset) { index, url in
                    ZStack(alignment: .bottomLeading) {
                        KFImage(url)
                            .placeholder {
                                Rectangle()
                                    .fill(DS.Semantic.fillSubtle)
                                    .overlay(ProgressView())
                            }
                            .fade(duration: 0.25)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .clipped()
                            .clipShape(ChamferedRectangle(.small))
                            .contentShape(Rectangle())

                        // Pace badge only on route map slides
                        if index < generatedMapURLs.count,
                           let distanceMeters = post.post.workoutData.matchedHealthKitDistance,
                           let durationSec = post.post.workoutData.matchedHealthKitDuration,
                           distanceMeters > 0 {
                            let paceSecPerKm = Double(durationSec) / (distanceMeters / 1000)
                            HStack(spacing: 4) {
                                Image(systemName: "figure.run").dsFont(.caption2)
                                Text(WorkoutPostStatsViews.formatPace(paceSecPerKm))
                                    .dsFont(.caption, weight: .bold)
                                Text("/km").dsFont(.caption2)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(8)
                        }
                    }
                    .tag(index)
                    .onTapGesture {
                        selectedImageIndex = index
                        showingImageViewer = true
                    }
                }
            }
            .frame(height: 180)
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Line-style dots matching the rest of the app's carousel design
            if allCardioImageURLs.count > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<allCardioImageURLs.count, id: \.self) { idx in
                        Capsule()
                            .fill(idx == selectedImageIndex ? DS.Semantic.brand : Color.secondary.opacity(0.3))
                            .frame(width: idx == selectedImageIndex ? 24 : 8, height: 3)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedImageIndex)
                    }
                }
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 20) {
            // Like button
            Button {
                Haptics.light()
                onLike()
            } label: {
                Image(post.isLikedByCurrentUser ? "tab-cardio" : "tab-cardio-inactive")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }

            // Comment button
            Button {
                Haptics.light()
                onComment()
            } label: {
                Image("tab-social-inactive")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }

            Spacer()

            // Share button
            Button {
                Haptics.light()
                sharePost()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .dsFont(.title3)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 4) {
            if post.post.likesCount > 0 {
                Button {
                    Haptics.light()
                    onShowLikes?()
                } label: {
                    Text("\(post.post.likesCount) \(post.post.likesCount == 1 ? "like" : "likes")")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(onShowLikes == nil)
            }

            if post.post.commentsCount > 0 {
                if post.post.likesCount > 0 {
                    Text("•")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Button {
                    Haptics.light()
                    onComment()
                } label: {
                    Text("\(post.post.commentsCount) \(post.post.commentsCount == 1 ? "comment" : "comments")")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func partnerDisplayName(_ partner: PostParticipant) -> String {
        partner.profile?.displayName ?? partner.profile?.username ?? "Partner"
    }

    private func distanceText(_ meters: Double?) -> String {
        guard let meters, meters > 0 else { return "--" }
        let km = meters / 1000
        if km >= 10 {
            return "\(Int(km.rounded())) km"
        }
        return String(format: "%.1f km", km)
    }

    private func durationText(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "--" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func paceText(for workout: CompletedWorkout) -> String {
        guard let distance = workout.matchedHealthKitDistance,
              let duration = workout.matchedHealthKitDuration,
              distance > 0,
              duration > 0 else {
            return "--"
        }
        let pace = Double(duration) / (distance / 1000)
        return "\(WorkoutPostStatsViews.formatPace(pace)) /km"
    }

    private func sharePost() {
        // Create share URL or text
        let shareText = "Check out this workout on WRKT!"
        let av = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            rootViewController.present(av, animated: true)
        }
    }

    private func reportPost() {
        showingReportAlert = true
    }

    private func submitReport() {
        // For now, just show a confirmation toast
        // In a full implementation, this would send to a backend reports table
        Haptics.success()
        WorkoutToastManager.shared.show(message: "Report submitted. Thank you.")
    }

}

// MARK: - Resolved Post Image

private struct ResolvedPostImage: Identifiable {
    let image: PostImage
    let url: URL

    var id: UUID { image.id }
}

// MARK: - Post Avatar

private struct PostAvatar: View {
    let avatarUrl: String?
    let fallbackName: String
    let size: CGFloat

    var body: some View {
        KFImage(URL(string: avatarUrl ?? ""))
            .placeholder {
                ChamferedRectangleAlt(.small)
                    .fill(DS.Semantic.brandSoft)
                    .overlay(
                        Text(fallbackName.prefix(1).uppercased())
                            .dsFont(size > 32 ? .title3 : .caption, weight: .bold)
                            .foregroundStyle(DS.Semantic.brand)
                    )
            }
            .fade(duration: 0.25)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(ChamferedRectangleAlt(.small))
            .contentShape(ChamferedRectangleAlt(.small))
    }
}

// MARK: - Shared Metric Column

private struct SharedMetricColumn: View {
    let name: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(name)
                .dsFont(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
                .lineLimit(1)

            Text(value)
                .dsFont(.subheadline, weight: .bold)
                .foregroundStyle(DS.Semantic.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(label)
                .dsFont(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Post Image Strip

struct PostImageStrip: View {
    let imageUrls: [String]
    @Binding var selectedImageIndex: Int
    let onImageTap: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Divider()

            TabView {
                ForEach(Array(imageUrls.enumerated()), id: \.offset) { index, urlString in
                    KFImage(URL(string: urlString))
                        .placeholder {
                            Rectangle()
                                .fill(DS.Semantic.fillSubtle)
                                .overlay(ProgressView())
                        }
                        .fade(duration: 0.25)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedImageIndex = index
                            onImageTap()
                        }
                }
            }
            .frame(height: 180)
            .tabViewStyle(.page(indexDisplayMode: imageUrls.count > 1 ? .always : .never))
        }
    }
}

// MARK: - Image Viewer

struct ImageViewer: View {
    let imageUrls: [String]
    @Binding var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(imageUrls.enumerated()), id: \.offset) { index, urlString in
                    KFImage(URL(string: urlString))
                        .placeholder {
                            ProgressView()
                                .tint(.white)
                        }
                        .fade(duration: 0.25)
                        .resizable()
                        .scaledToFit()
                        .tag(index)
                }
            }
            .tabViewStyle(.page)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .dsFont(.title)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding()
            }
        }
    }
}

// MARK: - Weekly Progress Feed Card

struct WeeklyProgressFeedCard: View {
    let stats: WeeklyPostStats

    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    private var volumeFormatted: String {
        unit.formatVolume(stats.totalVolumeKg)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("WEEKLY PROGRESS")
                    .dsFont(.caption, weight: .bold)
                    .foregroundStyle(DS.Semantic.brand)
                    .tracking(0.8)
                Spacer()
                Text(stats.weekStart, format: .dateTime.month(.abbreviated).day())
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Rectangle().fill(DS.Semantic.border.opacity(0.6)).frame(height: 1)

            // Top row: volume, exercises, sets
            HStack(spacing: 0) {
                weekStatCell(value: volumeFormatted, label: "TONNAGE")
                weekStatDivider()
                weekStatCell(value: "\(stats.totalExercises)", label: "EXERCISES")
                weekStatDivider()
                weekStatCell(value: "\(stats.totalSets)", label: "SETS")
            }
            .padding(.vertical, 14)

            Rectangle().fill(DS.Semantic.border.opacity(0.6)).frame(height: 1)

            // Bottom row: strength, active min, streak
            HStack(spacing: 0) {
                weekStatCell(
                    value: "\(stats.strengthDaysDone)/\(stats.strengthTarget)",
                    label: "STRENGTH"
                )
                weekStatDivider()
                weekStatCell(
                    value: "\(stats.activeMinutesDone)/\(stats.activeMinutesTarget)",
                    label: "ACTIVE MIN"
                )
                weekStatDivider()
                weekStatCell(
                    value: "\(stats.streak)w",
                    label: "STREAK",
                    valueColor: stats.streak > 0 ? DS.Semantic.brand : DS.Semantic.textPrimary
                )
            }
            .padding(.vertical, 14)

            if stats.superStreak > 0 {
                Rectangle().fill(DS.Semantic.border.opacity(0.6)).frame(height: 1)
                HStack(spacing: 5) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Semantic.brand)
                    Text("Super Streak: \(stats.superStreak) week\(stats.superStreak == 1 ? "" : "s")")
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(DS.Semantic.brand)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(DS.Semantic.card)
        .clipShape(DS.RoleShape(.nested, legacy: ChamferedRectangle(.medium)))
    }

    private func weekStatCell(value: String, label: String, valueColor: Color = DS.Semantic.textPrimary) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .dsFont(.subheadline, weight: .bold)
                .foregroundStyle(valueColor)
            Text(label)
                .dsFont(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private func weekStatDivider() -> some View {
        Rectangle()
            .fill(DS.Semantic.border)
            .frame(width: 1, height: 32)
    }
}
