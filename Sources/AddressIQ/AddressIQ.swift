//
// AddressIQ.swift — public singleton (Phase 3 SDK runtime).
//
// Mirrors the RN + Flutter SDKs at the public-method level:
//   AddressIQ.shared.initialize(config:)
//   AddressIQ.shared.setUser(_:)
//   AddressIQ.shared.startPhysical(_:) async throws -> StartPhysicalResult
//   AddressIQ.shared.startCombined(_:) async throws -> StartCombinedResult
//   AddressIQ.shared.cancelVerification(code:)
//   AddressIQ.shared.pauseVerification() / resumeVerification() / sync() / logout() / reset()
//   AddressIQ.shared.getVerificationState() / getPermissionState()
//
// Wire types and HTTP clients are generated from the OpenAPI + protobuf
// specs in CI (Phase 3 §protobuf-codegen). The structs below shape the
// public surface; the generated code drops into Generated/.

import Foundation
import CoreLocation
import Combine
#if canImport(UIKit)
import UIKit
#endif

public enum AddressIQLifecycleState: String {
    case uninitialized
    case idle
    case collecting
    case paused
    case terminated
}

public struct AddressIQConfig {
    public let apiKey: String
    public let environment: AddressIQEnvironment

    public init(
        apiKey: String,
        environment: AddressIQEnvironment = .production
    ) {
        self.apiKey = apiKey
        self.environment = environment
    }

    /// Effective API URL, resolved entirely from `environment`. The SDK
    /// never accepts a caller-supplied URL — production and sandbox point
    /// at the hosted backends, `.development` at the local dev backend.
    public var resolvedApiUrl: URL {
        return environment.defaultApiUrl
    }

    /// Effective ingest URL for transit-event batches, resolved entirely from
    /// `environment`. Ingestion is served by a dedicated host, distinct from
    /// the main API host.
    public var resolvedIngestUrl: URL {
        return environment.defaultIngestUrl
    }
}

public enum AddressIQEnvironment: String {
    case sandbox
    case production
    /// Local development backend. The compiled-in URL targets a backend
    /// running on the host machine; the iOS simulator reaches it via
    /// `localhost`. Never ship a build configured for `.development`.
    case development

    /// Public API base URL the SDK resolves to for this environment.
    public var defaultApiUrl: URL {
        switch self {
        case .production:
            // Baked in at publish time from the `ADDRESSIQ_API_URL` GitHub
            // variable; falls back to the literal if the value fails to parse.
            return URL(string: BuildConfig.apiURL) ?? URL(string: "https://api.addressiqpro.com")!
        case .sandbox:
            return URL(string: "https://api-staging.addressiqpro.com")!
        case .development:
            return URL(string: "http://localhost:3355")!
        }
    }

    /// Ingest base URL the SDK resolves to for this environment. Transit-event
    /// batches post here rather than to `defaultApiUrl`.
    public var defaultIngestUrl: URL {
        switch self {
        case .production:
            // Baked in at publish time from the `ADDRESSIQ_INGEST_URL` GitHub
            // variable; falls back to the literal if the value fails to parse.
            return URL(string: BuildConfig.ingestURL) ?? URL(string: "https://ingest-api.addressiqpro.com")!
        case .sandbox:
            return URL(string: "https://ingest-api-staging.addressiqpro.com")!
        case .development:
            return URL(string: "http://localhost:3355")!
        }
    }
}

public struct SDKUser {
    public let appUserId: String
    public let phone: String?
    public let email: String?
    public let firstName: String?
    public let lastName: String?

    public init(appUserId: String, phone: String? = nil, email: String? = nil, firstName: String? = nil, lastName: String? = nil) {
        self.appUserId = appUserId
        self.phone = phone
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
    }
}

public struct VerificationLifecycleState {
    public let state: AddressIQLifecycleState
    public let appUserId: String?
    public let verificationId: String?
    public let locationCode: String?
    public let pausedFor: TimeInterval?
}

public enum AddressIQError: Error, CustomStringConvertible {
    case notInitialized
    case noActiveSession
    case permissionDenied(message: String)
    case http(status: Int, code: String?, message: String?)
    case providerError(code: String, message: String)

