//
//  HomeWidgetViews.swift
//  WRKT
//
//  The three home screen widgets' views in the Cut language. Compiled into the app and the
//  widget extension (the app's tests render them to images). The extension cannot see
//  DesignSystem/Cut, and sharing it would drag in DS, its palette and the app's font helpers,
//  so this file carries small copies: the four colours, the two Barlow faces and the V mark and
//  cut corner geometry from CutShapes.swift.
//

import SwiftUI
import UIKit
import WidgetKit

// MARK: - Tokens (copies of DS.Cut values)

nonisolated enum HomeWidgetStyle {
    /// #CCFF00
    static let lime = Color(red: 204 / 255, green: 1, blue: 0)
    /// #0B0D00, ink on lime.
    static let ink = Color(red: 11 / 255, green: 13 / 255, blue: 0)
    /// #2A2E12, the unfilled part of the V mark on black.
    static let limeTrack = Color(red: 42 / 255, green: 46 / 255, blue: 18 / 255)
    /// #161616, the field's rest-day tone.
    static let darkField = Color(red: 22 / 255, green: 22 / 255, blue: 22 / 255)
    /// #C7C7CC, secondary text on black.
    static let textSecondary = Color(red: 199 / 255, green: 199 / 255, blue: 204 / 255)

    static let padding: CGFloat = 16
    /// Cut of the medium widget's lime field.
    static let fieldCut: CGFloat = 48
    /// Hero line height from the mock (CSS 0.88).
    static let heroLineHeight: CGFloat = 0.88

    static let condensedExtraBold = "BarlowCondensed-ExtraBold"
    static let textMedium = "BarlowSemiCondensed-Medium"
    static let textSemiBold = "BarlowSemiCondensed-SemiBold"

    /// Barlow Condensed ExtraBold, or a condensed heavy system font when it is not registered.
    static func condensed(_ size: CGFloat) -> Font {
        if UIFont(name: condensedExtraBold, size: size) != nil {
            return .custom(condensedExtraBold, size: size, relativeTo: .title)
        }
        return .system(size: size, weight: .heavy).width(.condensed)
    }

    /// Barlow Semi Condensed, or a condensed system font.
    static func text(_ size: CGFloat, semibold: Bool = false) -> Font {
        let name = semibold ? textSemiBold : textMedium
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size, relativeTo: .subheadline)
        }
        return .system(size: size, weight: semibold ? .semibold : .medium).width(.condensed)
    }

    /// Gap between stacked hero lines that reproduces the mock's tight line height.
    static func heroLineGap(size: CGFloat) -> CGFloat {
        let natural = UIFont(name: condensedExtraBold, size: 100).map { $0.lineHeight / 100 } ?? 1.2
        return (heroLineHeight - natural) * size
    }
}

/// Colours for the current rendering mode. Full colour is the design; in the accented and
/// vibrant modes the system tints the content, so fields become faint fills and the progress
/// and arrow are marked accentable.
nonisolated struct HomeWidgetPalette {
    let fullColor: Bool

    init(_ mode: WidgetRenderingMode) {
        fullColor = mode == .fullColor
    }

    func fieldFill(lime: Bool) -> Color {
        guard fullColor else { return Color.white.opacity(0.16) }
        return lime ? HomeWidgetStyle.lime : HomeWidgetStyle.darkField
    }

    func fieldText(lime: Bool) -> Color {
        fullColor && lime ? HomeWidgetStyle.ink : .white
    }

    var markTrack: Color { fullColor ? HomeWidgetStyle.limeTrack : Color.white.opacity(0.25) }
    var markFill: Color { fullColor ? HomeWidgetStyle.lime : .white }
    var secondary: Color { fullColor ? HomeWidgetStyle.textSecondary : Color.white.opacity(0.7) }
}

// MARK: - Shapes (copies of CutShapes geometry)

/// The V mark from the logo polygons (VMarkShape), fitted into the rect keeping proportions.
nonisolated struct HomeWidgetVMarkShape: Shape {
    enum Arm { case left, right }

    static let viewBox = CGRect(x: 132, y: 285, width: 758, height: 457)
    static let aspectRatio: CGFloat = viewBox.width / viewBox.height
    static let leftArm: [CGPoint] = [
        CGPoint(x: 132, y: 290), CGPoint(x: 290, y: 290), CGPoint(x: 582, y: 582),
        CGPoint(x: 582, y: 742), CGPoint(x: 438, y: 742), CGPoint(x: 132, y: 438)
    ]
    static let rightArm: [CGPoint] = [
        CGPoint(x: 735, y: 285), CGPoint(x: 890, y: 285), CGPoint(x: 890, y: 437),
        CGPoint(x: 735, y: 592), CGPoint(x: 582, y: 592), CGPoint(x: 582, y: 437)
    ]

    var arm: Arm
    /// Filled from the bottom up to this fraction of the arm's height; 1 is the whole arm.
    var fraction: Double = 1

    func path(in rect: CGRect) -> Path {
        let f = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        guard f > 0, rect.width > 0, rect.height > 0 else { return Path() }
        let points = arm == .left ? Self.leftArm : Self.rightArm
        let transform = Self.transform(for: rect)
        var armPath = Path()
        armPath.addLines(points)
        armPath.closeSubpath()
        armPath = armPath.applying(transform)
        guard f < 1 else { return armPath }
        let ys = points.map(\.y), xs = points.map(\.x)
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let fillHeight = (maxY - minY) * f
        let clip = Path(CGRect(x: minX, y: maxY - fillHeight, width: maxX - minX, height: fillHeight))
            .applying(transform)
        return armPath.intersection(clip)
    }

    static func transform(for rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let dx = rect.minX + (rect.width - viewBox.width * scale) / 2
        let dy = rect.minY + (rect.height - viewBox.height * scale) / 2
        return CGAffineTransform(translationX: dx, y: dy)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -viewBox.minX, y: -viewBox.minY)
    }
}

