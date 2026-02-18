//
//  DexTile.swift
//  WRKT
//
//  Created by You on 15.10.25.
//

import SwiftUI

// MARK: - Design tokens
private enum DexTileMetrics {
    static let corner: CGFloat = 16
    static let pad: CGFloat = 12
    static let badgeSize: CGFloat = 44
    static let iconFont: Font = .title3.weight(.bold)
    static let minHeight: CGFloat = 140           // identical height everywhere
    static let titleLines: Int = 2
}

private enum DexTileColors {
    static let cardFill: Material = .ultraThinMaterial
    static var cardStroke: some ShapeStyle { .quaternary }   // ← computed
    static let lockedFill = Color(.tertiarySystemFill)
    static let unlockedIcon = DS.Theme.accent
    static let lockedIcon = Color.secondary
    static let title = Color.primary
    static let meta = Color.secondary
    static let progressTint = DS.Theme.accent
}

// MARK: - Tile
struct DexTile: View, Equatable {
    let item: DexItem
    static func == (lhs: DexTile, rhs: DexTile) -> Bool { lhs.item == rhs.item }

    var body: some View {
        VStack(spacing: DexTileMetrics.pad) {
            TrophyBadge(unlocked: item.isUnlocked)

            Text(item.short)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(DexTileMetrics.titleLines)
                .minimumScaleFactor(0.85)
                .foregroundStyle(DexTileColors.title)

            MetaRow(item: item)
        }
        .padding(DexTileMetrics.pad)
        .frame(minHeight: DexTileMetrics.minHeight)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: DexTileMetrics.corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DexTileMetrics.corner, style: .continuous)
                .stroke(DexTileColors.cardStroke, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: DexTileMetrics.corner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if let when = item.unlockedAt {
            return "\(item.name), unlocked on \(DateFormatter.localizedString(from: when, dateStyle: .medium, timeStyle: .none))"
        } else {
            return "\(item.name), locked"
        }
    }
}

// MARK: - Pieces
private struct TrophyBadge: View {
    let unlocked: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(badgeFill)
                .overlay(
                    Circle().strokeBorder(borderColor, lineWidth: unlocked ? 1.5 : 1)
                )
                .shadow(color: shadowColor, radius: unlocked ? 6 : 3, y: unlocked ? 3 : 1)

            Image(systemName: unlocked ? "trophy.fill" : "trophy")
                .font(.title3.weight(.bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(trophyColor)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    private var badgeFill: some ShapeStyle {
        if unlocked {
            // Sleek dark gradient with subtle accent hint
            return LinearGradient(
                colors: [
                    Color.black.opacity(0.4),
                    Color.black.opacity(0.6)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            // Locked state - very subtle gray
            return LinearGradient(
                colors: [
                    Color(.tertiarySystemFill),
                    Color(.tertiarySystemFill)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var borderColor: Color {
        unlocked ? DS.Theme.accent.opacity(0.4) : .white.opacity(0.15)
    }

    private var shadowColor: Color {
        unlocked ? DS.Theme.accent.opacity(0.2) : .black.opacity(0.05)
    }

    private var trophyColor: Color {
        unlocked ? DS.Theme.accent : .secondary
    }
}

private struct MetaRow: View {
    let item: DexItem

    var body: some View {
        Group {
            if item.isUnlocked, let when = item.unlockedAt {
                // Unlocked date
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DexTileColors.unlockedIcon)
                    Text(when, style: .date)
                        .font(.caption2)
                        .foregroundStyle(DexTileColors.meta)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // Subtle progress bar (keeps same layout slot)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.secondary.opacity(0.18))
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(DexTileColors.progressTint)
                            .frame(width: max(6, geo.size.width * item.frac))
                    }
                }
                .frame(height: 6)
            }
        }
        .frame(height: 16) // fixed row height → identical tiles
    }
}
