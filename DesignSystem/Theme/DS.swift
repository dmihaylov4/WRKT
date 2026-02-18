//
//  DS.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 18.10.25.
//


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
import Combine
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
            let r = Double((n & 0xFF0000) >> 16) / 255.0
            let g = Double((n & 0x00FF00) >> 8)  / 255.0
            let b = Double(n & 0x0000FF) / 255.0
            // Use native SwiftUI Color with RGB color space to prevent adaptation
            // This ensures consistent vibrant colors across all app states
            self = Color(red: r, green: g, blue: b, opacity: alpha)
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
        // Main brand color
        public static let marone = Color(hex: "#CCFF00")

        // Accents (ONLY these + their shades)
        public static let brand   = marone // Using marone as primary brand color
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

    // MARK: - Colors (Feature-Specific)

    /// Status colors for feedback states (success, warning, error, info)
    public enum Status {
        /// Success state color (e.g., workout completed, goal achieved)
        public static let success     = Color(hex: "#22C55E") // green-500
        /// Success background tint
        public static let successBg   = success.opacity(0.12)

        /// Warning state color (e.g., approaching limit, attention needed)
        public static let warning     = Color(hex: "#F59E0B") // amber-500
        /// Warning background tint
        public static let warningBg   = warning.opacity(0.12)

        /// Error state color (e.g., failed validation, broken streak)
        public static let error       = Color(hex: "#EF4444") // red-500
        /// Error background tint
        public static let errorBg     = error.opacity(0.12)

        /// Info state color (e.g., tips, notifications)
        public static let info        = Color(hex: "#3B82F6") // blue-500
        /// Info background tint
        public static let infoBg      = info.opacity(0.12)
    }

    /// State colors for UI element states (active, inactive, disabled, selected)
    public enum State {
        /// Active/selected state (uses brand yellow)
        public static let active      = Palette.marone // #F4E409
        /// Inactive state
        public static let inactive    = Color.gray
        /// Disabled state (reduced opacity)
        public static let disabled    = Color.gray.opacity(0.4)
        /// Selected state (same as active)
        public static let selected    = Palette.marone
        /// Hover/pressed state background
        public static let hover       = Palette.marone.opacity(0.1)
    }

    /// Chart and data visualization colors
    public enum Charts {
        // Training split colors
        /// Push exercises (chest, shoulders, triceps)
        public static let push        = Color(hex: "#8B5CF6") // purple
        /// Pull exercises (back, biceps)
        public static let pull        = Color(hex: "#F97316") // orange
        /// Leg exercises
        public static let legs        = Color(hex: "#3B82F6") // blue
        /// Core exercises
        public static let core        = Color(hex: "#22C55E") // green

        // Trend indicators
        /// Positive trend (increasing, improving)
        public static let positive    = Color(hex: "#22C55E").opacity(0.7) // green
        /// Negative trend (decreasing, declining)
        public static let negative    = Color(hex: "#EF4444").opacity(0.7) // red
        /// Neutral trend (stable, no change)
        public static let neutral     = Color.gray.opacity(0.7)

        // Gradients for visualizations
        /// Primary gradient (purple to blue)
        public static let gradient1   = [Color(hex: "#8B5CF6"), Color(hex: "#3B82F6")]
        /// Secondary gradient (orange to yellow)
        public static let gradient2   = [Color(hex: "#F97316"), Color(hex: "#F4E409")]
    }

    /// Calendar-specific colors for workout tracking
    public enum Calendar {
        /// Workout completion indicator (yellow dot)
        public static let workout     = Palette.marone // #F4E409
        /// Cardio activity indicator (white dot)
        public static let cardio      = Color.white
        /// Planned workout (dimmed yellow)
        public static let planned     = Palette.marone.opacity(0.5)
        /// Streak border/highlight
        public static let streak      = Palette.marone
        /// Today indicator
        public static let today       = Palette.marone

        // Planner workout states
        /// Completed planned workout
        public static let completed   = Color(hex: "#22C55E") // green
        /// Partially completed workout
        public static let partial     = Color(hex: "#F4E409") // yellow
        /// Skipped workout
        public static let skipped     = Color.gray
        /// Rescheduled workout
        public static let rescheduled = Color(hex: "#F97316") // orange
    }

    /// Exercise session and workout colors
    public enum Exercise {
        /// Current exercise indicator
        public static let current     = Palette.marone // #F4E409
        /// Up next exercise
        public static let upNext      = Color(hex: "#3B82F6") // blue
        /// Finished exercise
        public static let finished    = Color(hex: "#22C55E") // green
        /// Rest period indicator
        public static let rest        = Color(hex: "#F97316") // orange

        // Set types
        /// Warmup set
        public static let warmup      = Color(hex: "#3B82F6").opacity(0.6) // blue tint
        /// Working set (main set)
        public static let working     = Palette.marone // #F4E409
        /// Backoff/drop set
        public static let backoff     = Color(hex: "#F97316").opacity(0.6) // orange tint
    }

    /// Dark mode specific theme colors
    public enum Theme {
        /// Card gradient top (darkest)
        public static let cardTop     = Color(hex: "#121212")
        /// Card gradient bottom (lighter)
        public static let cardBottom  = Color(hex: "#333333")
        /// Progress track background
        public static let track       = Color(hex: "#151515")
        /// Overlay backdrop
        public static let overlay     = Color.black.opacity(0.85)
        /// Accent color for dark theme (use for small elements: icons, borders, badges)
        public static let accent      = Palette.marone
        /// Subtle accent for large surfaces (cards, backgrounds) - very desaturated
        public static let accentSurface = Palette.marone.opacity(0.75)
    }

    // MARK: - Convenience Aliases (for backward compatibility)

    /// Primary tint color (alias for Theme.accent)
    public static let tint = Theme.accent

    /// Card background color (alias for Semantic.card)
    public static let card = Semantic.card

    // MARK: Spacing / Radii / Elevation
    public enum Space { public static let xs: CGFloat = 4; public static let s: CGFloat = 8; public static let m: CGFloat = 12; public static let l: CGFloat = 16; public static let xl: CGFloat = 24; public static let xxl: CGFloat = 32 }
    public enum Radius { public static let s: CGFloat = 8; public static let m: CGFloat = 12; public static let l: CGFloat = 16; public static let xl: CGFloat = 24; public static let pill: CGFloat = 999 }

    // MARK: Chamfer Sizes (for consistent angled corner cuts)
    /// Standardized chamfer sizes to maintain consistent 45° diagonal cuts across the app.
    /// Use these tokens instead of hardcoded values to ensure visual consistency.
    /// The chamfer ratio should stay between 5-15% of container size for optimal appearance.
    public enum Chamfer {
        /// 4pt - For micro elements (12-24pt): badges, tiny indicators, status dots
        case micro
        /// 8pt - For small elements (24-60pt): avatars, chips, small buttons, calendar cells
        case small
        /// 12pt - For medium elements (60-120pt): list rows, compact cards, input fields
        case medium
        /// 16pt - For large elements (120-280pt): standard cards, sections, primary containers
        case large
        /// 20pt - For extra large elements (280-400pt): profile cards, stat sections, hero areas
        case xl
        /// 24pt - For hero elements (400pt+): full-width banners, splash elements
        case hero

        public var size: CGFloat {
            switch self {
            case .micro: return 4
            case .small: return 8
            case .medium: return 12
            case .large: return 16
            case .xl: return 20
            case .hero: return 24
            }
        }

        /// Returns the recommended chamfer size based on container dimensions.
        /// Aims for approximately 8-10% ratio for balanced visual appearance.
        public static func recommended(for containerSize: CGFloat) -> Chamfer {
            switch containerSize {
            case ..<24: return .micro
            case 24..<60: return .small
            case 60..<120: return .medium
            case 120..<280: return .large
            case 280..<400: return .xl
            default: return .hero
            }
        }
    }

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

