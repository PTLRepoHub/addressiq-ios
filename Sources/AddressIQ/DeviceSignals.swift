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
    static func collect(
        location: CLLocation?,
        jailbreakMarkers markers: [String] = jailbreakMarkers,
        skipJailbreakCheckOnSimulator: Bool = true
    ) -> [String: [String: Any]] {
        var sections: [String: [String: Any]] = [
            "device": ["isEmulator": isSimulator],
            "security": [
                "isRooted": isJailbroken(
                    markers: markers,
                    skipOnSimulator: skipJailbreakCheckOnSimulator
                ),
            ],
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

    /**
     Whether any jailbreak marker is present.

     `markers` and `skipOnSimulator` are injectable so this can actually be
     exercised. The real markers are paths only a jailbroken device has, and the
     simulator short-circuit means that on the only hardware tests run on, this
     returns false unconditionally — so the firing path was never once observed.
     That is precisely the blind spot that hid Android's emulator heuristic and
     its spoofing-app check: both returned false meaning "could not look", and
     both were silently broken for their whole lives.

     Production passes nothing and behaves exactly as before.
     */
    static func isJailbroken(
        markers: [String] = jailbreakMarkers,
        skipOnSimulator: Bool = true
    ) -> Bool {
        #if targetEnvironment(simulator)
        // The simulator ships several of these paths; reporting every simulator
        // run as jailbroken would be noise. isEmulator already covers it.
        if skipOnSimulator { return false }
        #endif
        return markers.contains { FileManager.default.fileExists(atPath: $0) }
    }
}
