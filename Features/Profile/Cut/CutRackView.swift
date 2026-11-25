//
//  CutRackView.swift
//  WRKT
//
//  The Cut rack ("Your bar"), direction A: the back button, title and Edit on one row, a compact
//  total (the numeral with "kg on the bar" and the lime summary beside it), the live 3D bar (a
//  slot the host fills, given every spare point of height) with one quiet hint over its lower
//  edge, and a raised tray of earned plates pinned at the bottom. The tray shows the loaded
//  plates, then the stored plates grouped by look in family sections, one tile per look with a
//  count. Tapping a tile loads a copy or takes a loaded plate off; holding it (or the VoiceOver
//  action) opens its detail. "Drop all" drops the stored plates into the room to play with and
//  becomes "Tidy up" while they lie there. Also the plate detail (a choice sheet) and the full
//  collection (a browser sheet). Plain values and closures only.
//

import SwiftUI

struct CutRackActions {
    var back: () -> Void
    var edit: () -> Void
    var showAll: () -> Void
    var toggle: (String) -> Void
    var details: (String) -> Void
    /// Drop all or tidy up, as the model's play action says.
    var play: () -> Void = {}
}

struct CutRackView<SceneContent: View, Thumbnail: View>: View {
    let model: CutRackModel
    let actions: CutRackActions
    @ViewBuilder var scene: () -> SceneContent
    @ViewBuilder var thumbnail: (String) -> Thumbnail

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The tray surface: the base sheet surface, so the tray reads as a raised sheet edge.
    private static var traySurface: Color { DS.Cut.SheetLevel.base.surface }
    private static var tileFill: Color { DS.Cut.SheetLevel.base.inset }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Large text: everything scrolls and the scene keeps a fixed height. Drags that
                // start on the scene stay with the scene; the page scrolls from anywhere else.
                ScrollView {
                    VStack(spacing: 0) {
                        top
                        sceneArea(height: 300)
                        tray
                    }
                }
            } else {
                VStack(spacing: 0) {
                    top
                    sceneArea(height: nil)
                    tray
                }
            }
        }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .foregroundStyle(DS.Cut.Colors.textPrimary)
    }

    // MARK: Header and total

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
                // Large text: Edit gets its own row under the title row so neither is squeezed.
                editButton
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.top, 12)
            }
            total
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 6)
        }
    }

    private var title: some View {
        Text(model.title)
            .font(DS.Cut.Typography.hero(.xs))
            .textCase(.uppercase)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var editButton: some View {
        Button("Edit", action: actions.edit)
            .buttonStyle(CutPillButtonStyle(.outline))
            .accessibilityHint(Text("Bar, collars and room."))
    }

    /// One compact row: the numeral, and beside it "kg on the bar" over the lime summary, the
    /// summary's last line on the numeral's baseline. When that does not fit (a long pound total
    /// on a small phone, large text) the unit stays beside the numeral and the summary wraps
    /// under it; at accessibility sizes everything stacks.
    private var total: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                totalNumeral
                VStack(alignment: .leading, spacing: 1) {
                    totalUnit
                    totalSummary
                }
                .fixedSize()
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    totalNumeral
                    totalUnit.fixedSize()
                }
                totalSummary.fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                totalNumeral
                totalUnit.fixedSize(horizontal: false, vertical: true)
                totalSummary.fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.headerAccessibilityLabel))
    }

    private var totalNumeral: some View {
        Text(model.totalValue)
            .font(DS.Cut.Typography.condensed(size: 48, relativeTo: .largeTitle, monospacedDigits: true))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.25), value: model.totalValue)
    }

    private var totalUnit: some View {
        Text(model.totalUnit)
            .font(DS.Typography.custom(size: 16, weight: .semibold, relativeTo: .callout))
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
    }

    private var totalSummary: some View {
        Text(model.summary)
            .font(DS.Typography.custom(size: 15, weight: .semibold, relativeTo: .subheadline))
            .foregroundStyle(DS.Cut.Colors.lime)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
    }

    // MARK: Scene

    /// - Parameter height: a fixed scene height (large text, where the page scrolls); nil fills the space.
    /// The hint sits over the scene's faded lower edge (it never takes touches), so the band keeps
    /// that height. With large text the page scrolls and the hint gets its own line under it.
    private func sceneArea(height: CGFloat?) -> some View {
        let hintBelow = height != nil
        return VStack(spacing: 12) {
            scene()
                .accessibilityValue(Text(model.sceneAccessibilityValue))
                .frame(maxWidth: .infinity, maxHeight: height == nil ? .infinity : nil)
                .frame(height: height)
                .clipped()
                .overlay { edgeFades(tall: !hintBelow && model.hint != nil).allowsHitTesting(false) }
                .overlay(alignment: .bottom) {
                    if !hintBelow { hintText.padding(.bottom, 6).allowsHitTesting(false) }
                }
            if hintBelow { hintText }
        }
        .padding(.top, 2)
        .padding(.bottom, hintBelow ? 12 : 6)
    }

    @ViewBuilder
    private var hintText: some View {
        if let hint = model.hint {
            Text(hint)
                .font(DS.Typography.custom(size: 15, weight: .medium, relativeTo: .callout))
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// Soft top and bottom edges so the room melts into the black page instead of ending in a line.
    /// Taller at the bottom when the hint sits there, so the line reads on the page colour.
    private func edgeFades(tall: Bool) -> some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [DS.Cut.Colors.background, DS.Cut.Colors.background.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 24)
            Spacer(minLength: 0)
            LinearGradient(stops: [
                .init(color: DS.Cut.Colors.background.opacity(0), location: 0),
                .init(color: DS.Cut.Colors.background.opacity(tall ? 0.85 : 1), location: tall ? 0.55 : 1),
                .init(color: DS.Cut.Colors.background, location: 1)
            ], startPoint: .top, endPoint: .bottom)
                .frame(height: tall ? 48 : 28)
        }
    }

    // MARK: Tray

    private var tray: some View {
        VStack(alignment: .leading, spacing: 10) {
            CutPanelHeader(model.trayTitle) {
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
            }
            if model.sections.isEmpty {
                Text(model.emptyTray)
                    .font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .callout))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.bottom, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(model.sections) { section in
                            sectionView(section)
                        }
                    }
                    .padding(.horizontal, 20)
                    // Room for the count badges that sit over the tiles' top corners.
                    .padding(.top, 4)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Self.traySurface))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .environment(\.cutSheetLevel, .base)
    }

    /// A section of the tray's one horizontal row: a small caption over its tiles.
    private func sectionView(_ section: CutRackModel.Section) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = section.title {
                Text(title)
                    .font(DS.Typography.custom(size: 13, weight: .semibold, relativeTo: .footnote))
                    .textCase(.uppercase)
                    .foregroundStyle(section.id == "bar" ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            HStack(spacing: 10) {
                ForEach(section.tiles) { tile in
                    tileButton(tile)
                }
            }
        }
    }

    private func tileButton(_ tile: CutRackModel.Tile) -> some View {
        Button { actions.toggle(tile.plateID) } label: {
            VStack(spacing: 6) {
                thumbnail(tile.plateID)
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                Text(tile.weight)
                    .font(DS.Typography.custom(size: 15, weight: tile.isLoaded ? .bold : .semibold, relativeTo: .subheadline))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(minWidth: 84)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Self.tileFill))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tile.isLoaded ? DS.Cut.Colors.lime : .clear, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) { tileMarks(tile) }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(CutRackTileButtonStyle())
        .contextMenu {
            Button("Show details", systemImage: "info.circle") { actions.details(tile.plateID) }
        }
        .accessibilityLabel(Text(tile.accessibilityLabel))
        .accessibilityHint(Text(tile.accessibilityHint))
        .accessibilityAddTraits(tile.isLoaded ? .isSelected : [])
        .accessibilityAction(named: Text("Show details")) { actions.details(tile.plateID) }
    }

    /// The count of stored copies ("×12") and, when copies of the same plate are on the bar, a
    /// small lime dot. Both are in the tile's VoiceOver label already.
    @ViewBuilder
    private func tileMarks(_ tile: CutRackModel.Tile) -> some View {
        if tile.badge != nil || tile.onBarCount > 0 {
            HStack(spacing: 3) {
                if tile.onBarCount > 0 {
                    Circle().fill(DS.Cut.Colors.lime).frame(width: 7, height: 7)
                }
                if let badge = tile.badge {
                    Text(badge)
                        .font(DS.Typography.custom(size: 12, weight: .bold, relativeTo: .caption))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(DS.Cut.Colors.panelControl))
            .offset(x: 4, y: -4)
            .accessibilityHidden(true)
        }
    }
}

