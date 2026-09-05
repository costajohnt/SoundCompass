import XCTest
@testable import SoundCompass

final class SessionStatsTests: XCTestCase {

    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    func testBeginResetsCounters() {
        let stats = SessionStats()
        stats.begin()
        stats.record(label: "Speech", direction: 0, isHazard: false)
        stats.record(label: "Siren", direction: -0.9, isHazard: true)
        stats.begin()  // reset
        XCTAssertEqual(stats.snapshot.totalEvents, 0)
        XCTAssertEqual(stats.snapshot.hazardCount, 0)
        XCTAssertTrue(stats.snapshot.labelCounts.isEmpty)
    }

    func testRecordIncrementsCounts() {
        let stats = SessionStats()
        stats.begin()
        stats.record(label: "Speech", direction: 0.1, isHazard: false)
        stats.record(label: "Speech", direction: 0.2, isHazard: false)
        stats.record(label: "Siren", direction: -0.9, isHazard: true)
        XCTAssertEqual(stats.snapshot.totalEvents, 3)
        XCTAssertEqual(stats.snapshot.hazardCount, 1)
        XCTAssertEqual(stats.snapshot.labelCounts["Speech"], 2)
        XCTAssertEqual(stats.snapshot.labelCounts["Siren"], 1)
    }

    func testTopLabel() {
        let stats = SessionStats()
        stats.begin()
        stats.record(label: "Speech", direction: 0, isHazard: false)
        stats.record(label: "Speech", direction: 0, isHazard: false)
        stats.record(label: "Bark", direction: 0, isHazard: false)
        XCTAssertEqual(stats.snapshot.topLabel, "Speech")
    }

    func testTopDirectionBucket() {
        let stats = SessionStats()
        stats.begin()
        stats.record(label: "A", direction: 0.8, isHazard: false)
        stats.record(label: "B", direction: 0.85, isHazard: false)
        stats.record(label: "C", direction: -0.7, isHazard: false)
        // Two "Far right" events dominate.
        XCTAssertEqual(stats.snapshot.topDirectionBucket, DirectionLabel.label(for: 0.8))
    }

    func testDurationTicksWhileRunning() {
        let clock = Clock()
        let stats = SessionStats(now: { clock.now })
        stats.begin()
        clock.advance(5)
        XCTAssertEqual(stats.snapshot.elapsed(at: clock.now), 5, accuracy: 1e-9)
    }

    func testEndFreezesDuration() {
        let clock = Clock()
        let stats = SessionStats(now: { clock.now })
        stats.begin()
        clock.advance(2)
        stats.end()
        clock.advance(10)
        XCTAssertEqual(stats.snapshot.elapsed(at: clock.now), 2, accuracy: 1e-9)
    }

    func testCSVEmitsHeaderAndRows() {
        let stats = SessionStats()
        stats.begin()
        let history = EventHistoryStore()
        history.record(label: "Speech", rawIdentifier: "speech", direction: 0.1, magnitude: 0.5, isHazard: false)
        let csv = stats.csv(events: history.events)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, "timestamp,label,rawIdentifier,direction,magnitude,hazard")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("Speech"))
        XCTAssertTrue(lines[1].contains("speech"))
    }
}
