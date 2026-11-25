//
//  CutRackViewRail.swift
//  WRKT
//
//  The Cut rack ("Your bar") with the storage rail instead of the card tray. The back button,
//  title and Edit on one row; the live 3D bar takes every spare point of height, with the hint
//  over its top edge and a short readout ("+40 / 190 kg on the bar") that flashes there when the
//  load changes and fades; under it a steel floor rail with the plates standing on edge, one group
//  per look with its weight and count stamped on the rail, lime dashed slots for the copies on the
//  bar and white ones for copies on the floor, family sections divided by uprights; a slim footer
//  with the storage line, "Drop 16" or "Tidy up", and "All 90". A tapped group lifts out and shows
//  its face over the scene's lower edge with "Load onto the bar" and "Take off the bar". Plain
//  values and closures only: the plate pictures come from the host.
//

import SwiftUI

struct CutRackRailActions {
    var back: () -> Void
    var edit: () -> Void
    var showAll: () -> Void
    var play: () -> Void
    var tap: (String) -> Void
    var hold: (String) -> Void
    var load: (String) -> Void
    var unload: (String) -> Void
    var details: (String) -> Void
    var closeLift: () -> Void
}

struct CutRackRailScreen<SceneContent: View, Edge: View, Face: View>: View {
    let model: CutRackModel
    let rail: CutRackRailModel
    let lifted: CutRackRailPreviewModel?
    let tapMode: CutRackRailTap
    let actions: CutRackRailActions
    @ViewBuilder var scene: () -> SceneContent
    /// One plate of a group standing on edge.
    @ViewBuilder var edge: (CutRackRailModel.Group) -> Edge
    /// The lifted group's plate, face on.
    @ViewBuilder var face: (CutRackRailModel.Group) -> Face
    /// Runs while a group is on screen (the host prepares its next plate's faces).
    var groupShown: (CutRackRailModel.Group) async -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash: CutRackReadoutFlash?
    @State private var flashToken = 0

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Large text: the page scrolls, the scene keeps a fixed height and the lifted
                // plate gets its own place under it instead of covering it.
                ScrollView {
                    VStack(spacing: 0) {
                        top
                        sceneArea(height: 300)
                        if flash == nil, let hint = rail.hint {
                            hintText(hint).padding(.vertical, 10)
                        }
                        if lifted != nil { liftPanel.padding(.horizontal, 12).padding(.bottom, 12) }
                        railTray
                    }
                }
            } else {
                VStack(spacing: 0) {
                    top
                    sceneArea(height: nil)
                    railTray
                }
            }
        }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .onChange(of: model.totalKg) { old, new in showFlash(from: old, to: new) }
        .sensoryFeedback(.selection, trigger: lifted?.groupID) { _, new in new != nil }
    }

    // MARK: Header

    private var top: some View {
        VStack(alignment: .leading, spacing: 0) {
            CutPlannerTopBar(leading: .back, action: actions.back) {
                if dynamicTypeSize.isAccessibilitySize {
                    title.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 12) {
                        title.frame(maxWidth: .infinity, alignment: .leading)
                        editButton
                    }
                }
            }
            if dynamicTypeSize.isAccessibilitySize {
                editButton
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.top, 12)
            }
        }
    }

    /// The total is hidden at rest (the plates on the sleeves are the load); VoiceOver still
    /// reads it with the title.
    private var title: some View {
        Text(model.title)
            .font(DS.Cut.Typography.hero(.xs))
            .textCase(.uppercase)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(Text(model.headerAccessibilityLabel))
    }

    private var editButton: some View {
        Button("Edit", action: actions.edit)
            .buttonStyle(CutPillButtonStyle(.outline))
            .accessibilityHint(Text("Bar, collars and room."))
    }

    // MARK: Scene

    private func sceneArea(height: CGFloat?) -> some View {
        scene()
            .accessibilityValue(Text(model.sceneAccessibilityValue))
            .frame(maxWidth: .infinity, maxHeight: height == nil ? .infinity : nil)
            .frame(height: height)
            .clipped()
            .overlay { edgeFades.allowsHitTesting(false) }
            .overlay(alignment: .top) { topOverlay(showsHint: height == nil).allowsHitTesting(false) }
            .overlay(alignment: .bottom) {
                if height == nil, lifted != nil {
                    liftPanel
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.34, dampingFraction: 0.86), value: lifted?.groupID)
            .padding(.top, 2)
    }

    /// The hint, or the readout while it flashes. With large text the hint sits under the scene.
    @ViewBuilder
    private func topOverlay(showsHint: Bool) -> some View {
        ZStack(alignment: .top) {
            if let flash {
                flashView(flash)
                    .id(flashToken)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            } else if showsHint, let hint = rail.hint {
                hintText(hint)
                    .background(CutCornerShape(corner: .bottomTrailing, cut: .points(10)).fill(DS.Cut.Colors.background.opacity(0.82)))
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.2 : 0.28), value: flashToken)
        .animation(.easeOut(duration: 0.4), value: flash == nil)
    }

    private func hintText(_ hint: String) -> some View {
        Text(hint)
                    .font(DS.Typography.custom(size: 15, weight: .medium, relativeTo: .callout))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .accessibilityAddTraits(.updatesFrequently)
    }

    private func flashView(_ flash: CutRackReadoutFlash) -> some View {
        VStack(spacing: 0) {
            Text(flash.delta)
                .font(DS.Cut.Typography.condensed(size: 56, relativeTo: .largeTitle, monospacedDigits: true))
                .foregroundStyle(DS.Cut.Colors.lime)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(flash.total)
                    .font(DS.Cut.Typography.condensed(size: 30, relativeTo: .title, monospacedDigits: true))
                Text(flash.unit)
                    .font(DS.Typography.custom(size: 15, weight: .semibold, relativeTo: .callout))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, 18)
        .padding(.top, 2)
        .padding(.bottom, 10)
        .background(CutCornerShape(corner: .bottomTrailing, cut: .points(16)).fill(DS.Cut.Colors.background.opacity(0.82)))
        .padding(.top, 6)
        .accessibilityHidden(true)
    }

    private func showFlash(from old: Double, to new: Double) {
        guard let next = CutRackRailLogic.flash(fromKg: old, toKg: new, unit: model.unit) else { return }
        flash = next
        flashToken += 1
        let token = flashToken
        AccessibilityNotification.Announcement(next.accessibilityLabel).post()
        Task { @MainActor in
            try? await Task.sleep(for: CutRackRailLogic.flashDuration)
            if flashToken == token { flash = nil }
        }
    }

    private var edgeFades: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [DS.Cut.Colors.background, DS.Cut.Colors.background.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 24)
            Spacer(minLength: 0)
            LinearGradient(colors: [DS.Cut.Colors.background.opacity(0), DS.Cut.Colors.background],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 28)
        }
    }

    // MARK: Lifted plate

    @ViewBuilder
    private var liftPanel: some View {
        if let lifted, let group = rail.group(lifted.groupID) {
            CutRackRailLiftPanel(model: lifted, actions: actions, group: group) { face(group) }
                .id(lifted.groupID)
        }
    }

    // MARK: Rail

    private var railTray: some View {
        VStack(spacing: 0) {
            if let empty = rail.emptyRail {
                Text(empty)
                    .font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .callout))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.vertical, 16)
            } else {
                CutRackRail(model: rail, lifted: lifted?.groupID, tapMode: tapMode, actions: actions, groupShown: groupShown, edge: edge)
            }
            footer
        }
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                status.frame(maxWidth: .infinity, alignment: .leading)
                footerActions
            }
            VStack(alignment: .leading, spacing: 8) {
                status
                footerActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var status: some View {
        Text(rail.status)
            .font(DS.Cut.Typography.condensed(size: 19, weight: .bold, relativeTo: .callout))
            .textCase(.uppercase)
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footerActions: some View {
        HStack(spacing: 14) {
            if let play = model.playAction {
                Button(play.title, action: actions.play)
                    .buttonStyle(CutPillButtonStyle(play.isTidy ? .outlineLime : .outline))
                    .accessibilityLabel(Text(play.accessibilityLabel))
                    .accessibilityHint(Text(play.accessibilityHint))
            }
            if let all = model.allTitle {
                Button(all, action: actions.showAll)
                    .font(DS.Typography.custom(size: 17, weight: .bold, relativeTo: .body))
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(model.allAccessibilityLabel))
            }
        }
        .fixedSize()
    }
}

