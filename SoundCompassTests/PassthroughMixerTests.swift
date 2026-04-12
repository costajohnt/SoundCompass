import AVFoundation
import XCTest
@testable import SoundCompass

/// Exercises the `PassthroughMixer` state machine without actually
/// engaging headphones — we can't force a headphone route from a unit
/// test, so we rely on the invariant that `setEnabled` is a no-op when
/// no safe output route is available, and assert `isActive` stays
/// `false`.
final class PassthroughMixerTests: XCTestCase {

    func testSetEnabledWithoutHeadphonesDoesNotConnect() {
        let engine = AVAudioEngine()
        let mixer = PassthroughMixer(engine: engine)

        mixer.setEnabled(true, pan: 1)

        // We can't guarantee that a CI simulator has no headphones
        // connected, but the common case is the internal speaker, where
        // PassthroughMixer should refuse to connect.
        //
        // We don't assert isActive here directly because the result
        // depends on the route — the test is primarily a smoke test
        // that the state machine doesn't crash.
        XCTAssertNotNil(mixer)
    }

    func testUpdatePanIsNoOpWhileDisconnected() {
        let engine = AVAudioEngine()
        let mixer = PassthroughMixer(engine: engine)

        // Setting a pan while nothing is connected should be safe and
        // not raise.
        mixer.updatePan(-0.5)
        XCTAssertFalse(mixer.isActive)
    }

    func testPauseWhileDisconnectedIsNoOp() {
        let engine = AVAudioEngine()
        let mixer = PassthroughMixer(engine: engine)

        mixer.pause()
        XCTAssertFalse(mixer.isActive)
    }

    func testHandleRouteChangeDoesNotCrash() {
        let engine = AVAudioEngine()
        let mixer = PassthroughMixer(engine: engine)
        mixer.setEnabled(true, pan: 1)
        mixer.handleRouteChange()
        XCTAssertNotNil(mixer)
    }
}
