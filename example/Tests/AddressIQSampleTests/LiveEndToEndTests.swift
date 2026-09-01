import XCTest
import CoreLocation
import AddressIQ

/**
 The whole chain, against the running stack: collect on a real device, upload
 through the real ingest, and let the real worker score it.

 Not a unit test and not hermetic — it is pointed at a verification created
 through the dashboard/API beforehand, and the codes below are substituted by
 the runner. It exists to prove the legs that only a device can prove: that
 CoreLocation actually fires, that what the SDK puts on the wire is accepted by
 ingest as-is, and that the queue drains afterwards.
 */
final class LiveEndToEndTests: XCTestCase {

    /// Supplied by scripts/run-live-e2e.sh, which creates the verification
    /// against the running stack first. Baking codes in would make this pass
    /// once and fail forever after.
    private let locationCode = ProcessInfo.processInfo.environment["AIQ_E2E_LOCATION_CODE"] ?? ""
    private let verificationCode = ProcessInfo.processInfo.environment["AIQ_E2E_VERIFICATION_CODE"] ?? ""
    private let latitude = 6.5244
    private let longitude = 3.3792

    func testCollectUploadsThroughRealIngestAndDrainsTheQueue() throws {
        try XCTSkipUnless(
            !locationCode.isEmpty && !verificationCode.isEmpty,
            "no verification supplied — run via scripts/run-live-e2e.sh"
        )
        let status: CLAuthorizationStatus = CLLocationManager().authorizationStatus
        try XCTSkipUnless(
            status == .authorizedAlways || status == .authorizedWhenInUse,
            "no location authorization — run via scripts/run-live-e2e.sh"
        )

        let queue = AddressIQTelemetryQueue.shared
        queue.wipe()

        AddressIQ.shared.initialize(
            config: AddressIQConfig(
                apiKey: "aiq_test_demo_bank_seed01",
                deployment: .development
            )
        )
        AddressIQ.shared.startCollecting(
            locationCode: locationCode,
            verificationCode: verificationCode,
            latitude: latitude,
            longitude: longitude,
            radiusM: 150
        )

        // `wait(for:)` rather than `await Task.sleep`: CoreLocation delivers
        // region callbacks on the main run loop, and an async test body does
        // not spin it — the geofence simply never fires.
        let enqueued = expectation(description: "geofence produced an event")
        let deadline = Date().addingTimeInterval(45)
        func poll() {
            if queue.count() > 0 { return enqueued.fulfill() }
            guard Date() < deadline else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: poll)
        }
        poll()
        wait(for: [enqueued], timeout: 50)

        // Upload through the real ingest. `sync` returns how many rows left the
        // queue — non-zero only if the server accepted AND the SDK recognised
        // the response, so this covers the 201-vs-200 acknowledge case too.
        let uploaded = expectation(description: "sync completed")
        var flushed = -1
        var syncError: Error?
        Task {
            do { flushed = try await AddressIQ.shared.sync() }
            catch { syncError = error }
            uploaded.fulfill()
        }
        wait(for: [uploaded], timeout: 60)

        XCTAssertNil(syncError, "sync threw: \(String(describing: syncError))")
        XCTAssertGreaterThan(flushed, 0, "ingest accepted nothing, or the ack was not recognised")
        XCTAssertEqual(queue.count(), 0, "queue did not drain — events would be re-uploaded forever")
    }
}