    /// Stable cross-SDK error code string. Matches the closed set used by
    /// the RN / Flutter / Android SDKs.
    public var code: String {
        switch self {
        case .notInitialized: return "NOT_INITIALIZED"
        case .noActiveSession: return "NO_ACTIVE_SESSION"
        case .permissionDenied: return "PERMISSION_DENIED"
        case let .http(_, code, _): return code ?? "HTTP_ERROR"
        case let .providerError(code, _): return code
        }
    }

    public var description: String {
        switch self {
        case .notInitialized: return "AddressIQ.shared.initialize must be called first"
        case .noActiveSession: return "No active verification session"
        case let .permissionDenied(message): return "AddressIQ permission denied: \(message)"
        case let .http(status, code, message):
            return "AddressIQ HTTP \(status) \(code ?? "")\(message.map { ": \($0)" } ?? "")"
        case let .providerError(code, message):
            return "AddressIQ provider error \(code): \(message)"
        }
    }
}

public struct StartPhysicalArgs {
    public let locationCode: String
    public let provider: String
    public let agentId: String?
    public let slaHours: Int?
    public let metadata: [String: Any]?
    public let idempotencyKey: String?
    public let branchId: String?

    public init(
        locationCode: String,
        provider: String,
        agentId: String? = nil,
        slaHours: Int? = nil,
        metadata: [String: Any]? = nil,
        idempotencyKey: String? = nil,
        branchId: String? = nil
    ) {
        self.locationCode = locationCode
        self.provider = provider
        self.agentId = agentId
        self.slaHours = slaHours
        self.metadata = metadata
        self.idempotencyKey = idempotencyKey
        self.branchId = branchId
    }
}

public struct StartCombinedArgs {
    public let locationCode: String
    public let digitalProvider: String?
    public let physicalProvider: String
    public let startDigital: Bool
    public let agentId: String?
    public let slaHours: Int?
    public let metadata: [String: Any]?
    public let idempotencyKey: String?
    public let branchId: String?

    public init(
        locationCode: String,
        physicalProvider: String,
        digitalProvider: String? = nil,
        startDigital: Bool = true,
        agentId: String? = nil,
        slaHours: Int? = nil,
        metadata: [String: Any]? = nil,
        idempotencyKey: String? = nil,
        branchId: String? = nil
    ) {
        self.locationCode = locationCode
        self.digitalProvider = digitalProvider
        self.physicalProvider = physicalProvider
        self.startDigital = startDigital
        self.agentId = agentId
        self.slaHours = slaHours
        self.metadata = metadata
        self.idempotencyKey = idempotencyKey
        self.branchId = branchId
    }
}

public struct StartDigitalArgs {
    public let locationCode: String
    public let digitalProvider: String?
    public let metadata: [String: Any]?
    public let idempotencyKey: String?
    public let branchId: String?

    public init(
        locationCode: String,
        digitalProvider: String? = nil,
        metadata: [String: Any]? = nil,
        idempotencyKey: String? = nil,
        branchId: String? = nil
    ) {
        self.locationCode = locationCode
        self.digitalProvider = digitalProvider
        self.metadata = metadata
        self.idempotencyKey = idempotencyKey
        self.branchId = branchId
    }
}

/// Adaptive geofence the backend may return on a start* response. The SDK
/// honors it when registering OS region monitoring.
public struct AddressIQGeofence: Equatable {
    public let lat: Double
    public let lon: Double
    public let radiusM: Double

    public init(lat: Double, lon: Double, radiusM: Double) {
        self.lat = lat
        self.lon = lon
        self.radiusM = radiusM
    }

    /// Parse the `geofence` object from a backend JSON response. Returns
    /// `nil` when coordinates are absent so callers can no-op gracefully.
    public init?(json: [String: Any]?) {
        guard
            let json,
            let lat = (json["lat"] as? Double) ?? (json["lat"] as? NSNumber)?.doubleValue,
            let lon = (json["lon"] as? Double) ?? (json["lon"] as? NSNumber)?.doubleValue
        else { return nil }
        let radius = (json["radiusM"] as? Double)
            ?? (json["radiusM"] as? NSNumber)?.doubleValue
            ?? (json["radius"] as? Double)
            ?? 150
        self.lat = lat
        self.lon = lon
        self.radiusM = radius
    }
}

