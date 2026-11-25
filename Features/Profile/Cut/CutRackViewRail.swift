//
//  CutRackViewRail.swift
//  WRKT
//
//  The Cut rack ("Your bar") with the plates standing in the room instead of the card tray. The
//  back button, title and Edit on one row; the live 3D bar takes every point of height down to
//  the footer, and the earned plates stand on its floor in a row along the bottom, faces toward
//  the viewer, each grounded by a soft contact shadow, one per look with up to two copies behind
//  it and a stamped count. The floor fades to black only below the plates' feet. A look whose
//  copies are all on the bar (or on the floor after "Drop all") stays as a dim ghost with a tag.
//  The hint, and a short readout ("+40 / 190 kg on the bar") when the load changes, sit over the
//  scene's top. A held plate (or a tapped one, with VOLIA_RACK_RAIL_TAP=preview) lifts out over
//  the row with its face, name, weight and load or take-off; the bar above stays in view. Under
//  the scene a slim footer: the storage line, "Drop 16" or "Tidy up", and "All 90". Plain values
//  and closures only: the plate pictures come from the host.
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

struct CutRackRailScreen<SceneContent: View, Stand: View, Face: View>: View {
    let model: CutRackModel
    let rail: CutRackRailModel
    let lifted: CutRackRailPreviewModel?
    let tapMode: CutRackRailTap
    let actions: CutRackRailActions
    @ViewBuilder var scene: () -> SceneContent
    /// A group's plate standing on the floor, face toward the viewer.
    @ViewBuilder var stand: (CutRackRailModel.Group) -> Stand
    /// The lifted group's plate, face on.
    @ViewBuilder var face: (CutRackRailModel.Group) -> Face
    /// Runs while a group is on screen (the host prepares its next plate's faces).
    var groupShown: (CutRackRailModel.Group) async -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash: CutRackReadoutFlash?
    @State private var flashToken = 0
    @State private var width: CGFloat = 390

    /// A plate's drawn side: about four plates across the screen, 90 to 128 points (the plate's
    /// face is about nine tenths of it).
    private var plateSide: CGFloat { min(128, max(90, (width / 3.6).rounded())) }

