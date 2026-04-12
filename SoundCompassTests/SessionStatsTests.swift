import XCTest
@testable import SoundCompass

final class SessionStatsTests: XCTestCase {

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
        XCTAssertEqual(stats.snapshot.topDirectionBucket, "Far right")
    }

    func testDurationTicksWhileRunning() {
        let stats = SessionStats()
        stats.begin()
        usleep(50_000)
        XCTAssertGreaterThan(stats.snapshot.duration, 0)
    }

    func testEndFreezesDuration() {
        let stats = SessionStats()
        stats.begin()
        usleep(20_000)
        stats.end()
        let frozen = stats.snapshot.duration
        usleep(20_000)
        XCTAssertEqual(stats.snapshot.duration, frozen, accuracy: 0.01)
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
