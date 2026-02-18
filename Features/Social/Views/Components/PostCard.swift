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
    let onProfileTap: () -> Void
    let onPostTap: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    @State private var isExpanded = false
    @State private var showingImageViewer = false
    @State private var selectedImageIndex = 0
    @State private var showingDeleteAlert = false
    @State private var showingReportAlert = false
    @State private var showingMenuSheet = false
    @State private var displayImageURLs: [URL] = []

    private let imageUploadService = ImageUploadService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Avatar + Username + Time
            header

            // Caption (skip for cardio posts — the card itself is the content)
            if !post.post.workoutData.isCardioWorkout,
               let caption = post.post.caption, !caption.isEmpty {
                Text(caption)
                    .font(.body)
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Workout Summary
            workoutSummary

            // Images (if any) - skip for cardio workouts since map is shown inline
            if !displayImageURLs.isEmpty && !post.post.workoutData.isCardioWorkout {
                imageGallery(imageUrls: displayImageURLs.map { $0.absoluteString })
            }

            // Expandable Workout Details
            if isExpanded {
                workoutDetails
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
            ImageViewer(imageUrls: displayImageURLs.map { $0.absoluteString }, selectedIndex: $selectedImageIndex)
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
        .task {
            await loadImageURLs()
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
            let urls = try await imageUploadService.getImageURLs(
                for: images,
                currentUserId: userId,
                postOwnerId: post.post.userId
            )
            print("✅ [PostCard] Loaded \(urls.count) URLs")
            await MainActor.run {
                displayImageURLs = urls
            }
        } catch {
            print("❌ [PostCard] Failed to load image URLs: \(error)")
        }
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
                                .font(.title3.bold())
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
                    .font(.subheadline.bold())
                    .foregroundStyle(DS.Semantic.textPrimary)

                HStack(spacing: 4) {
                    Text(post.relativeTime)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Image(systemName: post.post.visibility.icon)
                        .font(.caption)
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
                    .font(.body)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .padding(8)
            }
        }
    }

    // MARK: - Workout Summary

    private var workoutSummary: some View {
        ZStack(alignment: .leading) {
            // Accent stripe on left (clipped by container's chamfered shape)
            Rectangle()
                .fill(DS.Semantic.brand)
                .frame(width: 4)

            // Main content
            VStack(alignment: .leading, spacing: 12) {
                // Workout Type/Name with expand indicator
                HStack {
                    // Icon with accent circle background
                    ZStack {
                        Circle()
                            .fill(DS.Semantic.brand.opacity(0.12))
                            .frame(width: 40, height: 40)

                        Image(systemName: post.post.workoutData.workoutIcon)
                            .font(.title3)
                            .foregroundStyle(DS.Semantic.brand)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.post.workoutData.workoutName ?? post.post.workoutData.workoutTypeDisplayName)
                            .font(.headline)
                            .foregroundStyle(DS.Semantic.textPrimary)

                        Text(post.post.workoutData.isCardioWorkout ? "Tap for details" : "Tap to \(isExpanded ? "hide" : "view") exercises")
                            .font(.caption2)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }

                    Spacer()

                    if !post.post.workoutData.isCardioWorkout {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }

                // Stats Grid - different for cardio vs strength
                if post.post.workoutData.isCardioWorkout {
                    cardioStats
                } else {
                    strengthStats
                }
            }
            .padding(16)
            .padding(.leading, 4) // Extra space for accent stripe
        }
        .background(DS.Semantic.fillSubtle, in: ChamferedRectangle(.medium))
        .clipShape(ChamferedRectangle(.medium))
        .overlay(ChamferedRectangle(.medium).stroke(DS.Semantic.border, lineWidth: 1))
        .onTapGesture {
            if !post.post.workoutData.isCardioWorkout {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
                Haptics.light()
            }
        }
    }

    // MARK: - Strength Stats
    private var strengthStats: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                statPill(
                    icon: "dumbbell.fill",
                    value: "\(post.post.exerciseCount)",
                    label: post.post.exerciseCount == 1 ? "exercise" : "exercises"
                )

                Spacer()

                statPill(
                    icon: "list.bullet",
                    value: "\(post.post.totalSets)",
                    label: post.post.totalSets == 1 ? "set" : "sets"
                )
            }

            HStack(spacing: 12) {
                if post.post.totalVolume > 0 {
                    statPill(
                        icon: "scalemass.fill",
                        value: formatVolume(post.post.totalVolume),
                        label: "kg total"
                    )

                    Spacer()
                }

                if let duration = post.post.duration, duration > 0 {
                    statPill(
                        icon: "clock.fill",
                        value: post.post.durationFormatted,
                        label: "duration"
                    )
                }
            }
        }
    }

    // MARK: - Cardio Stats
    private var cardioStats: some View {
        VStack(spacing: 12) {
            // Map preview (if available) - first image is the map for cardio posts
            if !displayImageURLs.isEmpty {
                cardioMapPreview
            }

            // Hero display for distance and time (if distance is available)
            if let distanceMeters = post.post.workoutData.matchedHealthKitDistance, distanceMeters > 0 {
                cardioHeroStats(distanceMeters: distanceMeters)
            }

            // Secondary stats in two rows for better formatting
            VStack(spacing: 6) {
                // First row: calories and duration (if no distance hero shown)
                HStack {
                    if let calories = post.post.workoutData.matchedHealthKitCalories {
                        statPill(icon: "flame.fill", value: String(format: "%.0f", calories), label: "cal")
                    }

                    Spacer()

                    if let avgHR = post.post.workoutData.matchedHealthKitHeartRate {
                        statPill(icon: "heart.fill", value: String(format: "%.0f", avgHR), label: "avg bpm")
                    }

                    Spacer()

                    if let maxHR = post.post.workoutData.matchedHealthKitMaxHeartRate {
                        statPill(icon: "bolt.heart.fill", value: String(format: "%.0f", maxHR), label: "max bpm")
                    }
                }
            }

            // HR zones summary (if available)
            if let hrZones = post.post.workoutData.cardioHRZones, !hrZones.isEmpty {
                hrZonesLegend(zones: hrZones)
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
                        .font(.caption2)
                    Text(formatPace(paceSecPerKm))
                        .font(.caption.bold())
                    Text("/km")
                        .font(.caption2)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.6))
                .clipShape(Capsule())
                .padding(8)
            }
        }
    }

    // MARK: - HR Zones Legend
    private func hrZonesLegend(zones: [HRZoneSummary]) -> some View {
        HStack(spacing: 4) {
            ForEach(zones.filter { $0.minutes > 0 }.sorted { $0.zone < $1.zone }) { zone in
                HStack(spacing: 2) {
                    Circle()
                        .fill(Color(hex: zone.colorHex))
                        .frame(width: 6, height: 6)
                    Text("Z\(zone.zone)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.Semantic.textSecondary)
                    Text("\(Int(zone.minutes))m")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DS.Semantic.fillSubtle)
        .clipShape(Capsule())
    }

    private func formatPace(_ secPerKm: Double) -> String {
        let minutes = Int(secPerKm) / 60
        let seconds = Int(secPerKm) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Cardio Hero Stats (Distance + Time)
    private func cardioHeroStats(distanceMeters: Double) -> some View {
        HStack(spacing: 16) {
            // Distance
            VStack(spacing: 2) {
                Text(String(format: "%.2f", distanceMeters / 1000))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Palette.marone)
                Text("KILOMETERS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .tracking(0.5)
            }

            // Divider
            Rectangle()
                .fill(DS.Semantic.border)
                .frame(width: 1, height: 40)

            // Duration
            VStack(spacing: 2) {
                if let durationSec = post.post.workoutData.matchedHealthKitDuration {
                    Text(formatCardioDuration(durationSec))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Semantic.textPrimary)
                } else {
                    Text("--:--")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Semantic.textPrimary)
                }
                Text("TIME")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .tracking(0.5)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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

    private func statPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(DS.Semantic.textSecondary)
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(DS.Semantic.textPrimary)
            if !label.isEmpty {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
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

    // MARK: - Workout Details

    private var workoutDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("Exercises")
                .font(.subheadline.bold())
                .foregroundStyle(DS.Semantic.textPrimary)

            ForEach(post.post.workoutData.entries) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(DS.Semantic.textSecondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.exerciseName)
                            .font(.subheadline)
                            .foregroundStyle(DS.Semantic.textPrimary)

                        Text("\(entry.sets.count) sets")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }

                    Spacer()
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 20) {
            // Like button
            Button {
                Haptics.light()
                onLike()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: post.isLikedByCurrentUser ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(post.isLikedByCurrentUser ? DS.Semantic.brand : DS.Semantic.textSecondary)
                        .symbolEffect(.bounce, value: post.isLikedByCurrentUser)
                }
            }

            // Comment button
            Button {
                Haptics.light()
                onComment()
            } label: {
                Image(systemName: "bubble.right")
                    .font(.title3)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            Spacer()

            // Share button
            Button {
                Haptics.light()
                sharePost()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 4) {
            if post.post.likesCount > 0 {
                Text("\(post.post.likesCount) \(post.post.likesCount == 1 ? "like" : "likes")")
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            if post.post.commentsCount > 0 {
                if post.post.likesCount > 0 {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Text("\(post.post.commentsCount) \(post.post.commentsCount == 1 ? "comment" : "comments")")
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
        }
        .onTapGesture {
            Haptics.light()
            onComment()
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

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return String(format: "%.0f", volume)
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
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding()
            }
        }
    }
}

