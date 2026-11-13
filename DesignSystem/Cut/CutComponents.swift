//
//  CutComponents.swift
//  WRKT
//
//  Cut building blocks. Content sits on the background, separated by space and
//  1 pt hairlines; lime appears only as a shaped field, a primary pill or a tile.
//

import SwiftUI

// MARK: - Surface environment

public extension DS.Cut {
    /// What a component sits on. Buttons, segments and the V mark switch to ink on lime.
    enum Surface: Sendable {
        case background, lime
    }
}

private struct CutSurfaceKey: EnvironmentKey {
    static let defaultValue: DS.Cut.Surface = .background
}

public extension EnvironmentValues {
    var cutSurface: DS.Cut.Surface {
        get { self[CutSurfaceKey.self] }
        set { self[CutSurfaceKey.self] = newValue }
    }
}

// MARK: - Hairline

/// 1 pt separator at 15 percent white (ink at 20 percent on lime).
public struct CutHairline: View {
    @Environment(\.cutSurface) private var surface

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(surface == .lime ? DS.Cut.Colors.inkHairline : DS.Cut.Colors.hairline)
            .frame(height: DS.Cut.Metrics.hairline)
            .accessibilityHidden(true)
    }
}

// MARK: - Field

/// The lime field: a full-bleed block of lime ending in a 45 degree cut.
/// Children default to ink and see `cutSurface == .lime`.
public struct CutField<Content: View>: View {
    public enum Tone: Sendable { case lime, dark }

    private let tone: Tone
    private let corner: DS.Cut.Corner
    private let cut: CGFloat
    private let padding: EdgeInsets
    private let content: Content

    public init(
        tone: Tone = .lime,
        corner: DS.Cut.Corner = .bottomTrailing,
        cut: CGFloat = DS.Cut.Metrics.fieldCut,
        padding: EdgeInsets = EdgeInsets(top: 24, leading: DS.Cut.Metrics.gutter, bottom: 58, trailing: DS.Cut.Metrics.gutter),
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.corner = corner
        self.cut = cut
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .foregroundStyle(tone == .lime ? DS.Cut.Colors.ink : DS.Cut.Colors.textPrimary)
        .environment(\.cutSurface, tone == .lime ? .lime : .background)
        .background(
            CutCornerShape(corner: corner, cut: .points(cut))
                .fill(tone == .lime ? DS.Cut.Colors.lime : DS.Cut.Colors.darkField)
        )
    }
}

// MARK: - Tile

/// Small square tile with one cut corner, usually holding an arrow or plus. Decorative.
public struct CutTile: View {
    public enum Tone: Sendable { case lime, ink }

    private let systemImage: String
    private let side: CGFloat
    private let tone: Tone

    public init(systemImage: String = "arrow.right", side: CGFloat = 60, tone: Tone = .lime) {
        self.systemImage = systemImage
        self.side = side
        self.tone = tone
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: side * 0.4, weight: .bold))
            .foregroundStyle(tone == .lime ? DS.Cut.Colors.ink : DS.Cut.Colors.lime)
            .frame(width: side, height: side)
            .background(CutCornerShape.tile.fill(tone == .lime ? DS.Cut.Colors.lime : DS.Cut.Colors.ink))
            .accessibilityHidden(true)
    }
}

// MARK: - V mark progress

/// The V mark carrying two values: the left arm fills with `left`, the right arm with `right`.
/// Fractions are clamped to 0...1. The caller supplies one combined VoiceOver label.
public struct VMarkProgress: View {
    public enum Tone: Sendable {
        /// Lime fill on a dimmed lime track, for the background.
        case standard
        /// Ink fill on a faint ink track, for a lime field.
        case ink
        /// Lime outline, no fill: empty states.
        case line
    }

    private let left: Double
    private let right: Double
    private let label: Text
    private let tone: Tone

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(left: Double, right: Double, tone: Tone = .standard, accessibilityLabel: Text) {
        self.left = DS.Cut.clampedFraction(left)
        self.right = DS.Cut.clampedFraction(right)
        self.tone = tone
        self.label = accessibilityLabel
    }

    public init(left: Double, right: Double, tone: Tone = .standard, accessibilityLabel: String) {
        self.init(left: left, right: right, tone: tone, accessibilityLabel: Text(accessibilityLabel))
    }

