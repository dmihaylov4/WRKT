// Features/Social/Views/BarbellShowcaseCard.swift
import SwiftUI
import SwiftData

struct BarbellShowcaseCard: View {
    let isOwnProfile: Bool
    let ownerId: UUID
    let sessionCount: Int
    var friendRackedPlates: [EarnedPlateInfo] = []

    @State private var showingPlateWall = false

    var body: some View {
        if isOwnProfile {
            OwnBarbellCard(sessionCount: sessionCount, showingPlateWall: $showingPlateWall)
        } else {
            FriendBarbellCard(plates: friendRackedPlates)
        }
    }
}

// MARK: - Own Profile Card

private struct OwnBarbellCard: View {
    let sessionCount: Int
    @Binding var showingPlateWall: Bool

    @Query(filter: #Predicate<EarnedPlate> { $0.isRacked == true })
    private var ownRackedPlates: [EarnedPlate]

    @Query(filter: #Predicate<EarnedPlate> { $0.earnedByEvent != "starter" })
    private var ownAllEarnedPlates: [EarnedPlate]

    private var plates: [EarnedPlateInfo] {
        ownRackedPlates.map {
            EarnedPlateInfo(tierID: $0.tierID, weightKg: $0.weightKg,
                            engravingText: $0.engravingText, earnedByEvent: $0.earnedByEvent)
        }
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
                BarbellPreviewView(mode: .showcase(plates: plates))
                    .frame(height: 240)
                    .clipped()

                Button { showingPlateWall = true } label: {
                    Text("Customize")
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(DS.Semantic.brand)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.1), in: Capsule())
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
    }
}

// MARK: - Friend Profile Card

private struct FriendBarbellCard: View {
    let plates: [EarnedPlateInfo]

    private var totalWeight: Double {
        let earned = plates.filter { $0.earnedByEvent != "starter" }
        return 20 + earned.reduce(0) { $0 + $1.weightKg } * 2
    }

    var body: some View {
        VStack(spacing: 0) {
            BarbellPreviewView(mode: .showcase(plates: plates))
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
