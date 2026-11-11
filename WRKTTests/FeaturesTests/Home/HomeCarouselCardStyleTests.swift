import Foundation
import Testing

struct HomeCarouselCardStyleTests {
    @Test func weeklyProgressAndFriendActivityUseSharedCarouselCardStyle() throws {
        let sharedSource = try String(
            contentsOfFile: sourcePath("Features/Home/Components/HomeCarouselCard.swift"),
            encoding: .utf8
        )
        let weeklySource = try String(
            contentsOfFile: sourcePath("Features/Home/Components/Cards/WeeklyProgressCard.swift"),
            encoding: .utf8
        )
        let friendSource = try String(
            contentsOfFile: sourcePath("Features/Home/Components/Cards/FriendActivityCard.swift"),
            encoding: .utf8
        )

        #expect(sharedSource.contains("struct HomeCarouselCard<Content: View>: View"))
        #expect(sharedSource.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.large))"))
        #expect(sharedSource.contains(".clipShape(surfaceShape)"))
        #expect(sharedSource.contains("surfaceShape.stroke"))
        #expect(weeklySource.contains("HomeCarouselCard("))
        #expect(friendSource.contains("HomeCarouselCard("))
        #expect(!weeklySource.contains(".clipShape(ChamferedRectangle(.large))"))
        #expect(!friendSource.contains(".clipShape(ChamferedRectangle(.large))"))
        #expect(!weeklySource.contains("ChamferedRectangle(.large).stroke"))
        #expect(!friendSource.contains("ChamferedRectangle(.large).stroke"))
    }

    private func sourcePath(_ relativePath: String) -> String {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
            directory.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: relativePath).path
    }
}