    /// Clamped values the view draws.
    public var fractions: (left: Double, right: Double) { (left, right) }

    private var trackColor: Color {
        switch tone {
        case .standard: DS.Cut.Colors.limeTrack
        case .ink: DS.Cut.Colors.ink.opacity(0.16)
        case .line: .clear
        }
    }

    private var fillColor: Color {
        tone == .ink ? DS.Cut.Colors.ink : DS.Cut.Colors.lime
    }

    public var body: some View {
        ZStack {
            VMarkShape().fill(trackColor)
            if tone == .line {
                VMarkShape().stroke(DS.Cut.Colors.lime, style: StrokeStyle(lineWidth: 2, lineJoin: .miter))
            }
            VMarkArmFillShape(arm: .left, fraction: left).fill(fillColor)
            VMarkArmFillShape(arm: .right, fraction: right).fill(fillColor)
        }
        // The outline's miter joins reach past the polygon; keep them inside the frame.
        .padding(tone == .line ? 2 : 0)
        .aspectRatio(VMarkShape.aspectRatio, contentMode: .fit)
        .animation(reduceMotion ? nil : .easeOut(duration: 1.1), value: left)
        .animation(reduceMotion ? nil : .easeOut(duration: 1.1), value: right)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

// MARK: - Hairline row

/// A row on the background: title, optional value, optional chevron, optional single secondary line.
/// Draws its own bottom hairline; put a `CutHairline` above the first row (or use `CutHairlineList`).
public struct CutHairlineRow: View {
    public enum ValueTone: Sendable { case secondary, lime }

    private let title: String
    private let value: String?
    private let valueTone: ValueTone
    private let subtitle: String?
    private let showsChevron: Bool

    public init(
        _ title: String,
        value: String? = nil,
        valueTone: ValueTone = .secondary,
        subtitle: String? = nil,
        showsChevron: Bool = false
    ) {
        self.title = title
        self.value = value
        self.valueTone = valueTone
        self.subtitle = subtitle
        self.showsChevron = showsChevron
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .cutFont(.title)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(DS.Cut.Typography.font(.secondary).weight(.semibold))
                        .foregroundStyle(valueTone == .lime ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 50)
            .padding(.vertical, 10)
            CutHairline()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Rows separated by hairlines, with a hairline above the first row.
public struct CutHairlineList<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            CutHairline()
            content
        }
    }
}

// MARK: - Buttons

/// Lime filled pill. On a lime field it becomes an ink pill with lime text.
public struct CutPrimaryButtonStyle: ButtonStyle {
    public enum Size: Sendable { case regular, compact }

    private let size: Size
    private let fillsWidth: Bool

    public init(size: Size = .regular, fillsWidth: Bool = true) {
        self.size = size
        self.fillsWidth = fillsWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        CutPill(configuration: configuration, size: size, fillsWidth: fillsWidth, filled: true)
    }
}

/// Outlined pill. On a lime field the outline and text are ink.
public struct CutSecondaryButtonStyle: ButtonStyle {
    private let size: CutPrimaryButtonStyle.Size
    private let fillsWidth: Bool

    public init(size: CutPrimaryButtonStyle.Size = .regular, fillsWidth: Bool = true) {
        self.size = size
        self.fillsWidth = fillsWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        CutPill(configuration: configuration, size: size, fillsWidth: fillsWidth, filled: false)
    }
}

private struct CutPill: View {
    let configuration: ButtonStyleConfiguration
    let size: CutPrimaryButtonStyle.Size
    let fillsWidth: Bool
    let filled: Bool

    @Environment(\.cutSurface) private var surface
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var height: CGFloat { size == .regular ? 56 : 44 }

    private var foreground: Color {
        switch (filled, surface) {
        case (true, .background): DS.Cut.Colors.ink
        case (true, .lime): DS.Cut.Colors.lime
        case (false, .background): DS.Cut.Colors.textPrimary
        case (false, .lime): DS.Cut.Colors.ink
        }
    }

    private var fill: Color {
        guard filled else { return .clear }
        return surface == .lime ? DS.Cut.Colors.ink : DS.Cut.Colors.lime
    }

