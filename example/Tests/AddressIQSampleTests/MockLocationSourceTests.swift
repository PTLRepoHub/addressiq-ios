import XCTest
import CoreLocation
@testable import AddressIQ

/**
 What does CoreLocation say about a fix the simulator was told to report?

 This is not academic. `location.isMocked` feeds MOCK_LOCATION, which is a
 *terminating* flag — a verification carrying it resolves NOT_AT_ADDRESS
 immediately. If `simctl location set` produces fixes the OS marks as simulated,
 then every verification run against a simulator is disqualified before the
 geofence maths is even reached, and no amount of correct collection would
 change that.

 It can only be answered with a fix that came from CoreLocation itself. A
 `CLLocation` built in code carries `sourceInformation` with
 `isSimulatedBySoftware == false` on iOS 15+, so it answers the wrong question.

 Run via scripts/run-geofence-test.sh, which places the device with
 `simctl location set` first.
 */
final class MockLocationSourceTests: XCTestCase {

    private var authorized: Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .authorizedAlways || status == .authorizedWhenInUse
    }

    func testWhatCoreLocationReportsForASimctlPlacedFix() throws {
        try XCTSkipUnless(authorized, "no location authorization — run via scripts/run-geofence-test.sh")

        let manager = AddressIQLocationManager()
        let got = expectation(description: "a real CoreLocation fix")
        var fix: CLLocation?

        manager.onTransition = { _, location, _ in
            guard fix == nil, let location else { return }
            fix = location
            got.fulfill()
        }
        manager.startMonitoring(
            latitude: 6.5244,
            longitude: 3.3792,
            radius: 150,
            identifier: "loc_mock_source_probe"
        )
        wait(for: [got], timeout: 60)
        manager.stopMonitoring()

        let location = try XCTUnwrap(fix, "no fix delivered")
        let mocked = AddressIQDeviceSignals.isMocked(location)

        XCTAssertNotNil(mocked, "iOS 15+ should always be able to answer for a CoreLocation fix")

        // MEASURED: true. `simctl location set` drives CoreLocation through the
        // same path a fake-GPS tool would, and the OS marks it honestly.
        //
        // The detection is correct. The consequence is the point of this test:
        // MOCK_LOCATION is terminal, so **a digital verification can never
        // succeed on an iOS simulator**. Every run resolves NOT_AT_ADDRESS /
        // fraud_confirmed on the location signal alone, before presence,
        // night cycles or evidence floors are reached — and it does so while
        // looking exactly like the SDK working correctly, because it is.
        //
        // Anyone validating the happy path needs a real device. A simulator can
        // prove collection, upload and the fraud path; it cannot prove a
        // VERIFIED outcome. Combined with EMULATOR_DETECTED, which is also
        // correct and also terminal, a simulator run carries two terminal flags
        // by construction.
        //
        // Asserted as `true` deliberately: if a future iOS stops marking these
        // fixes, this test fails and tells us the simulator has silently become
        // able to impersonate a real device.
        XCTAssertEqual(
            mocked, true,
            "a simctl-placed fix is no longer reported as simulated — simulator runs can now "
                + "impersonate real devices, and MOCK_LOCATION would miss software-driven fixes"
        )
    }
}
