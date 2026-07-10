import Foundation
import CoreLocation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit
#endif

/**
 * SDK-owned iOS permission orchestrator.
 *
 * **Permission Trigger Ownership principle:** the integrating app
 * decides *when* verification begins. Everything after — checking
 * grants, driving the OS prompt, recovering denial, deep-linking to
 * Settings — is the SDK's job.
 *
 * iOS doesn't expose a `shouldShowRationale` analogue like Android.
 * The closest equivalent is `CLAuthorizationStatus.notDetermined`
 * (can still prompt) vs `.denied` (must deep-link to Settings). The
 * SDK surfaces both states + the deep-link helper so partners don't
 * need to reach for `CLLocationManager` or `UIApplication` themselves.
 *
 * Two-stage sequencing:
 *   Stage 1: `requestWhenInUseAuthorization`
 *   Stage 2: `requestAlwaysAuthorization` (only if Stage 1 granted)
 *   Stage 3 (parallel): `UNUserNotificationCenter.requestAuthorization`
 *
 * Stage 2 is sequenced after Stage 1 because iOS only honours the
 * "Always" prompt when the app already has WhenInUse — otherwise the
 * call silently no-ops.
 */
public final class AddressIQPermissionRequester: NSObject, CLLocationManagerDelegate {

    public static let shared = AddressIQPermissionRequester()

    private let manager = CLLocationManager()
    private var pendingContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private let lock = NSLock()

    private override init() {
        super.init()
        manager.delegate = self
    }

    // MARK: - Public reads

    /// Cross-SDK shape: `Map<String, String>` with foregroundLocation,
    /// backgroundLocation, notifications. Each value drawn from
    /// `{GRANTED, DENIED, NOT_DETERMINED, BLOCKED, UNAVAILABLE}`.
    ///
    /// iOS doesn't distinguish DENIED from BLOCKED — once the user
    /// denies a location permission, the OS won't re-prompt without
    /// the user toggling the grant in Settings. We map `.denied` to
    /// BLOCKED so the cross-SDK semantic (BLOCKED = needs Settings
    /// redirect) holds.
    public func getPermissionState() -> [String: String] {
        let locationStatus = currentAuthorizationStatus()
        let fg: String
        let bg: String
        switch locationStatus {
        case .authorizedAlways:
            fg = "GRANTED"; bg = "GRANTED"
        case .authorizedWhenInUse:
            fg = "GRANTED"; bg = "DENIED"
        case .denied:
            fg = "BLOCKED"; bg = "BLOCKED"
        case .restricted:
            fg = "UNAVAILABLE"; bg = "UNAVAILABLE"
        case .notDetermined:
            fg = "NOT_DETERMINED"; bg = "NOT_DETERMINED"
        @unknown default:
            fg = "UNAVAILABLE"; bg = "UNAVAILABLE"
        }
        return [
            "foregroundLocation": fg,
            "backgroundLocation": bg,
            "preciseLocation": currentAccuracyState(),
            "notifications": currentNotificationState(),
        ]
    }

