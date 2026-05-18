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

enum BarbellShowcasePreviewRenderer: Equatable {
    case realityKit
}

enum BarbellShowcasePreviewContext {
    case socialProfileCard
    case socialProfileRoom
    case editor
}

func barbellShowcasePreviewRenderer(for context: BarbellShowcasePreviewContext) -> BarbellShowcasePreviewRenderer {
    switch context {
    case .socialProfileCard, .socialProfileRoom, .editor:
        return .realityKit
    }
}

struct BarbellShowcasePreviewSurface: View {
    let context: BarbellShowcasePreviewContext
    let plates: [EarnedPlateInfo]
    let selectedBarID: Int
    let selectedRoomThemeID: String
    let selectedRackStyleID: String
    let showPlateEngravings: Bool

    var body: some View {
        switch barbellShowcasePreviewRenderer(for: context) {
        case .realityKit:
            BarbellPreviewView(
                mode: .showcase(plates: plates),
                selectedBarID: selectedBarID,
                selectedRoomThemeID: selectedRoomThemeID,
                selectedRackStyleID: selectedRackStyleID,
                showPlateEngravings: showPlateEngravings
            )
        }
    }
}

// MARK: - Own Profile Card

private struct OwnBarbellCard: View {
    let sessionCount: Int
    @Binding var showingPlateWall: Bool
    @State private var showingCollection = false
    @EnvironmentObject private var store: WorkoutStoreV2

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
        if let configured = configuredBarPlates {
            return configured
        }

        let racked = ownRackedPlates.sorted {
            let leftPosition = $0.rackPosition ?? Int.max
            let rightPosition = $1.rackPosition ?? Int.max
            if leftPosition != rightPosition { return leftPosition < rightPosition }
            return $0.earnedAt > $1.earnedAt
        }
        if !racked.isEmpty { return racked }

        return ownAllEarnedPlates.sorted { $0.earnedAt > $1.earnedAt }
    }

    private var configuredBarPlates: [EarnedPlate]? {
        guard let config = configs.first else { return nil }
        let availablePlates = Array(
            Dictionary(grouping: ownRackedPlates + ownAllEarnedPlates, by: \.id)
                .compactMap { $0.value.first }
        )
        return configuredBarbellDisplayPlates(loadout: config.displayLoadout, earnedPlates: availablePlates)
    }

    private var selectedBarSkinIndex: Int {
        guard let config = configs.first else { return 0 }
        switch config.effectiveSelectedBarSkinID {
        case "black_oxide": return 1
        case "gold", "brass_accent", "may_2026_brass_accent": return 2
        case "cerakote": return 3
        case "volia": return 4
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
                BarbellShowcasePreviewSurface(
                    context: .socialProfileCard,
                    plates: plates,
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
                        Text("Storage")
                            .dsFont(.caption, weight: .semibold)
                            .foregroundStyle(DS.Semantic.brand)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                    .accessibilityLabel("Storage")

                    Button { showingPlateWall = true } label: {
                        Text("Rack")
                            .dsFont(.caption, weight: .semibold)
                            .foregroundStyle(DS.Semantic.brand)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                    .accessibilityLabel("Rack")
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
            BarbellEditorView(openOnStorage: true)
                .environmentObject(store)
        }
    }
}

// MARK: - Friend Profile Card

private struct FriendBarbellCard: View {
    let showcase: BarbellFriendShowcase?
    let fallbackPlates: [EarnedPlateInfo]

    @State private var showingFriendRoom = false

    private var plates: [EarnedPlateInfo] {
        showcase?.plates ?? fallbackPlates
    }

    private var selectedBarSkinIndex: Int {
        switch showcase?.barSkinID {
        case "black_oxide": return 1
        case "gold", "brass_accent", "may_2026_brass_accent": return 2
        case "cerakote": return 3
        case "volia": return 4
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
            ZStack(alignment: .topTrailing) {
                BarbellShowcasePreviewSurface(
                    context: .socialProfileCard,
                    plates: plates,
                    selectedBarID: selectedBarSkinIndex,
                    selectedRoomThemeID: selectedRoomThemeID,
                    selectedRackStyleID: selectedRackStyleID,
                    showPlateEngravings: showPlateEngravings
                )
                    .frame(height: 240)
                    .clipped()

                Button { showingFriendRoom = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Semantic.brand)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.1), in: Capsule())
                }
                .accessibilityLabel("Open barbell room")
                .padding(12)
            }

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
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            showingFriendRoom = true
        }
        .sheet(isPresented: $showingFriendRoom) {
            FriendBarbellRoomView(
                showcase: showcase,
                plates: plates,
                selectedBarSkinIndex: selectedBarSkinIndex,
                selectedRoomThemeID: selectedRoomThemeID,
                selectedRackStyleID: selectedRackStyleID,
                showPlateEngravings: showPlateEngravings,
                totalWeight: totalWeight
            )
        }
    }
}

struct FriendBarbellRoomView: View {
    let showcase: BarbellFriendShowcase?
    let plates: [EarnedPlateInfo]
    let selectedBarSkinIndex: Int
    let selectedRoomThemeID: String
    let selectedRackStyleID: String
    let showPlateEngravings: Bool
    let totalWeight: Double

    @Environment(\.dismiss) private var dismiss

    private var roomTitle: String {
        let trimmed = showcase?.roomName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Barbell Room" : trimmed
    }

    private var motto: String? {
        let trimmed = showcase?.roomMotto?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BarbellShowcasePreviewSurface(
                    context: .socialProfileRoom,
                    plates: plates,
                    selectedBarID: selectedBarSkinIndex,
                    selectedRoomThemeID: selectedRoomThemeID,
                    selectedRackStyleID: selectedRackStyleID,
                    showPlateEngravings: showPlateEngravings
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: 420)
                    .clipped()

                VStack(alignment: .leading, spacing: 10) {
                    if let motto {
                        Text(motto)
                            .dsFont(.body, weight: .medium)
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 12) {
                        Text("\(Int(totalWeight))kg loaded")
                        Text("\(plates.filter { $0.earnedByEvent != "starter" }.count) plates")
                    }
                    .dsFont(.caption, weight: .medium)
                    .foregroundStyle(DS.Semantic.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)

                Spacer(minLength: 0)
            }
            .background(DS.Semantic.surface)
            .navigationTitle(roomTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }
}
