import Foundation
import XCTest
@testable import SevenZipKit

final class ProgressParserTests: XCTestCase {

    // Parses a plain percentage token
    func testParsesPercent() {
        var parser = ProgressParser()
        let lines = parser.consume("  42%\u{08}\u{08}\u{08}\u{08}")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.percent, 42)
        XCTAssertNil(lines.first?.currentFile)
    }

    // Parses percentage with a current file
    func testParsesPercentWithFile() {
        var parser = ProgressParser()
        let lines = parser.consume(" 73% 7 - folder/sub/file.bin\u{08}\u{08}")
        XCTAssertEqual(lines.first?.percent, 73)
        XCTAssertEqual(lines.first?.currentFile, "folder/sub/file.bin")
    }

    // Parses the '+' separator used while compressing
    func testParsesCompressionFile() {
        var parser = ProgressParser()
        let lines = parser.consume(" 50% 20 + ctest/docs/f_28.txt\u{08}")
        XCTAssertEqual(lines.first?.percent, 50)
        XCTAssertEqual(lines.first?.currentFile, "ctest/docs/f_28.txt")
    }

    // Handles carriage-return redraws
    func testHandlesCarriageReturn() {
        var parser = ProgressParser()
        let lines = parser.consume(" 10%\r 20%\r 30%\r")
        XCTAssertEqual(lines.map(\.percent), [10, 20, 30])
    }

    // Joins a token split across two chunks
    func testJoinsSplitToken() {
        var parser = ProgressParser()
        let first = parser.consume(" 5")
        XCTAssertTrue(first.isEmpty)
        let second = parser.consume("5% 2 - a.txt\u{08}")
        XCTAssertEqual(second.first?.percent, 55)
        XCTAssertEqual(second.first?.currentFile, "a.txt")
    }

    // Ignores non-progress lines
    func testIgnoresNoise() {
        var parser = ProgressParser()
        let lines = parser.consume("Extracting archive: big.7z\nEverything is Ok\n")
        XCTAssertTrue(lines.isEmpty)
    }

    // Clamps out-of-range percentages
    func testClampsRange() {
        XCTAssertEqual(ProgressParser.parse("150%")?.percent, 100)
    }
}
