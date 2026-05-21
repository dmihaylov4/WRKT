import SwiftUI

// MARK: - Fallback summary types (free functions, usable without store)

struct PlateCollectionFallbackSummary: Equatable {
    let title: String
    let detail: String
}

func plateCollectionHealthKitSummary(for plate: EarnedPlate, run: Run) -> PlateCollectionFallbackSummary? {
    guard plate.earnedByEvent.hasPrefix("hk_") || run.countsAsStrengthDay else { return nil }
    return PlateCollectionFallbackSummary(
        title: run.category.displayName,
        detail: (run.workoutType ?? run.workoutName ?? "HealthKit Workout").uppercased()
    )
}

func plateCollectionFallbackSummary(for plate: EarnedPlate) -> PlateCollectionFallbackSummary? {
    let title: String
    if !plate.engravingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        title = plate.engravingText
    } else if let liftTypeID = plate.liftTypeID,
              !BarbellPlateProgressionScope.isGlobal(liftTypeID) {
        title = liftTypeID
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    } else if plate.earnedByEvent.hasPrefix("hk_") {
        title = "HealthKit Strength"
    } else {
        return nil
    }

    let detail: String
    if plate.earnedByEvent.hasPrefix("hk_") {
        detail = plate.sourceWorkoutID == nil ? "HEALTHKIT HISTORY" : "HEALTHKIT SOURCE UNAVAILABLE"
    } else {
        detail = plate.sourceWorkoutID == nil ? "EARNED HISTORY" : "SOURCE WORKOUT DELETED"
    }

    return PlateCollectionFallbackSummary(title: title, detail: detail)
}

extension HealthKitWorkoutCategory {
    var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .hybrid: return "Hybrid"
        case .cardio: return "Cardio"
        case .flexibility: return "Flexibility"
        case .other: return "HealthKit"
        }
    }
}

// MARK: - PlateWorkoutSummary

struct PlateWorkoutSummary {
    let title: String
    let detail: String

    init(fallback: PlateCollectionFallbackSummary) {
        title = fallback.title
        detail = fallback.detail
    }

    init(plate: EarnedPlate, workout: CompletedWorkout) {
        let bestSet = workout.entries
            .flatMap { entry in entry.sets.map { (entry: entry, set: $0) } }
            .filter { $0.set.tag == .working && $0.set.hasData }
            .sorted {
                if $0.set.weight != $1.set.weight { return $0.set.weight > $1.set.weight }
                return $0.set.reps > $1.set.reps
            }
            .first

        if plate.earnedByEvent.hasPrefix("pr_"), let bestSet {
            title = bestSet.entry.exerciseName
            detail = "PR \(bestSet.set.displayValue.uppercased())"
            return
        }

        title = workout.workoutName ?? workout.workoutTypeDisplayName
        if let bestSet {
            detail = "\(bestSet.entry.exerciseName.uppercased()) / \(bestSet.set.displayValue.uppercased())"
        } else {
            detail = workout.date.formatted(date: .abbreviated, time: .omitted).uppercased()
        }
    }
}

// MARK: - PlateMedallionView

struct PlateMedallionView: View {
    let plate: EarnedPlate
    let accentColor: Color

