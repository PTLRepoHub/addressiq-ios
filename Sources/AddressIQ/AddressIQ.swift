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
import os.log
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
    /// Tenant API key. This — not ``deployment`` — decides whether the tenant is
    /// in sandbox or production mode: `aiq_test_…` resolves to a sandbox App row
    /// server-side, `aiq_live_…` to a production one. The SDK never sends a mode.
    public let apiKey: String

    /// Which AddressIQ deployment (i.e. which hosts) to talk to. Orthogonal to
    /// sandbox-vs-production, which lives in ``apiKey``.
    public let deployment: AddressIQDeployment

    public init(
        apiKey: String,
        deployment: AddressIQDeployment = .production
    ) {
        self.apiKey = apiKey
        self.deployment = deployment
    }

    /// Effective API URL, resolved entirely from `deployment`. The SDK never
    /// accepts a caller-supplied URL — `.production` and `.staging` point at the
    /// hosted backends, `.development` at the local dev backend.
    public var resolvedApiUrl: URL {
        return deployment.defaultApiUrl
    }

    /// Effective ingest URL for transit-event batches, resolved entirely from
    /// `deployment`. Ingestion is served by a dedicated host, distinct from
    /// the main API host.
    public var resolvedIngestUrl: URL {
        return deployment.defaultIngestUrl
    }

    /// Effective CDN base URL for this deployment.
    ///
    /// The verify widget is loaded from here at the immutable, SRI-pinned path
    /// `{cdn}/v{deployment.defaultWidgetVersion}/iqcollect.js`, and ONLY from here — the
    /// SDK ships no bundled copy, so a failure surfaces WIDGET_LOAD_FAILED rather
    /// than falling back. See AddressIQWebFlowView for the full model.
    public var resolvedCdnUrl: URL {
        return deployment.defaultCdnUrl
    }
}

/// Which AddressIQ DEPLOYMENT the SDK talks to — i.e. which hosts.
///
/// This is NOT the tenant's mode. Sandbox-vs-production is a property of the API
/// KEY (`aiq_test_…` resolves to a sandbox tenant server-side, `aiq_live_…` to a
/// production one) and is decided entirely by the backend on every request — the
/// SDK neither sends it nor can influence it. The two axes are orthogonal: a test
/// key against the `.production` deployment is still sandbox.
///
/// `sandbox` was previously accepted here as an alias for ``staging`` — both as a
/// source-level `static let` and as a `"sandbox"` raw value — which asserted that
/// sandbox was a deployment. It is not, and both are now removed:
/// `AddressIQDeployment(rawValue: "sandbox")` returns `nil`.
public enum AddressIQDeployment: String {
    /// Pre-production. Named `staging` across all AddressIQ SDKs and matching
    /// the `STAGING_*` build variables.
    case staging
    case production
    /// Local development backend. The compiled-in URL targets a backend
    /// running on the host machine; the iOS simulator reaches it via
    /// `localhost`. Deliberately NOT baked from CI — it is a local-only
    /// concern. Never ship a build configured for `.development`.
    case development

    // NOTE: no custom `init?(rawValue:)`. The previous one existed solely to map
    // the legacy `"sandbox"` string onto `.staging`; with the alias gone, the
    // synthesised initialiser is correct and returns nil for an unknown value.

    /// A development-only override read from the process environment, or nil.
    ///
    /// Set them as **Environment Variables on your Xcode scheme** (Product → Scheme
    /// → Edit Scheme → Run → Arguments), or export them before `swift test`. They
    /// exist because the `development` hosts are otherwise hardcoded to
    /// `localhost:4000`, with no way to reach a backend on another machine.
    ///
    /// Scheme variables belong to the scheme, not the binary, so they cannot leak
    /// into a released build — but the gate below does not rely on that: an
    /// override supplied on any deployment other than `.development` is a **fatal
    /// misconfiguration**, not a value to be quietly ignored. A build-time variable
    /// must never be able to point a shipped app at an arbitrary host.
    ///
    /// `env` is a parameter only so tests can drive both sides of the switch.
    func devOverride(
        _ name: String,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard let value = env[name], !value.isEmpty else { return nil }
        guard self == .development else {
            preconditionFailure(
                "AddressIQ: \(name) is a development-only override, but deployment is "
                    + "\"\(rawValue)\". Outside development the SDK resolves its hosts from the "
                    + "values baked at release — it will not let an environment variable point a "
                    + "shipped app at an arbitrary host. Unset \(name), or use .development."
            )
        }
        return value
    }