/// Result of a digital verification start. Carries the public
/// `verificationCode` + `status` plus the optional adaptive geofence.
public struct StartDigitalResult {
    public let verificationCode: String
    public let status: String
    public let geofence: AddressIQGeofence?

    public init(verificationCode: String, status: String, geofence: AddressIQGeofence?) {
        self.verificationCode = verificationCode
        self.status = status
        self.geofence = geofence
    }
}

public final class AddressIQ {
    public static let shared = AddressIQ()

    private let queue = DispatchQueue(label: "com.addressiq.sdk", attributes: .concurrent)
    private var config: AddressIQConfig?
    private var user: SDKUser?
    private var state: AddressIQLifecycleState = .uninitialized
    private var activeVerificationId: String?
    private var activeLocationCode: String?
    private var pausedAt: Date?
    private lazy var locationManager: AddressIQLocationManager = .init()
    private let stateSubject = CurrentValueSubject<VerificationLifecycleState, Never>(
        VerificationLifecycleState(
            state: .uninitialized,
            appUserId: nil,
            verificationId: nil,
            locationCode: nil,
            pausedFor: nil
        )
    )

    /// Combine publisher that emits the current lifecycle state on every
    /// transition. Drives partner UIs.
    public var statePublisher: AnyPublisher<VerificationLifecycleState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    private init() {}

    private func emitState() {
        // Always invoked from inside a `queue` barrier block, so build the
        // snapshot directly. Do NOT call getVerificationState() here — it does
        // `queue.sync`, which re-enters the same queue and deadlocks (crash).
        stateSubject.send(currentStateSnapshot())
    }

    /// Snapshot of the lifecycle state. Caller MUST already be on `queue`.
    private func currentStateSnapshot() -> VerificationLifecycleState {
        VerificationLifecycleState(
            state: state,
            appUserId: user?.appUserId,
            verificationId: activeVerificationId,
            locationCode: activeLocationCode,
            pausedFor: pausedAt.map { Date().timeIntervalSince($0) }
        )
    }

    // MARK: - Lifecycle

    public func initialize(config: AddressIQConfig) {
        queue.async(flags: .barrier) {
            self.config = config
            self.state = .idle
            self.emitState()
        }
        // Register the BGTaskScheduler handler so iOS can wake us for telemetry
        // flushes. Partners still need to declare the task identifier in their
        // Info.plist — see Phase 3 §iOS.
        AddressIQBackgroundScheduler.shared.register {
            await self.flushTelemetryQueue()
        }
    }

