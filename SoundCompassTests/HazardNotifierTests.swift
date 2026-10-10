import UserNotifications
import XCTest
@testable import SoundCompass

/// Records calls and holds completions so each test decides when the
/// "system" answers.
private final class FakeNotificationCenter: HazardNotificationCenter {
    var status: UNAuthorizationStatus = .notDetermined
    var requestCount = 0
    var pendingRequest: ((Bool) -> Void)?
    var added: [UNNotificationRequest] = []

    func requestAlertAuthorization(options: UNAuthorizationOptions, completion: @escaping (Bool) -> Void) {
        requestCount += 1
        pendingRequest = completion
    }

    func fetchAuthorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        completion(status)
    }

    func addRequest(_ request: UNNotificationRequest) {
        added.append(request)
    }
}

final class HazardNotifierTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func makeNotifier(_ center: FakeNotificationCenter) -> HazardNotifier {
        HazardNotifier(center: center, onMain: { $0() }, now: { [unowned self] in self.clock })
    }

    func testLaunchReadsGrantedStatusSoFirstBackgroundHazardDelivers() {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let notifier = makeNotifier(center)

        XCTAssertEqual(notifier.authState, .granted)
        notifier.post(label: "Siren", direction: 0, allowed: true)
        XCTAssertEqual(center.added.count, 1)
        XCTAssertEqual(center.requestCount, 0)
    }

    func testLaunchReadsDeniedStatus() {
        let center = FakeNotificationCenter()
        center.status = .denied
        let notifier = makeNotifier(center)

        XCTAssertEqual(notifier.authState, .denied)
        notifier.requestAuthorizationIfNeeded()
        XCTAssertEqual(center.requestCount, 0)
    }

    func testForegroundRequestThenBackgroundHazardDelivers() {
        let center = FakeNotificationCenter()
        let notifier = makeNotifier(center)
        XCTAssertEqual(notifier.authState, .unknown)

        notifier.requestAuthorizationIfNeeded()
        XCTAssertEqual(notifier.authState, .requesting)
        XCTAssertEqual(center.requestCount, 1)

        center.pendingRequest?(true)
        XCTAssertEqual(notifier.authState, .granted)
        XCTAssertTrue(center.added.isEmpty)  // a prompt alone delivers nothing

        notifier.post(label: "Siren", direction: 0, allowed: true)
        XCTAssertEqual(center.added.count, 1)
    }

    func testRepeatedForegroundRequestsAskOnce() {
        let center = FakeNotificationCenter()
        let notifier = makeNotifier(center)
        notifier.requestAuthorizationIfNeeded()
        notifier.requestAuthorizationIfNeeded()
        XCTAssertEqual(center.requestCount, 1)
    }

    func testHazardsWhileRequestPendingDoNotAskAgain() {
        let center = FakeNotificationCenter()
        let notifier = makeNotifier(center)

        notifier.post(label: "Siren", direction: 0, allowed: true)  // lazy fallback
        XCTAssertEqual(center.requestCount, 1)
        for step in 1...5 {
            clock = clock.addingTimeInterval(TimeInterval(step * 20))
            notifier.post(label: "Siren", direction: 0, allowed: true)
        }
        XCTAssertEqual(center.requestCount, 1)
        XCTAssertTrue(center.added.isEmpty)

        center.pendingRequest?(true)
        XCTAssertEqual(center.added.count, 1)  // the hazard that triggered the fallback
    }

    func testDeniedRequestStopsPosting() {
        let center = FakeNotificationCenter()
        let notifier = makeNotifier(center)
        notifier.requestAuthorizationIfNeeded()
        center.pendingRequest?(false)
        XCTAssertEqual(notifier.authState, .denied)

        notifier.post(label: "Siren", direction: 0, allowed: true)
        XCTAssertTrue(center.added.isEmpty)
        XCTAssertEqual(center.requestCount, 1)
    }

    func testRefreshPicksUpPermissionChangedInSettings() {
        let center = FakeNotificationCenter()
        center.status = .denied
        let notifier = makeNotifier(center)
        XCTAssertEqual(notifier.authState, .denied)

        center.status = .authorized
        notifier.refreshAuthorization()
        XCTAssertEqual(notifier.authState, .granted)
    }

    func testRefreshDoesNotClobberPendingRequest() {
        let center = FakeNotificationCenter()
        let notifier = makeNotifier(center)
        notifier.requestAuthorizationIfNeeded()
        notifier.refreshAuthorization()  // still .notDetermined while the prompt is up
        XCTAssertEqual(notifier.authState, .requesting)
    }

    func testRateLimitStillApplies() {
        let center = FakeNotificationCenter()
        center.status = .authorized
        let notifier = makeNotifier(center)

        notifier.post(label: "Siren", direction: 0, allowed: true)
        clock = clock.addingTimeInterval(5)
        notifier.post(label: "Siren", direction: 0, allowed: true)
        XCTAssertEqual(center.added.count, 1)
        clock = clock.addingTimeInterval(10)
        notifier.post(label: "Siren", direction: 0, allowed: true)
        XCTAssertEqual(center.added.count, 2)
    }

    func testDisallowedPostDoesNothing() {
        let center = FakeNotificationCenter()
        let notifier = makeNotifier(center)
        notifier.post(label: "Siren", direction: 0, allowed: false)
        XCTAssertEqual(center.requestCount, 0)
    }
}
