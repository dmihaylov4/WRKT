import SwiftUI

struct PlateInfoCardView: View {
    let plate: EarnedPlate
    let onDismiss: () -> Void

    private var tier: PlateTier? {
        PlateTier.all.first { $0.id == plate.tierID }
    }

    private var tierName: String {
        tier?.name ?? "Unknown Plate"
    }

    private var rarity: PlateTier.Rarity {
        tier?.rarity ?? .common
    }

    private var tierColor: Color {
        tier.map { Color(uiColor: $0.plateColor) } ?? DS.Semantic.brand
    }

    private var earnedDateText: String {
        plate.earnedAt.formatted(date: .abbreviated, time: .omitted)
    }

    private var weightText: String? {
        guard plate.weightKg > 0 else { return nil }
        if plate.weightKg.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(plate.weightKg)) kg"
        }
        return String(format: "%.1f kg", plate.weightKg)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: DS.Space.l) {
                if let weightText {
                    infoRow(label: "WEIGHT", value: weightText)
                }

                infoRow(label: "HOW YOU EARNED IT", value: infoCardFormatEvent(plate.earnedByEvent))
                infoRow(label: "EARNED ON", value: earnedDateText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.xl)
        }
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.xl))
        .overlay(
            ChamferedRectangle(.xl)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 12)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: DS.Space.m) {
                PlateFaceView(
                    tierID: plate.tierID,
                    progressionTier: plate.currentTier,
                    liftTypeID: plate.liftTypeID,
                    weightKg: plate.weightKg
                )
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 5)

                VStack(spacing: DS.Space.s) {
                    Text(tierName)
                        .font(DS.Typography.custom(size: 30, weight: .bold, relativeTo: .title2))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)

                    Text(rarity.rawValue.uppercased())
                        .font(DS.Typography.custom(size: 12, weight: .black, relativeTo: .caption))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.m)
                        .padding(.vertical, DS.Space.xs)
                        .background(.white.opacity(0.18), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Space.xl)
            .padding(.horizontal, DS.Space.xl)
            .padding(.bottom, DS.Space.xl)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.24), in: ChamferedRectangle(.small))
                    .overlay(
                        ChamferedRectangle(.small)
                            .stroke(.white.opacity(0.24), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss plate info")
            .padding(.top, DS.Space.m)
            .padding(.trailing, DS.Space.m)
        }
        .background(
            LinearGradient(
                colors: [
                    tierColor.opacity(0.90),
                    tierColor.darken(0.18).opacity(0.70),
                    DS.Theme.cardTop.opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(ChamferedRectangle(.xl))
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(label)
                .font(DS.Typography.custom(size: 12, weight: .black, relativeTo: .caption))
                .foregroundStyle(DS.Semantic.textSecondary)

            Text(value)
                .font(DS.Typography.custom(size: 22, weight: .bold, relativeTo: .title3))
                .foregroundStyle(DS.Semantic.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private func infoCardFormatEvent(_ event: String) -> String {
    switch event {
    case "starter": return "Awarded at account creation"
    case "first_workout": return "Completed your first workout"
    default: break
    }

    if event.hasPrefix("pr_") {
        return "Hit a personal record"
    }

    if event.hasPrefix("strength_milestone_") {
        let n = event.replacingOccurrences(of: "strength_milestone_", with: "")
        return "Reached strength milestone \(n)"
    }

    return event.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
}