    var body: some View {
        let _ = RackWorkCounters.debugTick(.railScreenBodies)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Large text: the page scrolls, the scene keeps a fixed height with the plates on
                // its floor, and the lifted plate and the hint get their own place under it.
                ScrollView {
                    VStack(spacing: 0) {
                        top
                        sceneArea(height: 340)
                        if flash == nil, let hint = rail.hint {
                            hintText(hint).padding(.vertical, 10)
                        }
                        if lifted != nil { liftPanel.padding(.horizontal, 12).padding(.vertical, 12) }
                        footer
                    }
                }
            } else {
                VStack(spacing: 0) {
                    top
                    sceneArea(height: nil)
                    footer
                }
            }
        }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
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
        .padding(.bottom, 4)
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

    // MARK: Scene and the row on its floor

    private func sceneArea(height: CGFloat?) -> some View {
        let inline = height != nil
        return scene()
            .accessibilityValue(Text(model.sceneAccessibilityValue))
            .frame(maxWidth: .infinity, maxHeight: inline ? nil : .infinity)
            .frame(height: height)
            .overlay { floorShade.allowsHitTesting(false) }
            .overlay(alignment: .top) { topOverlay(showsHint: !inline).allowsHitTesting(false) }
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    plateRow
                        .opacity(!inline && lifted != nil ? 0 : 1)
                    if !inline, lifted != nil {
                        liftPanel
                            .padding(.horizontal, 10)
                            .padding(.bottom, 6)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.34, dampingFraction: 0.86),
                           value: lifted?.groupID)
            }
            .clipped()
    }

    /// The room melts into the page at the top; at the bottom the floor darkens only below the
    /// plates' feet, where their counts and tags sit.
    private var floorShade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [DS.Cut.Colors.background, DS.Cut.Colors.background.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 20)
            Spacer(minLength: 0)
            LinearGradient(stops: [
                .init(color: DS.Cut.Colors.background.opacity(0), location: 0),
                .init(color: DS.Cut.Colors.background.opacity(0.7), location: 0.4),
                .init(color: DS.Cut.Colors.background, location: 1)
            ], startPoint: .top, endPoint: .bottom)
                .frame(height: CutRackPlateRow<Stand>.belowFeet + 4)
        }
    }

    /// The hint, or the readout while it flashes. With large text the hint sits under the scene.
    private func topOverlay(showsHint: Bool) -> some View {
        ZStack(alignment: .top) {
            if let flash {
                flashView(flash)
                    .id(flashToken)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            } else if showsHint, let hint = rail.hint {
                hintText(hint)
                    .shadow(color: DS.Cut.Colors.background, radius: 6)
                    .shadow(color: DS.Cut.Colors.background, radius: 2)
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.top, 10)
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
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .accessibilityAddTraits(.updatesFrequently)
    }

    /// The change in lime and the new total under it, in the display type, lifted off the room
    /// by a soft shadow.
    private func flashView(_ flash: CutRackReadoutFlash) -> some View {
        VStack(spacing: -6) {
            Text(flash.delta)
                .font(DS.Cut.Typography.condensed(size: 64, relativeTo: .largeTitle, monospacedDigits: true))
                .foregroundStyle(DS.Cut.Colors.lime)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(flash.total)
                    .font(DS.Cut.Typography.condensed(size: 30, relativeTo: .title, monospacedDigits: true))
                Text(flash.unit)
                    .font(DS.Cut.Typography.condensed(size: 17, weight: .bold, relativeTo: .callout))
                    .textCase(.uppercase)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .shadow(color: .black.opacity(0.9), radius: 14)
        .shadow(color: .black.opacity(0.7), radius: 3)
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

    @ViewBuilder
    private var plateRow: some View {
        if let empty = rail.emptyRail {
            Text(empty)
                .font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .callout))
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.bottom, 16)
        } else {
            CutRackPlateRow(model: rail, side: plateSide, lifted: lifted?.groupID, tapMode: tapMode,
                            actions: actions, groupShown: groupShown, stand: stand)
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

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DS.Cut.Colors.hairline).frame(height: DS.Cut.Metrics.hairline)
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
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
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

// MARK: - The row

/// The plates standing on the floor in one row that scrolls sideways: a family's name stamped
/// small over its first plate and a wider gap between families.
struct CutRackPlateRow<Stand: View>: View {
    let model: CutRackRailModel
    let side: CGFloat
    let lifted: String?
    let tapMode: CutRackRailTap
    let actions: CutRackRailActions
    var groupShown: (CutRackRailModel.Group) async -> Void = { _ in }
    @ViewBuilder var stand: (CutRackRailModel.Group) -> Stand

    /// Points under the plates' feet: the tags line and the bottom margin.
    static var belowFeet: CGFloat { 34 }
    /// How far a copy behind shows to the right and up, as a share of the plate.
    static var copyOffset: CGFloat { 0.07 }

    private enum Item: Identifiable {
        case group(CutRackRailModel.Group, title: String?)
        case gap(String)

        var id: String {
            switch self {
            case .group(let group, _): return group.id
            case .gap(let section): return "gap-" + section
            }
        }
    }

    private var items: [Item] {
        var items: [Item] = []
        for (index, section) in model.sections.enumerated() {
            if index > 0 { items.append(.gap(section.id)) }
            for (position, group) in section.groups.enumerated() {
                items.append(.group(group, title: position == 0 && model.showsFamilyTitles ? section.title : nil))
            }
        }
        return items
    }

    var body: some View {
        let _ = RackWorkCounters.debugTick(.railRowBodies)
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .bottom, spacing: -side * 0.06) {
                ForEach(items) { item in
                    switch item {
                    case .group(let group, let title):
                        groupView(group)
                            .overlay(alignment: .topLeading) {
                                if let title { familyTitle(title) }
                            }
                    case .gap:
                        Color.clear.frame(width: side * 0.32, height: 1).accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 20)
        }
        // A horizontal scroll view takes every spare point of height; the row keeps its own, so
        // the room above stays the scene's.
        .fixedSize(horizontal: false, vertical: true)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// The family's name, stamped small over its first plate.
    private func familyTitle(_ title: String) -> some View {
        Text(title)
            .font(DS.Cut.Typography.condensed(size: 15, weight: .bold, relativeTo: .footnote))
            .textCase(.uppercase)
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .shadow(color: .black, radius: 4)
            .lineLimit(1)
            .fixedSize()
            .offset(x: 6, y: -18)
            .accessibilityAddTraits(.isHeader)
    }

    private func groupView(_ group: CutRackRailModel.Group) -> some View {
        let isLifted = lifted == group.id
        let behind = CGFloat(group.copiesBehind) * side * Self.copyOffset
        return VStack(spacing: 2) {
            plates(group)
                .frame(width: side + behind, height: side + behind * 0.25, alignment: .bottomLeading)
            tags(group)
                .frame(height: Self.belowFeet - 6, alignment: .top)
        }
        .padding(.bottom, 4)
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
            return group.nextToUnload != nil ? "Takes one off the bar." : "Shows the plate."
        }
    }

    /// The front plate with up to two copies behind it, each grounded by a soft shadow; a ghost
    /// when no copy stands here.
    private func plates(_ group: CutRackRailModel.Group) -> some View {
        ZStack(alignment: .bottomLeading) {
            contactShadow
            ForEach((0..<group.copiesBehind).reversed(), id: \.self) { index in
                let step = CGFloat(index + 1) * side * Self.copyOffset
                plate(group)
                    .brightness(-0.12 * Double(index + 1))
                    .offset(x: step, y: -step * 0.25)
            }
            plate(group)
                .saturation(group.isGhost ? 0.15 : 1)
                .opacity(group.isGhost ? 0.32 : 1)
        }
    }

    /// One plate: its picture, darkening toward the floor as the room does.
    private func plate(_ group: CutRackRailModel.Group) -> some View {
        stand(group)
            .frame(width: side, height: side)
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.45), .init(color: .black.opacity(0.32), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .mask { stand(group).frame(width: side, height: side) }
            }
    }

    /// Where the plate meets the floor: a soft pool spreading past both sides of the plate and a
    /// tight dark core under its rim, so it stands on the floor instead of floating over it.
    private var contactShadow: some View {
        ZStack {
            Ellipse().fill(Color.black.opacity(0.7))
                .frame(width: side * 1.2, height: side * 0.22)
                .blur(radius: 10)
            Ellipse().fill(Color.black.opacity(0.9))
                .frame(width: side * 0.7, height: side * 0.07)
                .blur(radius: 2.5)
                .offset(y: -side * 0.02)
        }
        .frame(width: side)
        .offset(y: side * 0.03)
    }

    /// The count and where the other copies are, stamped under the plate.
    private func tags(_ group: CutRackRailModel.Group) -> some View {
        // At most two tags, so they stay within the plate: the count, then where the others are
        // (the bar first; the footer already counts the floor).
        HStack(spacing: 4) {
            if let count = group.count { tag(count, tone: .count) }
            if let onBar = group.onBarTag {
                tag(onBar, tone: .bar)
            } else if let onFloor = group.onFloorTag, group.count == nil || group.isGhost {
                tag(onFloor, tone: .floor)
            }
        }
        .frame(width: side)
        .accessibilityHidden(true)
    }

    private enum TagTone { case count, bar, floor }

    private func tag(_ text: String, tone: TagTone) -> some View {
        Text(text)
            .font(DS.Cut.Typography.condensed(size: tone == .count ? 17 : 14, weight: .bold, relativeTo: .footnote,
                                              monospacedDigits: true))
            .textCase(.uppercase)
            .foregroundStyle(tone == .bar ? DS.Cut.Colors.ink : DS.Cut.Colors.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background {
                switch tone {
                case .bar: CutCornerShape(corner: .bottomTrailing, cut: .points(5)).fill(DS.Cut.Colors.lime)
                case .count: CutCornerShape(corner: .bottomTrailing, cut: .points(5)).fill(DS.Cut.Colors.panelControl)
                case .floor: CutCornerShape(corner: .bottomTrailing, cut: .points(5)).strokeBorder(DS.Cut.Colors.hairlineStrong, lineWidth: 1)
                }
            }
    }
}

/// Load and take-off as VoiceOver actions, plus showing the plate.
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

/// The plate lifted out of the row: its face, large, turning toward the viewer, with its name,
/// engraving, weight and counts, and load or take-off. A compact chamfered panel over the row,
/// so the bar above stays in view.
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
                // The buttons beside the facts when they fit in one line there, else full width
                // under the face and facts.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        plate
                        VStack(alignment: .leading, spacing: 8) {
                            facts
                            HStack(spacing: 8) { loadButton; unloadButton; detailsButton }.fixedSize()
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 12) { plate; facts }
                        buttons
                    }
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
            .buttonStyle(CutIconButtonStyle(tone: .fill, diameter: 30))
            .frame(width: DS.Cut.Metrics.minTouchTarget, height: DS.Cut.Metrics.minTouchTarget)
            .offset(x: -10, y: 2)
            .accessibilityLabel(Text("Put the plate back"))
        }
        .environment(\.cutSheetLevel, .base)
        .accessibilityElement(children: .contain)
        .onAppear { turned = true }
    }

    /// The face turns toward the viewer as it lifts out of the row.
    private var plate: some View {
        face()
            .frame(width: 104, height: 104)
            .rotation3DEffect(.degrees(turned || reduceMotion ? 0 : 40), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(turned || reduceMotion ? 1 : 0.85, anchor: .bottom)
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: turned)
            .contentShape(Circle())
            .onTapGesture { actions.details(group.plateID) }
            .accessibilityHidden(true)
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.engraving ?? model.title)
                .font(DS.Cut.Typography.condensed(size: 24, relativeTo: .title2))
                .textCase(.uppercase)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 34)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.weight)
                    .font(DS.Cut.Typography.condensed(size: 26, relativeTo: .title, monospacedDigits: true))
                    .textCase(.uppercase)
                    .foregroundStyle(DS.Cut.Colors.lime)
                    .fixedSize()
                if model.engraving != nil {
                    Text(model.title)
                        .font(DS.Typography.custom(size: 15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
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
            HStack(spacing: 8) { loadButton; unloadButton }
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