    private var stroke: Color {
        guard !filled else { return .clear }
        return surface == .lime ? DS.Cut.Colors.ink : DS.Cut.Colors.hairlineStrong
    }

    var body: some View {
        configuration.label
            .font(DS.Cut.Typography.font(size == .regular ? .button : .buttonCompact)
                .weight(filled ? .bold : .semibold))
            .labelStyle(CutPillLabelStyle())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(foreground)
            .padding(.horizontal, size == .regular ? 24 : 18)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: height)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(stroke, lineWidth: surface == .lime ? 2 : 1.5))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Pill labels put the icon after the title, as in the mock ("Start workout ->").
private struct CutPillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.title
            configuration.icon
        }
    }
}

/// Round icon button. Default is 48 pt (tab headers); never below 44 pt.
public struct CutIconButtonStyle: ButtonStyle {
    public enum Tone: Sendable {
        /// Grey fill, white glyph.
        case fill
        /// Lime fill, ink glyph: the one primary action in a header.
        case lime
        /// Outline only. On a lime field the outline and glyph are ink.
        case outline
    }

    private let tone: Tone
    private let diameter: CGFloat

    public init(tone: Tone = .fill, diameter: CGFloat = DS.Cut.Metrics.headerIconButton) {
        self.tone = tone
        self.diameter = max(diameter, DS.Cut.Metrics.minTouchTarget)
    }

    public func makeBody(configuration: Configuration) -> some View {
        CutIconButton(configuration: configuration, tone: tone, diameter: diameter)
    }
}

private struct CutIconButton: View {
    let configuration: ButtonStyleConfiguration
    let tone: CutIconButtonStyle.Tone
    let diameter: CGFloat

    @Environment(\.cutSurface) private var surface
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var foreground: Color {
        switch tone {
        case .fill: DS.Cut.Colors.textPrimary
        case .lime: DS.Cut.Colors.ink
        case .outline: surface == .lime ? DS.Cut.Colors.ink : DS.Cut.Colors.textPrimary
        }
    }

    private var fill: Color {
        switch tone {
        case .fill: DS.Cut.Colors.controlFill
        case .lime: DS.Cut.Colors.lime
        case .outline: .clear
        }
    }

    var body: some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: diameter * 0.42, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(fill))
            .overlay {
                if tone == .outline {
                    Circle().strokeBorder(surface == .lime ? DS.Cut.Colors.ink : DS.Cut.Colors.hairlineStrong,
                                          lineWidth: surface == .lime ? 2 : 1.5)
                }
            }
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .brightness(configuration.isPressed ? 0.15 : 0)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == CutPrimaryButtonStyle {
    static var cutPrimary: CutPrimaryButtonStyle { CutPrimaryButtonStyle() }
}

public extension ButtonStyle where Self == CutSecondaryButtonStyle {
    static var cutSecondary: CutSecondaryButtonStyle { CutSecondaryButtonStyle() }
}

public extension ButtonStyle where Self == CutIconButtonStyle {
    static var cutIcon: CutIconButtonStyle { CutIconButtonStyle() }
}

// MARK: - Segment progress

/// A row of slanted segments: `filled` done, an optional `current` one, the rest empty.
public struct CutSegmentProgress: View {
    public enum SegmentState: Equatable, Sendable { case empty, filled, current }
    public enum Thickness: Sendable { case regular, thin }

    private let total: Int
    private let filled: Int
    private let current: Int?
    private let thickness: Thickness
    private let label: Text?

    @Environment(\.cutSurface) private var surface

    /// - Parameters:
    ///   - total: number of segments (negative counts as 0)
    ///   - filled: how many leading segments are done (clamped to 0...total)
    ///   - current: zero-based index of the segment in progress, ignored when out of range or already filled
    public init(total: Int, filled: Int, current: Int? = nil, thickness: Thickness = .regular, accessibilityLabel: Text? = nil) {
        self.total = max(0, total)
        self.filled = min(max(0, filled), max(0, total))
        self.current = current
        self.thickness = thickness
        self.label = accessibilityLabel
    }

    /// The state of every segment, in order.
    public static func states(total: Int, filled: Int, current: Int?) -> [SegmentState] {
        let count = max(0, total)
        let done = min(max(0, filled), count)
        return (0..<count).map { index in
            if index < done { return .filled }
            if index == current { return .current }
            return .empty
        }
    }

