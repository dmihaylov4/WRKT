import XCTest
@testable import WRKT

/// The history files are replaced through `DurableFileWriter`: a temporary file beside the
/// target, written and synchronized, renamed over it, then the directory synchronized. A failure
/// anywhere leaves the old whole file and throws; a barrier flushes the device.
final class DurableFileWriterTests: XCTestCase {
    private var directory: URL!
    private var target: URL { directory.appendingPathComponent("runs_v2.json") }
    private let fileSystem = RecordingDurableFileSystem()
    private var writer: DurableFileWriter { DurableFileWriter(fileSystem: fileSystem) }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private func fileNumber(_ url: URL) throws -> Int {
        try XCTUnwrap((FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber)?.intValue)
    }

    func testWritesInOrderAndReplacesTheTarget() throws {
        try Data("old".utf8).write(to: target)
        try writer.write(Data("new".utf8), to: target, protection: .completeUntilFirstUserAuthentication)

        XCTAssertEqual(fileSystem.calls, [.createExclusive, .setProtection, .write, .synchronize, .close,
                                          .rename, .synchronizeDirectory])
        XCTAssertEqual(try Data(contentsOf: target), Data("new".utf8))
        XCTAssertEqual(try names(), ["runs_v2.json"])
        // The temporary file is created beside the target and renamed onto it.
        let created = try XCTUnwrap(fileSystem.callsWithNames.first)
        XCTAssertTrue(DurableFileWriter.isTemporaryName(String(created.dropFirst("createExclusive ".count)), for: "runs_v2.json"))
        XCTAssertEqual(fileSystem.callsWithNames[5], "rename runs_v2.json")
    }

    func testWithoutProtectionSkipsSettingIt() throws {
        try writer.write(Data("new".utf8), to: target, protection: nil)
        XCTAssertFalse(fileSystem.calls.contains(.setProtection))
    }

    func testEveryWriteCreatesANewFileNumber() throws {
        try writer.write(Data("one".utf8), to: target, protection: nil)
        let first = try fileNumber(target)
        try writer.write(Data("one".utf8), to: target, protection: nil)
        XCTAssertNotEqual(try fileNumber(target), first, "FileStamp tells versions apart by file number")
    }

