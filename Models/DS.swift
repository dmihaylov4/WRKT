//
//  DS.swift
//  WRKT
//
//  Design System – accents locked to #6B21A8, #BA5C12, #FFB86F, #E0CA3C
//  Neutrals used for surfaces & text contrast.
//  iOS 17+, Swift 5.9
//

import SwiftUI
import UIKit

// MARK: - Hex & Dynamic Helpers
public extension Color {
    /// Initialize a Color with a hex string like "#6B21A8" or "6B21A8".
    init(hex: String, alpha: CGFloat = 1.0) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        if hexString.count == 3 {
            // e.g. F0A -> FF00AA
            let c = Array(hexString)
            hexString = String([c[0],c[0],c[1],c[1],c[2],c[2]])
        }

        var n: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&n)
        if hexString.count == 6 {
            let r = CGFloat((n & 0xFF0000) >> 16) / 255
            let g = CGFloat((n & 0x00FF00) >> 8)  / 255
            let b = CGFloat(n & 0x0000FF) / 255
            self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
        } else {
            self = .clear
        }
    }

    /// Dynamic color that resolves to different values in light/dark mode.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    /// HSB adjust (values are deltas; range clamped to 0...1)
    func hsbAdjust(h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0) -> Color {
        var hh: CGFloat = 0, ss: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        UIColor(self).getHue(&hh, saturation: &ss, brightness: &bb, alpha: &aa)
        func clamp(_ v: CGFloat) -> CGFloat { max(0, min(1, v)) }
        let nh = clamp(hh + h)
        let ns = clamp(ss + s)
        let nb = clamp(bb + b)
        return Color(hue: Double(nh), saturation: Double(ns), brightness: Double(nb), opacity: Double(aa))
    }
    func lighten(_ amount: CGFloat) -> Color { hsbAdjust(b: amount) }
    func darken(_ amount: CGFloat)  -> Color { hsbAdjust(b: -amount) }
    func saturate(_ amount: CGFloat)   -> Color { hsbAdjust(s: amount) }
    func desaturate(_ amount: CGFloat) -> Color { hsbAdjust(s: -amount) }
}

// MARK: - DS (Design System)
public enum DS {

    // MARK: Palette — locked accents + neutrals
    public enum Palette {
        // Accents (ONLY these + their shades)
        public static let brand   = Color(hex: "#FFB86F") // deep purple (primary)
        public static let spice   = Color(hex: "#BA5C12") // warm (danger/emphasis)
        public static let apricot = Color(hex: "#FFB86F") // soft positive
        public static let saffron = Color(hex: "#E0CA3C") // warning/highlight

        // Neutrals (for surfaces & legible text)
        public static let gray50  = Color(hex: "#FAFAFA")
        public static let gray100 = Color(hex: "#F4F4F5")
        public static let gray200 = Color(hex: "#E4E4E7")
        public static let gray300 = Color(hex: "#D4D4D8")
        public static let gray400 = Color(hex: "#A1A1AA")
        public static let gray500 = Color(hex: "#71717A")
        public static let gray600 = Color(hex: "#52525B")
        public static let gray700 = Color(hex: "#3F3F46")
        public static let gray800 = Color(hex: "#27272A")
        public static let gray900 = Color(hex: "#18181B")
        public static let gray950 = Color(hex: "#0B0B0C")
        
        // In DS.Palette
        public static let paperLight = Color(hex: "#FBF7FF") // brand-tinted near white
        public static let paperDark  = Color(hex: "#0F0718") // deep indigo
        
        public static let marone = Color(hex: "#F4E409")


    }

    // MARK: Semantic tokens
    public enum Semantic {
        // Brand & variations (calmer)
        public static let brand       = Palette.brand
        public static let onBrand     = Color.white
        public static let brandDim    = Palette.brand.darken(0.08).desaturate(0.06)
        public static let brandSoft   = Palette.brand.opacity(0.12)     // tinted bg

        // Other allowed accents
        public static let accentWarm  = Palette.spice
        public static let accentSoft  = Palette.apricot
        public static let accentGold  = Palette.saffron

        // Surfaces & text
        //public static let surface     = Color.dynamic(light: .white, dark: Palette.gray950)
        //public static let card        = Color.dynamic(light: .white, dark: Palette.gray900)
        public static let textPrimary = Color.dynamic(light: Color(hex: "#0B0B0C"), dark: .white)
        public static let textSecondary = Color.dynamic(light: Palette.gray600, dark: Palette.gray300)
        //public static let border      = Color.dynamic(light: Palette.gray200, dark: Palette.gray700)
        //public static let fillSubtle  = Color.dynamic(light: Palette.gray100, dark: Palette.gray800)

        // Feedback mapped to allowed hues
        public static let success     = Palette.apricot
        public static let warning     = Palette.saffron
        public static let danger      = Palette.spice
        
        // In DS.Semantic
        public static let surface = Color(hex: "#000000")
        public static let surface50 = Color(hex: "#333333")
        public static let card    = Color.dynamic(light: Color.white.opacity(0.96), dark: DS.Palette.paperDark.darken(0.06))
        public static let border  = Color.dynamic(light: Color.white.opacity(0.55), dark: Color.white.opacity(0.12))
        public static let fillSubtle = Color.dynamic(light: Color.white.opacity(0.70), dark: Color.white.opacity(0.06))
    }

    // MARK: Spacing / Radii / Elevation
    public enum Space { public static let xs: CGFloat = 4; public static let s: CGFloat = 8; public static let m: CGFloat = 12; public static let l: CGFloat = 16; public static let xl: CGFloat = 24; public static let xxl: CGFloat = 32 }
    public enum Radius { public static let s: CGFloat = 8; public static let m: CGFloat = 12; public static let l: CGFloat = 16; public static let xl: CGFloat = 24; public static let pill: CGFloat = 999 }

