import Foundation
import Testing

struct ProfileSettingsControlTests {
    @Test func meTabSettingsControlIsIconOnlyInsideProgressCard() throws {
        let source = try String(
            contentsOfFile: sourcePath("Features/Profile/Views/ProfileView.swift"),
            encoding: .utf8
        )
        let cardSource = try structBody(named: "ProgressOverviewCard", in: source)

        #expect(FileManager.default.fileExists(atPath: sourcePath("Resources/Assets.xcassets/settings-wheel-icon.imageset/settings-wheel-icon.svg")))
        #expect(cardSource.contains("var onSettingsTapped: (() -> Void)? = nil"))
        #expect(cardSource.contains("Button(action: onSettingsTapped)"))
        #expect(cardSource.contains("Image(\"settings-wheel-icon\")"))
        #expect(!source.contains("gearshape.fill"))
        #expect(!source.contains("Text(\"Settings\")"))
        #expect(!source.contains("private var profileHeader"))
    }

    private func sourcePath(_ relativePath: String) -> String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url.appendingPathComponent(relativePath).path
    }

    private func structBody(named name: String, in source: String) throws -> String {
        guard let range = source.range(of: "struct \(name)") else {
            throw TestFailure("Missing struct \(name)")
        }

        guard let openingBrace = source[range.lowerBound...].firstIndex(of: "{") else {
            throw TestFailure("Missing opening brace for \(name)")
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            if source[index] == "{" {
                depth += 1
            } else if source[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openingBrace...index])
                }
            }
            index = source.index(after: index)
        }

        throw TestFailure("Missing closing brace for \(name)")
    }

    private struct TestFailure: Error, CustomStringConvertible {
        let description: String

        init(_ description: String) {
            self.description = description
        }
    }
}
