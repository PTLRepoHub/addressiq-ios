import Foundation
import CoreLocation

/**
 Device-integrity signals attached to every transit event.

 Booleans only. They answer "is this device lying about where it is" without
 identifying it: no install id, no IP, no carrier, no WiFi. Those are personal
 data and are a separate decision.

 iOS cannot enumerate installed apps, so it reports no spoofing-app signal at
 all rather than a `false` it has not checked.
 */
enum AddressIQDeviceSignals {

    /// Paths that only exist on a jailbroken device.
    private static let jailbreakMarkers = [
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/private/var/lib/apt/",
    ]

    private static let installIdKey = "addressiq_install_id"

    /// Sections for one event's `rawPayload`.
    static func collect(location: CLLocation?) -> [String: [String: Any]] {
        var sections: [String: [String: Any]] = [
            "device": ["isEmulator": isSimulator],
            "security": ["isRooted": isJailbroken()],
        ]
        if let installId = installId() {
            sections["fingerprint"] = ["installId": installId]
        }
        // Only claimable on iOS 15+. Omitted below that, so the server can tell
        // "not mocked" from "could not tell".
        if let isMocked = isMocked(location) {
            sections["location"] = ["isMocked": isMocked]
        }
        return sections
    }

    /**
     Random per-install identifier, minted once and kept in the keychain.

     Deliberately not a hardware id: it identifies this installation only and is
     scoped to this app. It is what links the same install verifying several
     different addresses.

     Keychain entries outlive an uninstall on iOS, which is a stronger signal
     than Android's but also means a reinstall keeps the same id.
     */
    static func installId(keychain: AddressIQKeychain = .shared) -> String? {
        if let existing = keychain.get(installIdKey), !existing.isEmpty { return existing }
        let minted = UUID().uuidString
        return keychain.set(minted, for: installIdKey) ? minted : nil
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Whether CoreLocation says this fix was simulated. Returns nil when the OS
    /// cannot say, which is anything below iOS 15.
    static func isMocked(_ location: CLLocation?) -> Bool? {
        guard let location else { return nil }
        if #available(iOS 15.0, *) {
            guard let source = location.sourceInformation else { return nil }
            return source.isSimulatedBySoftware
        }
        return nil
    }

    static func isJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        // The simulator ships several of these paths; reporting every simulator
        // run as jailbroken would be noise. isEmulator already covers it.
        return false
        #else
        return jailbreakMarkers.contains { FileManager.default.fileExists(atPath: $0) }
        #endif
    }
}
