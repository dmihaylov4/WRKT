//
//  CutRackView.swift
//  WRKT
//
//  The Cut rack ("Your bar"), direction A: the back button, title and Edit on one row, the total
//  on the bar with one lime summary line, the live 3D bar (a slot the host fills) with one quiet
//  hint, and a raised tray of earned plates pinned at the bottom. Tapping a tray plate loads it
//  or takes it off; holding it (or the VoiceOver action) opens its detail. Also the plate detail
//  (a choice sheet) and the full collection (a browser sheet). Plain values and closures only.
//

import SwiftUI

struct CutRackActions {
    var back: () -> Void
    var edit: () -> Void
    var showAll: () -> Void
    var toggle: (String) -> Void
    var details: (String) -> Void
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
                .padding(.top, 14)
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

    private var total: some View {
        VStack(alignment: .leading, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) { totalNumeral; totalUnit }
                VStack(alignment: .leading, spacing: 0) { totalNumeral; totalUnit }
            }
            Text(model.summary)
                .font(DS.Typography.custom(size: 17, weight: .semibold, relativeTo: .body))
                .foregroundStyle(DS.Cut.Colors.lime)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(model.totalAccessibilityLabel). \(model.summary)"))
    }

    private var totalNumeral: some View {
        Text(model.totalValue)
            .font(DS.Cut.Typography.condensed(size: 72, relativeTo: .largeTitle, monospacedDigits: true))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.25), value: model.totalValue)
    }

    private var totalUnit: some View {
        Text(model.totalUnit)
            .font(DS.Typography.custom(size: 22, weight: .semibold, relativeTo: .title3))
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Scene

    /// - Parameter height: a fixed scene height (large text, where the page scrolls); nil fills the space.
    private func sceneArea(height: CGFloat?) -> some View {
        VStack(spacing: 12) {
            scene()
                .accessibilityValue(Text(model.sceneAccessibilityValue))
                .frame(maxWidth: .infinity, maxHeight: height == nil ? .infinity : nil)
                .frame(height: height)
                .clipped()
                .overlay { edgeFades.allowsHitTesting(false) }
            if let hint = model.hint {
                Text(hint)
                    .font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .callout))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// Soft top and bottom edges so the room melts into the black page instead of ending in a line.
    private var edgeFades: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [DS.Cut.Colors.background, DS.Cut.Colors.background.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 28)
            Spacer(minLength: 0)
            LinearGradient(colors: [DS.Cut.Colors.background.opacity(0), DS.Cut.Colors.background],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 28)
        }
    }

    // MARK: Tray

    private var tray: some View {
        VStack(alignment: .leading, spacing: 12) {
            CutPanelHeader(model.trayTitle) {
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
            if model.tiles.isEmpty {
                Text(model.emptyTray)
                    .font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .callout))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.bottom, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(model.tiles) { tile in
                            tileButton(tile)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Self.traySurface))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .environment(\.cutSheetLevel, .base)
    }

    private func tileButton(_ tile: CutRackModel.Tile) -> some View {
        Button { actions.toggle(tile.id) } label: {
            VStack(spacing: 6) {
                thumbnail(tile.id)
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
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(CutRackTileButtonStyle())
        .contextMenu {
            Button("Show details", systemImage: "info.circle") { actions.details(tile.id) }
        }
        .accessibilityLabel(Text(tile.accessibilityLabel))
        .accessibilityHint(Text(tile.accessibilityHint))
        .accessibilityAddTraits(tile.isLoaded ? .isSelected : [])
        .accessibilityAction(named: Text("Show details")) { actions.details(tile.id) }
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
