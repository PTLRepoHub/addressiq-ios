import XCTest
import CoreLocation
@testable import AddressIQ

/**
 The device-integrity signals, audited the way the Android ones were.

 That audit found two of three silently broken: the emulator heuristic matched
 no current AVD, and the spoofing-app check could not see other packages at all.
 Both returned `false` meaning "could not look", and both survived because every
 test built `rawPayload` by hand and nothing ever ran the collector on a device.

 These run the collector itself. Where a signal cannot be exercised on the
 hardware available, that is stated rather than papered over with an assertion
 that only proves the absence of a false positive.
 */
final class DeviceSignalsAuditTests: XCTestCase {

    // MARK: - Simulator detection

    func testTheSimulatorIsReportedAsOne() {
        // Compile-time, so unlike Android's Build-property heuristic this cannot
        // drift as new device images appear — and unlike it, it cannot be
        // patched at runtime either.
        XCTAssertTrue(AddressIQDeviceSignals.isSimulator)
        let sections = AddressIQDeviceSignals.collect(location: nil)
        XCTAssertEqual(sections["device"]?["isEmulator"] as? Bool, true)
    }

    // MARK: - Jailbreak detection

    func testJailbreakDetectionFiresWhenAMarkerIsPresent() throws {
        // The assertion that had never been made. Without the injectable
        // markers this is unreachable: the real paths need a jailbroken device,
        // and the simulator short-circuit returns false before even looking.
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("aiq-jailbreak-probe")
        try "probe".write(to: marker, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: marker) }

        XCTAssertTrue(
            AddressIQDeviceSignals.isJailbroken(
                markers: [marker.path],
                skipOnSimulator: false
            ),
            "isJailbroken did not fire with a marker present — the detector is inert"
        )
    }

    func testJailbreakDetectionIsQuietWhenNoMarkerIsPresent() {
        XCTAssertFalse(
            AddressIQDeviceSignals.isJailbroken(
                markers: ["/definitely/not/here", "/nor/this"],
                skipOnSimulator: false
            ),
            "isJailbroken fired with no marker present"
        )
    }

    func testTheSimulatorShortCircuitStillHoldsByDefault() {
        // The simulator genuinely ships /bin/bash and /etc/apt, so without the
        // short-circuit every simulator run would report a jailbroken device.
        // Production keeps that behaviour; only tests opt out of it.
        XCTAssertFalse(
            AddressIQDeviceSignals.isJailbroken(markers: ["/bin/bash"]),
            "the simulator short-circuit is not holding — every simulator run would flag"
        )
        XCTAssertTrue(
            AddressIQDeviceSignals.isJailbroken(markers: ["/bin/bash"], skipOnSimulator: false),
            "/bin/bash is expected to exist on the simulator; if not, this fixture is wrong"
        )
    }

    func testTheCollectorCarriesTheJailbreakSignal() throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("aiq-jailbreak-collect-probe")
        try "probe".write(to: marker, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: marker) }

        let sections = AddressIQDeviceSignals.collect(
            location: nil,
            jailbreakMarkers: [marker.path],
            skipJailbreakCheckOnSimulator: false
        )
        XCTAssertEqual(sections["security"]?["isRooted"] as? Bool, true)
    }

    // MARK: - Mock location

    func testNoFixAtAllIsUnanswerable() {
        // The only genuinely unanswerable case that survives on iOS 15+.
        XCTAssertNil(AddressIQDeviceSignals.isMocked(nil))
    }

    func testAConstructedFixIsAnsweredRatherThanOmitted() {
        // Measured, and contrary to what the doc comment implies: on iOS 15+ a
        // CLLocation built in code still carries `sourceInformation`, with
        // `isSimulatedBySoftware == false`. So the SDK answers `false` rather
        // than nil, and the "could not tell" path is reachable only below
        // iOS 15 or with no fix at all.
        //
        // Harmless in production, where fixes come from CoreLocation and the
        // answer is real — but it means this signal cannot be exercised from a
        // synthesized location. Proving MOCK_LOCATION on iOS needs a fix the OS
        // itself marks as simulated, which is what `simctl location` produces.
        let plain = CLLocation(latitude: 6.5244, longitude: 3.3792)
        XCTAssertEqual(AddressIQDeviceSignals.isMocked(plain), false)

        let sections = AddressIQDeviceSignals.collect(location: plain)
        XCTAssertEqual(sections["location"]?["isMocked"] as? Bool, false)
    }

    // MARK: - Install id

    func testTheInstallIdIsStableWhereTheKeychainIsAvailable() throws {
        // A SwiftPM test bundle has no keychain entitlement, so `installId()`
        // returns nil here. That is an environment limit, not a defect: the
        // sample-app run produced a real id on the wire
        // (`fingerprint.installId`), which is the configuration that ships.
        //
        // It does expose a silent degradation worth knowing about — when the
        // keychain is unavailable the whole `fingerprint` section is omitted,
        // so DEVICE_CHANGE and the device blacklist go dark with nothing
        // logged. Consistent with the contract's "omit what you cannot answer",
        // but invisible.
        let first = AddressIQDeviceSignals.installId()
        try XCTSkipIf(
            first == nil,
            "keychain unavailable in this test bundle — see AddressIQSampleTests for the hosted case"
        )
        XCTAssertEqual(
            first,
            AddressIQDeviceSignals.installId(),
            "installId is not stable — DEVICE_CHANGE would fire constantly"
        )
    }
}