// MARK: - Chamfered Rectangle Shape (Hexagonal-style corners)

/// A rectangle with chamfered (angled) corners on top-right and bottom-left,
/// and square corners on top-left and bottom-right - matching the hexagonal user icon theme.
public struct ChamferedRectangle: Shape {
    /// Size of the diagonal chamfer cut
    public var chamferSize: CGFloat

    /// Initialize with a design token (recommended)
    public init(_ chamfer: DS.Chamfer = .large) {
        self.chamferSize = chamfer.size
    }

    /// Initialize with explicit size (for edge cases)
    public init(chamferSize: CGFloat) {
        self.chamferSize = chamferSize
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        // Start at top-left (square corner)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top edge to chamfer start
        path.addLine(to: CGPoint(x: rect.maxX - chamferSize, y: rect.minY))

        // Top-right chamfer (diagonal cut)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + chamferSize))

        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        // Bottom-right (square corner)
        // Already at bottom-right from previous line

        // Bottom edge to chamfer start
        path.addLine(to: CGPoint(x: rect.minX + chamferSize, y: rect.maxY))

        // Bottom-left chamfer (diagonal cut)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - chamferSize))

        // Left edge back to start
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        path.closeSubpath()

        return path
    }
}

/// Alternate chamfered rectangle with chamfers on top-left and bottom-right,
/// and square corners on top-right and bottom-left - opposite of ChamferedRectangle.
public struct ChamferedRectangleAlt: Shape {
    /// Size of the diagonal chamfer cut
    public var chamferSize: CGFloat

