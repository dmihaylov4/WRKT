import SwiftUI

struct BattleResultOverlay: View {
    let battle: BattleWithParticipants
    let currentUserId: UUID
    let earnedPlate: EarnedPlateInfo?
    let onShare: () async -> Void
    let onDismiss: () -> Void

    @State private var showIcon      = false
    @State private var showTitle     = false
    @State private var showScoreCard = false
    @State private var showPlate     = false
    @State private var showButtons   = false
    @State private var showRack      = false

    private var isWinner: Bool { battle.battle.winnerId == currentUserId }
    private var isTie: Bool    { battle.battle.status == .completed && battle.battle.winnerId == nil }

    private var opponent: UserProfile { battle.opponentProfile }
    private var opponentDisplayName: String { opponent.displayName ?? opponent.username }

    private var myScore: Decimal      { battle.battle.score(for: currentUserId) }
    private var opponentScore: Decimal { battle.battle.opponentScore(for: currentUserId) }

    private var headerIconName: String {
        isWinner ? "challenge-trophy-icon" : battle.battle.battleType.customIconName
    }

    private var headline: String {
        if isTie { return "Battle Tied" }
        return isWinner ? "You Won!" : "Battle Complete"
    }

    private var alreadyShared: Bool { battle.battle.sharedPostId != nil }
    private var iShared: Bool       { battle.battle.sharedByUserId == currentUserId }
    private var shareLabel: String {
        if iShared      { return "Shared" }
        if alreadyShared { return "Already Shared" }
        return "Share Battle"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 56)

                if showIcon {
                    Image(headerIconName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                        .foregroundStyle(isWinner ? DS.Semantic.accentWarm : DS.Semantic.textPrimary)
                        .transition(.scale.combined(with: .opacity))
                }

                Spacer().frame(height: 14)

                if showTitle {
                    Text(headline)
                        .dsFont(.title2, weight: .bold)
                        .foregroundStyle(isWinner ? DS.Semantic.accentWarm : .white)
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                    Text("vs \(opponentDisplayName) · \(battle.battle.battleType.displayName)")
                        .dsFont(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer().frame(height: 28)

                if showScoreCard {
                    scoreCard
                        .padding(.horizontal, 20)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.85).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

                if showPlate, let plate = earnedPlate {
                    plateRow(plate)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

                Spacer()

                if showButtons {
                    buttons
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .fullScreenCover(isPresented: $showRack) {
            PlateWallView()
        }
        .onAppear { startReveal() }
    }

    // MARK: - Score Card

    private var scoreCard: some View {
        HStack(spacing: 0) {
            scoreColumn(
                score: myScore,
                label: "You",
                highlighted: isWinner || isTie
            )
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1, height: 44)

            scoreColumn(
                score: opponentScore,
                label: opponentDisplayName.components(separatedBy: " ").first ?? opponentDisplayName,
                highlighted: !isWinner || isTie
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 20)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func scoreColumn(score: Decimal, label: String, highlighted: Bool) -> some View {
        VStack(spacing: 4) {
            Text(formatScore(score))
                .dsFont(.title3, weight: .bold)
                .foregroundStyle(highlighted ? DS.Semantic.accentWarm : .white)
            Text(label)
                .dsFont(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Plate Row

    private func plateRow(_ plate: EarnedPlateInfo) -> some View {
        HStack(spacing: 12) {
            PlateFaceView(
                tierID: plate.tierID,
                progressionTier: .iron,
                liftTypeID: nil,
                weightKg: plate.weightKg
            )
            .frame(width: 44, height: 44)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(plate.engravingText.isEmpty ? "Battle Plate" : plate.engravingText)
                    .dsFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.white)
                Text("New plate unlocked")
                    .dsFont(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()
        }
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Semantic.accentWarm.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Buttons

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                guard !alreadyShared else { return }
                Haptics.medium()
                Task { await onShare() }
            } label: {
                Text(shareLabel)
                    .dsFont(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .background(alreadyShared ? Color.white.opacity(0.08) : DS.Semantic.accentWarm)
            .foregroundStyle(alreadyShared ? DS.Semantic.textSecondary : .black)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(alreadyShared)

            Button {
                Haptics.light()
                showRack = true
            } label: {
                Text("Open Your Rack")
                    .dsFont(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .background(Color.white.opacity(0.08))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                Haptics.light()
                onDismiss()
            } label: {
                Text("Continue")
                    .dsFont(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Animation

    private func startReveal() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showIcon = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showTitle = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { showScoreCard = true }
            Haptics.medium()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { showPlate = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showButtons = true }
        }
    }

    // MARK: - Formatting

    private func formatScore(_ score: Decimal) -> String {
        let value = NSDecimalNumber(decimal: score).doubleValue
        switch battle.battle.scoreUnit {
        case "kg":   return String(format: "%.1f kg", value)
        case "days": return "\(Int(value)) days"
        default:     return "\(Int(value)) \(battle.battle.scoreUnit)"
        }
    }
}
