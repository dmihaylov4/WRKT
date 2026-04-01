// Features/Social/Views/BarbellShowcaseCard.swift
import SwiftUI
import SwiftData

struct BarbellShowcaseCard: View {
    let isOwnProfile: Bool
    let ownerId: UUID
    let sessionCount: Int

    // Own profile: read from SwiftData directly
    @Query(filter: #Predicate<EarnedPlate> { $0.isRacked == true })
    private var ownRackedPlates: [EarnedPlate]

    // All owned earned plates (excluding starter) for collection count
    @Query(filter: #Predicate<EarnedPlate> { $0.earnedByEvent != "starter" })
    private var ownAllEarnedPlates: [EarnedPlate]

    // Friend profile: passed in
    var friendRackedPlates: [EarnedPlateInfo] = []

    @State private var showingPlateWall = false

    private var plates: [EarnedPlateInfo] {
        if isOwnProfile {
            return ownRackedPlates.map {
                EarnedPlateInfo(tierID: $0.tierID, weightKg: $0.weightKg,
                                engravingText: $0.engravingText, earnedByEvent: $0.earnedByEvent)
            }
        }
        return friendRackedPlates
    }

    private var totalWeight: Double {
        let earned = plates.filter { $0.earnedByEvent != "starter" }
        return 20 + earned.reduce(0) { $0 + $1.weightKg } * 2
    }

    private var collectionCount: Int {
        // Total earned plates minus those currently racked
        guard isOwnProfile else { return 0 }
        let rackedEarnedCount = ownRackedPlates.filter { $0.earnedByEvent != "starter" }.count
        return max(0, ownAllEarnedPlates.count - rackedEarnedCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Barbell preview
            ZStack(alignment: .topTrailing) {
                BarbellPreviewView(mode: .showcase(plates: plates))
                    .frame(height: 240)
                    .clipped()

                if isOwnProfile {
                    Button {
                        showingPlateWall = true
                    } label: {
                        Text("Customize")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DS.Semantic.brand)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                    .padding(12)
                }
            }

            // Footer
            HStack {
                Text("\(sessionCount) sessions")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer(minLength: 8)

                Text("\(Int(totalWeight))kg loaded")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))

                if collectionCount > 0 {
                    Text("· \(collectionCount) more in collection")
                        .font(.caption)
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
