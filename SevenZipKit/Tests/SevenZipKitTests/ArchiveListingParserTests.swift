import Foundation
import XCTest
@testable import SevenZipKit

final class ArchiveListingParserTests: XCTestCase {

    private func loadFixture() throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "listing_slt", withExtension: "txt"),
            "fixture listing_slt.txt must be bundled with the tests"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    // Parses archive header properties
    func testParsesHeader() throws {
        let (properties, _) = try ArchiveListingParser.parse(loadFixture())
        XCTAssertEqual(properties.format, "7z")
        XCTAssertEqual(properties.physicalSize, 281)
        XCTAssertEqual(properties.headersSize, 225)
        XCTAssertEqual(properties.method, "LZMA2:6k")
        XCTAssertEqual(properties.isSolid, true)
        XCTAssertEqual(properties.blocks, 1)
    }

    // Parses the correct number of entries
    func testParsesEntryCount() throws {
        let (_, entries) = try ArchiveListingParser.parse(loadFixture())
        XCTAssertEqual(entries.count, 5)
    }

    // Distinguishes directories from files
    func testDetectsDirectories() throws {
        let (_, entries) = try ArchiveListingParser.parse(loadFixture())
        let directories = entries.filter(\.isDirectory).map(\.path)
        XCTAssertEqual(directories, ["sample", "sample/sub"])
        let files = entries.filter { !$0.isDirectory }.map(\.path)
        XCTAssertEqual(files, ["sample/a.txt", "sample/sub/big.dat", "sample/sub/c.log"])
    }

    // Parses sizes, CRC and method for a file entry
    func testParsesFileDetails() throws {
        let (_, entries) = try ArchiveListingParser.parse(loadFixture())
        let file = try XCTUnwrap(entries.first { $0.path == "sample/a.txt" })
        XCTAssertEqual(file.size, 12)
        XCTAssertEqual(file.packedSize, 56)
        XCTAssertEqual(file.crc, "AF083B2D")
        XCTAssertEqual(file.method, "LZMA2:6k")
        XCTAssertEqual(file.isEncrypted, false)
    }

    // Leaves packed size nil when the engine omits it
    func testParsesMissingPackedSize() throws {
        let (_, entries) = try ArchiveListingParser.parse(loadFixture())
        let file = try XCTUnwrap(entries.first { $0.path == "sample/sub/big.dat" })
        XCTAssertNil(file.packedSize)
        XCTAssertEqual(file.size, 5000)
    }

    // Parses the modified timestamp to whole-second precision
    func testParsesModifiedDate() throws {
        let (_, entries) = try ArchiveListingParser.parse(loadFixture())
        let file = try XCTUnwrap(entries.first { $0.path == "sample/a.txt" })
        let date = try XCTUnwrap(file.modified)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 8)
        XCTAssertEqual(components.second, 47)
    }

    // Derives name and parent path from the full path
    func testDerivesNameAndParent() throws {
        let (_, entries) = try ArchiveListingParser.parse(loadFixture())
        let file = try XCTUnwrap(entries.first { $0.path == "sample/sub/c.log" })
        XCTAssertEqual(file.name, "c.log")
        XCTAssertEqual(file.parentPath, "sample/sub")
    }

    // Throws when the entries section is missing
    func testThrowsOnMalformedOutput() {
        let garbage = "not a 7-zip listing at all\njust some text"
        XCTAssertThrowsError(try ArchiveListingParser.parse(garbage)) { error in
            XCTAssertTrue(error is ArchiveError)
        }
    }
}
