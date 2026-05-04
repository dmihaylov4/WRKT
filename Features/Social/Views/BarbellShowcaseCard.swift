// Features/Social/Views/BarbellShowcaseCard.swift
import SwiftUI
import SwiftData

struct BarbellShowcaseCard: View {
    let isOwnProfile: Bool
    let ownerId: UUID
    let sessionCount: Int
    var friendRackedPlates: [EarnedPlateInfo] = []
    var friendShowcase: BarbellFriendShowcase?

    @State private var showingPlateWall = false

    var body: some View {
        if isOwnProfile {
            OwnBarbellCard(sessionCount: sessionCount, showingPlateWall: $showingPlateWall)
        } else {
            FriendBarbellCard(showcase: friendShowcase, fallbackPlates: friendRackedPlates)
        }
    }
}

// MARK: - Own Profile Card

private struct OwnBarbellCard: View {
    let sessionCount: Int
    @Binding var showingPlateWall: Bool
    @State private var showingCollection = false

    @Query(filter: #Predicate<EarnedPlate> { $0.isRacked == true })
    private var ownRackedPlates: [EarnedPlate]

    @Query(filter: #Predicate<EarnedPlate> { $0.earnedByEvent != "starter" })
    private var ownAllEarnedPlates: [EarnedPlate]

    @Query(filter: #Predicate<BarbellConfig> { $0.id == "global" })
    private var configs: [BarbellConfig]

    private var plates: [EarnedPlateInfo] {
        displaySourcePlates.map {
            EarnedPlateInfo(
                tierID: $0.tierID,
                weightKg: $0.weightKg,
                engravingText: $0.engravingText,
                earnedByEvent: $0.earnedByEvent,
                liftTypeID: $0.liftTypeID
            )
        }
    }

    private var displaySourcePlates: [EarnedPlate] {
        if let configured = configuredBarPlates, !configured.isEmpty {
            return configured
        }

        return ownRackedPlates.sorted {
            let leftPosition = $0.rackPosition ?? Int.max
            let rightPosition = $1.rackPosition ?? Int.max
            if leftPosition != rightPosition { return leftPosition < rightPosition }
            return $0.earnedAt > $1.earnedAt
        }
    }

    private var configuredBarPlates: [EarnedPlate]? {
        guard let config = configs.first else { return nil }
        let availablePlates = Array(
            Dictionary(grouping: ownRackedPlates + ownAllEarnedPlates, by: \.id)
                .compactMap { $0.value.first }
        )
        let loadout = config.displayLoadout
            .sanitized(earnedPlateIDs: Set(availablePlates.map(\.id)), maximumBarPlateCount: 4)
        guard !loadout.onBar.isEmpty else { return nil }

        let platesByID = Dictionary(uniqueKeysWithValues: availablePlates.map { ($0.id, $0) })
        return loadout.onBar.compactMap { platesByID[$0] }
    }

    private var selectedBarSkinIndex: Int {
        guard let config = configs.first else { return 0 }
        switch config.effectiveSelectedBarSkinID {
        case "black_oxide": return 1
        case "gold", "brass_accent", "may_2026_brass_accent": return 2
        case "cerakote": return 3
        default: return 0
        }
    }

    private var selectedRoomThemeID: String {
        configs.first?.effectiveSelectedRoomThemeID ?? BarbellCustomizationDefaults.roomThemeID
    }

    private var selectedRackStyleID: String {
        configs.first?.effectiveSelectedRackStyleID ?? BarbellCustomizationDefaults.rackStyleID
    }

    private var showPlateEngravings: Bool {
        configs.first?.showPlateEngravings ?? BarbellCustomizationDefaults.showPlateEngravings
    }

    private var previewIdentity: String {
        [
            "\(selectedBarSkinIndex)",
            selectedRoomThemeID,
            selectedRackStyleID,
            "\(showPlateEngravings)",
            plates.map(\.earnedByEvent).joined(separator: "|")
        ].joined(separator: "-")
    }

    private var totalWeight: Double {
        let earned = plates.filter { $0.earnedByEvent != "starter" }
        return 20 + earned.reduce(0) { $0 + $1.weightKg } * 2
    }

    private var collectionCount: Int {
        let rackedEarnedCount = ownRackedPlates.filter { $0.earnedByEvent != "starter" }.count
        return max(0, ownAllEarnedPlates.count - rackedEarnedCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                BarbellPreviewView(
                    mode: .showcase(plates: plates),
                    selectedBarID: selectedBarSkinIndex,
                    selectedRoomThemeID: selectedRoomThemeID,
                    selectedRackStyleID: selectedRackStyleID,
                    showPlateEngravings: showPlateEngravings
                )
                    .id(previewIdentity)
                    .frame(height: 240)
                    .clipped()

                HStack(spacing: 8) {
                    Button { showingCollection = true } label: {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(DS.Semantic.brand)
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                    .accessibilityLabel("Collection")

                    Button { showingPlateWall = true } label: {
                        Text("Customize")
                            .dsFont(.caption, weight: .semibold)
                            .foregroundStyle(DS.Semantic.brand)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                }
                .padding(12)
            }

            HStack {
                Text("\(sessionCount) sessions")
                    .dsFont(.caption, weight: .medium)
                    .foregroundStyle(.white.opacity(0.5))

                Spacer(minLength: 8)

                Text("\(Int(totalWeight))kg loaded")
                    .dsFont(.caption, weight: .medium)
                    .foregroundStyle(.white.opacity(0.5))

                if collectionCount > 0 {
                    Text("· \(collectionCount) more in collection")
                        .dsFont(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(DS.Semantic.card)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DS.Semantic.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showingPlateWall) {
            PlateWallView()
        }
        .sheet(isPresented: $showingCollection) {
            PlateCollectionView()
        }
    }
}

// MARK: - Friend Profile Card

private struct FriendBarbellCard: View {
    let showcase: BarbellFriendShowcase?
    let fallbackPlates: [EarnedPlateInfo]

    private var plates: [EarnedPlateInfo] {
        showcase?.plates ?? fallbackPlates
    }

    private var selectedBarSkinIndex: Int {
        switch showcase?.barSkinID {
        case "black_oxide": return 1
        case "gold", "brass_accent", "may_2026_brass_accent": return 2
        case "cerakote": return 3
        default: return 0
        }
    }

    private var selectedRoomThemeID: String {
        showcase?.roomThemeID ?? BarbellCustomizationDefaults.roomThemeID
    }

    private var selectedRackStyleID: String {
        showcase?.rackStyleID ?? BarbellCustomizationDefaults.rackStyleID
    }

    private var showPlateEngravings: Bool {
        showcase?.showPlateEngravings ?? BarbellCustomizationDefaults.showPlateEngravings
    }

    private var totalWeight: Double {
        let earned = plates.filter { $0.earnedByEvent != "starter" }
        return 20 + earned.reduce(0) { $0 + $1.weightKg } * 2
    }

    var body: some View {
        VStack(spacing: 0) {
            BarbellPreviewView(
                mode: .showcase(plates: plates),
                selectedBarID: selectedBarSkinIndex,
                selectedRoomThemeID: selectedRoomThemeID,
                selectedRackStyleID: selectedRackStyleID,
                showPlateEngravings: showPlateEngravings
            )
                .frame(height: 240)
                .clipped()

            HStack {
                Text("\(Int(totalWeight))kg loaded")
                    .dsFont(.caption, weight: .medium)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(DS.Semantic.card)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DS.Semantic.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
