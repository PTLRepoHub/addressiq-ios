import XCTest
@testable import AddressIQ

/// The envelope has to match `TransitEventDto` in the ingest service. A wrong or
/// missing field is a 400 for the whole batch, not just the one event, and the
/// SDK treats a non-200 as "retry later" so nothing gets through at all.
final class TransitEventTests: XCTestCase {
    private func makeEvent(
        kind: AddressIQTransitEvent.Kind = .enter,
        latitude: Double? = 6.5001,
        longitude: Double? = 3.3501,
        accuracyM: Double? = 12.5
    ) -> AddressIQTransitEvent {
        AddressIQTransitEvent(
            eventId: "11111111-2222-3333-4444-555555555555",
            locationCode: "loc_abc123",
            kind: kind,
            latitude: latitude,
            longitude: longitude,
            accuracyM: accuracyM,
            deviceTimestamp: Date(timeIntervalSince1970: 1_756_000_000)
        )
    }

    private func decode(_ event: AddressIQTransitEvent) throws -> [String: Any] {
        let json = try XCTUnwrap(event.jsonString())
        let object = try JSONSerialization.jsonObject(with: XCTUnwrap(json.data(using: .utf8)))
        return try XCTUnwrap(object as? [String: Any])
    }

    func testCarriesEveryFieldIngestRequires() throws {
        let payload = try decode(makeEvent())

        // locationId is the public location code, which is the key the backend
        // registers the geofence under. A UUID here matches no geofence.
        XCTAssertEqual(payload["locationId"] as? String, "loc_abc123")
        XCTAssertEqual(payload["eventType"] as? String, "GEOFENCE_ENTER")
        XCTAssertEqual(payload["deviceOs"] as? String, "IOS")
        XCTAssertEqual(payload["eventId"] as? String, "11111111-2222-3333-4444-555555555555")
        XCTAssertFalse((payload["sdkVersion"] as? String ?? "").isEmpty)
        XCTAssertEqual(payload["lat"] as? Double, 6.5001)
        XCTAssertEqual(payload["lon"] as? Double, 3.3501)
        XCTAssertEqual(payload["accuracyM"] as? Double, 12.5)
    }

    func testTimestampIsISO8601() throws {
        let payload = try decode(makeEvent())
        let timestamp = try XCTUnwrap(payload["deviceTimestamp"] as? String)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertNotNil(formatter.date(from: timestamp), "not parseable as ISO-8601: \(timestamp)")
    }

    func testEveryKindMapsToAValueIngestAccepts() throws {
        let accepted: Set<String> = [
            "GEOFENCE_ENTER", "GEOFENCE_EXIT", "DWELL",
            "APP_OPEN", "BACKGROUND_CHECK", "ACTIVITY_UPDATE",
        ]
        for kind in [AddressIQTransitEvent.Kind.enter, .exit, .backgroundCheck] {
            XCTAssertTrue(accepted.contains(kind.rawValue), "\(kind.rawValue) would be rejected")
        }
    }

    func testOmitsCoordinatesRatherThanSendingNulls() throws {
        let payload = try decode(makeEvent(latitude: nil, longitude: nil, accuracyM: nil))

        XCTAssertNil(payload["lat"])
        XCTAssertNil(payload["lon"])
        XCTAssertNil(payload["accuracyM"])
        // The transition itself is still evidence, so the event is kept.
        XCTAssertEqual(payload["eventType"] as? String, "GEOFENCE_ENTER")
    }

    func testDropsAnInvalidAccuracy() throws {
        // CoreLocation reports a negative horizontal accuracy when the fix is
        // invalid; ingest validates the field as a number and would store it.
        let payload = try decode(makeEvent(accuracyM: -1))
        XCTAssertNil(payload["accuracyM"])
    }

    func testCarriesDeviceIntegrityAtThePathsTheServerReads() throws {
        // The scoring engine reads rawPayload.device.isEmulator and
        // rawPayload.location.isMocked; the dashboard reads those plus
        // rawPayload.security. A renamed key is a fraud check that silently
        // stops firing, not a compile error.
        var event = makeEvent()
        event.deviceSignals = [
            "device": ["isEmulator": true],
            "location": ["isMocked": true],
            "security": ["isRooted": true],
        ]
        let raw = try XCTUnwrap(try decode(event)["rawPayload"] as? [String: Any])

        XCTAssertEqual((raw["device"] as? [String: Any])?["isEmulator"] as? Bool, true)
        XCTAssertEqual((raw["location"] as? [String: Any])?["isMocked"] as? Bool, true)
        XCTAssertEqual((raw["security"] as? [String: Any])?["isRooted"] as? Bool, true)
    }

    func testOmitsRawPayloadWhenNothingWasCollected() throws {
        XCTAssertNil(try decode(makeEvent())["rawPayload"])
    }

    func testOmitsTheMockFlagWhenTheOSCannotSayRatherThanClaimingFalse() {
        // Below iOS 15, and for any fix with no source information, CoreLocation
        // cannot answer. Reporting `false` would be an unearned all-clear.
        XCTAssertNil(AddressIQDeviceSignals.isMocked(nil))
    }

    func testEachEventIsSelfContainedForBatchSplicing() throws {
        // Flush joins queued rows with commas into {"events":[...]}, so a row
        // that is not exactly one object corrupts the batch.
        let json = try XCTUnwrap(makeEvent().jsonString())
        XCTAssertTrue(json.hasPrefix("{"))
        XCTAssertTrue(json.hasSuffix("}"))

        let spliced = "{\"events\":[\(json),\(json)]}"
        let decoded = try JSONSerialization.jsonObject(with: XCTUnwrap(spliced.data(using: .utf8)))
        let events = (decoded as? [String: Any])?["events"] as? [[String: Any]]
        XCTAssertEqual(events?.count, 2)
    }
}