    /// Precise-vs-approximate accuracy authorisation. Cross-SDK value set:
    /// `{GRANTED, REDUCED, UNAVAILABLE}`. On iOS < 14 accuracy is always full,
    /// so we report GRANTED. REDUCED means the user granted approximate
    /// ("Precise Location" off) and the SDK should re-prompt for full accuracy.
    public func currentAccuracyState() -> String {
        if #available(iOS 14.0, *) {
            switch manager.accuracyAuthorization {
            case .fullAccuracy: return "GRANTED"
            case .reducedAccuracy: return "REDUCED"
            @unknown default: return "UNAVAILABLE"
            }
        }
        return "GRANTED"
    }

    /// Whether the SDK can still prompt for a given scope. Returns
    /// `true` while the status is `.notDetermined`; `false` otherwise.
    /// Use to decide whether to show rationale UI before
    /// [requestPermissions] (rationale is wasted if the OS won't show
    /// the prompt — partners should deep-link to Settings instead).
    public func canRequestPermission(scope: PermissionScope) -> Bool {
        switch scope {
        case .foregroundLocation, .backgroundLocation:
            return currentAuthorizationStatus() == .notDetermined
        case .notifications:
            return currentNotificationState() == "NOT_DETERMINED"
        }
    }

    // MARK: - Public request

    /// Drive the OS permission prompt sequence and return the final
    /// state. Idempotent — already-granted scopes are skipped so a
    /// re-call after partial grant just prompts for the missing pieces.
    public func requestPermissions() async -> [String: String] {
        // Stage 1: when-in-use.
        if currentAuthorizationStatus() == .notDetermined {
            _ = await requestWhenInUseAuthorization()
        }

        // Stage 2: always — only meaningful if WhenInUse is granted.
        if currentAuthorizationStatus() == .authorizedWhenInUse {
            _ = await requestAlwaysAuthorization()
        }

        // Stage 3: notifications — independent of location.
        await requestNotificationAuthorization()

        return getPermissionState()
    }

    /// Request temporary full ("Precise") accuracy for the given Info.plist
    /// purpose key. Returns `true` once full accuracy is authorised. iOS < 14
    /// always has full accuracy, so it returns `true` immediately there.
    public func requestFullAccuracy(purposeKey: String) async -> Bool {
        guard #available(iOS 14.0, *) else { return true }
        if manager.accuracyAuthorization == .fullAccuracy { return true }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: purposeKey) { _ in
                cont.resume()
            }
        }
        return manager.accuracyAuthorization == .fullAccuracy
    }

    /// Drive the OS toward the combination address verification needs: Always +
    /// Precise. Prompts once for permissions, then — mirroring the widget's
    /// "keep re-prompting until Precise is on" screen — requests full accuracy.
    /// Returns the final state so the caller (native shell / web bridge) can
    /// decide whether to re-prompt or deep-link to Settings.
    public func requestPreciseAndAlways(purposeKey: String) async -> [String: String] {
        _ = await requestPermissions()
        _ = await requestFullAccuracy(purposeKey: purposeKey)
        return getPermissionState()
    }

    /// Foreground-only prompt: When-In-Use + Precise (full accuracy), WITHOUT the
    /// Always upgrade. Use for the "verify where you live" gate and one-shot fixes.
    /// Requesting Always inline can **hang** on iOS — after When-In-Use is granted,
    /// `requestAlwaysAuthorization` often leaves the status unchanged, so the
    /// delegate never fires and the awaiting continuation never resumes. Always is
    /// instead driven by the Settings-route screen (which polls `getPermissionState`).
    public func requestForegroundPrecise(purposeKey: String) async -> [String: String] {
        NSLog("[AddressIQ] requestForegroundPrecise start — status=\(currentAuthorizationStatus().rawValue)")
        // Each step is time-bounded: if the OS never fires the delegate / accuracy
        // callback (which strands the awaiting continuation and freezes the widget's
        // permission gate on "Checking…"), we fall through to the current state so the
        // gate always resolves and can advance (to the Settings-route screen).
        if currentAuthorizationStatus() == .notDetermined {
            _ = await Self.withTimeout(seconds: 20, fallback: currentAuthorizationStatus()) {
                await self.requestWhenInUseAuthorization()
            }
            NSLog("[AddressIQ] after whenInUse — status=\(currentAuthorizationStatus().rawValue)")
        }
        _ = await Self.withTimeout(seconds: 6, fallback: false) {
            await self.requestFullAccuracy(purposeKey: purposeKey)
        }
        let state = getPermissionState()
        NSLog("[AddressIQ] requestForegroundPrecise done — \(state)")
        return state
    }

    /// Race an async operation against a timeout so a stranded OS callback can't
    /// hang the caller forever. Returns the operation's result if it finishes in
    /// time, otherwise `fallback`.
    static func withTimeout<T: Sendable>(
        seconds: Double,
        fallback: T,
        _ operation: @escaping @Sendable () async -> T
    ) async -> T {
        await withTaskGroup(of: T.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return fallback
            }
            let result = await group.next() ?? fallback
            group.cancelAll()
            return result
        }
    }

    /// Deep-link to the host app's Settings page so the user can
    /// re-enable a `.denied` permission. Returns `true` if the
    /// URL opened successfully.
    public func openSettings() async -> Bool {
        #if canImport(UIKit)
        return await MainActor.run {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return false }
            return UIApplication.shared.canOpenURL(url)
                .also { if $0 { UIApplication.shared.open(url) } }
        }
        #else
        return false
        #endif
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        lock.lock()
        let cont = pendingContinuation
        pendingContinuation = nil
        lock.unlock()
        cont?.resume(returning: currentAuthorizationStatus())
    }

    // MARK: - Internals

    private func requestWhenInUseAuthorization() async -> CLAuthorizationStatus {
        // iOS silently no-ops the request (no dialog, no delegate callback) when
        // the usage string is missing — which would hang this continuation forever.
        // Guard so a mis-configured host degrades gracefully instead of freezing
        // the widget's permission gate on "Checking…".
        guard hasInfoPlistKey("NSLocationWhenInUseUsageDescription") else {
            print("[AddressIQ] Cannot request location: add NSLocationWhenInUseUsageDescription to your app's Info.plist.")
            return currentAuthorizationStatus()
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<CLAuthorizationStatus, Never>) in
            lock.lock()
            pendingContinuation = cont
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.manager.requestWhenInUseAuthorization()
            }
        }
    }

    private func requestAlwaysAuthorization() async -> CLAuthorizationStatus {
        guard hasInfoPlistKey("NSLocationAlwaysAndWhenInUseUsageDescription") else {
            print("[AddressIQ] Cannot request Always location: add NSLocationAlwaysAndWhenInUseUsageDescription to your app's Info.plist.")
            return currentAuthorizationStatus()
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<CLAuthorizationStatus, Never>) in
            lock.lock()
            pendingContinuation = cont
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.manager.requestAlwaysAuthorization()
            }
        }
    }

    private func hasInfoPlistKey(_ key: String) -> Bool {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.isEmpty == false
    }

    private func requestNotificationAuthorization() async {
        #if canImport(UserNotifications)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                cont.resume()
            }
        }
        #endif
    }

    private func currentAuthorizationStatus() -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return manager.authorizationStatus
        }
        return CLLocationManager.authorizationStatus()
    }

    private func currentNotificationState() -> String {
        #if canImport(UserNotifications)
        var result = "NOT_DETERMINED"
        let sem = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: result = "GRANTED"
            case .denied: result = "BLOCKED"
            case .notDetermined: result = "NOT_DETERMINED"
            @unknown default: result = "UNAVAILABLE"
            }
            sem.signal()
        }
        // Notification settings query is fast but async — wait briefly.
        _ = sem.wait(timeout: .now() + .milliseconds(500))
        return result
        #else
        return "NOT_DETERMINED"
        #endif
    }
}

/// Permission scopes the SDK manages. Used by [canRequestPermission].
public enum PermissionScope {
    case foregroundLocation
    case backgroundLocation
    case notifications
}

// MARK: - Internal sugar

private extension Bool {
    /// Tap helper — runs `block` with self and returns self. Lets the
    /// `canOpenURL` check stay a single expression on `MainActor.run`.
    func also(_ block: (Bool) -> Void) -> Bool {
        block(self); return self
    }
}
