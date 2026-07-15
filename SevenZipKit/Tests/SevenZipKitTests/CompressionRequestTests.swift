import Foundation
import XCTest
@testable import SevenZipKit

final class CompressionRequestTests: XCTestCase {

    private func request(sources: [String]) -> CompressionRequest {
        CompressionRequest(
            destinationURL: URL(fileURLWithPath: "/tmp/out.7z"),
            sourceURLs: sources.map { URL(fileURLWithPath: $0) }
        )
    }

    // Uses the common parent as the working directory
    func testCommonParent() {
        let r = request(sources: ["/Users/x/Documents/a.txt", "/Users/x/Documents/b/c.txt"])
        XCTAssertEqual(r.workingDirectory?.path, "/Users/x/Documents")
    }

    // Stores sources relative to the working directory
    func testRelativeSources() {
        let r = request(sources: ["/Users/x/Documents/a.txt", "/Users/x/Documents/b"])
        XCTAssertEqual(r.sourceArguments, ["a.txt", "b"])
    }

    // Single source is stored by its basename
    func testSingleSource() {
        let r = request(sources: ["/Users/x/Documents/report"])
        XCTAssertEqual(r.workingDirectory?.path, "/Users/x/Documents")
        XCTAssertEqual(r.sourceArguments, ["report"])
    }

    // Password and header encryption only apply to supporting formats
    func testFormatCapabilities() {
        XCTAssertTrue(ArchiveFormat.sevenZip.supportsPassword)
        XCTAssertTrue(ArchiveFormat.sevenZip.supportsEncryptedHeaders)
        XCTAssertTrue(ArchiveFormat.zip.supportsPassword)
        XCTAssertTrue(!ArchiveFormat.zip.supportsEncryptedHeaders)
        XCTAssertTrue(!ArchiveFormat.tar.supportsPassword)
    }

    // Compression levels map to -mx values
    func testLevels() {
        XCTAssertEqual(CompressionLevel.store.mxValue, 0)
        XCTAssertEqual(CompressionLevel.normal.mxValue, 5)
        XCTAssertEqual(CompressionLevel.ultra.mxValue, 9)
    }
}
