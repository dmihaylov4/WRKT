import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct ExerciseRepositoryShapeRoleTests {
    #if DEBUG
    @Test func exerciseBrowseKeepsLegacyPaths() throws {
        let cross = try ShapeRoleTestSupport.source("ExerciseRepository/Components/CrossMuscleSearch.swift")
        #expect(cross.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.micro))"))
        #expect(cross.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.large))"))
        #expect(cross.contains("DS.RoleShape(.nested, legacy: RoundedRectangle(cornerRadius: 10, style: .continuous))"))
        #expect(cross.contains("DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 10, style: .continuous))"))
        let search = try ShapeRoleTestSupport.source("ExerciseRepository/Components/SearchBarComponent.swift")
        #expect(search.contains(".clipShape(DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 10)))"))
        #expect(!search.contains(".cornerRadius(10)"))
        let list = try ShapeRoleTestSupport.source("ExerciseRepository/Components/ExerciseListComponents.swift")
        #expect(list.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.micro))"))
        #expect(list.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.small))"))
        let empty = try ShapeRoleTestSupport.source("ExerciseRepository/Views/EmptyExercisesView.swift")
        #expect(empty.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous))"))
        #expect(empty.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 12))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.micro), expected: MainChamferedRectangle(.micro).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.nested, legacy: RoundedRectangle(cornerRadius: 10, style: .continuous), expected: RoundedRectangle(cornerRadius: 10, style: .continuous).path(in: rect), rect: rect, radius: 10)
            ShapeRoleTestSupport.check(.control, legacy: RoundedRectangle(cornerRadius: 10, style: .continuous), expected: RoundedRectangle(cornerRadius: 10, style: .continuous).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.control, legacy: RoundedRectangle(cornerRadius: 10), expected: RoundedRectangle(cornerRadius: 10).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.small), expected: MainChamferedRectangle(.small).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous), expected: RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 12), expected: RoundedRectangle(cornerRadius: 12).path(in: rect), rect: rect, radius: 26)
        }
    }
    #endif
}