private struct CutRackTileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - Plate detail

struct CutRackPlateDetailView<Thumbnail: View>: View {
    let model: CutRackPlateDetailModel
    let toggle: () -> Void
    let close: () -> Void
    @ViewBuilder var thumbnail: () -> Thumbnail

    var body: some View {
        CutSheet(model.title, subtitle: model.subtitle, kind: .choice, close: close) {
            VStack(spacing: 20) {
                thumbnail()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                CutSheetInset {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { CutHairline() }
                        CutSheetInsetRow(row.label, value: row.value)
                    }
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 12)
        } footer: {
            Button(model.actionTitle, action: toggle)
                .buttonStyle(CutPillButtonStyle(model.isLoaded ? .outline : .lime, size: .regular, fillsWidth: true))
                .disabled(!model.isActionEnabled)
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.vertical, 12)
        }
    }
}

// MARK: - Collection

struct CutRackCollectionView<Thumbnail: View>: View {
    let model: CutRackCollectionModel
    let open: (String) -> Void
    let close: () -> Void
    @ViewBuilder var thumbnail: (String) -> Thumbnail

    var body: some View {
        CutSheet(model.title, subtitle: model.subtitle, kind: .browser, close: close) {
            if model.rows.isEmpty {
                Text(model.empty)
                    .font(DS.Typography.custom(size: 17, weight: .medium, relativeTo: .body))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.vertical, 12)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    CutHairline()
                    ForEach(model.rows) { row in
                        Button { open(row.id) } label: { rowLabel(row) }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(row.accessibilityLabel))
                            .accessibilityHint(Text("Shows how it was earned."))
                            .accessibilityAddTraits(.isButton)
                        CutHairline()
                    }
                }
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.bottom, 24)
            }
        }
    }

    private func rowLabel(_ row: CutRackCollectionModel.Row) -> some View {
        HStack(spacing: 14) {
            thumbnail(row.id)
                .frame(width: 48, height: 48)
                .overlay(Circle().strokeBorder(row.isLoaded ? DS.Cut.Colors.lime : .clear, lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(DS.Typography.custom(size: 17, weight: .semibold, relativeTo: .body))
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.line)
                    .font(DS.Typography.custom(size: 15, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Cut.Colors.textTertiary)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }
}