    public enum Elevation {
        public static func level1(_ colorScheme: ColorScheme) -> (Color, CGFloat, CGFloat, CGFloat) {
            let c = colorScheme == .dark ? Color.black.opacity(0.45) : Color.black.opacity(0.08)
            return (c, 10, 0, 4) // color, radius, x, y
        }
    }

    // MARK: Typography (system, dynamic type friendly)
    public enum FontType {
        public static var largeTitle: Font { .system(.largeTitle, design: .rounded).weight(.bold) }
        public static var title: Font      { .system(.title2,     design: .rounded).weight(.semibold) }
        public static var subtitle: Font   { .system(.subheadline,design: .rounded).weight(.semibold) }
        public static var body: Font       { .system(.body,       design: .rounded) }
        public static var footnote: Font   { .system(.footnote,   design: .rounded) }
        public static var caption: Font    { .system(.caption,    design: .rounded) }
        public static var mono: Font       { .system(.body,       design: .monospaced) }
    }

    // MARK: Gradients
    public enum Gradients {
        public static let brand = LinearGradient(
            colors: [Palette.brand.lighten(0.10), Palette.brand.darken(0.08)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        public static let brandGlow = LinearGradient(
            colors: [Palette.brand.darken(0.25), Palette.brand],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: Buttons
    public enum ButtonSize { case compact, regular, large
        var height: CGFloat   { switch self { case .compact: 36; case .regular: 44; case .large: 52 } }
        var hPadding: CGFloat { switch self { case .compact: 12; case .regular: 16; case .large: 20 } }
        var font: Font {
            switch self {
            case .compact: .system(.callout, design: .rounded).weight(.semibold)
            case .regular: .system(.body,    design: .rounded).weight(.semibold)
            case .large:   .system(.headline,design: .rounded).weight(.semibold)
            }
        }
    }

    /// Softer filled button (primary action)
    public struct PrimaryButtonStyle: ButtonStyle {
        public init(size: ButtonSize = .regular) { self.size = size }
        private let size: ButtonSize

        public func makeBody(configuration: Configuration) -> some View {
            let base = Semantic.brand.desaturate(0.08).darken(0.02)
            let pressed = base.darken(0.06)
            return configuration.label
                .font(size.font)
                .foregroundStyle(Semantic.onBrand)
                .frame(minHeight: size.height)
                .padding(.horizontal, size.hPadding)
                .background(configuration.isPressed ? pressed : base)
                .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                        .stroke(Semantic.brand.darken(0.12).opacity(0.25), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    /// Tinted (subtle) button — great default
    public struct SecondaryButtonStyle: ButtonStyle {
        public init(size: ButtonSize = .regular) { self.size = size }
        private let size: ButtonSize

        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(size.font)
                .foregroundStyle(Semantic.brand)
                .frame(minHeight: size.height)
                .padding(.horizontal, size.hPadding)
                .background(Semantic.brandSoft)
                .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                        .stroke(Semantic.brand.opacity(0.28), lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.8 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    /// Quiet text button
    public struct TertiaryButtonStyle: ButtonStyle {
        public init(size: ButtonSize = .regular) { self.size = size }
        private let size: ButtonSize

        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(size.font)
                .foregroundStyle(Semantic.brand)
                .padding(.horizontal, size.hPadding)
                .frame(minHeight: size.height)
                .background(.clear)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    // MARK: Cards & Chips
    public struct Card: ViewModifier {
        @Environment(\.colorScheme) private var scheme
        public func body(content: Content) -> some View {
            let (shadowColor, radius, x, y) = Elevation.level1(scheme)
            return content
                .padding(Space.l)
                .background(Semantic.card, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .stroke(Semantic.border, lineWidth: 1)
                )
                .shadow(color: shadowColor, radius: radius, x: x, y: y)
        }
    }

    public enum ChipTone { case brand, warm, soft, gold }

    public struct Chip: View {
        public let title: String
        public var systemImage: String? = nil
        public var tone: ChipTone = .brand

        private var fg: Color {
            switch tone {
            case .brand: return Semantic.brand
            case .warm:  return Semantic.accentWarm
            case .soft:  return Semantic.accentSoft.darken(0.35) // readable on tint
            case .gold:  return Semantic.accentGold.darken(0.45)
            }
        }
        private var bg: Color {
            switch tone {
            case .brand: return Semantic.brandSoft
            case .warm:  return Semantic.accentWarm.opacity(0.12)
            case .soft:  return Semantic.accentSoft.opacity(0.18)
            case .gold:  return Semantic.accentGold.opacity(0.16)
            }
        }
        private var stroke: Color { fg.opacity(0.35) }

        public var body: some View {
            HStack(spacing: 6) {
                if let s = systemImage { Image(systemName: s) }
                Text(title).font(.caption).bold()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
            .overlay(Capsule().stroke(stroke, lineWidth: 1))
        }
    }
}

// MARK: - View helpers
public extension View {
    func dsCard() -> some View { modifier(DS.Card()) }

    func dsSectionHeader(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(DS.FontType.subtitle).foregroundStyle(DS.Semantic.textPrimary)
            if let s = subtitle { Text(s).font(.footnote).foregroundStyle(DS.Semantic.textSecondary) }
        }
        .padding(.horizontal, DS.Space.l)
    }

    func dsInputField() -> some View {
        self
            .padding(12)
            .background(DS.Semantic.fillSubtle, in: RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.l).stroke(DS.Semantic.border, lineWidth: 1))
    }
}
