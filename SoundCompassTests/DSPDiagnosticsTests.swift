import XCTest
@testable import SoundCompass

final class DSPDiagnosticsTests: XCTestCase {

    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsp-diagnostics-test-\(UUID().uuidString).csv")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        super.tearDown()
    }

    private func makeEstimate() -> DirectionEstimate {
        DirectionEstimate(
            direction: 0.5,
            magnitude: 0.3,
            combinedRms: 0.1,
            isConfident: true,
            rawILD: 0.05,
            rawITD: 0,
            lagSamples: 0,
            leftRms: 0.04,
            rightRms: 0.06,
            itdConfidence: 0.8,
            ildLeftRms: 0.03,
            ildRightRms: 0.07
        )
    }

    func testDisabledBeginWritesNothingAndRemovesStaleTrace() throws {
        try Data("stale".utf8).write(to: fileURL)
        let diagnostics = DSPDiagnostics(fileURL: fileURL)

        diagnostics.begin(config: "test", enabled: false)
        diagnostics.append(estimate: makeEstimate(), smoothDir: 0.4, magnitude: 0.3)
        diagnostics.note("marker")
        diagnostics.end()
        diagnostics.flush()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path),
                       "Disabled tracing must remove any previous session's trace")
    }

    func testEnabledBeginWritesHeaderConfigAndFrames() throws {
        let diagnostics = DSPDiagnostics(fileURL: fileURL)

        diagnostics.begin(config: "source=Back sign=1.0", enabled: true)
        diagnostics.append(estimate: makeEstimate(), smoothDir: 0.4, magnitude: 0.3, bandILD: "Low:0.0100|Speech:0.0500")
        diagnostics.note("MONO input")
        diagnostics.end()
        diagnostics.flush()

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        XCTAssertEqual(lines[0], "# source=Back sign=1.0")
        XCTAssertEqual(lines[1], "t,leftRms,rightRms,ildLeftRms,ildRightRms,ildRaw,lag,itdConf,rawDir,smoothDir,magnitude,bandILD")
        XCTAssertTrue(lines[2].hasSuffix(",0.04000,0.06000,0.03000,0.07000,0.0500,0,0.80,0.500,0.400,0.300,Low:0.0100|Speech:0.0500"),
                      "Frame row should carry the estimate values, got: \(lines[2])")
        XCTAssertEqual(lines[3], "# MONO input")
    }

    func testTraceStopsAtByteCap() throws {
        let cap = 256
        let diagnostics = DSPDiagnostics(fileURL: fileURL, maxBytes: cap)

        diagnostics.begin(config: "cap test", enabled: true)
        for _ in 0..<100 {
            diagnostics.append(estimate: makeEstimate(), smoothDir: 0.4, magnitude: 0.3)
        }
        diagnostics.end()
        diagnostics.flush()

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contents.hasSuffix("# trace capped at \(cap) bytes\n"))
        // Cap plus the one marker line, never unbounded growth.
        let size = try FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.size] as? Int ?? 0
        XCTAssertLessThan(size, cap + 64)
    }
}