    /// Public API base URL the SDK resolves to for this deployment.
    ///
    /// `production` and `staging` are baked in at publish time from the
    /// `PROD_ADDRESSIQ_API_BASE_URL` / `STAGING_ADDRESSIQ_API_BASE_URL` GitHub variables; each
    /// falls back to its checked-in literal if the baked value fails to parse.
    public var defaultApiUrl: URL {
        // Development-only override (see `devOverride`). Lets a build reach a backend
        // on another machine — the default is a hardcoded localhost literal.
        if let o = devOverride("ADDRESSIQ_DEV_API_URL"), let url = URL(string: o) { return url }
        switch self {
        case .production:
            return URL(string: BuildConfig.prodApiURL) ?? URL(string: "https://api.addressiqpro.com")!
        case .staging:
            return URL(string: BuildConfig.stagingApiURL) ?? URL(string: "https://api-staging.addressiqpro.com")!
        case .development:
            return URL(string: "http://localhost:4000")!
        }
    }

    /// Ingest base URL the SDK resolves to for this deployment. Transit-event
    /// batches post here rather than to `defaultApiUrl`. Baked from
    /// `PROD_ADDRESSIQ_INGEST_BASE_URL` / `STAGING_ADDRESSIQ_INGEST_BASE_URL`.
    public var defaultIngestUrl: URL {
        // Development-only override (see `devOverride`). Lets a build reach a backend
        // on another machine — the default is a hardcoded localhost literal.
        if let o = devOverride("ADDRESSIQ_DEV_INGEST_URL"), let url = URL(string: o) { return url }
        switch self {
        case .production:
            return URL(string: BuildConfig.prodIngestURL) ?? URL(string: "https://ingest-api.addressiqpro.com")!
        case .staging:
            return URL(string: BuildConfig.stagingIngestURL) ?? URL(string: "https://ingest-api-staging.addressiqpro.com")!
        case .development:
            // Ingest is its own service on its own port — 4000 is the API.
            // See docker-compose.yml: api 4000, ingest 4001.
            return URL(string: "http://localhost:4001")!
        }
    }

    /// CDN base URL for this deployment. Baked from `PROD_ADDRESSIQ_CDN_BASE_URL` /
    /// `STAGING_ADDRESSIQ_CDN_BASE_URL`. See ``AddressIQConfig/resolvedCdnUrl`` — the
    /// verify widget is loaded from here (SRI-pinned) with the bundled asset as
    /// the fallback. `.development` never loads remotely.
    public var defaultCdnUrl: URL {
        // Development-only override (ADDRESSIQ_DEV_CDN_URL). Lets a dev build load
        // the widget from a CDN you serve yourself.
        if let o = devOverride("ADDRESSIQ_DEV_CDN_URL"), let url = URL(string: o) { return url }
        switch self {
        case .production:
            return URL(string: BuildConfig.prodCdnURL) ?? URL(string: "https://cdn.addressiqpro.com")!
        case .staging:
            return URL(string: BuildConfig.stagingCdnURL) ?? URL(string: "https://cdn-staging.addressiqpro.com")!
        case .development:
            // NOT the dev host: the local backend serves no /v{x.y.z}/iqcollect.js,
            // and the SDK ships no bundled copy, so a dev build loads the real
            // pinned widget from the production CDN. Override with ADDRESSIQ_DEV_CDN_URL.
            return URL(string: BuildConfig.prodCdnURL) ?? URL(string: "https://cdn.addressiqpro.com")!
        }
    }

    /// Bare widget version pinned for this deployment. staging and prod are
    /// pinned separately (their bundles differ byte-for-byte); `.development`
    /// reuses the prod pin because it loads the widget from the prod CDN.
    public var defaultWidgetVersion: String {
        switch self {
        case .production, .development: return BuildConfig.prodWidgetVersion
        case .staging: return BuildConfig.stagingWidgetVersion
        }
    }

