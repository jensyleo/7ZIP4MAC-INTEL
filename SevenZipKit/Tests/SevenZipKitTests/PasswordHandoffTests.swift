import XCTest
import Foundation
@testable import SevenZipKit

final class PasswordHandoffTests: XCTestCase {
    func testSecretStaysOffTheCommandLine() {
        let opening = PasswordHandoff("hunter2 ñ'\"$x")
        XCTAssertNil(opening.argument)
        XCTAssertEqual(opening.input, "hunter2 ñ'\"$x\n")
        let creating = PasswordHandoff("pw", creating: true)
        XCTAssertEqual(creating.argument, "-p")
        XCTAssertEqual(creating.input, "pw\npw\n")
    }

    func testUnusablePasswordsFallBackToTheArgumentForm() {
        XCTAssertNil(PasswordHandoff("").input)
        XCTAssertEqual(PasswordHandoff("").argument, "-p")
        XCTAssertNil(PasswordHandoff("a\nb").input)
        XCTAssertEqual(PasswordHandoff("a\nb").argument, "-pa\nb")
        XCTAssertNil(PasswordHandoff(String(repeating: "x", count: 1001)).input)
    }
}

/// Real 7-Zip, password supplied only through the terminal input.
final class PasswordHandoffEngineTests: XCTestCase {
    private let fm = FileManager.default

    override func setUpWithError() throws {
        try XCTSkipUnless(SevenZipEngine.isAvailable, "7zz not bundled")
    }

    private func service() throws -> ArchiveService {
        ArchiveService(executable: try SevenZipExecutable(validatingURL: SevenZipEngine.url))
    }

    private func workspace() throws -> URL {
        let base = fm.temporaryDirectory.appending(path: "7zk-pw-\(UUID().uuidString)", directoryHint: .isDirectory)
        let root = base.appending(path: "root", directoryHint: .isDirectory)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try "alpha".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try "beta".write(to: root.appending(path: "b.txt"), atomically: true, encoding: .utf8)
        return base
    }

    private func assertThrowsWrongPassword(_ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected wrongPassword", file: file, line: line)
        } catch ArchiveError.wrongPassword {
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }

    func testFullCycleWithAPassword() async throws {
        for (format, encryptNames) in [(ArchiveFormat.sevenZip, true), (.sevenZip, false), (.zip, false)] {
            let base = try workspace()
            defer { try? fm.removeItem(at: base) }
            let password = "p ss'\"w0rd $1"
            let archive = base.appending(path: "x.\(format.fileExtension)")
            let svc = try service()

            try await svc.compress(
                CompressionRequest(destinationURL: archive, sourceURLs: [base.appending(path: "root")],
                                   format: format, level: .fast, password: password,
                                   encryptFileNames: encryptNames),
                progress: { _ in }
            )

            let opened = try await svc.open(archiveAt: archive, password: password)
            XCTAssertEqual(opened.fileCount, 2)
            if encryptNames {
                await assertThrowsWrongPassword { _ = try await svc.open(archiveAt: archive, password: "nope") }
            }

            let passed = try await svc.test(archiveAt: archive, selectedPaths: [], password: password)
            XCTAssertTrue(passed)
            await assertThrowsWrongPassword { _ = try await svc.test(archiveAt: archive, selectedPaths: [], password: "nope") }

            let out = base.appending(path: "out", directoryHint: .isDirectory)
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            try await svc.extract(
                ExtractionRequest(archiveURL: archive, destinationURL: out, password: password, selectedPaths: []),
                progress: { _ in }
            )
            XCTAssertEqual(try String(contentsOf: out.appending(path: "root/b.txt"), encoding: .utf8), "beta")

            try await svc.rename(archiveAt: archive, from: "root/a.txt", to: "root/z.txt", password: password)
            try await svc.delete(archiveAt: archive, paths: ["root/b.txt"], password: password)
            let after = try await svc.open(archiveAt: archive, password: password)
            XCTAssertTrue(after.entries.map(\.path).contains("root/z.txt"))
            XCTAssertFalse(after.entries.map(\.path).contains("root/b.txt"))
        }
    }
}

