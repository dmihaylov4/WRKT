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
    let onBackfillRoute: (() async -> Bool)?

    @State private var showingImageViewer = false
    @State private var selectedImageIndex = 0
    @State private var showingDeleteAlert = false
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Avatar + Username + Time
            header

            // Caption
            if let caption = post.post.caption, !caption.isEmpty {
                Text(caption)
                    .dsFont(.body)
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Workout Summary
            if post.post.isMultiWorkout {
                MultiWorkoutCarousel(
                    workouts: post.post.allWorkouts,
                    mapURLs: generatedMapURLs
                )
            } else {
                VStack(spacing: 12) {
                    WorkoutPostHeroSummaryCard(
                        summary: .make(for: [post.post.workoutData]),
                        context: .feed
                    )

                    singleCardioRoutePreview
                }
            }

            if post.post.isMultiWorkout {
                if !userImageURLs.isEmpty {
                    imageGallery(imageUrls: userImageURLs.map { $0.absoluteString })
                }
            } else if !displayImageURLs.isEmpty && !post.post.workoutData.isCardioWorkout {
                imageGallery(imageUrls: displayImageURLs.map { $0.absoluteString })
            }

            // Action Buttons (Like, Comment, Share)
            actionButtons

            // Like/Comment Counts
            statsRow
        }
        .padding(16)
        .background(DS.Semantic.card)
        .clipShape(ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.light()
            onPostTap()
        }
        .sheet(isPresented: $showingImageViewer) {
            let viewerURLs = post.post.isMultiWorkout
                ? userImageURLs.map { $0.absoluteString }
                : displayImageURLs.map { $0.absoluteString }
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
               displayImageURLs.isEmpty,
               post.post.workoutData.matchedHealthKitUUID != nil {
                await runBackfill()
            }
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

    private var header: some View {
        HStack(spacing: 12) {
            // Avatar with chamfered logo style
            KFImage(URL(string: post.author.avatarUrl ?? ""))
                .placeholder {
                    ChamferedRectangleAlt(.small)
                        .fill(DS.Semantic.brandSoft)
                        .overlay(
                            Text(post.author.username.prefix(1).uppercased())
                                .dsFont(.title3, weight: .bold)
                                .foregroundStyle(DS.Semantic.brand)
                        )
                }
                .fade(duration: 0.25)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(ChamferedRectangleAlt(.small))
                .onTapGesture {
                    onProfileTap()
                }

            // Username + Time
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
            .onTapGesture {
                onProfileTap()
            }

            Spacer()

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

    // MARK: - Single Cardio Route Preview

    @ViewBuilder
    private var singleCardioRoutePreview: some View {
        if post.post.workoutData.isCardioWorkout {
            if !displayImageURLs.isEmpty {
                cardioMapPreview
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
                    .background(DS.Semantic.fillSubtle, in: RoundedRectangle(cornerRadius: 8))
                }
                .disabled(isBackfilling)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Cardio Map Preview
    private var cardioMapPreview: some View {
        ZStack(alignment: .bottomLeading) {
            // Map image
            KFImage(displayImageURLs.first)
                .placeholder {
                    Rectangle()
                        .fill(DS.Semantic.fillSubtle)
                        .overlay(
                            ProgressView()
                        )
                }
                .fade(duration: 0.25)
                .resizable()
                .scaledToFill()
                .frame(height: 140)
                .clipped()
                .clipShape(ChamferedRectangle(.small))

            // Pace badge overlay (bottom-left)
            if let distanceMeters = post.post.workoutData.matchedHealthKitDistance,
               let durationSec = post.post.workoutData.matchedHealthKitDuration,
               distanceMeters > 0 {
                let paceSecPerKm = Double(durationSec) / (distanceMeters / 1000)
                HStack(spacing: 4) {
                    Image(systemName: "figure.run")
                        .dsFont(.caption2)
                    Text(WorkoutPostStatsViews.formatPace(paceSecPerKm))
                        .dsFont(.caption, weight: .bold)
                    Text("/km")
                        .dsFont(.caption2)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.6))
                .clipShape(Capsule())
                .padding(8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedImageIndex = 0
            showingImageViewer = true
        }
    }

    // MARK: - Image Gallery

    private func imageGallery(imageUrls: [String]) -> some View {
        TabView {
            ForEach(Array(imageUrls.enumerated()), id: \.offset) { index, urlString in
                KFImage(URL(string: urlString))
                    .placeholder {
                        Rectangle()
                            .fill(DS.Semantic.fillSubtle)
                            .overlay(
                                ProgressView()
                            )
                    }
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 300)
                    .clipped()
                    .onTapGesture {
                        selectedImageIndex = index
                        showingImageViewer = true
                    }
            }
        }
        .frame(height: 300)
        .tabViewStyle(.page(indexDisplayMode: imageUrls.count > 1 ? .always : .never))
        .clipShape(ChamferedRectangle(.medium))
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
        WorkoutToastManager.shared.show(
            message: "Report submitted. Thank you.",
            icon: "checkmark.circle.fill"
        )
    }

}

// MARK: - Resolved Post Image

private struct ResolvedPostImage: Identifiable {
    let image: PostImage
    let url: URL

    var id: UUID { image.id }
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
