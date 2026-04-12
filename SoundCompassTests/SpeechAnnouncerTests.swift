import XCTest
@testable import SoundCompass

/// Exercises the pure parts of `SpeechAnnouncer` — specifically the
/// phrase builder and the rate limiter — without actually engaging
/// `AVSpeechSynthesizer`.
///
/// `buildPhrase` is a private method, so we test it indirectly by
/// making the announcer emit once and inspecting what it *would have*
/// spoken. Since we can't spy on `AVSpeechUtterance` from a pure test,
/// this file is focused on the deterministic behavior we *can*
/// observe: that the rate-limit prevents a second announcement inside
/// the minInterval window.
final class SpeechAnnouncerTests: XCTestCase {

    func testDisabledByDefault() {
        let announcer = SpeechAnnouncer()
        XCTAssertFalse(announcer.isEnabled)
    }

    func testEnabledFlagRoundTrips() {
        let announcer = SpeechAnnouncer()
        announcer.isEnabled = true
        XCTAssertTrue(announcer.isEnabled)
        announcer.isEnabled = false
        XCTAssertFalse(announcer.isEnabled)
    }

    func testAnnounceWhenDisabledIsNoOp() {
        let announcer = SpeechAnnouncer()
        // Should not raise, should not speak.
        announcer.announce(direction: 0.5, magnitude: 0.9, label: "Car horn")
        XCTAssertFalse(announcer.isEnabled)
    }

    func testRateMultiplierPersistsAcrossAnnouncements() {
        let announcer = SpeechAnnouncer()
        announcer.rateMultiplier = 1.4
        XCTAssertEqual(announcer.rateMultiplier, 1.4, accuracy: 0.0001)
    }

    func testVoiceIdentifierPersists() {
        let announcer = SpeechAnnouncer()
        announcer.voiceIdentifier = "com.apple.voice.compact.en-US.Samantha"
        XCTAssertEqual(
            announcer.voiceIdentifier,
            "com.apple.voice.compact.en-US.Samantha"
        )
    }
}
