// Features/Rewards/Views/BarbellWelcomeView.swift
import SwiftUI
import SwiftData

struct BarbellWelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var ownedPlates: [EarnedPlate]
    @State private var showPlateWall = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Text("Your workouts have paid off.")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("\(ownedPlates.filter { $0.earnedByEvent != "starter" }.count) plates earned")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 24)

                // Plate grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                    ForEach(ownedPlates.filter { $0.earnedByEvent != "starter" }) { plate in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(plateColor(for: plate.tierID))
                                .frame(width: 52, height: 52)
                                .overlay(
                                    Text(plate.weightKg > 0 ? "\(Int(plate.weightKg))" : "")
                                        .font(.caption.weight(.black))
                                        .foregroundStyle([0,1,2].contains(plate.tierID) ? Color.white : Color.black)
                                )
                            Text(plate.engravingText)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                // Opens into PlateWallView: dismiss only happens from inside PlateWallView.
                Button {
                    showPlateWall = true
                } label: {
                    Text("Build Your Rack")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .background(DS.Semantic.brand)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .fullScreenCover(isPresented: $showPlateWall) {
            PlateWallView()
                .onDisappear { dismiss() }
        }
    }

    private func plateColor(for tierID: Int) -> Color {
        switch tierID {
        case 0: return Color(red: 0.40, green: 0.18, blue: 0.07)
        case 1: return Color(red: 0.14, green: 0.14, blue: 0.14)
        case 2: return Color(red: 0.07, green: 0.07, blue: 0.07)
        case 3: return Color(red: 0.75, green: 0.60, blue: 0.25)
        case 4: return Color(red: 0.82, green: 0.09, blue: 0.09)
        case 5: return Color(red: 0.72, green: 0.76, blue: 0.80)
        case 6: return Color(red: 0.88, green: 0.68, blue: 0.12)
        default: return .gray
        }
    }
}
