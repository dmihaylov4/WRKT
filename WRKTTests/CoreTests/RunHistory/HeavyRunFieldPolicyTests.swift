import XCTest

/// Only the files on the allowlist may read a workout's detail arrays or ask for a full run.
///
/// The hard guarantee is the compiler: `WorkoutStoreV2.runs` is private, so history-wide code can
/// only see `RunSummary`, which has no arrays. This test watches the other way in: a full `Run`
/// obtained through the detail handle, the loader or a conversion, and the arrays read or built
/// by name. It scans the app's sources for `.routeWithHR`, `.hrSamples`, `routeWithHR:`,
/// `hrSamples:`, `toCompletedWorkout(`, `sharedWorkout(`, `loadRun(`, `loadRuns(`, `runDetail(`
/// and `RunDetailHolder`. `route` and `splits` are not scanned: the names are too common (navigation
/// routes, training splits); for them the private `runs` is the guarantee.
///
/// A new file reading these needs a reason here. A listed file that no longer reads them must
/// leave the list, so the list stays the true set of heavy readers.
final class HeavyRunFieldPolicyTests: XCTestCase {
    static let allowlist: [String: String] = [
        "Core/Persistence/WorkoutStorage.swift":
            "Stores and loads the history file: the full run is what it writes and reads.",
        "Features/WorkoutSession/Services/WorkoutStoreV2.swift":
            "Owns the full runs and hands them out through runDetail, loadRun and loadRuns.",
        "Features/Health/Models/RunSummary.swift":
            "Builds a summary's facts from a full run's arrays, once per run.",
        "Features/Health/Models/RouteModels.swift":
            "Defines Run and its conversion to a posted workout, samples included.",
        "Features/Health/Services/RunDetail.swift":
            "The live handle on one workout's full record.",
        "Features/Health/Services/RunEdit.swift":
            "Edits and replaces one workout's arrays for the writers.",
        "Features/Health/Services/HealthKitManager.swift":
            "Reads routes, samples and splits from HealthKit and writes them as edits; posts a run after its route is stored.",
        "Core/Services/CardioDataExtractor.swift":
            "Heart-rate zones, map snapshot and the shared workout for one run.",
        "Features/Social/Services/CardioAutoPostService.swift":
            "Posts one full run that a writer has just stored.",
        "Features/Social/ViewModels/PostCreationViewModel.swift":
            "Completes the chosen picker runs before posting and draws one run's map.",
        "Features/Health/Views/CardioDetailView.swift":
            "The legacy detail screen: one workout's map, splits and heart rate.",
        "Features/Health/Cut/CutCardioHost.swift":
            "The Cut detail host: one workout's map, splits and heart rate.",
        "Features/Health/Cut/CutCardioModel.swift":
            "The Cut detail model for one workout, built from its full record.",
        "Features/Health/Views/CardioView.swift":
            "A legacy cardio row draws its own workout's route preview through the handle.",
        "Core/Models/ExportBundle.swift":
            "Clears one exported workout's route and heart-rate arrays for a backup without routes.",
        "Core/Persistence/RunsV3Merge.swift":
            "The merge keeps a stored route when an older build's copy only dropped it.",
    ]

    /// Whether `text` uses `token` as a whole name: `.routeWithHR` matches `run.routeWithHR`
    /// but not the summary fact `summary.routeWithHRPointCount`, which reads no array.
    static func mentions(_ text: String, _ token: String) -> Bool {
        guard let last = token.unicodeScalars.last, last.properties.isAlphabetic || last == "_" else {
            return text.contains(token)
        }
        var searchStart = text.startIndex
        while let range = text.range(of: token, range: searchStart..<text.endIndex) {
            guard range.upperBound < text.endIndex else { return true }
            let next = text[range.upperBound]
            if !(next.isLetter || next.isNumber || next == "_") { return true }
            searchStart = range.upperBound
        }
        return false
    }

    static let tokens = [".routeWithHR", ".hrSamples", "routeWithHR:", "hrSamples:", "toCompletedWorkout(",
                         "sharedWorkout(", "loadRun(", "loadRuns(", "runDetail(", "RunDetailHolder"]

    /// App, Watch and widget sources, relative to the repository root.
    static let sourceRoots = ["App", "Core", "Features", "Shared", "DesignSystem", "WRKT Watch Watch App", "WRKTWidgets"]

    private static var repositoryRoot: URL {
        // .../WRKTTests/CoreTests/RunHistory/HeavyRunFieldPolicyTests.swift
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    func testOnlyAllowlistedFilesReadHeavyRunData() throws {
        let root = Self.repositoryRoot
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.appendingPathComponent("Features").path) else {
            throw XCTSkip("Sources are not readable from this test host")
        }
        var readers: [String: [String]] = [:]
        for sourceRoot in Self.sourceRoots {
            let base = root.appendingPathComponent(sourceRoot)
            guard let walker = fileManager.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                let found = Self.tokens.filter { Self.mentions(text, $0) }
                guard !found.isEmpty else { continue }
                let relative = String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
                readers[relative] = found
            }
        }
        XCTAssertFalse(readers.isEmpty, "the scan found no sources")
        for (file, found) in readers.sorted(by: { $0.key < $1.key }) where Self.allowlist[file] == nil {
            XCTFail("\(file) reads heavy run data (\(found.joined(separator: ", "))) but is not on the allowlist")
        }
        for file in Self.allowlist.keys.sorted() where readers[file] == nil {
            XCTFail("\(file) is on the allowlist but no longer reads heavy run data: remove it")
        }
    }
}
