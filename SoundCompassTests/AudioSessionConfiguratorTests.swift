import AVFoundation
import XCTest
@testable import SoundCompass

final class AudioSessionConfiguratorTests: XCTestCase {

    private typealias Candidate = AudioSessionConfigurator.SourceCandidate

    func testPrefersBackSourceEvenWhenFrontEnumeratesFirst() {
        let candidates = [
            Candidate(name: "Front", orientation: .front, supportsStereo: true),
            Candidate(name: "Back", orientation: .back, supportsStereo: true),
            Candidate(name: "Bottom", orientation: .bottom, supportsStereo: false),
        ]
        let choice = AudioSessionConfigurator.chooseStereoSource(from: candidates)
        XCTAssertEqual(choice?.index, 1)
        XCTAssertEqual(choice?.selection.directionSign, 1.0)
        XCTAssertEqual(choice?.selection.description, "Back")
    }

    func testFallsBackToFrontWithMirroredSign() {
        let candidates = [
            Candidate(name: "Bottom", orientation: .bottom, supportsStereo: false),
            Candidate(name: "Front", orientation: .front, supportsStereo: true),
        ]
        let choice = AudioSessionConfigurator.chooseStereoSource(from: candidates)
        XCTAssertEqual(choice?.index, 1)
        XCTAssertEqual(choice?.selection.directionSign, -1.0)
        XCTAssertEqual(choice?.selection.description, "Front (mirrored)")
    }

    func testNoStereoSourceReturnsNil() {
        let candidates = [
            Candidate(name: "Bottom", orientation: .bottom, supportsStereo: false),
        ]
        XCTAssertNil(AudioSessionConfigurator.chooseStereoSource(from: candidates))
    }

    func testUnknownOrientationStereoSourceIsNotMirrored() {
        let candidates = [
            Candidate(name: "Array", orientation: nil, supportsStereo: true),
        ]
        let choice = AudioSessionConfigurator.chooseStereoSource(from: candidates)
        XCTAssertEqual(choice?.selection.directionSign, 1.0)
    }
}
