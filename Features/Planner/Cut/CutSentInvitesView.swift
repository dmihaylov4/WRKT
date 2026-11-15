//
//  CutSentInvitesView.swift
//  WRKT
//

import SwiftUI

struct CutSentInvitesView: View {
    let model: CutSentInvitesModel
    var revoke: (UUID) -> Void = { _ in }
    var close: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        CutSheet("Sent invites", subtitle: model.subtitle, close: close) {
            VStack(alignment: .leading, spacing: 0) {
                switch model.state {
                case .loading:
                    ProgressView().tint(DS.Cut.Colors.textSecondary).frame(maxWidth: .infinity, minHeight: 120).accessibilityLabel(Text("Loading invites"))
                case .empty:
                    CutPlannerLine(CutSentInvitesLogic.emptyLine, size: 17).padding(.top, 8)
                case .loaded:
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { CutHairline() }
                        inviteRow(row)
                    }
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func inviteRow(_ row: CutSentInvitesModel.Row) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 14))
        return layout {
            HStack(spacing: 14) {
                CutCompeteAvatar(initials: row.initials, url: row.avatarURL, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    CutPlannerRowTitle(row.name)
                    CutPlannerLine(row.status)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            if row.canRevoke {
                Button { revoke(row.id) } label: {
                    ZStack {
                        Text("Revoke").opacity(row.revoking ? 0 : 1)
                        if row.revoking { ProgressView().tint(DS.Cut.Colors.textPrimary) }
                    }
                }
                .buttonStyle(CutPillButtonStyle(.outline))
                .fixedSize()
                .allowsHitTesting(!row.revoking)
                .accessibilityLabel(Text("Revoke invite for \(row.name)"))
            }
        }
        .padding(.vertical, 12)
        .frame(minHeight: 68)
    }
}
