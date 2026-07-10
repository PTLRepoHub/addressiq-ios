#if canImport(UIKit)
import SwiftUI
import WebKit
import CoreLocation
import Foundation

/// Host for the shared AddressIQ web widget (the single cross-platform source of
/// truth for the collect/verify UI). This SwiftUI view embeds a `WKWebView` that
/// loads the widget and bridges the parts a webview cannot do itself — the
/// Always/Precise location prompt and the resulting fix — to the native
/// `AddressIQPermissionRequester`.
///
/// The widget speaks the `HostBridge` protocol:
///   JS → native (via `window.webkit.messageHandlers.addressiq`):
///     { kind: 'event',   name, payload }              — result handoff / close
///     { kind: 'request', id, action, payload }        — awaits a native reply
///   native → JS: `window.AddressIQBridge.resolve(id, result)` / `.reject(id, err)`
@available(iOS 15.0, *)
struct AddressIQWebFlowView: UIViewRepresentable {
    let apiKey: String
    let appUserId: String
    let apiURL: URL
    let widgetURL: URL
    let businessName: String?
    let primaryColorHex: String?
    let onCompleted: (AddressIQVerifyResult) -> Void
    let onCancelled: () -> Void
    let onFailed: (AddressIQVerifyError) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompleted: onCompleted, onCancelled: onCancelled, onFailed: onFailed)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "addressiq")
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.webView = webView
        context.coordinator.observeForeground()
        webView.loadHTMLString(htmlDocument(), baseURL: apiURL)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    /// Inline page that mounts the widget. `locationProvider` is intentionally
    /// omitted so the widget auto-selects its `BridgeLocationProvider` (native
    /// owns Always/Precise). The bridge is detected via `window.webkit`.
    private func htmlDocument() -> String {
        // Business identity (name/logo/colour) is fetched by the widget from the
        // backend (tenant behind the API key). Only forward a client-supplied
        // fallback when the integrator explicitly provided one.
        var cfg: [String: Any] = [
            "apiKey": apiKey,
            "apiUrl": apiURL.absoluteString,
            "appUserId": appUserId,
            // Drives the platform-specific "Location permission" Settings screen.
            "platform": "ios",
        ]
        var business: [String: Any] = [:]
        if let businessName { business["displayName"] = businessName }
        if let primaryColorHex { business["primaryColor"] = primaryColorHex }
        if !business.isEmpty { cfg["business"] = business }
        let cfgJSON = (try? JSONSerialization.data(withJSONObject: cfg))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        // Prefer the bundled widget (works offline, version-pinned); fall back to
        // the hosted bundle only if the resource is missing.
        let widgetScript: String
        if let bundled = Self.bundledWidgetJS() {
            widgetScript = "<script>\(bundled)</script>"
        } else {
            widgetScript = "<script src=\"\(widgetURL.absoluteString)\"></script>"
        }
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover" />
        <style>html,body{margin:0;height:100%;background:#fff}#mount{min-height:100%}</style>
        </head><body>
        <div id="mount"></div>
        \(widgetScript)
        <script>
          var cfg = \(cfgJSON);
          var c = new window.AddressIQ.IQCollect(document.getElementById('mount'), cfg);
          c.open();
        </script>
        </body></html>
        """
    }

    /// The widget bundle shipped as an SPM resource, if present.
    private static func bundledWidgetJS() -> String? {
        guard let url = Bundle.module.url(forResource: "iqcollect", withExtension: "js") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Bridge coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, CLLocationManagerDelegate {
        weak var webView: WKWebView?
        private let onCompleted: (AddressIQVerifyResult) -> Void
        private let onCancelled: () -> Void
        private let onFailed: (AddressIQVerifyError) -> Void

        private let locationManager = CLLocationManager()
        private var locationRequestId: String?
        private var foregroundObserver: NSObjectProtocol?

        init(
            onCompleted: @escaping (AddressIQVerifyResult) -> Void,
            onCancelled: @escaping () -> Void,
            onFailed: @escaping (AddressIQVerifyError) -> Void
        ) {
            self.onCompleted = onCompleted
            self.onCancelled = onCancelled
            self.onFailed = onFailed
            super.init()
            locationManager.delegate = self
        }

        deinit {
            if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
        }

        /// When the app returns to the foreground (e.g. back from Settings after
        /// the user changed Location to Always + Precise), nudge the widget to
        /// re-check permission immediately. The widget's `onHostVisible` listens on
        /// the window `focus` event; WKWebView's own `visibilitychange`/`focus` are
        /// unreliable across app background/foreground, so we dispatch it explicitly.
        func observeForeground() {
            guard foregroundObserver == nil else { return }
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.webView?.evaluateJavaScript("window.dispatchEvent(new Event('focus'));", completionHandler: nil)
            }
        }

        // MARK: JS → native

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            // The web HostBridge posts `JSON.stringify(...)`, so on iOS the body
            // is a String. Accept a raw dict too, for robustness.
            let dict: [String: Any]?
            if let s = message.body as? String, let data = s.data(using: .utf8) {
                dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            } else {
                dict = message.body as? [String: Any]
            }
            guard let dict = dict, let kind = dict["kind"] as? String else { return }
            if kind == "event" {
                handleEvent(name: dict["name"] as? String ?? "", payload: dict["payload"])
            } else if kind == "request", let id = dict["id"] as? String {
                handleRequest(id: id, action: dict["action"] as? String ?? "", payload: dict["payload"])
            }
        }

        private func handleEvent(name: String, payload: Any?) {
            let p = payload as? [String: Any]
            switch name {
            case "addressSelected", "verificationStarted":
                // Either terminal path completes the flow with a locationCode.
                let code = (p?["locationCode"] as? String) ?? ""
                let result = AddressIQVerifyResult(
                    locationCode: code,
                    formattedAddress: p?["formattedAddress"] as? String,
                    lat: (p?["geoPoint"] as? [String: Any])?["lat"] as? Double ?? 0,
                    lon: (p?["geoPoint"] as? [String: Any])?["lng"] as? Double ?? 0,
                    placeId: p?["placeId"] as? String
                )
                onCompleted(result)
            case "close":
                onCancelled()
            case "error":
                onFailed(AddressIQVerifyError(
                    code: p?["code"] as? String ?? "WIDGET_ERROR",
                    message: p?["message"] as? String ?? "Widget reported an error",
                    httpStatus: p?["httpStatus"] as? Int
                ))
            default:
                break
            }
        }

        private func handleRequest(id: String, action: String, payload: Any?) {
            switch action {
            case "getPermissionStatus":
                let fg = AddressIQ.shared.getPermissionState()["foregroundLocation"] ?? "NOT_DETERMINED"
                resolve(id, webPermission(from: fg))
            case "getLocation":
                Task { await self.provideLocation(requestId: id) }
            case "requestPermission":
                // The "Verify where you currently live" screen asks the host to run
                // its Always + Precise prompt here (a webview cannot). Report the
                // grant so the widget can gate progress: `foreground` requires BOTH
                // whenInUse and full ("Precise") accuracy — approximate is not enough.
                NSLog("[AddressIQ] bridge requestPermission received (id=\(id))")
                Task {
                    // Foreground + Precise ONLY. Requesting Always here can hang on
                    // iOS (the delegate doesn't fire when status stays WhenInUse),
                    // which left the gate button stuck on "Checking…". Always is
                    // granted separately via the Settings-route screen, which polls
                    // `getPermissionState` until `background` flips to granted.
                    let state = await AddressIQ.shared.requestForegroundLocation()
                    NSLog("[AddressIQ] bridge requestPermission resolving (id=\(id)) fg=\(state["foregroundLocation"] ?? "?") precise=\(state["preciseLocation"] ?? "?")")
                    self.resolve(id, [
                        "foreground": state["foregroundLocation"] == "GRANTED" && state["preciseLocation"] == "GRANTED",
                        "background": state["backgroundLocation"] == "GRANTED",
                    ])
                }
            case "getPermissionState":
                // Read WITHOUT prompting — the Settings screen polls this to detect
                // when Always + Precise has been toggled on return from Settings.
                let state = AddressIQ.shared.getPermissionState()
                resolve(id, [
                    "foreground": state["foregroundLocation"] == "GRANTED" && state["preciseLocation"] == "GRANTED",
                    "background": state["backgroundLocation"] == "GRANTED",
                ])
            case "openSettings":
                Task {
                    _ = await AddressIQ.shared.openSettings()
                    self.resolve(id, true)
                }
            default:
                reject(id, ["code": "UNKNOWN_ACTION", "message": "Unsupported bridge action: \(action)"])
            }
        }

        /// Ensure foreground + Precise, then return a one-shot fix. This is the
        /// moment the native permission prompt appears (webview cannot do it). Uses
        /// the foreground-only request — a one-shot fix needs When-In-Use + Precise,
        /// not Always (which can hang; see requestPermission above).
        private func provideLocation(requestId: String) async {
            let state = await AddressIQ.shared.requestForegroundLocation()
            let fg = state["foregroundLocation"] ?? "NOT_DETERMINED"
            guard fg == "GRANTED" else {
                reject(requestId, ["code": "PERMISSION_DENIED", "message": "Location permission not granted"])
                return
            }
            await MainActor.run {
                self.locationRequestId = requestId
                self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
                self.locationManager.requestLocation()
            }
        }

        // MARK: CLLocationManagerDelegate (one-shot fix)

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let id = locationRequestId, let loc = locations.last else { return }
            locationRequestId = nil
            resolve(id, [
                "lat": loc.coordinate.latitude,
                "lon": loc.coordinate.longitude,
                "accuracy": loc.horizontalAccuracy,
            ])
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            guard let id = locationRequestId else { return }
            locationRequestId = nil
            reject(id, ["code": "LOCATION_UNAVAILABLE", "message": error.localizedDescription])
        }

        // MARK: native → JS

        private func resolve(_ id: String, _ result: Any) {
            evaluate("window.AddressIQBridge && window.AddressIQBridge.resolve(\(quote(id)), \(json(result)));")
        }

        private func reject(_ id: String, _ error: Any) {
            evaluate("window.AddressIQBridge && window.AddressIQBridge.reject(\(quote(id)), \(json(error)));")
        }

        private func evaluate(_ js: String) {
            DispatchQueue.main.async { [weak self] in
                self?.webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        private func webPermission(from foreground: String) -> String {
            switch foreground {
            case "GRANTED": return "granted"
            case "BLOCKED", "DENIED": return "denied"
            case "NOT_DETERMINED": return "prompt"
            default: return "unknown"
            }
        }

        private func json(_ value: Any) -> String {
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let s = String(data: data, encoding: .utf8) else {
                // Scalars aren't valid top-level JSON objects — quote strings, print numbers.
                if let s = value as? String { return quote(s) }
                return "\(value)"
            }
            return s
        }

        private func quote(_ s: String) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
            let arr = String(data: data, encoding: .utf8) ?? "[\"\"]"
            return String(arr.dropFirst().dropLast()) // strip the surrounding [ ]
        }
    }
}
#endif
