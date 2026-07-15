import Foundation
import XCTest
@testable import SevenZipKit

/// A fake bridge that returns canned data, so the service can be tested
/// without a real engine or filesystem.
private struct FakeBridge: SevenZipBridge {
    let properties: ArchiveProperties
    let entries: [ArchiveEntry]
    let error: ArchiveError?

    init(
        properties: ArchiveProperties = .unknown,
        entries: [ArchiveEntry] = [],
        error: ArchiveError? = nil
    ) {
        self.properties = properties
        self.entries = entries
        self.error = error
    }

    func list(archiveAt url: URL, password: String?) async throws -> (ArchiveProperties, [ArchiveEntry]) {
        if let error { throw error }
        return (properties, entries)
    }

    func extract(
        _ request: ExtractionRequest,
        progress: @escaping @Sendable (ProgressInfo) -> Void
    ) async throws {
        if let error { throw error }
        progress(ProgressInfo(
            fractionCompleted: 1, processedBytes: request.totalUncompressedSize,
            totalBytes: request.totalUncompressedSize, bytesPerSecond: 0,
            estimatedTimeRemaining: 0, currentFile: nil
        ))
    }

    func compress(
        _ request: CompressionRequest,
        progress: @escaping @Sendable (ProgressInfo) -> Void
    ) async throws {
        if let error { throw error }
        progress(ProgressInfo(
            fractionCompleted: 1, processedBytes: request.totalSourceSize,
            totalBytes: request.totalSourceSize, bytesPerSecond: 0,
            estimatedTimeRemaining: 0, currentFile: nil
        ))
    }

    func benchmark(passes: Int?) async throws -> BenchmarkResult {
        if let error { throw error }
        return BenchmarkResult(totalRatingMIPS: 12345)
    }

    func test(archiveAt url: URL, selectedPaths: [String], password: String?) async throws -> Bool {
        if let error { throw error }
        return true
    }

    func delete(archiveAt url: URL, paths: [String], password: String?) async throws {
        if let error { throw error }
    }

    func rename(archiveAt url: URL, from oldPath: String, to newPath: String, password: String?) async throws {
        if let error { throw error }
    }
}

final class ArchiveServiceTests: XCTestCase {

    private func entry(_ path: String, dir: Bool, size: UInt64) -> ArchiveEntry {
        ArchiveEntry(
            path: path, isDirectory: dir, size: size, packedSize: nil,
            modified: nil, crc: nil, isEncrypted: false, method: nil, attributes: nil
        )
    }

    // Assembles an Archive from the bridge output
    func testBuildsArchive() async throws {
        let bridge = FakeBridge(
            properties: ArchiveProperties(
                format: "7z", physicalSize: 281, headersSize: 225,
                method: "LZMA2:6k", isSolid: true, blocks: 1
            ),
            entries: [
                entry("dir", dir: true, size: 0),
                entry("dir/a.txt", dir: false, size: 100),
                entry("dir/b.txt", dir: false, size: 250)
            ]
        )
        let service = ArchiveService(bridge: bridge)
        let archive = try await service.open(archiveAt: URL(fileURLWithPath: "/tmp/x.7z"))

        XCTAssertEqual(archive.properties.format, "7z")
        XCTAssertEqual(archive.entries.count, 3)
        XCTAssertEqual(archive.fileCount, 2)
        XCTAssertEqual(archive.folderCount, 1)
        XCTAssertEqual(archive.totalSize, 350)
    }

    // Propagates a wrong-password error
    func testPropagatesWrongPassword() async {
        let bridge = FakeBridge(error: .wrongPassword)
        let service = ArchiveService(bridge: bridge)
        await XCTAssertThrowsErrorAsync(try await service.open(archiveAt: URL(fileURLWithPath: "/tmp/x.7z"))) { error in
            XCTAssertEqual(error as? ArchiveError, .wrongPassword)
        }
    }
}

/// Small async-aware helper mirroring `XCTAssertThrowsError` for `async throws` expressions.
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (_ error: Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail(message().isEmpty ? "Expected expression to throw an error" : message(), file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
