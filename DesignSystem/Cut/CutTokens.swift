//
//  CutTokens.swift
//  WRKT
//
//  Cut design language: colours, type and metrics.
//  Near-black background, white text, one lime accent used as a shaped field.
//  Nothing outside DesignSystem/Cut reads these yet; screens adopt them behind
//  DS.Redesign.cutEnabled in later steps.
//

import SwiftUI
import UIKit

public extension DS {
    /// Namespace for the Cut design language.
    enum Cut {}
}

// MARK: - Colours

public extension DS.Cut {
    enum Colors {
        /// Screen background: pure black, the existing surface token.
        public static let background = DS.Semantic.surface
        /// The one accent: lime #CCFF00 (17.9:1 on black).
        public static let lime = DS.Palette.brand
        /// Primary text on the background (white in the app's dark scheme).
        public static let textPrimary = DS.Semantic.textPrimary
        /// Secondary text on the background (gray300 in dark, 14:1 on black).
        public static let textSecondary = DS.Semantic.textSecondary

        /// Ink on lime: #0B0D00 (16.6:1 on lime).
        public static let ink = Color(hex: "#0B0D00")
        /// Secondary ink on lime: ink at 74 percent (8:1 on lime).
        public static let inkSecondary = Color(hex: "#0B0D00", alpha: 0.74)
        /// Hairline and empty segment track on lime.
        public static let inkHairline = Color(hex: "#0B0D00", alpha: 0.2)

        /// 1 pt separator on the background: white at 15 percent.
        public static let hairline = Color.white.opacity(0.15)
        /// Outline of secondary pills and outlined icon buttons: white at 40 percent.
        public static let hairlineStrong = Color.white.opacity(0.4)
        /// Fill behind round icon buttons.
        public static let controlFill = Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255, opacity: 0.3)
        /// Empty slanted segment on the background.
        public static let segmentTrack = Color.white.opacity(0.22)
        /// Dimmed lime: the unfilled part of the V mark on the background.
        public static let limeTrack = Color(hex: "#2A2E12")
        /// Dark field: the lime field's rest-day variant.
        public static let darkField = Color(hex: "#161616")
    }
}

// MARK: - Metrics

public extension DS.Cut {
    enum Metrics {
        /// Side gutter for Cut screens.
        public static let gutter: CGFloat = 24
        /// Cut of the large lime field (the Train hero).
        public static let fieldCut: CGFloat = 112
        /// Cut of the action bar ("Log set").
        public static let actionBarCut: CGFloat = 72
        /// Corner cut of a tile, as a fraction of its shorter side.
        public static let tileCutFraction: CGFloat = 0.38
        /// Hairline thickness.
        public static let hairline: CGFloat = 1
        /// Minimum touch target.
        public static let minTouchTarget: CGFloat = 44
        /// Round icon button in tab headers.
        public static let headerIconButton: CGFloat = 48
    }
}

// MARK: - Type

public extension DS.Cut {
    /// Cut type styles. Heroes and numerals use Barlow Condensed, the rest Barlow Semi Condensed.
    /// Every style scales with Dynamic Type; nothing goes below 15 pt.
    enum Typography {
        public static let condensedBold = "BarlowCondensed-Bold"
        public static let condensedExtraBold = "BarlowCondensed-ExtraBold"

        /// Uppercase condensed hero sizes used by the mock.
        public enum Hero: CaseIterable {
            /// 132 pt: rest countdown, win screen "Done."
            case xxl
            /// 96 pt: Train field title
            case xl
            /// 72 pt: exercise name while logging
            case l
            /// 60 pt: tab header title
            case m
            /// 52 pt: action bar title
            case action
            /// 44 pt: big destination rows, empty states
            case s
            /// 34 pt: compact headings, alert titles
            case xs

            public var size: CGFloat {
                switch self {
                case .xxl: 132
                case .xl: 96
                case .l: 72
                case .m: 60
                case .action: 52
                case .s: 44
                case .xs: 34
                }
            }

            /// Letter spacing in points, from the mock.
            public var tracking: CGFloat {
                switch self {
                case .xxl: -2
                case .xl: -1
                case .l, .m, .action: -0.5
                case .s, .xs: 0
                }
            }

            /// CSS line-height factor from the mock; used to pull multi-line heroes together.
            public var lineHeight: CGFloat {
                switch self {
                case .xxl: 0.8
                case .xl: 0.84
                case .l: 0.86
                case .m: 0.88
                case .action, .s: 0.9
                case .xs: 0.95
                }
            }
        }

        /// Big condensed numerals with tabular digits.
        public enum Numeral: CaseIterable {
            /// 96 pt: set inputs, timers
            case hero
            /// 44 pt: battle score, rest countdown in rows
            case large
            /// 34 pt: stat columns, weekly goal
            case medium
            /// 22 pt: inline values
            case small

            public var size: CGFloat {
                switch self {
                case .hero: 96
                case .large: 44
                case .medium: 34
                case .small: 22
                }
            }
        }