    public var states: [SegmentState] { Self.states(total: total, filled: filled, current: current) }

    private func color(_ state: SegmentState) -> Color {
        switch (state, surface) {
        case (.filled, .background): DS.Cut.Colors.lime
        case (.filled, .lime): DS.Cut.Colors.ink
        // White marks the current segment on the background; on lime white would vanish (1.2:1),
        // so the current segment is half-strength ink there.
        case (.current, .background): DS.Cut.Colors.textPrimary
        case (.current, .lime): DS.Cut.Colors.ink.opacity(0.5)
        case (.empty, .background): DS.Cut.Colors.segmentTrack
        case (.empty, .lime): DS.Cut.Colors.inkHairline
        }
    }

    public var body: some View {
        let height: CGFloat = thickness == .regular ? 10 : 6
        HStack(spacing: 8) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                SlantedSegmentShape()
                    .fill(color(state))
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? Text("Progress"))
        .accessibilityValue(Text("\(filled) of \(total)"))
    }
}

// MARK: - Action bar

/// The lime bar at the bottom of the set logging screen ("Log set").
/// Cut at the top leading corner; extends under the home indicator.
public struct CutActionBar: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String
    private let action: () -> Void

    public init(_ title: String, subtitle: String? = nil, systemImage: String = "checkmark", action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .cutHero(.action)
                    if let subtitle {
                        Text(subtitle)
                            .font(DS.Cut.Typography.font(.secondary).weight(.semibold))
                            .foregroundStyle(DS.Cut.Colors.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .bold))
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(DS.Cut.Colors.ink)
            .padding(.top, 34)
            .padding(.leading, 96)
            .padding(.trailing, DS.Cut.Metrics.gutter)
            .frame(maxWidth: .infinity, minHeight: 134, alignment: .topLeading)
            .contentShape(CutCornerShape.actionBar)
        }
        .buttonStyle(CutActionBarButtonStyle())
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(subtitle ?? ""))
    }
}

private struct CutActionBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                CutCornerShape.actionBar
                    .fill(DS.Cut.Colors.lime)
                    .ignoresSafeArea(edges: .bottom)
            )
            .brightness(configuration.isPressed ? 0.08 : 0)
    }
}

// MARK: - Tab header

/// Tab header: 60 pt condensed title on the left, round icon actions on the right, one row.
public struct CutTabHeader<Actions: View>: View {
    private let title: String
    private let actions: Actions

    public init(_ title: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.actions = actions()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .cutHero(.m)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                actions
            }
            .buttonStyle(.cutIcon)
            .fixedSize()
        }
        .frame(minHeight: DS.Cut.Metrics.headerIconButton)
    }
}

public extension CutTabHeader where Actions == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

// MARK: - Scroll edge

public extension View {
    /// Hides the system top scroll edge effect (iOS 26 and later), which would tint a lime field
    /// running under the status bar. No effect on earlier systems.
    @ViewBuilder
    func cutHidesTopScrollEdge() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}

// MARK: - Stat columns

/// One stat column: a big condensed value, an optional unit beside it, a plain label under it.
public struct CutStatColumn: Hashable, Sendable {
    public var value: String
    public var label: String
    /// A short unit set beside the value at the secondary size ("km", "kcal").
    public var unit: String?
    /// Lime value: a winning side or a record.
    public var isHighlighted: Bool

    public init(value: String, label: String, unit: String? = nil, isHighlighted: Bool = false) {
        self.value = value
        self.label = label
        self.unit = unit
        self.isHighlighted = isHighlighted
    }
}

/// Stat columns: big condensed values over a plain label, 1 pt hairlines between columns.
/// Every column takes an equal share of the width; labels stay on one line.
public struct CutStatColumns: View {
    private let columns: [CutStatColumn]