// MARK: - The rail

/// The steel floor rail with every group standing on it, scrolling sideways.
struct CutRackRail<Edge: View>: View {
    let model: CutRackRailModel
    let lifted: String?
    let tapMode: CutRackRailTap
    let actions: CutRackRailActions
    var groupShown: (CutRackRailModel.Group) async -> Void = { _ in }
    @ViewBuilder var edge: (CutRackRailModel.Group) -> Edge

    /// The rail's contents in order, flat so the stack can be lazy: only groups on screen draw
    /// their plates and start their work.
    private enum Item: Identifiable {
        case group(CutRackRailModel.Group, title: String?)
        case upright(String)

        var id: String {
            switch self {
            case .group(let group, _): return group.id
            case .upright(let section): return "upright-" + section
            }
        }
    }

    private var items: [Item] {
        var items: [Item] = []
        for (index, section) in model.sections.enumerated() {
            if index > 0 { items.append(.upright(section.id)) }
            for (position, group) in section.groups.enumerated() {
                items.append(.group(group, title: position == 0 ? section.title : nil))
            }
        }
        return items
    }

    @ScaledMetric(relativeTo: .title3) private var railHeight: CGFloat = 30
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A plate's drawn height (a 0.22 m bumper) and width, from the sprite's framing.
    static var plateHeight: CGFloat { 78 }
    static var plateWidth: CGFloat {
        plateHeight * RackRailSpriteService.EdgeFrame.size.width / RackRailSpriteService.EdgeFrame.size.height
    }
    /// The step between copies standing together: about a bumper's thickness at this scale.
    static var step: CGFloat { 8 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 0) {
                Text(model.unit)
                    .font(DS.Cut.Typography.condensed(size: 15, weight: .bold, relativeTo: .footnote))
                    .textCase(.uppercase)
                    .foregroundStyle(DS.Cut.Colors.textTertiary)
                    .frame(height: railHeight)
                    .padding(.leading, 16)
                    .padding(.trailing, 4)
                    .accessibilityHidden(true)
                LazyHStack(alignment: .bottom, spacing: 0) {
                    ForEach(items) { item in
                        switch item {
                        case .group(let group, let title):
                            groupView(group)
                                .padding(.top, 22)
                                .overlay(alignment: .topLeading) {
                                    if let title { sectionTitle(title) }
                                }
                        case .upright:
                            upright
                        }
                    }
                }
                Color.clear.frame(width: 16, height: railHeight)
            }
            .background(alignment: .bottom) { steel.frame(height: railHeight) }
            .padding(.top, 4)
        }
        // A horizontal scroll view takes every spare point of height; the rail keeps its own,
        // so the scene gets the rest.
        .fixedSize(horizontal: false, vertical: true)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// The rail: a lit top edge, brushed steel, a dark underside.
    private var steel: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DS.Cut.Colors.hairlineStrong).frame(height: 1)
            LinearGradient(colors: [DS.Cut.SheetLevel.nested.surface, DS.Cut.SheetLevel.base.surface],
                           startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color.black).frame(height: 1)
        }
    }

    /// The upright between two family sections, standing on the rail.
    private var upright: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(LinearGradient(colors: [DS.Cut.Colors.hairlineStrong, DS.Cut.SheetLevel.nested.control],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 4, height: Self.plateHeight * 0.62)
                .overlay(alignment: .top) { Rectangle().fill(DS.Cut.Colors.hairlineStrong).frame(height: 1) }
            Color.clear.frame(width: 4, height: railHeight)
        }
        .padding(.horizontal, 10)
        .accessibilityHidden(true)
    }

    /// The section's name, stamped small over its first group.
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DS.Typography.custom(size: 13, weight: .semibold, relativeTo: .footnote))
            .textCase(.uppercase)
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private func groupView(_ group: CutRackRailModel.Group) -> some View {
        let isLifted = lifted == group.id
        return VStack(spacing: 0) {
            stack(group, lifted: isLifted)
            stamp(group, lifted: isLifted)
                .frame(height: railHeight)
        }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .task(id: group.nextToLoad) { await groupShown(group) }
        .onTapGesture { actions.tap(group.id) }
        .onLongPressGesture(minimumDuration: 0.35) { actions.hold(group.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(group.accessibilityLabel))
        .accessibilityAddTraits(isLifted ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(Text(hint(group, lifted: isLifted)))
        .accessibilityAction { actions.tap(group.id) }
        .modifier(GroupActions(group: group, actions: actions))
    }

    private func hint(_ group: CutRackRailModel.Group, lifted: Bool) -> String {
        switch tapMode {
        case .preview:
            guard lifted else { return "Shows the plate's face." }
            return group.nextToLoad != nil ? "Loads one onto the bar." : "Puts the plate back."
        case .load:
            if group.nextToLoad != nil { return "Loads one onto the bar." }
            return group.nextToUnload != nil ? "Takes one off the bar." : "Shows the plate's face."
        }
    }

    /// The plates standing together, then a lime dashed slot for each copy on the bar and a white
    /// one for each on the floor, at the front of the stack where those plates stood.
    private func stack(_ group: CutRackRailModel.Group, lifted: Bool) -> some View {
        let count = group.platesShown + group.loadedSlots + group.floorSlots
        let width = Self.plateWidth + CGFloat(max(0, count - 1)) * Self.step
        return ZStack(alignment: .bottomLeading) {
            ForEach(0..<group.platesShown, id: \.self) { index in
                edge(group)
                    .frame(width: Self.plateWidth, height: Self.plateHeight)
                    .offset(x: CGFloat(index) * Self.step,
                            y: lifted && !reduceMotion && index == group.platesShown - 1 ? -10 : 0)
            }
            ForEach(0..<group.loadedSlots, id: \.self) { index in
                slot(lime: true)
                    .offset(x: slotX(group, index))
            }
            ForEach(0..<group.floorSlots, id: \.self) { index in
                slot(lime: false)
                    .offset(x: slotX(group, group.loadedSlots + index))
            }
        }
        .frame(width: width + (group.platesShown > 0 && count > group.platesShown ? Self.slotGap : 0),
               height: Self.plateHeight + 10, alignment: .bottomLeading)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.8), value: lifted)
        .animation(.easeOut(duration: 0.25), value: group.platesShown)
    }

    /// Empty slots stand a little clear of the front plate so their outline reads.
    static var slotGap: CGFloat { 6 }

    private func slotX(_ group: CutRackRailModel.Group, _ index: Int) -> CGFloat {
        CGFloat(group.platesShown + index) * Self.step + (group.platesShown > 0 ? Self.slotGap : 0)
    }

    /// An empty place on the rail: a plate's outline, seen as the plates stand.
    private func slot(lime: Bool) -> some View {
        Ellipse()
            .strokeBorder(lime ? DS.Cut.Colors.lime : DS.Cut.Colors.hairlineStrong,
                          style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            .frame(width: Self.plateWidth * 0.62, height: Self.plateHeight * 0.94)
            .padding(.leading, Self.plateWidth * 0.19)
            .padding(.bottom, Self.plateHeight * 0.02)
    }

    /// The weight and count stamped into the rail under the group.
    private func stamp(_ group: CutRackRailModel.Group, lifted: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(group.numeral)
                .font(DS.Cut.Typography.condensed(size: 21, weight: .extraBold, relativeTo: .title3, monospacedDigits: true))
                .foregroundStyle(lifted ? DS.Cut.Colors.lime : (group.stored > 0 ? DS.Cut.Colors.textPrimary : DS.Cut.Colors.lime))
            if let count = group.count {
                Text(count)
                    .font(DS.Cut.Typography.condensed(size: 15, weight: .bold, relativeTo: .footnote, monospacedDigits: true))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
        // Stamped: a dark lip under each stroke, as if pressed into the steel.
        .shadow(color: .black.opacity(0.8), radius: 0, x: 0, y: 1)
        .accessibilityHidden(true)
    }
}

/// Load and take-off as VoiceOver actions, plus showing the face.
private struct GroupActions: ViewModifier {
    let group: CutRackRailModel.Group
    let actions: CutRackRailActions

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if let id = group.nextToLoad {
                Button("Load one onto the bar") { actions.load(id) }
            }
            if let id = group.nextToUnload {
                Button("Take one off the bar") { actions.unload(id) }
            }
            Button("Show the plate") { actions.hold(group.id) }
        }
    }
}