    /// SRI hash pinned for this deployment's widget bundle. Must correspond to
    /// `defaultWidgetVersion` on `defaultCdnUrl`, or the SRI check fails.
    public var defaultWidgetIntegrity: String {
        switch self {
        case .production, .development: return BuildConfig.prodWidgetIntegrity
        case .staging: return BuildConfig.stagingWidgetIntegrity
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

extension URLRequest {
    /// Auth plus SDK identity, on every request.
    ///
    /// `x-sdk-name`/`x-sdk-version` let the server tell platforms and versions
    /// apart — without them a request from this SDK is indistinguishable from
    /// one from Android or Flutter. The version comes from `BuildConfig`, baked
    /// from `version.txt`, so it cannot drift from the released artifact.
    mutating func setIdentifyingHeaders(apiKey: String) {
        setValue(apiKey, forHTTPHeaderField: "x-api-key")
        setValue("addressiq-ios", forHTTPHeaderField: "x-sdk-name")
        setValue(BuildConfig.sdkVersion, forHTTPHeaderField: "x-sdk-version")
    }
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
        // Region crossings are the collection path. Wired here rather than at
        // start-verification time because iOS relaunches a killed app straight
        // into the delegate callback, and initialize() is what runs first.
        locationManager.onTransition = { [weak self] kind, location, locationCode in
            self?.recordTransitEvent(kind: kind, location: location, locationCode: locationCode)
        }
        // Register the BGTaskScheduler handler so iOS can wake us for telemetry
        // flushes. Partners still need to declare the task identifier in their
        // Info.plist — see Phase 3 §iOS.
        AddressIQBackgroundScheduler.shared.register {
            await self.recordBackgroundCheck()
            await self.flushTelemetryQueue()
        }
    }

    /// Queue one event against `locationCode`, which is what ingest resolves the
    /// geofence by.
    ///
    /// The code is taken from the monitored region rather than the in-memory
    /// session: iOS relaunches a killed app straight into a region callback, and
    /// at that point nothing in memory has been restored yet.
    func recordTransitEvent(
        kind: AddressIQTransitEvent.Kind,
        location: CLLocation?,
        locationCode: String
    ) {
        guard !locationCode.isEmpty else { return }

        let coordinate = location
            .map(\.coordinate)
            .flatMap { CLLocationCoordinate2DIsValid($0) ? $0 : nil }
        let event = AddressIQTransitEvent(
            eventId: UUID().uuidString,
            locationCode: locationCode,
            kind: kind,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            accuracyM: location?.horizontalAccuracy,
            deviceTimestamp: location?.timestamp ?? Date(),
            deviceSignals: AddressIQDeviceSignals.collect(location: location)
        )
        guard let json = event.jsonString() else { return }
        AddressIQTelemetryQueue.shared.enqueue(eventJSON: json, eventId: event.eventId)

        // A crossing wakes the app for a few seconds, so try to send now and
        // leave the scheduled task as the fallback for when that is not enough.
        Task { await self.flushTelemetryQueue() }
        AddressIQBackgroundScheduler.shared.schedule()
    }

    /// Periodic evidence that the device is still where it claims, recorded each
    /// time iOS grants a background window. Region crossings alone say nothing
    /// about someone who simply stays home, which is the case being verified.
    private func recordBackgroundCheck() async {
        let sessionCode = queue.sync { self.activeLocationCode }
        // After a relaunch nothing in memory is restored yet, but CoreLocation
        // is still monitoring, so the region identifier stands in.
        guard let locationCode = sessionCode ?? locationManager.monitoredIdentifier else { return }

        // A cached fix from hours ago is not evidence of where the device is
        // now. Better to record nothing than to record it as current.
        //
        // Region monitoring is edge-triggered, so someone asleep at home crosses
        // nothing all night and the cached fix ages out — leaving the overnight
        // hours, the ones that actually evidence residency, with no readings at
        // all. So when the cache is stale, ask for a current fix rather than
        // giving up. The request is bounded well inside the background window,
        // and yields nil if the OS declines or is slow, which lands on the same
        // "record nothing" as before.
        var location = locationManager.lastKnownLocation
        if !Self.isFixFresh(location) {
            location = await locationManager.requestFreshLocation(
                timeout: Self.backgroundFixTimeout
            )
        }

        guard let location, Self.isFixFresh(location) else { return }
        recordTransitEvent(kind: .backgroundCheck, location: location, locationCode: locationCode)
    }

    private static func isFixFresh(_ location: CLLocation?) -> Bool {
        guard let location else { return false }
        return Date().timeIntervalSince(location.timestamp) <= backgroundCheckMaxFixAge
    }

    /// Oldest cached fix still worth reporting as a background check.
    private static let backgroundCheckMaxFixAge: TimeInterval = 15 * 60

    /// Bounded well inside the ~30s the background task gets, leaving room for
    /// the queue flush that follows.
    private static let backgroundFixTimeout: TimeInterval = 10

    private func flushTelemetryQueue() async {
        let batch = AddressIQTelemetryQueue.shared.dequeue(batchSize: 50)
        guard !batch.isEmpty, let config else { return }
        let payload = batch.map { $0.payload }.joined(separator: ",")
        let body = "{\"events\":[\(payload)]}"
        var request = URLRequest(url: config.resolvedIngestUrl.appendingPathComponent("/v1/transit-events/batch"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setIdentifyingHeaders(apiKey: config.apiKey)
        request.httpBody = body.data(using: .utf8)
        // Any 2xx, not just 200. `POST /v1/transit-events/batch` is a NestJS
        // @Post and answers 201 Created, so an exact `== 200` never
        // acknowledged: the rows stayed on the queue and the same batch was
        // re-uploaded on every flush, for the life of the install. Ingest
        // deduplicates by eventId so nothing was corrupted server-side — the
        // queue simply never drained, and grew without bound.
        if let (_, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse,
           (200..<300).contains(http.statusCode)
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
            request.setIdentifyingHeaders(apiKey: config.apiKey)
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
        request.setIdentifyingHeaders(apiKey: config.apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw AddressIQError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0, code: nil, message: nil)
        }
        if data.isEmpty { return [] }
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw AddressIQError.http(
                status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                code: "INVALID_RESPONSE",
                message: "Expected a JSON array of objects"
            )
        }
        return list
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
            // Identified by LOCATION code, not verification code: the identifier
            // is all a relaunched process has, and it is the key ingest resolves
            // the geofence by.
            locationManager.startMonitoring(
                latitude: geofence.lat,
                longitude: geofence.lon,
                radius: geofence.radiusM,
                identifier: locationCode
            )
        }
    }

    /**
     Begin collecting for a verification this SDK did not start.

     The Flutter and React Native SDKs make their own REST call and then need
     the native collection path — geofence monitoring, device signals, the
     encrypted queue, background scheduling — to run underneath. Without a
     public entry they reimplemented all of it, and neither reimplementation
     collected a single device signal, so every fraud check was dark on those
     platforms.

     `activateCollection` is the internal equivalent used by `start*`; this is
     the same behaviour with the arguments a wrapper actually has. Best-effort
     in the same way: a monitoring failure never throws, because the
     verification has already been created server-side by the caller.
     */
    public func startCollecting(
        locationCode: String,
        verificationCode: String,
        latitude: Double?,
        longitude: Double?,
        radiusM: Double?
    ) {
        let geofence: AddressIQGeofence? = {
            guard let latitude, let longitude else { return nil }
            return AddressIQGeofence(lat: latitude, lon: longitude, radiusM: radiusM ?? 150)
        }()
        activateCollection(
            locationCode: locationCode,
            verificationCode: verificationCode,
            geofence: geofence
        )
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
        request.setIdentifyingHeaders(apiKey: config.apiKey)
        request.setValue(idempotencyKey ?? Self.makeIdempotencyKey(), forHTTPHeaderField: "idempotency-key")
        if let branchId { request.setValue(branchId, forHTTPHeaderField: "x-branch-id") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // An error body that is not JSON must not mask the status it came with,
        // so decode leniently here and strictly below.
        let errorJSON = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if status >= 400 {
            throw AddressIQError.http(
                status: status,
                code: errorJSON["code"] as? String,
                message: errorJSON["message"] as? String
            )
        }
        return try Self.decodeObject(data, status: status)
    }

    /// Decodes a success body, refusing to invent an empty one.
    ///
    /// This used to be `(try? …) ?? [:]`, so a 200 carrying a truncated or
    /// non-JSON body became an empty dictionary; callers then read
    /// `json["verificationCode"] as? String ?? ""` and returned a *successful*
    /// result with empty fields. A response we cannot read is an error, and
    /// saying so beats handing back a verification code of "".
    ///
    /// An empty body stays an empty dictionary: 204-shaped endpoints (cancel)
    /// legitimately return nothing.
    internal static func decodeObject(_ data: Data, status: Int) throws -> [String: Any] {
        if data.isEmpty { return [:] }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AddressIQError.http(
                status: status,
                code: "INVALID_RESPONSE",
                message: "Expected a JSON object; got \(data.count) bytes that could not be read as one"
            )
        }
        return json
    }

    private static func makeIdempotencyKey() -> String {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16)
        return "iqidem_ios_\(token)"
    }
}

/// Wraps CLLocationManager + geofence registration, and turns region crossings
/// into telemetry.
///
/// Region monitoring is what makes collection survive the app being killed: iOS
/// relaunches the host on a crossing and delivers it to the delegate.
final class AddressIQLocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    /// Raised on every crossing, carrying the region's identifier. Region
    /// callbacks bring no fix of their own, so the manager's last known location
    /// is passed alongside.
    var onTransition: ((AddressIQTransitEvent.Kind, CLLocation?, String) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        // The one-shot background fix runs on battery, in a window iOS grants
        // grudgingly. Ten metres is well inside the smallest geofence we
        // register, so the default best-available accuracy would spend power
        // and time resolving a precision the decision cannot use.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Most recent fix, for the periodic background check. Reading this does not
    /// start location updates.
    var lastKnownLocation: CLLocation? { manager.location }

    /// Continuations waiting on `requestFreshLocation`. Guarded by `stateLock`,
    /// because CoreLocation calls back on the main queue while the background
    /// task awaits on its own.
    private var fixWaiters: [CheckedContinuation<CLLocation?, Never>] = []
    private let stateLock = NSLock()

    /**
     Ask CoreLocation for one current fix, giving up after `timeout`.

     `manager.location` is only whatever CoreLocation last happened to produce.
     With region monitoring alone — which is edge-triggered — a device sitting
     still at home overnight produces nothing, so the cached fix ages out and the
     periodic background check has nothing recent enough to report. That is
     precisely the resident being verified, and precisely when evidence matters.

     Returns nil rather than throwing when the OS declines or is too slow: the
     caller then records nothing, which is the same outcome as before this
     existed. It can only add readings, never fabricate one.
     */
    func requestFreshLocation(timeout: TimeInterval) async -> CLLocation? {
        // Only meaningful with an authorization that survives backgrounding.
        // Asking without one wakes the radio for a callback that never arrives.
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = manager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        guard status == .authorizedAlways else { return nil }
        return await awaitFix(timeout: timeout)
    }

    /// Asks for a fix and waits, with no view on whether asking was allowed.
    /// Split from the check above so each half can be exercised on its own —
    /// the simulator never grants `authorizedAlways`, so the waiting half is
    /// otherwise unreachable in a test.
    func awaitFix(timeout: TimeInterval) async -> CLLocation? {
        return await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            stateLock.lock()
            fixWaiters.append(continuation)
            let isFirst = fixWaiters.count == 1
            stateLock.unlock()

            // One in-flight request serves every waiter; requestLocation()
            // cancels the previous one if called again.
            if isFirst {
                DispatchQueue.main.async { self.manager.requestLocation() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    self.resolveFixWaiters(with: nil)
                }
            }
        }
    }