/// A rectangle with its bottom trailing corner cut at 45 degrees (CutCornerShape).
nonisolated struct HomeWidgetCutCornerShape: Shape {
    var cut: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = min(max(0, cut), rect.width, rect.height)
        var path = Path()
        path.addLines([
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY - c), CGPoint(x: rect.maxX - c, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ])
        path.closeSubpath()
        return path
    }
}

/// The 34 pt tile with a cut corner (the mock's polygon 0,0 34,0 34,21 21,34 0,34) and an arrow.
nonisolated struct HomeWidgetArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 34
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 9 * s, y: rect.minY + 16 * s))
        path.addLine(to: CGPoint(x: rect.minX + 22 * s, y: rect.minY + 16 * s))
        path.move(to: CGPoint(x: rect.minX + 17 * s, y: rect.minY + 11 * s))
        path.addLine(to: CGPoint(x: rect.minX + 22 * s, y: rect.minY + 16 * s))
        path.addLine(to: CGPoint(x: rect.minX + 17 * s, y: rect.minY + 21 * s))
        return path
    }
}

// MARK: - Pieces

/// The V mark as weekly progress: left arm strength, right arm cardio.
struct HomeWidgetVMarkProgress: View {
    let strength: Double
    let cardio: Double
    let palette: HomeWidgetPalette

