import XCTest
import Foundation
@testable import SevenZipKit

final class ResilientCopyTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "7zk-rc-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testAFileIsCopiedWholeWithItsDate() throws {
        let source = dir.appending(path: "a.bin")
        let payload = Data((0..<9_000_000).map { UInt8($0 & 0xFF) })   // more than one 4 MB piece
        try payload.write(to: source)
        let date = Date(timeIntervalSince1970: 1_500_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: source.path)
        let destination = dir.appending(path: "b.bin")
        try ResilientCopy.copyContentsOnly(at: source, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), payload)
        let copiedDate = try destination.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        XCTAssertEqual(copiedDate, date)
    }

    func testAFolderTreeAndASymlinkAreCopied() throws {
        let source = dir.appending(path: "src", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source.appending(path: "sub/deep"), withIntermediateDirectories: true)
        try "one".write(to: source.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: source.appending(path: "sub/deep/b.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: source.appending(path: "link").path, withDestinationPath: "a.txt")
        let destination = dir.appending(path: "dst", directoryHint: .isDirectory)
        try ResilientCopy.copyContentsOnly(at: source, to: destination)
        XCTAssertEqual(try String(contentsOf: destination.appending(path: "sub/deep/b.txt"), encoding: .utf8), "two")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination.appending(path: "link").path), "a.txt")
    }

    func testThePublicEntryPointCopiesLikeCopyItemWhenNothingGoesWrong() throws {
        let source = dir.appending(path: "a.txt")
        try "hello".write(to: source, atomically: true, encoding: .utf8)
        let destination = dir.appending(path: "b.txt")
        try ResilientCopy.copyItem(at: source, to: destination)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "hello")
    }

    func testAMissingSourceFailsAndLeavesNothingAtTheDestination() {
        let destination = dir.appending(path: "b.txt")
        XCTAssertThrowsError(try ResilientCopy.copyItem(at: dir.appending(path: "nope"), to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}
