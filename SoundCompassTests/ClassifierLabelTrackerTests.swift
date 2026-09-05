import XCTest
@testable import SoundCompass

final class ClassifierLabelTrackerTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testConfidentResultPublishesHumanizedLabel() {
        var tracker = ClassifierLabelTracker(minConfidence: 0.5, maxAge: 2.5)
        XCTAssertTrue(tracker.ingest(identifier: "car_horn", confidence: 0.9, now: t0))
        XCTAssertEqual(tracker.current.rawIdentifier, "car_horn")
        XCTAssertEqual(tracker.current.label, "Car horn")
        XCTAssertEqual(tracker.current.confidence, 0.9)
    }

    func testLowConfidenceResultClearsLabel() {
        var tracker = ClassifierLabelTracker()
        tracker.ingest(identifier: "siren", confidence: 0.9, now: t0)
        XCTAssertTrue(tracker.ingest(identifier: "speech", confidence: 0.2, now: t0.addingTimeInterval(1)))
        XCTAssertNil(tracker.current.rawIdentifier)
        XCTAssertNil(tracker.current.label)
        XCTAssertEqual(tracker.current.confidence, 0)
    }

    func testStaleLabelExpires() {
        var tracker = ClassifierLabelTracker(minConfidence: 0.5, maxAge: 2.5)
        tracker.ingest(identifier: "siren", confidence: 0.9, now: t0)
        XCTAssertFalse(tracker.expire(now: t0.addingTimeInterval(2.0)))
        XCTAssertEqual(tracker.current.rawIdentifier, "siren")
        XCTAssertTrue(tracker.expire(now: t0.addingTimeInterval(3.0)))
        XCTAssertNil(tracker.current.rawIdentifier)
    }

    func testRefreshExtendsLifetime() {
        var tracker = ClassifierLabelTracker(minConfidence: 0.5, maxAge: 2.5)
        tracker.ingest(identifier: "siren", confidence: 0.9, now: t0)
        tracker.ingest(identifier: "siren", confidence: 0.8, now: t0.addingTimeInterval(2))
        XCTAssertFalse(tracker.expire(now: t0.addingTimeInterval(4)))
        XCTAssertEqual(tracker.current.rawIdentifier, "siren")
    }

    func testIdenticalResultIsNotAChange() {
        var tracker = ClassifierLabelTracker()
        XCTAssertTrue(tracker.ingest(identifier: "speech", confidence: 0.7, now: t0))
        XCTAssertFalse(tracker.ingest(identifier: "speech", confidence: 0.7, now: t0.addingTimeInterval(1)))
    }

    func testClearOnEmptyIsNoOp() {
        var tracker = ClassifierLabelTracker()
        XCTAssertFalse(tracker.clear())
        XCTAssertFalse(tracker.expire(now: t0))
    }
}
