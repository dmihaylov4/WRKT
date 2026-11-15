//
//  CutWhatsNewView.swift
//  WRKT
//
//  What's New as a Cut sheet sized to its content: the version line in lime, the release title,
//  the release's points on an inner panel, one lime button.
//

import SwiftUI

struct CutWhatsNewView: View {
    let model: CutWhatsNewModel
    var primary: () -> Void = {}
    var close: () -> Void = {}

    var body: some View {
        CutSheet(model.title, eyebrow: model.eyebrow, close: close) {
            CutSheetInset {
                ForEach(Array(model.points.enumerated()), id: \.offset) { index, point in
                    if index > 0 { CutHairline() }
                    HStack(spacing: 14) {
                        Rectangle()
                            .fill(DS.Cut.Colors.lime)
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(point)
                            .font(DS.Typography.custom(size: 18, weight: .semibold, relativeTo: .body))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 10)
                    .frame(minHeight: 60)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        } footer: {
            Button(model.buttonTitle, action: primary)
                .buttonStyle(CutPillButtonStyle(.lime, size: .regular, fillsWidth: true))
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
    }
}