    var body: some View {
        ZStack {
            HomeWidgetVMarkShape(arm: .left).fill(palette.markTrack)
            HomeWidgetVMarkShape(arm: .right).fill(palette.markTrack)
            Group {
                HomeWidgetVMarkShape(arm: .left, fraction: strength).fill(palette.markFill)
                HomeWidgetVMarkShape(arm: .right, fraction: cardio).fill(palette.markFill)
            }
            .widgetAccentable()
        }
        .aspectRatio(HomeWidgetVMarkShape.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A condensed numeral with its label on one baseline ("2/3 strength").
struct HomeWidgetStatLine: View {
    let value: String
    let label: String
    let size: CGFloat
    let palette: HomeWidgetPalette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(HomeWidgetStyle.condensed(size))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(label)
                .font(HomeWidgetStyle.text(15))
                .foregroundStyle(palette.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// The uppercase two-line hero ("UPPER / BODY"), set tight. Both lines step down to one
/// common size that fits the width, so the tight line gap stays right for that size (lines
/// that shrank on their own would overlap).
struct HomeWidgetHero: View {
    let text: String
    let size: CGFloat

    private static let steps: [CGFloat] = [1, 0.85, 0.72, 0.62, 0.54]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Self.steps, id: \.self) { step in
                lines(size: size * step, truncates: false)
            }
            // Nothing fits: the smallest size, both lines truncated at the same size.
            lines(size: size * (Self.steps.last ?? 1), truncates: true)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func lines(size: CGFloat, truncates: Bool) -> some View {
        VStack(alignment: .leading, spacing: HomeWidgetStyle.heroLineGap(size: size)) {
            ForEach(Array(HomeWidgetLogic.heroLines(text).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(HomeWidgetStyle.condensed(size))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: !truncates, vertical: false)
            }
        }
    }
}

struct HomeWidgetArrowTile: View {
    let onLime: Bool
    let palette: HomeWidgetPalette

    var body: some View {
        let tile = palette.fullColor ? (onLime ? HomeWidgetStyle.ink : HomeWidgetStyle.lime) : Color.white
        let arrow = palette.fullColor ? (onLime ? HomeWidgetStyle.lime : HomeWidgetStyle.ink) : Color.black
        ZStack {
            HomeWidgetCutCornerShape(cut: 13).fill(tile)
            HomeWidgetArrowShape()
                .stroke(arrow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 34, height: 34)
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}

/// Today's line and hero, in the field's text colour.
struct HomeWidgetTodayText: View {
    let today: HomeWidgetContent.Today
    let now: Date
    let heroSize: CGFloat
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(HomeWidgetLogic.todayLine(today, now: now))
                .font(HomeWidgetStyle.text(15, semibold: true))
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            HomeWidgetHero(text: HomeWidgetLogic.todayTitle(today), size: heroSize)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Widgets

/// Small: weekly goal on black.
struct WeeklyGoalWidgetView: View {
    let content: HomeWidgetContent
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let palette = HomeWidgetPalette(renderingMode)
        let week = content.week
        VStack(alignment: .leading, spacing: 0) {
            HomeWidgetVMarkProgress(
                strength: week.map { HomeWidgetLogic.fraction($0.strengthDone, of: $0.strengthTarget) } ?? 0,
                cardio: week.map { HomeWidgetLogic.fraction($0.cardioMinutes, of: $0.cardioTarget) } ?? 0,
                palette: palette
            )
            .frame(width: 90, height: 72, alignment: .topLeading)
            Spacer(minLength: 4)
            if let week {
                VStack(alignment: .leading, spacing: 2) {
                    HomeWidgetStatLine(value: "\(week.strengthDone)/\(week.strengthTarget)", label: "strength",
                                       size: 24, palette: palette)
                    HomeWidgetStatLine(value: "\(week.cardioMinutes)/\(week.cardioTarget)", label: "min",
                                       size: 24, palette: palette)
                }
            } else {
                Text("Set a weekly goal in VOLIA")
                    .font(HomeWidgetStyle.text(15, semibold: true))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(HomeWidgetStyle.padding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeWidgetLogic.weeklyGoalSentence(week))
        .containerBackground(for: .widget) { Color.black }
        .widgetURL(HomeWidgetShared.trainURL)
    }
}

/// Small: today's session on a lime field (dark on rest and done days).
struct TodayWidgetView: View {
    let content: HomeWidgetContent
    let now: Date
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let palette = HomeWidgetPalette(renderingMode)
        let lime = HomeWidgetLogic.fieldIsLime(content.today)
        let text = palette.fieldText(lime: lime)
        VStack(alignment: .leading, spacing: 0) {
            Text(HomeWidgetLogic.todayLine(content.today, now: now))
                .font(HomeWidgetStyle.text(15, semibold: true))
                .foregroundStyle(text)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            HStack(alignment: .bottom, spacing: 4) {
                HomeWidgetHero(text: HomeWidgetLogic.todayTitle(content.today), size: 40)
                    .foregroundStyle(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HomeWidgetArrowTile(onLime: lime, palette: palette)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(HomeWidgetStyle.padding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeWidgetLogic.todaySentence(content.today, now: now))
        .containerBackground(for: .widget) { palette.fullColor ? palette.fieldFill(lime: lime) : Color.black }
        .widgetURL(HomeWidgetShared.trainURL)
    }
}

/// Medium: the Today field on the left with a cut corner, the weekly goal on the right.
struct TodayAndWeekWidgetView: View {
    let content: HomeWidgetContent
    let now: Date
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let palette = HomeWidgetPalette(renderingMode)
        let lime = HomeWidgetLogic.fieldIsLime(content.today)
        GeometryReader { proxy in
            HStack(spacing: 0) {
                HomeWidgetTodayText(today: content.today, now: now, heroSize: 40,
                                    color: palette.fieldText(lime: lime))
                    .padding(HomeWidgetStyle.padding)
                    // Keeps the hero's last line clear of the cut corner.
                    .padding(.trailing, 16)
                    .frame(width: proxy.size.width * 0.52)
                    .frame(maxHeight: .infinity)
                    .background {
                        HomeWidgetCutCornerShape(cut: HomeWidgetStyle.fieldCut)
                            .fill(palette.fieldFill(lime: lime))
                            .widgetAccentable(!palette.fullColor)
                    }
                weekColumn(palette)
                    .padding(HomeWidgetStyle.padding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeWidgetLogic.todayAndWeekSentence(content, now: now))
        .containerBackground(for: .widget) { Color.black }
        .widgetURL(HomeWidgetShared.trainURL)
    }

    @ViewBuilder
    private func weekColumn(_ palette: HomeWidgetPalette) -> some View {
        let week = content.week
        VStack(alignment: .leading, spacing: 0) {
            HomeWidgetVMarkProgress(
                strength: week.map { HomeWidgetLogic.fraction($0.strengthDone, of: $0.strengthTarget) } ?? 0,
                cardio: week.map { HomeWidgetLogic.fraction($0.cardioMinutes, of: $0.cardioTarget) } ?? 0,
                palette: palette
            )
            .frame(width: 70, height: 56, alignment: .topLeading)
            Spacer(minLength: 4)
            if let week {
                VStack(alignment: .leading, spacing: 2) {
                    HomeWidgetStatLine(value: "\(week.strengthDone)/\(week.strengthTarget)", label: "strength",
                                       size: 22, palette: palette)
                    if let streak = week.streakWeeks, streak > 0 {
                        HomeWidgetStatLine(value: HomeWidgetLogic.weeks(streak), label: "streak",
                                           size: 22, palette: palette)
                    } else {
                        HomeWidgetStatLine(value: "\(week.cardioMinutes)/\(week.cardioTarget)", label: "min",
                                           size: 22, palette: palette)
                    }
                }
            } else {
                Text("Set a weekly goal")
                    .font(HomeWidgetStyle.text(15, semibold: true))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
        }
    }
}
