import Foundation

struct CutFilteredExerciseBrowserModel: Equatable {
    let title: String
    let subregions: [String]
}

enum CutFilteredExerciseBrowserLogic {
    static func model(filter: MuscleFilter?, title: String) -> CutFilteredExerciseBrowserModel {
        let upper = MuscleTaxonomy.subregions(for: .upper)
        let lower = MuscleTaxonomy.subregions(for: .lower)
        let groups: [String]
        switch filter {
        case .upperBody: groups = upper
        case .lowerBody: groups = lower
        case .fullBody, .none: groups = upper + lower
        }
        return .init(title: title, subregions: groups)
    }
}