    func testCreatesTheTargetWhenItDoesNotExist() throws {
        try writer.write(Data("first".utf8), to: target, protection: .completeUntilFirstUserAuthentication)
        XCTAssertEqual(try Data(contentsOf: target), Data("first".utf8))
        let permissions = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue, 0o644, "the same permissions an atomic Data write gives")
    }

    func testAFailureBeforeTheRenameKeepsTheOldFileAndLeavesNoTemporaryFile() throws {
        for call: RecordingDurableFileSystem.Call in [.createExclusive, .write, .synchronize, .close, .rename] {
            try Data("old".utf8).write(to: target)
            fileSystem.fail(call)
            XCTAssertThrowsError(try writer.write(Data("new".utf8), to: target, protection: nil), "\(call)")
            XCTAssertEqual(try Data(contentsOf: target), Data("old".utf8), "\(call)")
            XCTAssertEqual(try names(), ["runs_v2.json"], "\(call)")
        }
    }

    func testAFailureBeforeTheRenameLeavesNoFileWhenThereWasNone() throws {
        fileSystem.fail(.synchronize)
        XCTAssertThrowsError(try writer.write(Data("new".utf8), to: target, protection: nil))
        XCTAssertEqual(try names(), [])
    }

    func testAFailedDirectorySyncThrowsWithTheNewFileInPlace() throws {
        try Data("old".utf8).write(to: target)
        fileSystem.fail(.synchronizeDirectory)
        XCTAssertThrowsError(try writer.write(Data("new".utf8), to: target, protection: nil))
        // The rename happened, but the write is reported as failed, so the caller stays unsaved
        // and writes again.
        XCTAssertEqual(try Data(contentsOf: target), Data("new".utf8))
        XCTAssertEqual(try names(), ["runs_v2.json"])
    }

    func testAProtectionClassThatCannotBeSetDoesNotFailTheWrite() throws {
        fileSystem.fail(.setProtection)
        try writer.write(Data("new".utf8), to: target, protection: .completeUntilFirstUserAuthentication)
        XCTAssertEqual(try Data(contentsOf: target), Data("new".utf8))
    }

    func testAWriteOntoADirectoryFailsWithoutLeftovers() throws {
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        XCTAssertThrowsError(try writer.write(Data("new".utf8), to: target, protection: nil))
        XCTAssertEqual(try names(), ["runs_v2.json"])
    }

    func testBarrierFlushesTheDeviceAndReportsFailure() throws {
        try writer.barrier(at: directory)
        XCTAssertEqual(fileSystem.calls, [.flushDevice])
        fileSystem.fail(.flushDevice)
        XCTAssertThrowsError(try writer.barrier(at: directory))
    }

    func testRealBarrierSucceedsOnThisVolume() throws {
        try DurableFileWriter().barrier(at: directory)
    }

    // MARK: - Temporary names

    func testWriterTemporaryNames() {
        let token = UUID()
        let name = DurableFileWriter.temporaryName(for: "runs_v2.json", token: token)
        XCTAssertEqual(name, "runs_v2.json.wrkt-\(token.uuidString.lowercased()).tmp")
        XCTAssertTrue(DurableFileWriter.isTemporaryName(name, for: "runs_v2.json"))
        let misses = [
            "runs_v2.json",
            "runs_v2.json.wrkt-\(token.uuidString).tmp",                    // uppercase
            "runs_v2.json.wrkt-\(token.uuidString.lowercased()).tmp.bak",
            "runs_v2.json.wrkt-\(token.uuidString.lowercased()).TMP",
            "runs_v2.json.wrkt-not-a-uuid.tmp",
            "runs_v2.json.wrkt-.tmp",
            "x_runs_v2.json.wrkt-\(token.uuidString.lowercased()).tmp",
            "workouts_v2.json.wrkt-\(token.uuidString.lowercased()).tmp",   // another file's
        ]
        for miss in misses { XCTAssertFalse(DurableFileWriter.isTemporaryName(miss, for: "runs_v2.json"), miss) }
    }

    func testSystemAtomicWriteNames() {
        XCTAssertTrue(DurableFileWriter.isSystemAtomicWriteName("runs_v2.json.sb-44c8b3bc-DkKNDb", for: "runs_v2.json"))
        XCTAssertTrue(DurableFileWriter.isSystemAtomicWriteName("runs_v2.json.sb-0123abcd-0a9Z8y", for: "runs_v2.json"))
        let misses = [
            "runs_v2.json",
            "runs_v2.json.sb-44c8b3bc-DkKND",       // too short
            "runs_v2.json.sb-44c8b3bc-DkKNDbb",     // too long
            "runs_v2.json.sb-44C8B3BC-DkKNDb",      // uppercase hex
            "runs_v2.json.sb-44c8b3bg-DkKNDb",      // not hex
            "runs_v2.json.sb-44c8b3bc_DkKNDb",
            "runs_v2.json.sb-44c8b3bc-DkK.Db",
            "runs_v2.json.sb-44c8b3bc-DkKNDb.json",
            "RUNS_V2.json.sb-44c8b3bc-DkKNDb",      // different case
            "custom_exercises.json.sb-44c8b3bc-DkKNDb",
            "runs_v2.json.SB-44c8b3bc-DkKNDb",
        ]
        for miss in misses { XCTAssertFalse(DurableFileWriter.isSystemAtomicWriteName(miss, for: "runs_v2.json"), miss) }
    }

    /// What Foundation's atomic write leaves on this platform when it is interrupted: the
    /// temporary file it writes before the rename must match the pattern the cleanup removes.
    func testFoundationAtomicWriteTemporaryFileMatchesThePattern() throws {
        let big = Data(repeating: 7, count: 64_000_000)
        let target = self.target
        let writing = Thread {
            for _ in 0..<4 { try? big.write(to: target, options: .atomic) }
        }
        writing.start()
        var seen: Set<String> = []
        let deadline = Date().addingTimeInterval(10)
        while !writing.isFinished, Date() < deadline {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] { seen.insert(name) }
        }
        while !writing.isFinished { Thread.sleep(forTimeInterval: 0.01) }
        let temporary = seen.subtracting(["runs_v2.json"])
        XCTAssertFalse(temporary.isEmpty, "did not observe the temporary file")
        for name in temporary {
            XCTAssertTrue(DurableFileWriter.isSystemAtomicWriteName(name, for: "runs_v2.json"), name)
        }
    }
}