    public init(_ columns: [CutStatColumn]) {
        self.columns = columns
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                if index > 0 {
                    Rectangle().fill(DS.Cut.Colors.hairline).frame(width: DS.Cut.Metrics.hairline)
                }
                VStack(alignment: .leading, spacing: 2) {
                    // A full-size placeholder fixes the numeral's height, so a value that shrinks
                    // to fit keeps its baseline and every label in the row stays on one line.
                    Text(verbatim: "0")
                        .cutNumeral(.medium)
                        .hidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: Alignment(horizontal: .leading, vertical: .lastTextBaseline)) {
                            HStack(alignment: .lastTextBaseline, spacing: 4) {
                                Text(column.value)
                                    .cutNumeral(.medium)
                                    .foregroundStyle(column.isHighlighted ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                                if let unit = column.unit {
                                    Text(unit)
                                        .cutFont(.secondary)
                                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                                        .lineLimit(1)
                                        .fixedSize()
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    Text(column.label)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, index > 0 ? 14 : 0)
                .padding(.trailing, 8)
                .accessibilityElement(children: .combine)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Underline tabs

/// Underline tabs: equal titles over a hairline, the selected one marked by a slanted lime bar.
/// Sits on the background below a tab header, outside the scrolling content.
public struct CutUnderlineTabs<Item: Hashable>: View {
    private let items: [Item]
    private let selection: Item
    private let title: (Item) -> String
    private let badge: (Item) -> String?
    private let accessibilityLabel: (Item) -> String
    private let select: (Item) -> Void

    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ items: [Item],
        selection: Item,
        title: @escaping (Item) -> String,
        badge: @escaping (Item) -> String? = { _ in nil },
        accessibilityLabel: ((Item) -> String)? = nil,
        select: @escaping (Item) -> Void
    ) {
        self.items = items
        self.selection = selection
        self.title = title
        self.badge = badge
        self.accessibilityLabel = accessibilityLabel ?? title
        self.select = select
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(items, id: \.self) { item in
                    Button {
                        guard item != selection else { return }
                        Haptics.light()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { select(item) }
                    } label: {
                        VStack(spacing: 10) {
                            HStack(spacing: 6) {
                                Text(title(item))
                                    .cutFont(.title)
                                    .foregroundStyle(item == selection ? DS.Cut.Colors.textPrimary : DS.Cut.Colors.textSecondary)
                                if let badge = badge(item) {
                                    Text(badge)
                                        .font(DS.Cut.Typography.font(.secondary).weight(.bold))
                                        .foregroundStyle(DS.Cut.Colors.lime)
                                }
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            ZStack {
                                if item == selection {
                                    SlantedSegmentShape()
                                        .fill(DS.Cut.Colors.lime)
                                        .matchedGeometryEffect(id: "indicator", in: indicator)
                                }
                            }
                            .frame(height: 6)
                        }
                        .frame(maxWidth: .infinity, minHeight: DS.Cut.Metrics.minTouchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(accessibilityLabel(item)))
                    .accessibilityAddTraits(item == selection ? [.isSelected, .isHeader] : [])
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            CutHairline()
        }
    }
}

// MARK: - Big row

/// A destination row: a 44 pt condensed title, an optional trailing numeral or tile, and a bottom
/// hairline. The whole row is the button.
public struct CutBigRow<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing
    private let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.action = action
        self.trailing = trailing()
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(title)
                        .cutHero(.s)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    trailing
                }
                .frame(minHeight: 76)
                .padding(.vertical, 6)
                CutHairline()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

public extension CutBigRow where Trailing == EmptyView {
    init(_ title: String, action: @escaping () -> Void) {
        self.init(title, action: action) { EmptyView() }
    }
}

// MARK: - Split bar

/// One slanted bar split in two: the leading share in lime, the rest as the empty track.
/// Decorative; the caller states both values in text.
public struct CutSplitBar: View {
    private let fraction: Double

    public init(fraction: Double) {
        self.fraction = fraction
    }

    public var body: some View {
        GeometryReader { proxy in
            let clamped = DS.Cut.clampedFraction(fraction)
            let gap: CGFloat = 4
            let lead = max(0, (proxy.size.width - gap) * clamped)
            HStack(spacing: gap) {
                if lead > 0 {
                    SlantedSegmentShape().fill(DS.Cut.Colors.lime).frame(width: lead)
                }
                SlantedSegmentShape().fill(DS.Cut.Colors.segmentTrack)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

// MARK: - Section title

/// 17 pt semibold sentence-case section title.
public struct CutSectionTitle: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .cutFont(.title)
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
