import Testing
import Foundation
@testable import WRKT

struct ProfileSectionIconDesignTests {
    @Test func meStatsSectionsUseCustomAccentIconKinds() {
        #expect(ProfileSectionIconKind.trainingTrends.accessibilityLabel == "Training trends")
        #expect(ProfileSectionIconKind.trainingBalance.accessibilityLabel == "Training balance")
        #expect(ProfileSectionIconKind.achievementCup.accessibilityLabel == "Achievement cup")
        #expect(ProfileSectionIconKind.allCases == [.trainingTrends, .trainingBalance, .achievementCup])
    }

    @Test func meStatsSectionHeadersOmitDecorativeIcons() throws {
        let profileStatsSource = try String(
            contentsOfFile: sourcePath("Features/Statistics/Views/ProfileStatsSection.swift"),
            encoding: .utf8
        )
        let trainingBalanceSource = try String(
            contentsOfFile: sourcePath("Features/Statistics/Views/TrainingBalanceSection.swift"),
            encoding: .utf8
        )
        let trendsHeader = profileStatsSource.section(
            from: "struct ProfileStatsView",
            to: "private func getStatsAggregator"
        )
        let balanceHeader = trainingBalanceSource.section(
            from: "struct TrainingBalanceSection",
            to: "// MARK: - Empty Data Card"
        )

        #expect(trendsHeader.contains("Text(\"Training Trends\")"))
        #expect(balanceHeader.contains("Text(\"Training Balance\")"))
        #expect(!trendsHeader.contains("ProfileSectionIcon(kind: .trainingTrends)"))
        #expect(!balanceHeader.contains("ProfileSectionIcon(kind: .trainingBalance)"))
    }

    @Test func trainingTotalsKeepBodyweightQualityBadgeInsideMetricTile() throws {
        let source = try String(
            contentsOfFile: sourcePath("Features/Statistics/Views/ProfileStatsSection.swift"),
            encoding: .utf8
        )

        #expect(source.contains("StatPill(title: \"Volume\", value: prettyVolume(t.volume), footnote: hasBodyweightEst ? \"estimated\" : nil)"))
        #expect(!source.contains("DataQualityBadge(quality: .bodyweightEst)"))
    }

    @Test func statsSubsectionTitlesUseTextInsteadOfLeadingIcons() throws {
        let profileStatsSource = try String(
            contentsOfFile: sourcePath("Features/Statistics/Views/ProfileStatsSection.swift"),
            encoding: .utf8
        )
        let trainingBalanceSource = try String(
            contentsOfFile: sourcePath("Features/Statistics/Views/TrainingBalanceSection.swift"),
            encoding: .utf8
        )

        #expect(profileStatsSource.contains("Text(\"Weekly Tonnage\")"))
        #expect(profileStatsSource.contains("Text(\"Top lifts (by volume)\")"))
        #expect(trainingBalanceSource.contains("Text(\"Push/Pull Balance\")"))
        #expect(!profileStatsSource.contains("Label(\"Weekly Tonnage\""))
        #expect(!profileStatsSource.contains("Label(\"Top lifts (by volume)\""))
        #expect(!trainingBalanceSource.contains("Label(\"Push/Pull Balance\""))
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

private extension String {
    func section(from startMarker: String, to endMarker: String) -> String {
        guard
            let start = range(of: startMarker)?.lowerBound,
            let end = range(of: endMarker, range: start..<endIndex)?.lowerBound
        else {
            return self
        }

        return String(self[start..<end])
    }
}
