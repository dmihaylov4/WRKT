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
    @State private var selectedTab: ChallengeTab = .active

    enum ChallengeTab {
        case active, browse, completed
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel = viewModel {
                    content(viewModel: viewModel)
                } else {
                    loadingState
                }
            }
            .navigationTitle("Challenges")
            .navigationBarTitleDisplayMode(.large)
            .task {
                if viewModel == nil {
                    let vm = ChallengesViewModel(
                        challengeRepository: deps.challengeRepository,
                        authService: deps.authService
                    )
                    viewModel = vm
                    await vm.onAppear()
                }
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: ChallengesViewModel) -> some View {
        @Bindable var bindableVM = viewModel

        VStack(spacing: 0) {
            // Tab selector
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
                .padding(.vertical, 8)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .background(DS.Semantic.surface.ignoresSafeArea())
        .sheet(isPresented: $bindableVM.showChallengeDetail, onDismiss: {
            // Refresh challenges when detail view is dismissed
            Task {
                await viewModel.refresh()
            }
        }) {
            if let challenge = viewModel.selectedChallenge {
                ChallengeDetailView(challenge: challenge, viewModel: viewModel)
            }
        }
        .alert(item: $bindableVM.error) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var tabPicker: some View {
        // Premium segmented control with frosted glass effect (matching Social view)
        HStack(spacing: 0) {
            ChallengePillButton(
                title: "Active",
                icon: "flame.fill",
                isSelected: selectedTab == .active
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = .active
                    Haptics.light()
                }
            }

            ChallengePillButton(
                title: "Browse",
                icon: "magnifyingglass",
                isSelected: selectedTab == .browse
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = .browse
                    Haptics.light()
                }
            }

            ChallengePillButton(
                title: "Completed",
                icon: "checkmark.seal.fill",
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
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Semantic.card.opacity(0.5))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DS.Semantic.border.opacity(0.3), lineWidth: 1)
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
                    onTap: { viewModel.openChallengeDetail(challenge) },
                    onAction: { await viewModel.leaveChallenge(challenge.challenge) }
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
                    .font(.title3.bold())
                    .foregroundStyle(DS.Semantic.textPrimary)

                ForEach(viewModel.getFeaturedChallenges(), id: \.title) { preset in
                    PresetChallengeCard(
                        preset: preset,
                        onJoin: { await viewModel.createChallengeFromPreset(preset) }
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
                        .font(.title3.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)

                    ForEach(viewModel.availableChallenges) { challenge in
                        ChallengeCard(
                            challenge: challenge,
                            isActive: false,
                            onTap: { viewModel.openChallengeDetail(challenge) },
                            onAction: { await viewModel.joinChallenge(challenge.challenge) }
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
                    onTap: { viewModel.openChallengeDetail(challenge) },
                    onAction: nil
                )
            }
        }
    }

    // MARK: - Empty States
    @ViewBuilder
    private func emptyActiveChallengesState(viewModel: ChallengesViewModel) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(DS.Semantic.brand.opacity(0.3))

                Text("No Active Challenges")
                    .font(.title2.bold())
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text("Join a challenge to start competing!")
                    .font(.body)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

            // Recommended challenges
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recommended for You")
                        .font(.title3.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Spacer()

                    Button {
                        withAnimation { selectedTab = .browse }
                    } label: {
                        HStack(spacing: 4) {
                            Text("View All")
                                .font(.subheadline)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .foregroundStyle(DS.Semantic.brand)
                    }
                }

                ForEach(viewModel.getFeaturedChallenges().prefix(3), id: \.title) { preset in
                    PresetChallengeCard(
                        preset: preset,
                        onJoin: { await viewModel.createChallengeFromPreset(preset) }
                    )
                }
            }
        }
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private var emptyBrowseState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(DS.Semantic.brand.opacity(0.3))

            Text("No Challenges Available")
                .font(.title2.bold())
                .foregroundStyle(DS.Semantic.textPrimary)

            Text("Check back later for new challenges")
                .font(.body)
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
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(DS.Semantic.brand.opacity(0.3))

                Text("No Completed Challenges")
                    .font(.title2.bold())
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text("Complete your first challenge to see it here")
                    .font(.body)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

            // Recommended challenges
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Start a New Challenge")
                        .font(.title3.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Spacer()

                    Button {
                        withAnimation { selectedTab = .browse }
                    } label: {
                        HStack(spacing: 4) {
                            Text("View All")
                                .font(.subheadline)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .foregroundStyle(DS.Semantic.brand)
                    }
                }

                ForEach(viewModel.getFeaturedChallenges().prefix(3), id: \.title) { preset in
                    PresetChallengeCard(
                        preset: preset,
                        onJoin: { await viewModel.createChallengeFromPreset(preset) }
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

// MARK: - Challenge Pill Button (matching Social view design)
struct ChallengePillButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let badge: Int?
    let action: () -> Void

    init(title: String, icon: String, isSelected: Bool, badge: Int? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.badge = badge
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // Icon with optional badge
                ZStack {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .black : DS.Semantic.textSecondary)
                        .symbolEffect(.bounce, value: isSelected)

                    // Badge indicator (top-right corner)
                    if let count = badge, count > 0 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(DS.Semantic.accentWarm)
                            .clipShape(Circle())
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
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DS.Semantic.brand)
                            .shadow(color: DS.Semantic.brand.opacity(0.3), radius: 6, x: 0, y: 2)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Challenge Card Component
struct ChallengeCard: View {
    let challenge: ChallengeWithProgress
    let isActive: Bool
    let onTap: () -> Void
    let onAction: (() async -> Void)?

    @State private var isProcessing = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(challenge.challenge.title)
                            .font(.headline)
                            .foregroundStyle(DS.Semantic.textPrimary)

                        Text(challengeTypeLabel)
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
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
                                .font(.caption.bold())
                                .foregroundStyle(DS.Semantic.brand)

                            Spacer()

                            Text("\(challenge.userProgressPercentage)%")
                                .font(.caption.bold())
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }

                        ProgressView(value: Double(challenge.userProgressPercentage), total: 100)
                            .tint(DS.Semantic.brand)
                    }
                }

                // Footer
                HStack {
                    Label(
                        "\(challenge.challenge.participantCount) \(challenge.challenge.participantCount == 1 ? "person" : "people")",
                        systemImage: "person.2.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)

                    Spacer()

                    let daysRemaining = challenge.challenge.daysRemaining
                    if daysRemaining > 0 {
                        Label(
                            "\(daysRemaining) \(daysRemaining == 1 ? "day" : "days") left",
                            systemImage: "clock.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }

                // Action button
                if let onAction = onAction {
                    Button {
                        Task {
                            isProcessing = true
                            await onAction()
                            isProcessing = false
                        }
                    } label: {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(isActive ? "Leave Challenge" : "Join Challenge")
                            }
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(isActive ? DS.Semantic.textPrimary : DS.Semantic.onBrand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isActive ? DS.Semantic.surface50 : DS.Semantic.brand)
                        .clipShape(Capsule())
                    }
                    .disabled(isProcessing)
                }
            }
            .padding(16)
            .background(DS.Semantic.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(DS.Semantic.border, lineWidth: 1)
            )
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

    @ViewBuilder
    private var difficultyBadge: some View {
        if let difficulty = challenge.challenge.difficulty {
            Text(difficulty.displayName)
                .font(.caption2.bold())
                .foregroundStyle(difficultyTextColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(difficultyColor)
                .clipShape(Capsule())
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
    let onJoin: () async -> Void

    @State private var isJoining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.title)
                    .font(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text(preset.description)
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .lineLimit(2)
            }

            HStack {
                Text("\(preset.duration) days")
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)

                Spacer()

                Text(preset.difficulty.rawValue.capitalized)
                    .font(.caption2.bold())
                    .foregroundStyle(difficultyTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(difficultyBackgroundColor)
                    .clipShape(Capsule())
            }

            Button {
                Task {
                    isJoining = true
                    await onJoin()
                    isJoining = false
                }
            } label: {
                HStack {
                    if isJoining {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Text("Join Challenge")
                    }
                }
                .font(.subheadline.bold())
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(DS.Semantic.brand)
                .clipShape(Capsule())
            }
            .disabled(isJoining)
        }
        .padding(16)
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
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
                        .clipShape(Capsule())

                    Rectangle()
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 100, height: 12)
                        .clipShape(Capsule())
                }

                Spacer()

                Circle()
                    .fill(DS.Semantic.fillSubtle)
                    .frame(width: 60, height: 24)
            }

            Rectangle()
                .fill(DS.Semantic.fillSubtle)
                .frame(height: 40)
                .clipShape(Capsule())
        }
        .padding(16)
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}