/// A tiny file that unpacks to far more than the disk can take must be refused.
final class UnpackedTooLargeTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(SevenZipEngine.isAvailable, "7zz not bundled")
    }

    private func makeGzip(megabytes: Int, in dir: URL) throws -> URL {
        let raw = dir.appending(path: "zeros.bin")
        try Data(count: megabytes << 20).write(to: raw)
        let gz = dir.appending(path: "zeros.bin.gz")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        p.arguments = ["-k", "-f", raw.path]
        try p.run(); p.waitUntilExit()
        try FileManager.default.removeItem(at: raw)
        return gz
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "7zk-bomb-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testASingleStreamArchiveThatOutgrowsTheLimitIsNotOpened() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gz = try makeGzip(megabytes: 200, in: dir)
        let service = ArchiveService(
            bridge: SystemSevenZipBridge(executable: try SevenZipExecutable(validatingURL: SevenZipEngine.url)),
            unwrapLimit: 1 << 20
        )
        do {
            _ = try await service.open(archiveAt: gz, password: nil)
            XCTFail("a decompression bomb must be refused")
        } catch ArchiveError.unpackedTooLarge {
        }
    }

    func testWithinTheLimitItOpensAsBefore() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gz = try makeGzip(megabytes: 2, in: dir)
        let service = ArchiveService(
            bridge: SystemSevenZipBridge(executable: try SevenZipExecutable(validatingURL: SevenZipEngine.url))
        )
        let archive = try await service.open(archiveAt: gz, password: nil)
        XCTAssertEqual(archive.entries.count, 1)
    }

    func testTheDefaultLimitLeavesRoomOnTheDisk() {
        XCTAssertGreaterThanOrEqual(ArchiveService.defaultUnwrapLimit(for: FileManager.default.temporaryDirectory), 256 << 20)
    }
}

/// The fallback engine's password never reaches its command line.
final class RarFallbackPasswordTests: XCTestCase {
    func testPasswordGoesOnStdinNotTheCommandLine() {
        XCTAssertEqual(RarFallbackEngine.passwordArguments("s3cret"), ["-password-stdin"])
        XCTAssertEqual(RarFallbackEngine.passwordInput(for: "s3cret"), "s3cret\n")
        XCTAssertEqual(RarFallbackEngine.passwordArguments(nil), [])
        XCTAssertEqual(RarFallbackEngine.passwordArguments(""), [])
        XCTAssertNil(RarFallbackEngine.passwordInput(for: ""))
    }

    func testAPasswordWithALineBreakKeepsTheOldForm() {
        XCTAssertEqual(RarFallbackEngine.passwordArguments("a\nb"), ["-p", "a\nb"])
        XCTAssertNil(RarFallbackEngine.passwordInput(for: "a\nb"))
    }

    func testExtractionArgumentsCarryNoSecret() {
        var request = ExtractionRequest(
            archiveURL: URL(fileURLWithPath: "/tmp/x.part01.rar"),
            destinationURL: URL(fileURLWithPath: "/tmp/out"), password: "s3cret", selectedPaths: []
        )
        request.overwritePolicy = .overwrite
        let arguments = RarFallbackEngine.extractionArguments(for: request)
        XCTAssertTrue(arguments.contains("-password-stdin"))
        XCTAssertFalse(arguments.contains("s3cret"))
    }

    /// Real `unar`/`lsar` from the app bundle: list, test and extract an encrypted
    /// archive with the password on stdin only (ZIP, since no RAR can be made here).
    func testBundledToolsAcceptThePasswordOnStdin() async throws {
        let engineDir = SevenZipEngine.url.deletingLastPathComponent()
        let lsar = engineDir.appendingPathComponent("lsar"), unar = engineDir.appendingPathComponent("unar")
        guard FileManager.default.isExecutableFile(atPath: unar.path) else { throw XCTSkip("bundled unar not found") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("7zk-unarpw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("root"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "alpha".write(to: dir.appendingPathComponent("root/a.txt"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("p.zip")
        let password = "p ss'\"w0rd $1"
        let service = ArchiveService(executable: try SevenZipExecutable(validatingURL: SevenZipEngine.url))
        try await service.compress(
            CompressionRequest(destinationURL: zip, sourceURLs: [dir.appendingPathComponent("root")],
                               format: .zip, level: .fast, password: password),
            progress: { _ in }
        )

        let engine = RarFallbackEngine(
            lister: try SevenZipExecutable(validatingURL: lsar), extractor: try SevenZipExecutable(validatingURL: unar)
        )
        let (_, entries) = try await engine.list(archiveAt: zip, password: password)
        XCTAssertFalse(entries.isEmpty)
        try await engine.test(archiveAt: zip, selectedPaths: [], password: password)
        let out = dir.appendingPathComponent("out")
        try await engine.extract(
            ExtractionRequest(archiveURL: zip, destinationURL: out, password: password, selectedPaths: []),
            progress: { _ in }
        )
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("root/a.txt"), encoding: .utf8), "alpha")
        // Wrong password must fail, not hang waiting for input.
        do {
            try await engine.test(archiveAt: zip, selectedPaths: [], password: "wrong")
            XCTFail("a wrong password must not pass")
        } catch {}
    }
}
