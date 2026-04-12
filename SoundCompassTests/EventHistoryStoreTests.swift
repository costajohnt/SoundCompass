import XCTest
@testable import SoundCompass

final class EventHistoryStoreTests: XCTestCase {

    func testAppendPrependsMostRecent() {
        let store = EventHistoryStore(maxEvents: 5)

        store.record(label: "Speech", rawIdentifier: "speech",
                     direction: 0.1, magnitude: 0.5, isHazard: false)
        // Sleep a touch so the coalesce hysteresis isn't triggered.
        usleep(1_500_000)  // 1.5 s > minInterval (0.8 s)
        store.record(label: "Car horn", rawIdentifier: "car_horn",
                     direction: -0.6, magnitude: 0.9, isHazard: true)

        XCTAssertEqual(store.events.count, 2)
        XCTAssertEqual(store.events.first?.rawIdentifier, "car_horn")
        XCTAssertEqual(store.events.last?.rawIdentifier, "speech")
    }

    func testMaxEventsIsRespected() {
        let store = EventHistoryStore(maxEvents: 3)
        for i in 0..<5 {
            store.record(
                label: "E\(i)",
                rawIdentifier: "id_\(i)",
                direction: 0,
                magnitude: 0.5,
                isHazard: false
            )
            usleep(900_000)  // 0.9s > minInterval
        }
        XCTAssertEqual(store.events.count, 3)
        // Latest should be at index 0.
        XCTAssertEqual(store.events.first?.rawIdentifier, "id_4")
        XCTAssertEqual(store.events.last?.rawIdentifier, "id_2")
    }

    func testCoalescesRepeats() {
        let store = EventHistoryStore()
        store.record(label: "Speech", rawIdentifier: "speech",
                     direction: 0, magnitude: 0.5, isHazard: false)
        // Immediately repeat — should be coalesced.
        store.record(label: "Speech", rawIdentifier: "speech",
                     direction: 0.1, magnitude: 0.5, isHazard: false)
        XCTAssertEqual(store.events.count, 1)
    }

    func testClearEmptiesStore() {
        let store = EventHistoryStore()
        store.record(label: "Speech", rawIdentifier: "speech",
                     direction: 0, magnitude: 0.5, isHazard: false)
        store.clear()
        XCTAssertTrue(store.events.isEmpty)
    }
}
