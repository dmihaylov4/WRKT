//
//  ChallengesBrowseView.swift
//  WRKT
//
//  Browse and join community challenges
//

import SwiftUI

struct ChallengesBrowseView: View {
    @Environment(\.dependencies) private var deps
    @State private var viewModel: ChallengesViewModel?
    @State private var selectedTab: ChallengeTab

    enum ChallengeTab {
        case active, browse, completed
    }

    init(initialTab: ChallengeTab = .active) {
        _selectedTab = State(initialValue: initialTab)
    }

    private enum Layout {
        static let standardVerticalPadding: CGFloat = 8
        static let browseBottomPadding: CGFloat = 96
        static let activeCompletedBottomNavigationClearance: CGFloat = 96
    }

    var body: some View {
        Group {
            if let viewModel = viewModel {
                content(viewModel: viewModel)
            } else {
                loadingState
            }
        }
        .task {
            if viewModel == nil {
                let vm = ChallengesViewModel(
                    challengeRepository: deps.challengeRepository,
                    authService: deps.authService,
                    workoutStore: deps.workoutStore
                )
                viewModel = vm
                await vm.onAppear()
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: ChallengesViewModel) -> some View {
        @Bindable var bindableVM = viewModel

        VStack(spacing: 0) {
            tabPicker

            ScrollView {
                LazyVStack(spacing: 16) {
                    switch selectedTab {
                    case .active:
                        activeChallengesSection(viewModel: viewModel)
                    case .browse:
                        browseChallengesSection(viewModel: viewModel)
                    case .completed:
                        completedChallengesSection(viewModel: viewModel)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, Layout.standardVerticalPadding)
                .padding(.bottom, tabContentBottomPadding)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .background(DS.Semantic.surface.ignoresSafeArea())
        .sheet(
            item: Binding(
                get: { viewModel.selectedChallenge },
                set: { _ in viewModel.closeChallengeDetail() }
            ),
            onDismiss: {
                Task { await viewModel.refresh() }
            }
        ) { challenge in
            ChallengeDetailView(challenge: challenge, viewModel: viewModel)
        }
        .alert(item: $bindableVM.error) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var tabContentBottomPadding: CGFloat {
        switch selectedTab {
        case .active, .completed:
            return Layout.activeCompletedBottomNavigationClearance
        case .browse:
            return Layout.browseBottomPadding
        }
    }

    @ViewBuilder
    private var tabPicker: some View {
        // Premium segmented control with frosted glass effect (matching Social view)
        HStack(spacing: 0) {
            ChallengePillButton(
                title: "Active",
                iconAsset: "streak-icon",
                isSelected: selectedTab == .active
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = .active
                    Haptics.light()
                }
            }

            ChallengePillButton(
                title: "Browse",
                iconAsset: "challenge-browse-icon",
                isSelected: selectedTab == .browse
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = .browse
                    Haptics.light()
                }
            }

            ChallengePillButton(
                title: "Completed",
                iconAsset: "challenge-completed-icon",
                isSelected: selectedTab == .completed
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = .completed
                    Haptics.light()
                }
            }
        }
        .padding(4)
        .background(
            ChamferedRectangleAlt(.large)
                .fill(DS.Semantic.card.opacity(0.5))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
        .overlay(
            ChamferedRectangleAlt(.large)
                .stroke(DS.Semantic.border.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func activeChallengesSection(viewModel: ChallengesViewModel) -> some View {
        if viewModel.isLoading {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonChallengeCard()
            }
        } else if viewModel.activeChallenges.isEmpty {
            emptyActiveChallengesState(viewModel: viewModel)
        } else {
            ForEach(viewModel.activeChallenges) { challenge in
                ChallengeCard(
                    challenge: challenge,
                    isActive: true,
                    onTap: { viewModel.openChallengeDetail(challenge) }
                )
            }
        }
    }

    @ViewBuilder
    private func browseChallengesSection(viewModel: ChallengesViewModel) -> some View {
        // Featured challenges
        if !viewModel.getFeaturedChallenges().isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Featured")
                    .dsFont(.title3, weight: .bold)
                    .foregroundStyle(DS.Semantic.textPrimary)

                ForEach(viewModel.getFeaturedChallenges(), id: \.title) { preset in
                    PresetChallengeCard(
                        preset: preset,
                        onTap: { await viewModel.openOrCreateChallengeFromPreset(preset) }
                    )
                }
            }
        }

        // All available challenges
        if viewModel.isLoading {
            ForEach(0..<5, id: \.self) { _ in
                SkeletonChallengeCard()
            }
        } else if viewModel.availableChallenges.isEmpty && viewModel.getFeaturedChallenges().isEmpty {
            emptyBrowseState
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !viewModel.availableChallenges.isEmpty {
                    Text("Community Challenges")
                        .dsFont(.title3, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    ForEach(viewModel.availableChallenges) { challenge in
                        ChallengeCard(
                            challenge: challenge,
                            isActive: false,
                            onTap: { viewModel.openChallengeDetail(challenge) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func completedChallengesSection(viewModel: ChallengesViewModel) -> some View {
        if viewModel.isLoading {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonChallengeCard()
            }
        } else if viewModel.completedChallenges.isEmpty {
            emptyCompletedState(viewModel: viewModel)
        } else {
            ForEach(viewModel.completedChallenges) { challenge in
                ChallengeCard(
                    challenge: challenge,
                    isActive: false,
                    onTap: { viewModel.openChallengeDetail(challenge) }
                )
            }
        }
    }

    // MARK: - Empty States
    @ViewBuilder
    private func emptyActiveChallengesState(viewModel: ChallengesViewModel) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 16) {
                ChallengeAssetIcon(
                    asset: "challenge-trophy-icon",
                    size: 68,
                    color: DS.Semantic.brand.opacity(0.32)
                )

                Text("No Active Challenges")
                    .dsFont(.title2, weight: .bold)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text("Join a challenge to start competing!")
                    .dsFont(.body)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

            // Recommended challenges
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recommended for You")
                        .dsFont(.title3, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Spacer()

                    Button {
                        withAnimation { selectedTab = .browse }
                    } label: {
                        HStack(spacing: 4) {
                            Text("View All")
                                .dsFont(.subheadline)
                            ChallengeAssetIcon(
                                asset: "angular-chevron-right-icon",
                                size: 14,
                                color: DS.Semantic.brand
                            )
                        }
                        .foregroundStyle(DS.Semantic.brand)
                    }
                }

                ForEach(viewModel.getFeaturedChallenges().prefix(3), id: \.title) { preset in
                    PresetChallengeCard(
                        preset: preset,
                        onTap: { await viewModel.openOrCreateChallengeFromPreset(preset) }
                    )
                }
            }
        }
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private var emptyBrowseState: some View {
        VStack(spacing: 16) {
            ChallengeAssetIcon(
                asset: "challenge-browse-icon",
                size: 68,
                color: DS.Semantic.brand.opacity(0.32)
            )

            Text("No Challenges Available")
                .dsFont(.title2, weight: .bold)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text("Check back later for new challenges")
                .dsFont(.body)
                .foregroundStyle(DS.Semantic.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func emptyCompletedState(viewModel: ChallengesViewModel) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 16) {
                ChallengeAssetIcon(
                    asset: "challenge-completed-icon",
                    size: 68,
                    color: DS.Semantic.brand.opacity(0.32)
                )

                Text("No Completed Challenges")
                    .dsFont(.title2, weight: .bold)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text("Complete your first challenge to see it here")
                    .dsFont(.body)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

            // Recommended challenges
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Start a New Challenge")
                        .dsFont(.title3, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Spacer()

                    Button {
                        withAnimation { selectedTab = .browse }
                    } label: {
                        HStack(spacing: 4) {
                            Text("View All")
                                .dsFont(.subheadline)
                            ChallengeAssetIcon(
                                asset: "angular-chevron-right-icon",
                                size: 14,
                                color: DS.Semantic.brand
                            )
                        }
                        .foregroundStyle(DS.Semantic.brand)
                    }
                }

                ForEach(viewModel.getFeaturedChallenges().prefix(3), id: \.title) { preset in
                    PresetChallengeCard(
                        preset: preset,
                        onTap: { await viewModel.openOrCreateChallengeFromPreset(preset) }
                    )
                }
            }
        }
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private var loadingState: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonChallengeCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

struct ChallengeAssetIcon: View {
    let asset: String
    let size: CGFloat
    let color: Color

    var body: some View {
        Image(asset)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
    }
}

struct ChallengeMetaPill: View {
    let asset: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            ChallengeAssetIcon(
                asset: asset,
                size: 14,
                color: DS.Semantic.textSecondary
            )

            Text(text)
                .dsFont(.caption)
        }
        .foregroundStyle(DS.Semantic.textSecondary)
    }
}

// MARK: - Challenge Pill Button (matching Social view design)
struct ChallengePillButton: View {
    let title: String
    let iconAsset: String
    let isSelected: Bool
    let badge: Int?
    let action: () -> Void

    init(title: String, iconAsset: String, isSelected: Bool, badge: Int? = nil, action: @escaping () -> Void) {
        self.title = title
        self.iconAsset = iconAsset
        self.isSelected = isSelected
        self.badge = badge
        self.action = action
    }

    init(title: String, icon: String, isSelected: Bool, badge: Int? = nil, action: @escaping () -> Void) {
        self.title = title
        self.iconAsset = Self.assetName(for: icon)
        self.isSelected = isSelected
        self.badge = badge
        self.action = action
    }

    private static func assetName(for systemIcon: String) -> String {
        switch systemIcon {
        case "bolt.fill", "flame.fill":
            return "streak-icon"
        case "magnifyingglass":
            return "challenge-browse-icon"
        case "checkmark.seal.fill":
            return "challenge-completed-icon"
        case "trophy.fill":
            return "challenge-trophy-icon"
        case "envelope.fill":
            return "social-feed-icon"
        default:
            return systemIcon
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // Icon with optional badge
                ZStack {
                    ChallengeAssetIcon(
                        asset: iconAsset,
                        size: 20,
                        color: isSelected ? .black : DS.Semantic.textSecondary
                    )

                    // Badge indicator (top-right corner)
                    if let count = badge, count > 0 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(DS.Semantic.accentWarm)
                            .clipShape(ChamferedRectangleAlt(.micro))
                            .offset(x: 12, y: -10)
                    }
                }

                // Label
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .black : DS.Semantic.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                Group {
                    if isSelected {
                        ChamferedRectangleAlt(.small)
                            .fill(DS.Semantic.brand)
                            .shadow(color: DS.Semantic.brand.opacity(0.3), radius: 6, x: 0, y: 2)
                    }
                }
            )
            .contentShape(ChamferedRectangleAlt(.small))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Challenge Card Component
struct ChallengeCard: View {
    let challenge: ChallengeWithProgress
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(challenge.challenge.title)
                            .dsFont(.headline)
                            .foregroundStyle(DS.Semantic.textPrimary)

                        Text(challengeTypeLabel)
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)

                        if !isActive, let description = challenge.challenge.description {
                            Text(description)
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    // Difficulty badge
                    difficultyBadge
                }

                // Progress bar (if active)
                if isActive, let participation = challenge.participation {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(progressText(progress: participation))
                                .dsFont(.caption, weight: .bold)
                                .foregroundStyle(DS.Semantic.brand)

                            Spacer()

                            Text("\(challenge.userProgressPercentage)%")
                                .dsFont(.caption, weight: .bold)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }

                        ProgressView(value: Double(challenge.userProgressPercentage), total: 100)
                            .tint(DS.Semantic.brand)
                    }
                }

                // Footer
                HStack(spacing: 8) {
                    if challenge.challenge.participantCount > 0 {
                        ChallengeMetaPill(
                            asset: "challenge-people-icon",
                            text: "\(challenge.challenge.participantCount) \(challenge.challenge.participantCount == 1 ? "person" : "people")"
                        )
                    } else {
                        ChallengeMetaPill(
                            asset: "challenge-trophy-icon",
                            text: goalText
                        )
                    }

                    Spacer()

                    let daysRemaining = challenge.challenge.daysRemaining
                    if daysRemaining > 0 || challenge.challenge.isEvergreen {
                        ChallengeMetaPill(
                            asset: "challenge-clock-icon",
                            text: challenge.challenge.daysRemainingDisplay
                        )
                    }
                }

                // Tap indicator
                HStack {
                    Text(actionText)
                        .dsFont(.caption, weight: .bold)
                        .foregroundStyle(DS.Semantic.brand)

                    ChallengeAssetIcon(
                        asset: "angular-chevron-right-icon",
                        size: 14,
                        color: DS.Semantic.brand
                    )
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(16)
            .background(DS.Semantic.card, in: ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(DS.Semantic.border, lineWidth: 1)
            )
            .contentShape(ChamferedRectangle(.large))
        }
        .buttonStyle(.plain)
    }

    private var challengeTypeLabel: String {
        switch challenge.challenge.challengeType {
        case .workoutCount:
            return "Workout Count"
        case .totalVolume:
            return "Total Volume"
        case .streak:
            return "Streak"
        case .specificExercise:
            return "Exercise Challenge"
        case .custom:
            return "Custom Challenge"
        }
    }

    private var actionText: String {
        if isActive { return "View Progress" }
        if challenge.isParticipating { return "View Challenge" }
        return "View & Join"
    }

    private var goalText: String {
        let goal = NSDecimalNumber(decimal: challenge.challenge.goalValue).intValue
        switch challenge.challenge.challengeType {
        case .workoutCount:
            return "\(goal) workouts"
        case .totalVolume:
            return "\(goal / 1000)K kg"
        case .streak:
            return "\(goal) days"
        case .specificExercise:
            return "\(goal) reps"
        case .custom:
            return challenge.challenge.goalMetric
        }
    }

    @ViewBuilder
    private var difficultyBadge: some View {
        if let difficulty = challenge.challenge.difficulty {
            Text(difficulty.displayName)
                .dsFont(.caption2, weight: .bold)
                .foregroundStyle(difficultyTextColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(difficultyColor, in: ChamferedRectangle(.small))
        }
    }

    private var difficultyTextColor: Color {
        guard let difficulty = challenge.challenge.difficulty else {
            return DS.Semantic.textSecondary
        }

        switch difficulty {
        case .beginner:
            return DS.Semantic.textSecondary
        case .intermediate:
            return DS.Semantic.textPrimary
        case .advanced:
            return DS.Semantic.textPrimary
        }
    }

    private var difficultyColor: Color {
        guard let difficulty = challenge.challenge.difficulty else {
            return DS.Semantic.textSecondary
        }

        switch difficulty {
        case .beginner:
            return DS.Semantic.fillSubtle
        case .intermediate:
            return DS.Semantic.surface50
        case .advanced:
            return DS.Semantic.textSecondary.opacity(0.2)
        }
    }

    private func progressText(progress: ChallengeParticipant) -> String {
        let currentValue = progress.currentProgress
        let goalValue = challenge.challenge.goalValue

        switch challenge.challenge.challengeType {
        case .workoutCount:
            return "\(Int(truncating: currentValue as NSDecimalNumber))/\(Int(truncating: goalValue as NSDecimalNumber)) workouts"
        case .totalVolume:
            let current = Int(truncating: currentValue as NSDecimalNumber)
            let goal = Int(truncating: goalValue as NSDecimalNumber)
            return "\(current / 1000)K/\(goal / 1000)K kg"
        case .streak:
            return "\(Int(truncating: currentValue as NSDecimalNumber))/\(Int(truncating: goalValue as NSDecimalNumber)) days"
        case .specificExercise:
            return "\(Int(truncating: currentValue as NSDecimalNumber))/\(Int(truncating: goalValue as NSDecimalNumber))"
        case .custom:
            return "\(Int(truncating: currentValue as NSDecimalNumber))/\(Int(truncating: goalValue as NSDecimalNumber)) \(challenge.challenge.goalMetric)"
        }
    }
}

// MARK: - Preset Challenge Card
struct PresetChallengeCard: View {
    let preset: PresetChallenge
    let onTap: () async -> Void

    var body: some View {
        Button {
            Task { await onTap() }
        } label: {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.title)
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text(preset.description)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .lineLimit(2)
            }

            HStack {
                Text("\(preset.duration) days")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)

                Spacer()

                Text(preset.difficulty.rawValue.capitalized)
                    .dsFont(.caption2, weight: .bold)
                    .foregroundStyle(difficultyTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(difficultyBackgroundColor, in: ChamferedRectangle(.small))
            }

            HStack {
                Text("Start Challenge")
                    .dsFont(.caption, weight: .bold)
                    .foregroundStyle(DS.Semantic.brand)

                ChallengeAssetIcon(
                    asset: "angular-chevron-right-icon",
                    size: 14,
                    color: DS.Semantic.brand
                )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .background(DS.Semantic.card, in: ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
        .contentShape(ChamferedRectangle(.large))
        }
        .buttonStyle(.plain)
    }

    private var difficultyBackgroundColor: Color {
        switch preset.difficulty {
        case .beginner:
            return DS.Semantic.fillSubtle
        case .intermediate:
            return DS.Semantic.surface50
        case .advanced:
            return DS.Semantic.textSecondary.opacity(0.2)
        }
    }

    private var difficultyTextColor: Color {
        switch preset.difficulty {
        case .beginner:
            return DS.Semantic.textSecondary
        case .intermediate:
            return DS.Semantic.textPrimary
        case .advanced:
            return DS.Semantic.textPrimary
        }
    }
}

// MARK: - Skeleton Loading Card
struct SkeletonChallengeCard: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Rectangle()
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 150, height: 16)
                        .clipShape(ChamferedRectangle(.micro))

                    Rectangle()
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 100, height: 12)
                        .clipShape(ChamferedRectangle(.micro))
                }

                Spacer()

                ChamferedRectangle(.small)
                    .fill(DS.Semantic.fillSubtle)
                    .frame(width: 60, height: 24)
            }

            Rectangle()
                .fill(DS.Semantic.fillSubtle)
                .frame(height: 40)
                .clipShape(ChamferedRectangle(.medium))
        }
        .padding(16)
        .background(DS.Semantic.card, in: ChamferedRectangle(.large))
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}