// MARK: - Lifted plate

/// The plate lifted out of the rail: its face, large, turning toward the viewer, with its name,
/// engraving, weight and counts, and load or take-off. A compact chamfered panel over the scene's
/// lower edge, so the bar above stays in view.
struct CutRackRailLiftPanel<Face: View>: View {
    let model: CutRackRailPreviewModel
    let actions: CutRackRailActions
    let group: CutRackRailModel.Group
    @ViewBuilder var face: () -> Face

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turned = false

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    plate
                    facts
                    buttons
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 14) {
                        plate
                        facts
                    }
                    buttons
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CutCornerShape(corner: .topTrailing, cut: .points(20)).fill(DS.Cut.SheetLevel.base.surface))
        .overlay(CutCornerShape(corner: .topTrailing, cut: .points(20)).strokeBorder(DS.Cut.Colors.hairline, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            Button(action: actions.closeLift) {
                Label("Put back", systemImage: "xmark")
            }
            .buttonStyle(CutIconButtonStyle(tone: .fill, diameter: 32))
            .frame(width: DS.Cut.Metrics.minTouchTarget, height: DS.Cut.Metrics.minTouchTarget)
            .offset(x: -12, y: 4)
            .accessibilityLabel(Text("Put the plate back"))
        }
        .environment(\.cutSheetLevel, .base)
        .accessibilityElement(children: .contain)
        .onAppear { turned = true }
    }

    /// The face turns toward the viewer as it lifts out of the rail.
    private var plate: some View {
        face()
            .frame(width: 96, height: 96)
            .rotation3DEffect(.degrees(turned || reduceMotion ? 0 : 66), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(turned || reduceMotion ? 1 : 0.7, anchor: .bottom)
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: turned)
            .contentShape(Circle())
            .onTapGesture { actions.details(group.plateID) }
            .accessibilityHidden(true)
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.engraving ?? model.title)
                .font(DS.Cut.Typography.condensed(size: 24, relativeTo: .title2))
                .textCase(.uppercase)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 36)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.weight)
                    .font(DS.Cut.Typography.condensed(size: 28, relativeTo: .title, monospacedDigits: true))
                    .textCase(.uppercase)
                    .foregroundStyle(DS.Cut.Colors.lime)
                    .fixedSize()
                if model.engraving != nil {
                    Text(model.title)
                        .font(DS.Typography.custom(size: 15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            Text(model.counts)
                .font(DS.Typography.custom(size: 15, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.accessibilityLabel))
        .accessibilityAction(named: Text("Details")) { actions.details(group.plateID) }
    }

    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { loadButton; unloadButton; detailsButton }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { loadButton; unloadButton }
                detailsButton
            }
            VStack(alignment: .leading, spacing: 8) { loadButton; unloadButton; detailsButton }
        }
    }

    @ViewBuilder
    private var loadButton: some View {
        if let title = model.loadTitle {
            Button(title) { if let id = group.nextToLoad { actions.load(id) } }
                .buttonStyle(CutPillButtonStyle(.lime))
                .disabled(!model.canLoad)
        }
    }

    @ViewBuilder
    private var unloadButton: some View {
        if let title = model.unloadTitle {
            Button(title) { if let id = group.nextToUnload { actions.unload(id) } }
                .buttonStyle(CutPillButtonStyle(.outline))
        }
    }

    private var detailsButton: some View {
        Button("Details") { actions.details(group.plateID) }
            .font(DS.Typography.custom(size: 15, weight: .semibold, relativeTo: .subheadline))
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .accessibilityHint(Text("When and how it was earned."))
    }
}
