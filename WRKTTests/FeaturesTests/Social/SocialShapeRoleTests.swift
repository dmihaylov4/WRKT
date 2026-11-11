import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct SocialShapeRoleTests {
    #if DEBUG
    @Test func authenticationAndSearchPreserveLegacyPaths() throws {
        let login = try ShapeRoleTestSupport.source("Social/Views/LoginView.swift")
        #expect(login.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.large))"))
        #expect(login.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.large))"))
        for path in ["Social/Views/FriendsListView.swift", "Social/Views/UserSearchView.swift"] {
            #expect(try ShapeRoleTestSupport.source(path).contains("DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 12))"))
        }
        #expect(try ShapeRoleTestSupport.source("Social/Views/SignupView.swift").contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 10))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.control, legacy: RoundedRectangle(cornerRadius: 12), expected: RoundedRectangle(cornerRadius: 12).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 10), expected: RoundedRectangle(cornerRadius: 10).path(in: rect), rect: rect, radius: 26)
        }
    }
    #endif
}

@MainActor
enum ShapeRoleTestSupport {
    #if DEBUG
    static let rects = [CGRect(x: 3, y: 7, width: 340, height: 180),
                        CGRect(x: 3, y: 7, width: 40, height: 30),
                        CGRect(x: 3, y: 7, width: 20, height: 60)]

    static func source(_ path: String) throws -> String {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while root.path != "/" && !FileManager.default.fileExists(atPath: root.appendingPathComponent("CLAUDE.md").path) {
            root.deleteLastPathComponent()
        }
        return try String(contentsOf: root.appendingPathComponent("Features/" + path), encoding: .utf8)
    }

    static func check<S: SwiftUI.Shape>(_ role: DS.Shape.Role, legacy: S, expected: Path,
                                       rect: CGRect, radius: CGFloat) {
        let shape = DS.RoleShape(role, legacy: legacy)
        #expect(shape.path(in: rect, rounded: false).cgPath == expected.cgPath)
        let clamped = min(radius, rect.width / 2, rect.height / 2)
        #expect(shape.path(in: rect, rounded: true).cgPath == RoundedRectangle(cornerRadius: clamped, style: .continuous).path(in: rect).cgPath)
    }
    #endif
}