    var body: some View {
        PlateFaceView(
            tierID: plate.tierID,
            progressionTier: plate.currentTier,
            liftTypeID: plate.liftTypeID,
            weightKg: plate.weightKg
        )
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

// MARK: - PlateButtonMode

enum PlateButtonMode {
    case remove
    case rack
    case store
    case storeReplacing
}

// MARK: - PlateCollectionCell

struct PlateCollectionCell: View {
    let plate: EarnedPlate
    let workoutSummary: PlateWorkoutSummary?
    let buttonMode: PlateButtonMode
    let isInWallStorage: Bool
    let onOpenDetail: () -> Void
    let onPrimaryAction: () -> Void

    private var tier: PlateTier? {
        PlateTier.all.first(where: { $0.id == plate.tierID })
    }

    private var tierName: String {
        tier?.name ?? "Tier \(plate.tierID + 1)"
    }

    private var rarityLabel: String {
        guard let tier else { return "Earned" }
        switch tier.rarity {
        case .common: return "Common"
        case .uncommon: return "Uncommon"
        case .rare: return "Rare"
        case .epic: return "Epic"
        case .legendary: return "Legendary"
        }
    }

    private var accentColor: Color {
        guard let tier else { return DS.Semantic.brand }
        switch tier.rarity {
        case .common: return .white.opacity(0.70)
        case .uncommon: return Color(hex: "#80E6A2")
        case .rare: return Color(hex: "#6CB7FF")
        case .epic: return Color(hex: "#C694FF")
        case .legendary: return DS.Semantic.brand
        }
    }

    private var displayTitle: String {
        plate.engravingText.isEmpty ? tierName : plate.engravingText
    }

    private var statusLabel: String {
        if plate.isRacked  { return "RACKED" }
        if isInWallStorage { return "STORED" }
        return "OWNED"
    }

    // Wall was full and user explicitly displaced a plate to put this one in — confirm it.
    // Only fires for .storeReplacing (wall was at capacity). When bar is full but wall has
    // space (.store), every plate already fits in the wall by default so no confirmation needed.
    private var isStorageConfirmed: Bool {
        buttonMode == .storeReplacing && isInWallStorage
    }

    private var buttonLabel: String {
        if isStorageConfirmed    { return "In Storage" }
        switch buttonMode {
        case .remove:            return "Remove"
        case .rack:              return "Rack"
        case .store, .storeReplacing: return "Rack Storage"
        }
    }

    private var buttonIcon: String? {
        if isStorageConfirmed    { return "checkmark.circle.fill" }
        switch buttonMode {
        case .remove:            return "arrow.down.circle.fill"
        case .rack:              return "plus.circle.fill"
        case .store, .storeReplacing: return nil
        }
    }

    private var buttonForeground: Color {
        if isStorageConfirmed    { return Color.white.opacity(0.45) }
        switch buttonMode {
        case .remove:            return .white
        case .rack:              return .black
        case .store, .storeReplacing: return .white
        }
    }

    private var buttonBackground: Color {
        if isStorageConfirmed    { return Color.white.opacity(0.06) }
        switch buttonMode {
        case .remove:            return Color.white.opacity(0.10)
        case .rack:              return DS.Semantic.brand
        case .store, .storeReplacing: return Color.white.opacity(0.14)
        }
    }

    private var buttonBorder: Color {
        if isStorageConfirmed    { return Color.white.opacity(0.08) }
        switch buttonMode {
        case .remove:            return Color.white.opacity(0.10)
        case .rack:              return .clear
        case .store, .storeReplacing: return Color.white.opacity(0.22)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            tappableContent

            Spacer(minLength: 0)

            Button(action: onPrimaryAction) {
                HStack(spacing: 7) {
                    if let icon = buttonIcon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(buttonLabel)
                        .dsFont(.caption, weight: .bold)
                }
                .foregroundStyle(buttonForeground)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(buttonBackground, in: ChamferedRectangle(.medium))
                .overlay(
                    ChamferedRectangle(.medium)
                        .stroke(buttonBorder, lineWidth: 1)
                )
            }
            .disabled(isStorageConfirmed)
        }
        .frame(minHeight: 214, alignment: .top)
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.white.opacity(0.055)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: ChamferedRectangle(.large)
        )
        .overlay(
            ChamferedRectangle(.large)
                .stroke(accentColor.opacity(0.28), lineWidth: 1)
        )
    }

    private var tappableContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(plate.weightKg))kg")
                        .font(DS.Typography.custom(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text(tierName)
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer(minLength: 8)
                PlateMedallionView(plate: plate, accentColor: accentColor)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(displayTitle)
                    .dsFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                HStack(spacing: 6) {
                    Text(rarityLabel.uppercased())
                    Text("/")
                    Text(statusLabel)
                }
                .font(DS.Typography.custom(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.48))
                .tracking(0.7)
            }

            if let workoutSummary {
                VStack(alignment: .leading, spacing: 3) {
                    Text(workoutSummary.title)
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(workoutSummary.detail)
                        .font(DS.Typography.custom(size: 10, weight: .bold))
                        .foregroundStyle(DS.Semantic.brand.opacity(0.90))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                        .tracking(0.5)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onOpenDetail() }
    }
}
