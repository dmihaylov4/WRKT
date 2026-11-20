//
//  CutPlannerComponents.swift
//  WRKT
//
//  Pieces shared by the Cut Programs screens and the new program flow.
//

import SwiftUI

/// The top row of a pushed Cut screen: a round back or close button with the title or progress beside it.
struct CutPlannerTopBar<Content: View>: View {
    enum Leading { case back, close }
    let leading: Leading
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 14) {
            Button(action: action) {
                Label(leading == .back ? "Back" : "Close", systemImage: leading == .back ? "chevron.left" : "xmark")
            }
            .buttonStyle(CutIconButtonStyle(tone: .fill, diameter: DS.Cut.Metrics.minTouchTarget))
            .accessibilityLabel(Text(leading == .back ? "Back" : "Close"))
            content()
        }
        .padding(.horizontal, DS.Cut.Metrics.panelInset)
        .padding(.top, 8)
        .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
    }
}

/// A big condensed capital title on one line when it fits, otherwise tight on balanced lines;
/// at accessibility sizes the title wraps freely so nothing is cut off.
struct CutPlannerTitle: View {
    let text: String
    var hero: DS.Cut.Typography.Hero = .s
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ text: String, hero: DS.Cut.Typography.Hero = .s) {
        self.text = text
        self.hero = hero
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize || text.count > 28 {
                Text(text)
                    .font(DS.Cut.Typography.hero(hero))
                    .textCase(.uppercase)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ViewThatFits(in: .horizontal) {
                    Text(text).cutHero(hero, lines: 1, minimumScaleFactor: 1).fixedSize()
                    CutHeroText(CutHeroText.balancedLines(text), hero: hero, minimumScaleFactor: 0.6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The "more" glyph used as a Menu label: round on a panel or on lime; on the background
/// (`open`) just the three dots, flush with the trailing edge of the same touch target.
struct CutPlannerMoreLabel: View {
    enum Tone { case panel, ink, open }
    var tone: Tone = .panel
    var diameter: CGFloat = DS.Cut.Metrics.minTouchTarget

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(tone == .ink ? DS.Cut.Colors.ink : DS.Cut.Colors.textPrimary)
            .frame(width: diameter, height: diameter, alignment: tone == .open ? .trailing : .center)
            .background(Circle().fill(tone == .panel ? DS.Cut.Colors.panelControl : Color.clear))
            .overlay { if tone == .ink { Circle().strokeBorder(DS.Cut.Colors.ink, lineWidth: 2) } }
            .contentShape(tone == .open ? AnyShape(Rectangle()) : AnyShape(Circle()))
    }
}

/// One segmented control of plain options; the chosen one is a white pill. Stacks at large sizes.
struct CutPlannerSegmented<Item: Hashable>: View {
    let items: [Item]
    let selected: Item?
    let title: (Item) -> String
    let select: (Item) -> Void
    var fill: Color = DS.Cut.SheetLevel.base.surface
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selected
                Button { select(item) } label: {
                    Text(title(item))
                        .font(DS.Typography.custom(size: 17, weight: isSelected ? .bold : .semibold, relativeTo: .body))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isSelected ? Color.black : DS.Cut.Colors.textPrimary)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: DS.Cut.Metrics.minTouchTarget)
                        .background(Capsule().fill(isSelected ? Color.white : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(fill))
    }
}

/// A filled, rounded text field on the background or a sheet.
struct CutPlannerField: View {
    let prompt: String
    @Binding var text: String
    var fill: Color = DS.Cut.Colors.panelControl
    var axis: Axis = .horizontal

    var body: some View {
        TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(DS.Cut.Colors.textSecondary), axis: axis)
            .font(DS.Typography.custom(size: 18, weight: .medium, relativeTo: .body))
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .lineLimit(axis == .vertical ? 1...4 : 1...1)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
    }
}

/// A plain label above a control ("Send to", "Run it for").
struct CutPlannerLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(DS.Typography.custom(size: 17, weight: .bold, relativeTo: .headline))
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The one supporting line under a title or a row.
struct CutPlannerLine: View {
    let text: String
    var color: Color = DS.Cut.Colors.textSecondary
    var size: CGFloat = 16
    init(_ text: String, color: Color = DS.Cut.Colors.textSecondary, size: CGFloat = 16) {
        self.text = text
        self.color = color
        self.size = size
    }
    var body: some View {
        Text(text)
            .font(DS.Typography.custom(size: size, weight: .medium, relativeTo: .subheadline))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A row title inside a panel.
struct CutPlannerRowTitle: View {
    let text: String
    var color: Color = DS.Cut.Colors.textPrimary
    init(_ text: String, color: Color = DS.Cut.Colors.textPrimary) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text)
            .font(DS.Typography.custom(size: 18, weight: .bold, relativeTo: .body))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
