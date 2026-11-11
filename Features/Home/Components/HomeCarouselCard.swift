//
//  HomeCarouselCard.swift
//  WRKT
//
//  Shared styling wrapper for cards shown inside the Home smart carousel.
//

import SwiftUI

struct HomeCarouselCard<Content: View>: View {
    var accent: Color = DS.tint
    @ViewBuilder let content: Content

    var surfaceShape: DS.RoleShape<ChamferedRectangle> {
        DS.RoleShape(.card, legacy: ChamferedRectangle(.large))
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                DS.card
                    .overlay(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.05),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .clipShape(surfaceShape)
            .overlay(surfaceShape.stroke(DS.Semantic.border, lineWidth: 1))
    }
}
