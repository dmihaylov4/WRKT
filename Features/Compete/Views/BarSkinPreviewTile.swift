import SwiftUI
import UIKit

struct BarSkinPreviewTile: View {
    let skin: BarSkin

    private var baseColor: Color {
        Color(uiColor: skin.barColor)
    }

    private var metallicStrength: Double {
        Double(skin.metallic).clamped(to: 0...1)
    }

    private var roughness: Double {
        Double(skin.roughness).clamped(to: 0...1)
    }

    var body: some View {
        GeometryReader { geo in
            let height = max(geo.size.height, 1)
            let radius = min(height * 0.5, 10)

            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(baseGradient)
                .overlay(metallicOverlay(cornerRadius: radius))
                .overlay(edgeHighlights(cornerRadius: radius))
                .shadow(color: .black.opacity(0.24), radius: 3, x: 0, y: 2)
        }
        .accessibilityLabel("\(skin.name) bar skin")
    }

    private var baseGradient: LinearGradient {
        LinearGradient(
            colors: [
                baseColor.brightenedForBarSkinPreview(by: 0.30 - roughness * 0.10),
                baseColor.brightenedForBarSkinPreview(by: 0.08),
                baseColor.darkenedForBarSkinPreview(by: 0.24 + roughness * 0.08),
                baseColor.brightenedForBarSkinPreview(by: 0.14)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func metallicOverlay(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.34 * metallicStrength), location: 0.00),
                        .init(color: .white.opacity(0.08 * metallicStrength), location: 0.22),
                        .init(color: .black.opacity(0.26 * metallicStrength), location: 0.52),
                        .init(color: .white.opacity(0.22 * metallicStrength), location: 0.78),
                        .init(color: .white.opacity(0.08 * metallicStrength), location: 1.00)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .blendMode(.overlay)
    }

    private func edgeHighlights(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color.white.opacity(0.20 + metallicStrength * 0.16), lineWidth: 1)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.34), lineWidth: 1)
                    .padding(1)
            )
    }
}

extension BarSkin {
    static func skin(forCosmeticID cosmeticID: String) -> BarSkin? {
        switch cosmeticID {
        case "steel_default", "chrome":
            return all.first { $0.id == 0 }
        case "black_oxide":
            return all.first { $0.id == 1 }
        case "brass_accent", "may_2026_brass_accent":
            return all.first { $0.id == 2 }
        case "cerakote":
            return all.first { $0.id == 3 }
        case "volia":
            return all.first { $0.id == 4 }
        default:
            return nil
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Color {
    func brightenedForBarSkinPreview(by amount: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(
            hue: Double(h),
            saturation: Double(s),
            brightness: min(1, Double(b) + amount),
            opacity: Double(a)
        )
    }

    func darkenedForBarSkinPreview(by amount: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(
            hue: Double(h),
            saturation: Double(s),
            brightness: max(0, Double(b) - amount),
            opacity: Double(a)
        )
    }
}