    /// Resumes every waiter exactly once. A continuation resumed twice traps, so
    /// the list is drained under the lock before any of them is touched.
    private func resolveFixWaiters(with location: CLLocation?) {
        stateLock.lock()
        let waiters = fixWaiters
        fixWaiters.removeAll()
        stateLock.unlock()
        for waiter in waiters { waiter.resume(returning: location) }
    }

    /// Identifier of the region still being monitored. CoreLocation keeps
    /// monitoring across launches, so this outlives the in-memory session.
    var monitoredIdentifier: String? { manager.monitoredRegions.first?.identifier }

    func startMonitoring(latitude: Double, longitude: Double, radius: Double, identifier: String) {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: radius,
            identifier: identifier
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true

        // Release whatever was being monitored first. CoreLocation keeps
        // regions across launches and caps an app at 20 of them; past that,
        // `startMonitoring(for:)` fails silently and the SDK collects nothing
        // for the rest of the install's life. The SDK only ever has one active
        // verification, so anything still registered is from a finished one.
        for stale in manager.monitoredRegions where stale.identifier != identifier {
            manager.stopMonitoring(for: stale)
        }

        manager.startMonitoring(for: region)
        // Someone who is already home when the verification starts crosses
        // nothing, so no entry is raised until they leave and come back. Ask for
        // the current state to record that they are inside from the outset.
        manager.requestState(for: region)
    }

    func stopMonitoring() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        resolveFixWaiters(with: locations.last)
    }

    /// Region registration failing is otherwise completely silent: monitoring
    /// simply never starts and no event is ever produced. The common cause is
    /// CoreLocation's 20-region-per-app cap, which is why stale regions are
    /// released in `startMonitoring`.
    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        os_log(
            "AddressIQ: geofence registration failed for %{public}@ — %{public}@ (monitoring %d region(s))",
            log: .default,
            type: .error,
            region?.identifier ?? "unknown",
            error.localizedDescription,
            manager.monitoredRegions.count
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A failed fix is indistinguishable from a slow one for our purposes:
        // either way there is nothing current to report.
        resolveFixWaiters(with: nil)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        onTransition?(.enter, manager.location, region.identifier)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        onTransition?(.exit, manager.location, region.identifier)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didDetermineState state: CLRegionState,
        for region: CLRegion
    ) {
        guard state == .inside else { return }
        onTransition?(.enter, manager.location, region.identifier)
    }
}
