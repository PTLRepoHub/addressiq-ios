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
            "notifications": currentNotificationState(),
        ]
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
        await withCheckedContinuation { (cont: CheckedContinuation<CLAuthorizationStatus, Never>) in
            lock.lock()
            pendingContinuation = cont
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.manager.requestWhenInUseAuthorization()
            }
        }
    }

    private func requestAlwaysAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { (cont: CheckedContinuation<CLAuthorizationStatus, Never>) in
            lock.lock()
            pendingContinuation = cont
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.manager.requestAlwaysAuthorization()
            }
        }
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
