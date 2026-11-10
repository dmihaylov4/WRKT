import XCTest
import SwiftData
@testable import WRKT

/// Opt-in verification of a private export. Never bundle real user records with tests.
@MainActor
final class PrivateExportVerificationTests: XCTestCase {
    func testExportSurvivesDecodingAndIsolatedPersistence() async throws {
        guard let path = ProcessInfo.processInfo.environment["WRKT_PRIVATE_EXPORT_PATH"] else {
            throw XCTSkip("Set WRKT_PRIVATE_EXPORT_PATH to verify a local export copy")
        }
        let sourceURL = URL(fileURLWithPath: path)
        let source = try Data(contentsOf: sourceURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let bundle = try? decoder.decode(ExportBundle.self, from: source) else {
            XCTFail("Export decoding failed; private values omitted")
            return
        }
        XCTAssertEqual(bundle.version, ExportBundle.currentVersion)
        XCTAssertEqual(Set(bundle.completedWorkouts.map(\.id)).count, bundle.completedWorkouts.count)
        XCTAssertEqual(Set(bundle.earnedPlates.map(\.id)).count, bundle.earnedPlates.count)
        try assertPreservesSource(source, encoded: encode(bundle))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let historyURL = root.appendingPathComponent("history")
        let storage = WorkoutStorage(directory: historyURL)
        try await storage.saveWorkouts(bundle.completedWorkouts, prIndex: [:])
        let reopenedHistory = WorkoutStorage(directory: historyURL)
        let loaded = try await reopenedHistory.loadWorkouts()
        XCTAssertTrue(loaded.workouts == bundle.completedWorkouts, "Workout values changed after reopening")

        let schema = Schema(versionedSchema: AppStoreSchema.self)
        let configuration = ModelConfiguration(schema: schema, url: root.appendingPathComponent("plates.store"))
        try autoreleasepool {
            let container = try ModelContainer(for: schema, migrationPlan: AppStoreMigration.self,
                                               configurations: configuration)
            for plate in bundle.earnedPlates {
                container.mainContext.insert(plate.toModel())
            }
            try container.mainContext.save()
        }
        let plates = try autoreleasepool {
            let reopened = try ModelContainer(for: schema, migrationPlan: AppStoreMigration.self,
                                              configurations: configuration)
            return try reopened.mainContext.fetch(FetchDescriptor<EarnedPlate>()).map(EarnedPlateExport.init)
        }
        XCTAssertEqual(plates.count, bundle.earnedPlates.count)
        let persisted = ExportBundle(version: bundle.version, appVersion: bundle.appVersion,
                                     exportedAt: bundle.exportedAt, completedWorkouts: loaded.workouts,
                                     earnedPlates: plates)
        try assertPreservesSource(source, encoded: encode(persisted))
        XCTAssertTrue(try Data(contentsOf: sourceURL) == source, "Source export must remain unchanged")
    }

    private func encode(_ bundle: ExportBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    private func assertPreservesSource(_ source: Data, encoded: Data) throws {
        let expected = try JSONSerialization.jsonObject(with: source)
        let actual = try JSONSerialization.jsonObject(with: encoded)
        assertPreserved(expected, in: actual, path: "export")
    }

    /// Check every supplied field, allowing new defaults and unordered plate/set collections.
    /// Failures report schema paths only, never private values or record identifiers.
    private func assertPreserved(_ expected: Any, in actual: Any?, path: String) {
        if expected is NSNull {
            XCTAssertTrue(actual == nil || actual is NSNull, "Changed null at \(path)")
        } else if let expected = expected as? [String: Any] {
            guard let actual = actual as? [String: Any] else {
                XCTFail("Missing object at \(path)"); return
            }
            for key in expected.keys.sorted() {
                assertPreserved(expected[key]!, in: actual[key], path: "\(path).\(key)")
            }
        } else if var expected = expected as? [Any] {
            guard var actual = actual as? [Any] else {
                XCTFail("Missing array at \(path)"); return
            }
            if path == "export.earnedPlates" {
                let byID: (Any, Any) -> Bool = {
                    (($0 as? [String: Any])?["id"] as? String ?? "") <
                    (($1 as? [String: Any])?["id"] as? String ?? "")
                }
                expected.sort(by: byID)
                actual.sort(by: byID)
            } else if path.hasSuffix(".excusedPlannedExerciseIDs") {
                expected = (expected as? [String] ?? []).sorted()
                actual = (actual as? [String] ?? []).sorted()
            }
            XCTAssertEqual(actual.count, expected.count, "Changed array size at \(path)")
            for (index, pair) in zip(expected, actual).enumerated() {
                assertPreserved(pair.0, in: pair.1, path: "\(path)[\(index)]")
            }
        } else {
            XCTAssertTrue((expected as? NSObject)?.isEqual(actual) == true, "Changed value at \(path)")
        }
    }
}
