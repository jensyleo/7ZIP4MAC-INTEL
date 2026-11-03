import XCTest
import Foundation
@testable import SevenZipKit

private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ProgressInfo] = []
    func add(_ info: ProgressInfo) { lock.lock(); values.append(info); lock.unlock() }
    var all: [ProgressInfo] { lock.lock(); defer { lock.unlock() }; return values }
}

final class DeleteProgressTests: XCTestCase {
    func testReadsTheRewriteAndTheMoveStretchesOf7ZipOutput() {
        XCTAssertEqual(DeleteProgressState.parse("  42%"), .init(rewrite: 42, move: nil, file: nil))
        XCTAssertEqual(
            DeleteProgressState.parse("100%  : 37% : 40 MiB / 107 MiB : temporary archive moving ... src/f9.bin"),
            .init(rewrite: 100, move: 37, file: "src/f9.bin"))
        XCTAssertEqual(
            DeleteProgressState.parse("100%  : 0% : 0 MiB / 107 MiB : temporary archive moving ..."),
            .init(rewrite: 100, move: 0, file: nil))
        XCTAssertNil(DeleteProgressState.parse("Updating archive: x.zip"))
        XCTAssertNil(DeleteProgressState.parse(""))
    }

    func testTheFractionOnlyGrowsAcrossStretchesAndBatches() {
        let seen = Collector()
        let state = DeleteProgressState(archiveSize: 1_000_000, batches: 2, report: seen.add)
        state.startBatch(0)
        state.consume("  10%\r  60%\r 100%  : 0% : 0 MiB / 1 MiB : temporary archive moving ...\r100%  : 50% : 0 MiB / 1 MiB : temporary archive moving ...\r")
        state.consume("  5%\r")     // a stray lower value must not move the bar back
        state.finishBatch()
        state.startBatch(1)
        state.consume("  20%\r")
        state.finishBatch()
        let fractions = seen.all.map(\.fractionCompleted)
        XCTAssertEqual(fractions, fractions.sorted())
        XCTAssertEqual(fractions.last, 1.0)
        XCTAssertTrue(fractions.contains { $0 > 0.4 && $0 < 0.6 }, "the first batch ends at one half")
    }

    func testAChunkThatSplitsALineInTwoIsStillRead() {
        let seen = Collector()
        let state = DeleteProgressState(archiveSize: 100, batches: 1, report: seen.add)
        state.startBatch(0)
        state.consume("  4")
        state.consume("0%\r")
        XCTAssertTrue(seen.all.contains { abs($0.fractionCompleted - 0.2) < 0.001 })
    }
}

final class DeleteProgressEngineTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(SevenZipEngine.isAvailable, "7zz not bundled")
    }

    func testARealDeleteReportsProgressThatEndsAt100PercentAndRemovesTheEntries() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "7zk-delp-\(UUID().uuidString)", directoryHint: .isDirectory)
        let root = dir.appending(path: "root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<5 { try Data(count: 200_000 + i).write(to: root.appending(path: "f\(i).bin")) }
        let archive = dir.appending(path: "x.7z")
        let service = ArchiveService(executable: try SevenZipExecutable(validatingURL: SevenZipEngine.url))
        try await service.compress(
            CompressionRequest(destinationURL: archive, sourceURLs: [root], format: .sevenZip, level: .fast),
            progress: { _ in }
        )
        let seen = Collector()
        try await service.delete(archiveAt: archive, paths: ["root/f0.bin", "root/f1.bin"], password: nil, progress: seen.add)
        let fractions = seen.all.map(\.fractionCompleted)
        XCTAssertFalse(fractions.isEmpty)
        XCTAssertEqual(fractions, fractions.sorted())
        XCTAssertEqual(fractions.last, 1.0)
        let names = try await service.open(archiveAt: archive, password: nil).entries.map(\.path)
        XCTAssertFalse(names.contains("root/f0.bin"))
        XCTAssertTrue(names.contains("root/f2.bin"))
    }
}
