import XCTest
import CoreLocation
import AddressIQ

/**
 The device-side geofence trigger, on a real simulator with real CoreLocation.

 Everything else about collection is provable from the server side; this leg is
 not. Region monitoring is delivered by the OS to a delegate, so nothing short
 of a device exercises the path from "the phone is inside the circle" to "an
 event is on the queue". This is the iOS counterpart of
 GeofenceTriggerInstrumentedTest.kt in the Android SDK, and it drives the same
 public seam — `startCollecting` — that the Flutter and RN wrappers call.

 Hosted in the sample app rather than the SwiftPM test bundle on purpose:
 location authorization is granted per app bundle id, and a test bundle has
 none, so `simctl privacy grant` has nothing to attach to there.

 Deterministic rather than timing-dependent. `startMonitoring` follows
 `startMonitoring(for:)` with `requestState(for:)`, so a device already inside
 the circle resolves to `.inside` at once and the SDK maps that to an `.enter`
 transition. The runner places the device before launching:

     ./scripts/run-geofence-test.sh
 */
final class GeofenceTriggerTests: XCTestCase {

    /// Lagos, matching the fixtures used throughout the backend tests.
    private let latitude = 6.5244
    private let longitude = 3.3792
    private let radiusM = 150.0

    private var authorized: Bool {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = CLLocationManager().authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        return status == .authorizedAlways || status == .authorizedWhenInUse
    }

    func testCrossingIntoTheGeofenceEnqueuesATransitEvent() throws {
        try XCTSkipUnless(
            authorized,
            "Location authorization not granted to the sample app. Run via "
                + "scripts/run-geofence-test.sh, which grants it with simctl privacy."
        )

        let queue = AddressIQTelemetryQueue.shared
        // Drain first: the assertion is that THIS crossing produced an event,
        // not that the queue happens to be non-empty from an earlier run.
        // `wipe`, not `dequeue` — dequeue is a peek, `acknowledge` is what
        // deletes, so dequeuing would leave every row in place.
        queue.wipe()
        XCTAssertEqual(queue.count(), 0, "queue should be drained before the probe")

        AddressIQ.shared.initialize(
            config: AddressIQConfig(
                apiKey: "aiq_test_demo_bank_seed01",
                deployment: .development
            )
        )

        // Identified by LOCATION code — that is all a relaunched process has,
        // and it is the key ingest resolves the geofence by.
        AddressIQ.shared.startCollecting(
            locationCode: "loc_geofence_probe",
            verificationCode: "ver_geofence_probe",
            latitude: latitude,
            longitude: longitude,
            radiusM: radiusM
        )

        let enqueued = expectation(description: "a transit event reaches the queue")
        let deadline = Date().addingTimeInterval(60)
        func poll() {
            if queue.count() > 0 { return enqueued.fulfill() }
            guard Date() < deadline else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: poll)
        }
        poll()
        wait(for: [enqueued], timeout: 65)

        // And what was enqueued must be something ingest would accept: the
        // envelope is what the whole scoring engine reads.
        let batch = queue.dequeue(batchSize: 10)
        let first = try XCTUnwrap(batch.first)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(first.payload.utf8)
            ) as? [String: Any]
        )
        XCTAssertEqual(json["locationId"] as? String, "loc_geofence_probe")
        XCTAssertEqual(json["deviceOs"] as? String, "IOS")
        XCTAssertNil(json["verificationId"], "ingest rejects the whole batch on this field")

        let eventType = try XCTUnwrap(json["eventType"] as? String)
        XCTAssertTrue(
            eventType.hasPrefix("GEOFENCE_") || eventType == "BACKGROUND_CHECK",
            "unexpected eventType \(eventType)"
        )

        // The simulator reports itself as an emulator, which is what the engine
        // turns into EMULATOR_DETECTED — proof the device-intelligence section
        // is populated on the real path, not just in unit fixtures.
        let payload = try XCTUnwrap(json["rawPayload"] as? [String: Any])
        XCTAssertNotNil(payload["device"], "no device section — every fraud check is dark")
        XCTAssertNotNil(payload["security"])
    }
}
