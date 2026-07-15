import Foundation
import XCTest
@testable import SevenZipKit

final class BenchmarkParserTests: XCTestCase {

    private func loadFixture() throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "benchmark", withExtension: "txt"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // Parses machine info
    func testMachineInfo() throws {
        let r = BenchmarkParser.parse(try loadFixture())
        XCTAssertEqual(r.cpuModel, "Apple M4 10C10T")
        XCTAssertEqual(r.ramSizeMB, 16384)
        XCTAssertEqual(r.benchmarkThreads, 2)
    }

    // Parses the average compress/decompress figures
    func testAverages() throws {
        let r = BenchmarkParser.parse(try loadFixture())
        XCTAssertEqual(r.compressSpeedKiBs, 26593)
        XCTAssertEqual(r.compressRatingMIPS, 27875)
        XCTAssertEqual(r.decompressSpeedKiBs, 234177)
        XCTAssertEqual(r.decompressRatingMIPS, 20410)
    }

    // Parses the total rating
    func testTotal() throws {
        let r = BenchmarkParser.parse(try loadFixture())
        XCTAssertEqual(r.totalRatingMIPS, 24143)
    }

    // Parses per-dictionary rows
    func testRows() throws {
        let r = BenchmarkParser.parse(try loadFixture())
        XCTAssertEqual(r.rows.count, 4)
        let first = try XCTUnwrap(r.rows.first)
        XCTAssertEqual(first.dictionary, 22)
        XCTAssertEqual(first.compressSpeedKiBs, 28472)
        XCTAssertEqual(first.compressRatingMIPS, 27698)
        XCTAssertEqual(first.decompressSpeedKiBs, 238919)
        XCTAssertEqual(first.decompressRatingMIPS, 20399)
    }
}
