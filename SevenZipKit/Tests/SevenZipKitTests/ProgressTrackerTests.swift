import Foundation
import XCTest
@testable import SevenZipKit

final class ProgressTrackerTests: XCTestCase {

    // Computes fraction and processed bytes from percent
    func testComputesProcessedBytes() {
        var tracker = ProgressTracker(totalBytes: 1000)
        let info = tracker.update(percent: 25, now: 0, currentFile: nil)
        XCTAssertEqual(info.fractionCompleted, 0.25)
        XCTAssertEqual(info.processedBytes, 250)
        XCTAssertEqual(info.totalBytes, 1000)
    }

    // Estimates throughput and ETA across samples
    func testEstimatesThroughputAndETA() throws {
        var tracker = ProgressTracker(totalBytes: 1000)
        _ = tracker.update(percent: 0, now: 0, currentFile: nil)
        // At t=1s, 50% => 500 bytes in 1s => 500 B/s.
        let mid = tracker.update(percent: 50, now: 1, currentFile: nil)
        XCTAssertTrue(mid.bytesPerSecond > 0)
        // Remaining 500 bytes at ~500 B/s => ~1s ETA (order of magnitude).
        let eta = try XCTUnwrap(mid.estimatedTimeRemaining)
        XCTAssertTrue(eta > 0)
    }

    // Reports nil ETA at completion
    func testNilETAAtCompletion() {
        var tracker = ProgressTracker(totalBytes: 1000)
        _ = tracker.update(percent: 0, now: 0, currentFile: nil)
        let done = tracker.update(percent: 100, now: 2, currentFile: nil)
        XCTAssertEqual(done.fractionCompleted, 1.0)
        XCTAssertNil(done.estimatedTimeRemaining)
    }

    // Passes through the current file name
    func testPassesCurrentFile() {
        var tracker = ProgressTracker(totalBytes: 0)
        let info = tracker.update(percent: 10, now: 0, currentFile: "x/y.bin")
        XCTAssertEqual(info.currentFile, "x/y.bin")
        // With unknown total, byte-based estimates stay zero.
        XCTAssertEqual(info.processedBytes, 0)
    }
}