    /// Initialize with a design token (recommended)
    public init(_ chamfer: DS.Chamfer = .large) {
        self.chamferSize = chamfer.size
    }

    /// Initialize with explicit size (for edge cases)
    public init(chamferSize: CGFloat) {
        self.chamferSize = chamferSize
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        // Start at top-left chamfer start point
        path.move(to: CGPoint(x: rect.minX + chamferSize, y: rect.minY))

        // Top edge (top-right is square)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        // Right edge to chamfer start
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - chamferSize))

        // Bottom-right chamfer (diagonal cut)
        path.addLine(to: CGPoint(x: rect.maxX - chamferSize, y: rect.maxY))

        // Bottom edge (bottom-left is square)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))

        // Left edge to chamfer start
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + chamferSize))

        // Top-left chamfer (diagonal cut)
        path.addLine(to: CGPoint(x: rect.minX + chamferSize, y: rect.minY))

        path.closeSubpath()

        return path
    }
}

/// Rectangle with only the top-left corner chamfered, and all other corners rounded.
/// Useful for small cells like calendar day cells where full chamfering would be too much.
public struct TopLeftChamferedRectangle: Shape {
    public var chamferSize: CGFloat
    public var cornerRadius: CGFloat

    /// Initialize with a design token (recommended)
    public init(_ chamfer: DS.Chamfer = .small, cornerRadius: CGFloat = 10) {
        self.chamferSize = chamfer.size
        self.cornerRadius = cornerRadius
    }

    /// Initialize with explicit size (for edge cases)
    public init(chamferSize: CGFloat, cornerRadius: CGFloat = 10) {
        self.chamferSize = chamferSize
        self.cornerRadius = cornerRadius
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        // Start after top-left chamfer
        path.move(to: CGPoint(x: rect.minX + chamferSize, y: rect.minY))

        // Top edge to top-right rounded corner
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )

        // Right edge to bottom-right rounded corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )

        // Bottom edge to bottom-left rounded corner
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )

        // Left edge to top-left chamfer
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + chamferSize))

        // Top-left chamfer (diagonal cut)
        path.addLine(to: CGPoint(x: rect.minX + chamferSize, y: rect.minY))

        path.closeSubpath()

        return path
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
