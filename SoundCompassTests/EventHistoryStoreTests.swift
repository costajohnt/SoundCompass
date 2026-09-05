import XCTest
@testable import SoundCompass

final class EventHistoryStoreTests: XCTestCase {

    /// A manual clock so the coalescing window can be exercised without
    /// sleeping.
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    func testAppendPrependsMostRecent() {
        let clock = Clock()
        let store = EventHistoryStore(maxEvents: 5, now: { clock.now })

        store.record(label: "Speech", rawIdentifier: "speech",
                     direction: 0.1, magnitude: 0.5, isHazard: false)
        clock.advance(1.5)
        store.record(label: "Car horn", rawIdentifier: "car_horn",
                     direction: -0.6, magnitude: 0.9, isHazard: true)

        XCTAssertEqual(store.events.count, 2)
        XCTAssertEqual(store.events.first?.rawIdentifier, "car_horn")
        XCTAssertEqual(store.events.last?.rawIdentifier, "speech")
    }

    func testMaxEventsIsRespected() {
        let clock = Clock()
        let store = EventHistoryStore(maxEvents: 3, now: { clock.now })
        for i in 0..<5 {
            store.record(
                label: "E\(i)",
                rawIdentifier: "id_\(i)",
                direction: 0,
                magnitude: 0.5,
                isHazard: false
            )
            clock.advance(0.9)
        }
        XCTAssertEqual(store.events.count, 3)
        // Latest should be at index 0.
        XCTAssertEqual(store.events.first?.rawIdentifier, "id_4")
        XCTAssertEqual(store.events.last?.rawIdentifier, "id_2")
    }

    func testCoalescesRepeats() {
        let clock = Clock()
        let store = EventHistoryStore(now: { clock.now })
        store.record(label: "Speech", rawIdentifier: "speech",
                     direction: 0, magnitude: 0.5, isHazard: false)
        clock.advance(0.2)
        store.record(label: "Speech", rawIdentifier: "speech",
                     direction: 0.1, magnitude: 0.5, isHazard: false)
        XCTAssertEqual(store.events.count, 1)
    }

    func testDifferentIdentifierIsNotCoalesced() {
        let clock = Clock()
        let store = EventHistoryStore(now: { clock.now })
        store.record(label: "Speech", rawIdentifier: "speech",
                     direction: 0, magnitude: 0.5, isHazard: false)
        store.record(label: "Siren", rawIdentifier: "siren",
                     direction: 0.1, magnitude: 0.5, isHazard: true)
        XCTAssertEqual(store.events.count, 2)
    }

    func testClearEmptiesStore() {
        let store = EventHistoryStore()
        store.record(label: "Speech", rawIdentifier: "speech",
                     direction: 0, magnitude: 0.5, isHazard: false)
        store.clear()
        XCTAssertTrue(store.events.isEmpty)
    }
}
