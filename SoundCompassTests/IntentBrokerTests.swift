import XCTest
@testable import SoundCompass

final class IntentBrokerTests: XCTestCase {

    func testRegisterAndReadBack() {
        let detector = AudioDirectionDetector()
        IntentBroker.register(detector)
        XCTAssertTrue(IntentBroker.detector === detector)
    }

    func testBrokerHoldsWeakReference() {
        weak var weakDetector: AudioDirectionDetector?
        autoreleasepool {
            let detector = AudioDirectionDetector()
            weakDetector = detector
            IntentBroker.register(detector)
            XCTAssertNotNil(IntentBroker.detector)
        }
        // Once the strong reference from autoreleasepool is gone, the
        // broker should drop back to nil since it only held a weak ref.
        XCTAssertNil(weakDetector)
        XCTAssertNil(IntentBroker.detector)
    }
}
