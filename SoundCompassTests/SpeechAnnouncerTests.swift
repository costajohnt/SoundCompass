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

    // MARK: - Rate limiting and phrasing (synthesizer disabled)

    private func silentAnnouncer(minInterval: TimeInterval = 2.0) -> (SpeechAnnouncer, () -> [String]) {
        let announcer = SpeechAnnouncer(minInterval: minInterval)
        announcer.speaksAloud = false
        announcer.isEnabled = true
        var spoken: [String] = []
        announcer.onPhrase = { spoken.append($0) }
        return (announcer, { spoken })
    }

    func testQuietSoundsAreNotAnnounced() {
        let (announcer, spoken) = silentAnnouncer()
        announcer.announce(direction: 0.8, magnitude: 0.1, label: "Car horn")
        XCTAssertTrue(spoken().isEmpty)
    }

    func testPhraseUsesLabelAndDirection() {
        let (announcer, spoken) = silentAnnouncer()
        announcer.announce(direction: 0.8, magnitude: 0.9, label: "Car horn")
        XCTAssertEqual(spoken(), ["car horn far right"])
    }

    func testPhraseWithoutLabel() {
        let (announcer, spoken) = silentAnnouncer()
        announcer.announce(direction: -0.4, magnitude: 0.9, label: nil)
        XCTAssertEqual(spoken(), ["Sound from your left"])
    }

    func testSecondAnnouncementInsideMinIntervalIsDropped() {
        let (announcer, spoken) = silentAnnouncer(minInterval: 2.0)
        let t0 = Date(timeIntervalSince1970: 1_000)
        announcer.announce(direction: 0.8, magnitude: 0.9, label: "Car horn", now: t0)
        announcer.announce(direction: -0.8, magnitude: 0.9, label: "Dog bark", now: t0.addingTimeInterval(1))
        XCTAssertEqual(spoken().count, 1)
        announcer.announce(direction: -0.8, magnitude: 0.9, label: "Dog bark", now: t0.addingTimeInterval(3))
        XCTAssertEqual(spoken().count, 2)
    }

    func testUnchangedDirectionAndLabelIsNotRepeated() {
        let (announcer, spoken) = silentAnnouncer(minInterval: 0)
        let t0 = Date(timeIntervalSince1970: 1_000)
        announcer.announce(direction: 0.8, magnitude: 0.9, label: "Car horn", now: t0)
        announcer.announce(direction: 0.85, magnitude: 0.9, label: "Car horn", now: t0.addingTimeInterval(1))
        XCTAssertEqual(spoken().count, 1)
        announcer.announce(direction: 0.2, magnitude: 0.9, label: "Car horn", now: t0.addingTimeInterval(2))
        XCTAssertEqual(spoken().count, 2, "a ≥0.3 direction change should be announced")
    }
}
