import Foundation

/// One telemetry event, in the shape `POST /v1/transit-events/batch` accepts.
///
/// Field names mirror `TransitEventDto` in the ingest service. `locationId`
/// carries the public **location code**, not a UUID, because that is the key the
/// backend registers its geofence under.
struct AddressIQTransitEvent {
    /// Reported as `sdk_version` on every event. Bump the number with the
    /// release tag, and keep the `ios/` prefix.
    ///
    /// The prefix is the only thing that identifies which SDK produced an
    /// event. `deviceOs` cannot: the Flutter and React Native SDKs report
    /// `IOS` and `ANDROID` too, and a bare semver collides across them —
    /// Android and Flutter both shipped "0.3.0". Without this, a Flutter
    /// verification is indistinguishable from a native one, so per-SDK
    /// collection health cannot be measured and a fraud-signal gap cannot be
    /// attributed to a platform. Tokens match the idempotency-key vocabulary
    /// (`iqidem_ios_*`), per SDK contract §6.6.
    static let sdkVersion = "ios/0.7.0"

    /// Event types the ingest DTO accepts. iOS raises the region ones plus the
    /// periodic check; the rest are other platforms'.
    enum Kind: String {
        case enter = "GEOFENCE_ENTER"
        case exit = "GEOFENCE_EXIT"
        case backgroundCheck = "BACKGROUND_CHECK"
    }

    let eventId: String
    let locationCode: String
    let kind: Kind
    let latitude: Double?
    let longitude: Double?
    let accuracyM: Double?
    let deviceTimestamp: Date
    /// Device-integrity sections, keyed as the server reads them.
    var deviceSignals: [String: [String: Any]] = [:]

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func jsonObject() -> [String: Any] {
        var object: [String: Any] = [
            "eventId": eventId,
            "locationId": locationCode,
            "eventType": kind.rawValue,
            "deviceOs": "IOS",
            "sdkVersion": Self.sdkVersion,
            "deviceTimestamp": Self.timestampFormatter.string(from: deviceTimestamp),
        ]
        // A region callback can arrive with no usable fix. The event still
        // carries evidence of the transition, so it is sent without coordinates
        // rather than dropped.
        if let latitude { object["lat"] = latitude }
        if let longitude { object["lon"] = longitude }
        if let accuracyM, accuracyM >= 0 { object["accuracyM"] = accuracyM }
        // Absent rather than empty when nothing was collected: the dashboard
        // tells "no device data" apart from "checked and clean" by its presence.
        if !deviceSignals.isEmpty { object["rawPayload"] = deviceSignals }
        return object
    }

    /// Serialized for the queue. Each row is spliced into a JSON array at flush,
    /// so it has to be one self-contained object.
    func jsonString() -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: jsonObject()) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
