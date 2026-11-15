//
//  CutWhatsNewModel.swift
//  WRKT
//
//  The Cut What's New sheet: a lime "New in <version>" line, the release title, its points in an
//  inner panel and one lime button. The button's words follow one rule: a release that names a
//  destination opens it ("See your rack"); any other release just closes ("Got it").
//

import Foundation

struct CutWhatsNewModel: Equatable {
    var eyebrow: String
    var title: String
    var points: [String]
    var buttonTitle: String
    /// The button opens a destination before the sheet closes.
    var destination: WhatsNewRelease.Destination?
}

enum CutWhatsNewLogic {
    static let closeTitle = "Got it"

    static func buttonTitle(for destination: WhatsNewRelease.Destination?) -> String {
        switch destination {
        case .rack: "See your rack"
        case nil: closeTitle
        }
    }

    static func model(release: WhatsNewRelease, currentVersion: String) -> CutWhatsNewModel {
        .init(
            eyebrow: currentVersion.isEmpty ? "New in VOLIA" : "New in \(currentVersion)",
            title: release.title,
            points: release.bullets,
            buttonTitle: buttonTitle(for: release.destination),
            destination: release.destination
        )
    }
}