        /// Text styles in Barlow Semi Condensed.
        public enum Style: CaseIterable {
            /// 17 pt semibold, sentence case: section, nav and sheet titles, row titles.
            case title
            /// 17 pt regular.
            case body
            /// 15 pt medium: the one supporting line, row values.
            case secondary
            /// 19 pt bold: pill button labels.
            case button
            /// 16 pt bold: compact pill labels.
            case buttonCompact

            var size: CGFloat {
                switch self {
                case .title, .body: 17
                case .secondary: 15
                case .button: 19
                case .buttonCompact: 16
                }
            }

            var weight: DS.Typography.Weight {
                switch self {
                case .title: .semibold
                case .body: .regular
                case .secondary: .medium
                case .button, .buttonCompact: .bold
                }
            }

            var textStyle: Font.TextStyle {
                switch self {
                case .title: .headline
                case .body: .body
                case .secondary: .subheadline
                case .button: .body
                case .buttonCompact: .callout
                }
            }
        }

        public enum CondensedWeight {
            case bold, extraBold

            public var fontName: String {
                switch self {
                case .bold: condensedBold
                case .extraBold: condensedExtraBold
                }
            }

            var fallback: Font.Weight {
                switch self {
                case .bold: .bold
                case .extraBold: .heavy
                }
            }
        }

        /// Barlow Condensed at a size, scaling relative to a text style.
        /// Falls back to a condensed-width system font if the face is not registered.
        public static func condensed(
            size: CGFloat,
            weight: CondensedWeight = .extraBold,
            relativeTo textStyle: Font.TextStyle = .largeTitle,
            monospacedDigits: Bool = false
        ) -> Font {
            let font: Font
            if UIFont(name: weight.fontName, size: size) != nil {
                font = .custom(weight.fontName, size: size, relativeTo: textStyle)
            } else {
                font = .system(size: size, weight: weight.fallback).width(.condensed)
            }
            return monospacedDigits ? font.monospacedDigit() : font
        }

        public static func hero(_ hero: Hero) -> Font {
            condensed(size: hero.size, relativeTo: .largeTitle)
        }

        public static func numeral(_ numeral: Numeral) -> Font {
            condensed(size: numeral.size, relativeTo: numeral == .small ? .title3 : .title, monospacedDigits: true)
        }

        public static func font(_ style: Style, monospacedDigits: Bool = false) -> Font {
            DS.Typography.custom(
                size: style.size,
                weight: style.weight,
                relativeTo: style.textStyle,
                monospacedDigits: monospacedDigits
            )
        }

        /// Natural line height of Barlow Condensed ExtraBold as a multiple of the point size.
        static let naturalLineHeight: CGFloat = {
            guard let font = UIFont(name: condensedExtraBold, size: 100) else { return 1.2 }
            return font.lineHeight / 100
        }()

        /// Spacing between stacked hero lines that reproduces the mock's tight CSS line height.
        /// Negative: SwiftUI ignores negative `lineSpacing`, so `CutHeroText` stacks lines instead.
        static func heroLineGap(_ hero: Hero, scaledSize: CGFloat) -> CGFloat {
            (hero.lineHeight - naturalLineHeight) * scaledSize
        }
    }
}

// MARK: - View helpers

public extension View {
    /// Cut text style (title, body, secondary, button labels).
    func cutFont(_ style: DS.Cut.Typography.Style, monospacedDigits: Bool = false) -> some View {
        font(DS.Cut.Typography.font(style, monospacedDigits: monospacedDigits))
    }

    /// Uppercase condensed hero for one line of text. Shrinks to fit instead of truncating.
    /// For a hero on several lines use `CutHeroText`, which keeps the lines tight.
    func cutHero(_ hero: DS.Cut.Typography.Hero, lines: Int = 1) -> some View {
        self
            .font(DS.Cut.Typography.hero(hero))
            .textCase(.uppercase)
            .tracking(hero.tracking)
            .lineLimit(lines)
            .minimumScaleFactor(0.4)
    }

    /// Big condensed numeral with tabular digits, on one line, shrinking to fit.
    func cutNumeral(_ numeral: DS.Cut.Typography.Numeral) -> some View {
        self
            .font(DS.Cut.Typography.numeral(numeral))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

// MARK: - Hero text

/// A multi-line hero ("Upper\nBody"): one line per newline, set as tight as the mock.
/// Each line shrinks to fit the width instead of truncating; VoiceOver reads it as one phrase.
public struct CutHeroText: View {
    private let text: String
    private let hero: DS.Cut.Typography.Hero

    @ScaledMetric(relativeTo: .largeTitle) private var scaledHundred: CGFloat = 100

    public init(_ text: String, hero: DS.Cut.Typography.Hero = .xl) {
        self.text = text
        self.hero = hero
    }

    /// The lines the hero is set on.
    public static func lines(of text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    public var body: some View {
        let scaledSize = hero.size * scaledHundred / 100
        VStack(alignment: .leading, spacing: DS.Cut.Typography.heroLineGap(hero, scaledSize: scaledSize)) {
            ForEach(Array(Self.lines(of: text).enumerated()), id: \.offset) { _, line in
                Text(line).cutHero(hero)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text.replacingOccurrences(of: "\n", with: " ")))
    }
}
