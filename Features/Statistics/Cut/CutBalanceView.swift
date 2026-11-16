//
//  CutBalanceView.swift
//  WRKT
//
//  Balance: the back button and title on one row, push against pull as two percentages over one
//  split bar with a one-sentence verdict, "Last trained" by muscle group (today in lime, stale in
//  amber) and "Movements" with thin bars. Plain values and closures only.
//

import SwiftUI

struct CutBalanceView: View {
    let model: CutBalanceModel
    var back: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CutStatsTopBar(title: model.title, back: back)
                if let split = model.split {
                    splitBlock(split)
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                        .padding(.top, 22)
                }
                if let empty = model.emptyLine {
                    CutStatsEmptyLine(text: empty)
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                        .padding(.top, 22)
                }
                if !model.muscles.isEmpty {
                    CutPanelHeader(model.musclesTitle)
                        .padding(.top, 26)
                    CutPanel {
                        ForEach(Array(model.muscles.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { CutHairline() }
                            muscleRow(row)
                        }
                    }
                    .padding(.top, 10)
                }
                if !model.movements.isEmpty {
                    CutPanelHeader(model.movementsTitle)
                        .padding(.top, 26)
                    CutPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(model.movements) { movementRow($0) }
                        }
                        .padding(.horizontal, DS.Cut.Metrics.panelRowPadding)
                        .padding(.vertical, 14)
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 96, system: 76))
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }

    private func splitBlock(_ split: CutBalanceModel.Split) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                share("Push", split.push, alignment: .leading)
                Spacer(minLength: 12)
                share("Pull", split.pull, alignment: .trailing)
            }
            CutBalanceSplitBar(pushFraction: split.pushFraction)
            Text(split.verdict)
                .font(DS.Typography.custom(size: 17, weight: .bold, relativeTo: .body))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(split.accessibilityLabel))
    }

    private func share(_ label: String, _ value: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(label)
                .font(DS.Typography.custom(size: 17, weight: .semibold, relativeTo: .body))
                .foregroundStyle(DS.Cut.Colors.textSecondary)
            Text(value)
                .font(DS.Cut.Typography.condensed(size: 52, relativeTo: .largeTitle, monospacedDigits: true))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private func muscleRow(_ row: CutBalanceModel.MuscleRow) -> some View {
        CutStatsMuscleRow(name: row.name, value: row.value, color: color(row.tone), isEmphasised: row.tone != .recent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(row.name), \(row.value)\(row.tone == .stale ? ", over a week ago" : "")"))
    }

    private func color(_ tone: CutBalanceModel.MuscleRow.Tone) -> Color {
        switch tone {
        case .today: DS.Cut.Colors.lime
        case .recent: DS.Cut.Colors.textSecondary
        case .stale: DS.Status.warning
        }
    }

    private func movementRow(_ movement: CutBalanceModel.Movement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    movementTitle(movement.title)
                    movementValue(movement.value)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    movementTitle(movement.title)
                    Spacer(minLength: 12)
                    movementValue(movement.value)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.14))
                    Rectangle().fill(DS.Cut.Colors.lime)
                        .frame(width: proxy.size.width * DS.Cut.clampedFraction(movement.fraction))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(movement.accessibilityLabel))
    }

    private func movementTitle(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.custom(size: 17, weight: .bold, relativeTo: .body))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func movementValue(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.custom(size: 17, weight: .medium, relativeTo: .body))
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Push in lime and pull in white, side by side with a 4 pt gap, as in the mock.
private struct CutBalanceSplitBar: View {
    let pushFraction: Double

    var body: some View {
        GeometryReader { proxy in
            let fraction = DS.Cut.clampedFraction(pushFraction)
            let gap: CGFloat = fraction > 0 && fraction < 1 ? 4 : 0
            let push = (proxy.size.width - gap) * fraction
            HStack(spacing: gap) {
                if push > 0 { Rectangle().fill(DS.Cut.Colors.lime).frame(width: push) }
                if fraction < 1 { Rectangle().fill(Color.white) }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// A muscle group and how long ago it was trained.
private struct CutStatsMuscleRow: View {
    let name: String
    let value: String
    let color: Color
    let isEmphasised: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    nameText
                    valueText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    nameText
                    Spacer(minLength: 12)
                    valueText
                }
            }
        }
        .padding(.horizontal, DS.Cut.Metrics.panelRowPadding)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
    }

    private var nameText: some View {
        Text(name)
            .font(DS.Typography.custom(size: 18, weight: .bold, relativeTo: .body))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value)
            .font(DS.Typography.custom(size: 18, weight: isEmphasised ? .semibold : .medium, relativeTo: .body))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