    private func flushTelemetryQueue() async {
        let batch = AddressIQTelemetryQueue.shared.dequeue(batchSize: 50)
        guard !batch.isEmpty, let config else { return }
        let payload = batch.map { $0.payload }.joined(separator: ",")
        let body = "{\"events\":[\(payload)]}"
        var request = URLRequest(url: config.resolvedIngestUrl.appendingPathComponent("/v1/transit-events/batch"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = body.data(using: .utf8)
        if let (_, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200
        {
            AddressIQTelemetryQueue.shared.acknowledge(rowIds: batch.map { $0.id })
        }
    }

    public func setUser(_ user: SDKUser) async throws {
        try requireInitialized()
        try await pauseVerification()
        queue.async(flags: .barrier) {
            self.user = user
            if self.state == .uninitialized || self.state == .terminated {
                self.state = .idle
            }
            self.emitState()
        }
        // Persist appUserId for crash-recovery so a relaunched app can resume
        // the right session after `setUser` is called again.
        AddressIQKeychain.shared.set(user.appUserId, for: "appUserId")
    }

    public func pauseVerification() async throws {
        guard state == .collecting else { return }
        queue.async(flags: .barrier) {
            self.pausedAt = Date()
            self.state = .paused
            self.emitState()
        }
        locationManager.stopMonitoring()
    }

    public func resumeVerification() async throws {
        guard state == .paused else { return }
        guard activeVerificationId != nil, activeLocationCode != nil else {
            throw AddressIQError.noActiveSession
        }
        queue.async(flags: .barrier) {
            self.pausedAt = nil
            self.state = .collecting
            self.emitState()
        }
    }

    @discardableResult
    public func sync() async throws -> Int {
        let before = AddressIQTelemetryQueue.shared.count()
        await flushTelemetryQueue()
        let after = AddressIQTelemetryQueue.shared.count()
        return max(0, before - after)
    }

    public func logout() async throws {
        try? await pauseVerification()
        if let user, let config {
            var request = URLRequest(url: config.resolvedApiUrl.appendingPathComponent("/api/v1/sdk/session"))
            request.httpMethod = "DELETE"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            let body: [String: Any] = [
                "appUserId": user.appUserId,
                "verificationCode": activeVerificationId as Any,
            ].compactMapValues { $0 }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: request)
        }
        queue.async(flags: .barrier) {
            self.user = nil
            self.activeVerificationId = nil
            self.activeLocationCode = nil
            self.pausedAt = nil
            self.state = .terminated
            self.emitState()
        }
        AddressIQKeychain.shared.wipeAll()
        AddressIQTelemetryQueue.shared.wipe()
    }

    public func reset() async {
        queue.async(flags: .barrier) {
            self.user = nil
            self.activeVerificationId = nil
            self.activeLocationCode = nil
            self.pausedAt = nil
            self.state = .uninitialized
            self.config = nil
            self.emitState()
        }
        AddressIQKeychain.shared.wipeAll()
        AddressIQTelemetryQueue.shared.wipe()
    }

    public func getVerificationState() -> VerificationLifecycleState {
        var snapshot: VerificationLifecycleState!
        queue.sync {
            snapshot = currentStateSnapshot()
        }
        return snapshot
    }

    // MARK: - Verification surface

    /// Start a digital address verification. Uses SDK telemetry +
    /// geofencing to score residency at the given location. Mirrors
    /// `startPhysicalVerification` but POSTs to `/verifications/digital`
    /// with `{"digitalProvider": <provider ?? "internal_ai">}`.
    @discardableResult
    public func startVerification(_ args: StartDigitalArgs) async throws -> StartDigitalResult {
        try assertReadyForVerificationStart()
        let config = try requireInitialized()
        let url = config.resolvedApiUrl.appendingPathComponent(
            "/api/v1/locations/\(args.locationCode)/verifications/digital"
        )
        var body: [String: Any] = ["digitalProvider": args.digitalProvider ?? "internal_ai"]
        if let metadata = args.metadata { body["metadata"] = metadata }
        let json = try await post(url, body: body, idempotencyKey: args.idempotencyKey, branchId: args.branchId)
        let result = StartDigitalResult(
            verificationCode: (json["verificationCode"] as? String) ?? "",
            status: (json["status"] as? String) ?? "PENDING",
            geofence: AddressIQGeofence(json: json["geofence"] as? [String: Any])
        )
        activateCollection(
            locationCode: (json["locationCode"] as? String) ?? args.locationCode,
            verificationCode: result.verificationCode,
            geofence: result.geofence
        )
        return result
    }

    /// Start a physical address verification. A partner-provided agent
    /// or KYC provider visits the address to confirm residency.
    @discardableResult
    public func startPhysicalVerification(_ args: StartPhysicalArgs) async throws -> [String: Any] {
        try assertReadyForVerificationStart()
        let config = try requireInitialized()
        let url = config.resolvedApiUrl.appendingPathComponent(
            "/api/v1/locations/\(args.locationCode)/verifications/physical"
        )
        var body: [String: Any] = ["provider": args.provider]
        if let agentId = args.agentId { body["agentId"] = agentId }
        if let slaHours = args.slaHours { body["slaHours"] = slaHours }
        if let metadata = args.metadata { body["metadata"] = metadata }
        let json = try await post(url, body: body, idempotencyKey: args.idempotencyKey, branchId: args.branchId)
        if let verificationCode = json["verificationCode"] as? String {
            activateCollection(
                locationCode: (json["locationCode"] as? String) ?? args.locationCode,
                verificationCode: verificationCode,
                geofence: AddressIQGeofence(json: json["geofence"] as? [String: Any])
            )
        }
        return json
    }

    /// Start a combined digital + physical verification. Digital runs
    /// first via the AI provider (uses SDK telemetry to score residency);
    /// physical fallback fires if the digital half resolves to UNKNOWN.
    @discardableResult
    public func startDigitalAndPhysicalVerification(_ args: StartCombinedArgs) async throws -> [String: Any] {
        try assertReadyForVerificationStart()
        let config = try requireInitialized()
        let url = config.resolvedApiUrl.appendingPathComponent(
            "/api/v1/locations/\(args.locationCode)/verifications/combined"
        )
        var body: [String: Any] = [
            "physicalProvider": args.physicalProvider,
            "startDigital": args.startDigital,
        ]
        if let digitalProvider = args.digitalProvider { body["digitalProvider"] = digitalProvider }
        if let agentId = args.agentId { body["agentId"] = agentId }
        if let slaHours = args.slaHours { body["slaHours"] = slaHours }
        if let metadata = args.metadata { body["metadata"] = metadata }
        let json = try await post(url, body: body, idempotencyKey: args.idempotencyKey, branchId: args.branchId)
        // The combined response nests the digital/physical codes; prefer the
        // digital verification code for the collection session.
        let digital = json["digital"] as? [String: Any]
        if let verificationCode = (digital?["verificationCode"] as? String)
            ?? (json["verificationCode"] as? String)
        {
            activateCollection(
                locationCode: (json["locationCode"] as? String) ?? args.locationCode,
                verificationCode: verificationCode,
                geofence: AddressIQGeofence(json: json["geofence"] as? [String: Any])
            )
        }
        return json
    }


    public func cancelVerification(_ code: String, idempotencyKey: String? = nil) async throws -> [String: Any] {
        let config = try requireInitialized()
        let url = config.resolvedApiUrl.appendingPathComponent("/api/v1/verifications/\(code)/cancel")
        return try await post(url, body: [:], idempotencyKey: idempotencyKey, branchId: nil)
    }

    public func listProviders(type: String? = nil) async throws -> [[String: Any]] {
        let config = try requireInitialized()
        let path = "/api/v1/providers" + (type.map { "?type=\($0)" } ?? "")
        var request = URLRequest(url: config.resolvedApiUrl.appendingPathComponent(path))
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw AddressIQError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0, code: nil, message: nil)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    // MARK: - Permission orchestration
    //
    // Cross-SDK contract §0 (Permission Trigger Ownership): the app
    // decides *when* verification begins; the SDK owns every step after
    // that. The methods below delegate to `AddressIQPermissionRequester`
    // so the singleton stays focused on lifecycle.

    /// Read-only permission snapshot. Cross-SDK shape:
    /// `{ foregroundLocation, backgroundLocation, notifications }` with
    /// values from `{GRANTED, DENIED, NOT_DETERMINED, BLOCKED, UNAVAILABLE}`.
    public func getPermissionState() -> [String: String] {
        AddressIQPermissionRequester.shared.getPermissionState()
    }

    /// Drive the OS permission prompts and return the final state.
    /// Two-stage sequencing: `requestWhenInUseAuthorization` →
    /// `requestAlwaysAuthorization` (only when stage 1 grants),
    /// plus parallel `UNUserNotificationCenter.requestAuthorization`.
    /// iOS silently no-ops "Always" without "WhenInUse" — sequencing
    /// matters.
    public func requestPermissions() async -> [String: String] {
        await AddressIQPermissionRequester.shared.requestPermissions()
    }

    /// Whether the SDK can still trigger the OS prompt for the given
    /// scope. Returns `true` only while the OS status is
    /// `.notDetermined`. Use to decide between rationale UI (when
    /// prompting is possible) and a Settings deep-link (when not).
    public func canRequestPermission(scope: PermissionScope) -> Bool {
        AddressIQPermissionRequester.shared.canRequestPermission(scope: scope)
    }

    /// Deep-link to the host app's Settings page so the user can
    /// re-enable a `.denied` permission. iOS will not re-prompt until
    /// they toggle the grant manually.
    public func openSettings() async -> Bool {
        await AddressIQPermissionRequester.shared.openSettings()
    }

    /// Precise-vs-approximate accuracy state: `{GRANTED, REDUCED, UNAVAILABLE}`.
    public func getAccuracyState() -> String {
        AddressIQPermissionRequester.shared.currentAccuracyState()
    }

    /// Drive the OS toward Always + Precise (the combination verification needs)
    /// and return the final permission snapshot. `purposeKey` must match an
    /// `NSLocationTemporaryUsageDescriptionDictionary` entry in the host
    /// app's Info.plist.
    public func requestPreciseAndAlways(purposeKey: String = "AddressVerification") async -> [String: String] {
        await AddressIQPermissionRequester.shared.requestPreciseAndAlways(purposeKey: purposeKey)
    }

    /// Foreground-only variant — When-In-Use + Precise, **no Always**. The web
    /// widget's permission gate and one-shot location fix use this; requesting
    /// Always inline can hang on iOS, so Always is granted via the Settings screen.
    public func requestForegroundLocation(purposeKey: String = "AddressVerification") async -> [String: String] {
        await AddressIQPermissionRequester.shared.requestForegroundPrecise(purposeKey: purposeKey)
    }

    // MARK: - Internal helpers

    public func markActiveSession(locationCode: String, verificationId: String) {
        queue.async(flags: .barrier) {
            self.activeLocationCode = locationCode
            self.activeVerificationId = verificationId
            self.state = .collecting
            self.pausedAt = nil
            self.emitState()
        }
        AddressIQBackgroundScheduler.shared.schedule()
    }

    /// Gate every verification start on granted location permissions
    /// (cross-SDK §0). Throws `AddressIQError.permissionDenied`
    /// (code string `PERMISSION_DENIED`) when foreground OR background
    /// location is not `GRANTED`.
    func assertReadyForVerificationStart() throws {
        let permissions = getPermissionState()
        if permissions["foregroundLocation"] != "GRANTED"
            || permissions["backgroundLocation"] != "GRANTED"
        {
            throw AddressIQError.permissionDenied(
                message: "Foreground and background location permissions are required before starting verification"
            )
        }
    }

    /// Activate the collection path for a freshly-started verification:
    /// mark the active session, register the adaptive geofence when the
    /// backend returned one, and schedule background monitoring. Reuses
    /// the existing helpers; best-effort so a monitoring failure never
    /// fails the start* call (P0-5 / P0-11).
    func activateCollection(
        locationCode: String,
        verificationCode: String,
        geofence: AddressIQGeofence?
    ) {
        guard !verificationCode.isEmpty else { return }
        markActiveSession(locationCode: locationCode, verificationId: verificationCode)
        if let geofence {
            locationManager.startMonitoring(
                latitude: geofence.lat,
                longitude: geofence.lon,
                radius: geofence.radiusM,
                identifier: verificationCode
            )
        }
    }

    private func requireInitialized() throws -> AddressIQConfig {
        guard let config = self.config else { throw AddressIQError.notInitialized }
        return config
    }

    private func post(
        _ url: URL,
        body: [String: Any],
        idempotencyKey: String?,
        branchId: String?
    ) async throws -> [String: Any] {
        let config = try requireInitialized()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(idempotencyKey ?? Self.makeIdempotencyKey(), forHTTPHeaderField: "idempotency-key")
        if let branchId { request.setValue(branchId, forHTTPHeaderField: "x-branch-id") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if status >= 400 {
            throw AddressIQError.http(
                status: status,
                code: json["code"] as? String,
                message: json["message"] as? String
            )
        }
        return json
    }

    private static func makeIdempotencyKey() -> String {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16)
        return "iqidem_ios_\(token)"
    }
}

/// Wraps CLLocationManager + geofence registration. Phase 3 ships the
/// public surface; the per-region monitoring details are filled in
/// alongside the protobuf-aligned telemetry envelope (P3.7).
final class AddressIQLocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    func startMonitoring(latitude: Double, longitude: Double, radius: Double, identifier: String) {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: radius,
            identifier: identifier
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
    }

    func stopMonitoring() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
    }
}
