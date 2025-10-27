//
//  WRKTTestCase.swift
//  WRKTTests
//
//  Base test case with common utilities and helpers
//

import XCTest
@testable import WRKT

class WRKTTestCase: XCTestCase {

    // MARK: - Lifecycle

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Async Test Helpers

    /// Helper to test async throwing functions
    func assertAsyncNoThrow<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> T? {
        do {
            return try await expression()
        } catch {
            XCTFail("Unexpected error thrown: \(error) - \(message())", file: file, line: line)
            return nil
        }
    }

    /// Helper to assert async throwing functions throw expected error
    func assertAsyncThrows<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        errorHandler: ((Error) -> Void)? = nil
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error to be thrown - \(message())", file: file, line: line)
        } catch {
            errorHandler?(error)
        }
    }

    // MARK: - Date Helpers

    /// Create date from components for consistent testing
    func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: "UTC")

        return Calendar.current.date(from: components)!
    }

    /// Assert dates are equal within tolerance
    func assertDatesEqual(
        _ date1: Date?,
        _ date2: Date?,
        tolerance: TimeInterval = 1.0,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let date1 = date1, let date2 = date2 else {
            if date1 == nil && date2 == nil {
                return // Both nil is ok
            }
            XCTFail("One date is nil - \(message())", file: file, line: line)
            return
        }

        let diff = abs(date1.timeIntervalSince(date2))
        XCTAssertLessThanOrEqual(
            diff,
            tolerance,
            "Dates differ by \(diff) seconds - \(message())",
            file: file,
            line: line
        )
    }

    // MARK: - Temporary Directory Helpers

    /// Create temporary directory for test file operations
    func makeTemporaryDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try? FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )

        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }

        return tempDir
    }

    // MARK: - JSON Helpers

    /// Encode and decode for testing Codable conformance
    func assertCodable<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(T.self, from: data)
            XCTAssertEqual(value, decoded, file: file, line: line)
        } catch {
            XCTFail("Codable test failed: \(error)", file: file, line: line)
        }
    }
}
