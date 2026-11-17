import Foundation
import XCTest
@testable import SevenZipKit

final class ProgressOrderingTests: XCTestCase {
    private func info(_ fraction: Double) -> ProgressInfo {
        ProgressInfo(fractionCompleted: fraction, processedBytes: 0, totalBytes: 0, bytesPerSecond: 0, estimatedTimeRemaining: nil, currentFile: nil)
    }

    func test_advancing() {
        XCTAssertNotNil(info(0.4).advancing(from: nil))
        XCTAssertNil(info(0.4).advancing(from: info(0.5)))
        XCTAssertNotNil(info(0.5).advancing(from: info(0.5)))
        XCTAssertEqual(info(0.6).advancing(from: info(0.5))?.fractionCompleted, 0.6)
    }

    func test_scaling() {
        XCTAssertEqual(info(0).scaled(into: 0, 0.5).fractionCompleted, 0)
        XCTAssertEqual(info(1).scaled(into: 0, 0.5).fractionCompleted, 0.5)
        XCTAssertEqual(info(0).scaled(into: 0.5, 1).fractionCompleted, 0.5)
        XCTAssertEqual(info(0.5).scaled(into: 0.5, 1).fractionCompleted, 0.75)
        XCTAssertEqual(info(1.7).scaled(into: 0.5, 1).fractionCompleted, 1)
    }

    func test_trackerIsMonotonic() {
        var tracker = ProgressTracker(totalBytes: 1_000_000)
        var last = 0.0
        for (i, percent) in [10, 40, 35, 60, 20, 100, 90].enumerated() {
            let value = tracker.update(percent: percent, now: Double(i), currentFile: nil).fractionCompleted
            XCTAssertTrue(value >= last)
            last = value
        }
        XCTAssertEqual(last, 1.0)
    }
}

final class AggregatorExpectedTotalTests: XCTestCase {
    func test_steadyTotal() {
        var aggregator = ProgressAggregator()
        let ids = (0..<10).map { _ in UUID() }
        for id in ids { aggregator.register(id, phases: 2, expectedTotal: 1_000) }
        XCTAssertEqual(aggregator.snapshot().total, 20_000)
        XCTAssertEqual(aggregator.snapshot().fraction, 0)

        var seen: [Double] = []
        for (index, id) in ids.enumerated() {
            aggregator.update(id, processed: 500, total: 1_000)
            seen.append(aggregator.snapshot().fraction)
            aggregator.update(id, processed: 1_000, total: 1_000)
            aggregator.startNextPhase(id)
            aggregator.update(id, processed: 1_000, total: 1_000)
            aggregator.finish(id)
            let fraction = aggregator.snapshot().fraction
            seen.append(fraction)
            XCTAssertTrue(abs(fraction - Double(index + 1) / 10) < 0.0001, "after \(index + 1) of 10 the bar is at \(Double(index + 1) / 10)")
        }
        XCTAssertEqual(seen, seen.sorted())
        XCTAssertEqual(aggregator.snapshot().fraction, 1)
    }
}
