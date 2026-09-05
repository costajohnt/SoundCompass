import XCTest
@testable import SoundCompass

final class SettingsStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearDefaults()
    }

    override func tearDown() {
        clearDefaults()
        super.tearDown()
    }

    func testDefaultsAreMediumAndLight() {
        let store = SettingsStore(defaults: isolatedDefaults())
        XCTAssertEqual(store.sensitivity, .medium)
        XCTAssertEqual(store.hapticStrength, .light)
        XCTAssertFalse(store.speechEnabled)
        XCTAssertEqual(store.speechRate, 1.0, accuracy: 0.0001)
        XCTAssertFalse(store.showDebugStats)
    }

    func testSensitivityBlendWeightsAreOrdered() {
        XCTAssertLessThan(
            SettingsStore.Sensitivity.low.directionBlend,
            SettingsStore.Sensitivity.medium.directionBlend
        )
        XCTAssertLessThan(
            SettingsStore.Sensitivity.medium.directionBlend,
            SettingsStore.Sensitivity.high.directionBlend
        )
    }

    func testHapticIntensityIsOrdered() {
        XCTAssertEqual(SettingsStore.HapticStrength.off.intensity, 0)
        XCTAssertLessThan(
            SettingsStore.HapticStrength.light.intensity,
            SettingsStore.HapticStrength.strong.intensity
        )
    }

    func testIldCalibrationRoundTrip() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        XCTAssertNil(store.ildGain)
        XCTAssertFalse(store.ildHighBand)

        store.ildGain = 18.5
        store.ildHighBand = true
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.ildGain ?? 0, 18.5, accuracy: 0.0001)
        XCTAssertTrue(reloaded.ildHighBand)

        reloaded.ildGain = nil
        XCTAssertNil(SettingsStore(defaults: defaults).ildGain)
    }

    func testHearingEarPan() {
        XCTAssertEqual(SettingsStore.HearingEar.left.pan, -1)
        XCTAssertEqual(SettingsStore.HearingEar.right.pan, 1)
        XCTAssertEqual(SettingsStore.HearingEar.unspecified.pan, 0)
    }

    func testPersistenceRoundTrip() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)

        store.sensitivity = .high
        store.hapticStrength = .strong
        store.speechEnabled = true
        store.speechRate = 1.4
        store.showDebugStats = true

        // Reinstantiate with the same UserDefaults to verify the values
        // came back out of the store rather than being held in memory.
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.sensitivity, .high)
        XCTAssertEqual(reloaded.hapticStrength, .strong)
        XCTAssertTrue(reloaded.speechEnabled)
        XCTAssertEqual(reloaded.speechRate, 1.4, accuracy: 0.0001)
        XCTAssertTrue(reloaded.showDebugStats)
    }

    // MARK: - Helpers

    /// A suite-specific `UserDefaults` so tests don't pollute the real one.
    /// `SettingsStore.didSet` still writes to `.standard`, so we also
    /// scrub that in tearDown.
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SoundCompassTests")!
    }

    private func clearDefaults() {
        let suite = UserDefaults(suiteName: "SoundCompassTests")!
        for key in suite.dictionaryRepresentation().keys {
            suite.removeObject(forKey: key)
        }
        let keys = [
            "soundcompass.settings.sensitivity",
            "soundcompass.settings.haptics",
            "soundcompass.settings.speech",
            "soundcompass.settings.speechRate",
            "soundcompass.settings.debug",
            "soundcompass.settings.ildGain",
            "soundcompass.settings.ildHighBand",
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
