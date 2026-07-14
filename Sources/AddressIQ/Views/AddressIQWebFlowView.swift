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
    /// Explicit developer override. Takes precedence over BOTH the CDN and the
    /// bundled widget. `nil` means "resolve normally" — see `widgetScriptTag`.
    let widgetURL: URL?
    /// Which deployment we resolved from. `.development` never loads remotely.
    let deployment: AddressIQDeployment
    /// CDN base for this deployment (no trailing slash). The immutable widget
    /// lives at `{cdnBaseURL}/v{version}/iqcollect.js`.
    let cdnBaseURL: URL?
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

        // Fail closed: with no CDN pin, no bundled widget and no explicit
        // override there is nothing to load. Never load an unpinned script.
        guard let document = htmlDocument() else {
            onFailed(AddressIQVerifyError(
                code: "WIDGET_BUNDLE_MISSING",
                message: "The bundled widget (iqcollect.js) is missing from the AddressIQ "
                    + "package and no widgetURL override was supplied. This is a packaging "
                    + "bug; the SDK will not load the widget from a remote host.",
                httpStatus: nil
            ))
            return webView
        }
        webView.loadHTMLString(document, baseURL: apiURL)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    /// Inline page that mounts the widget. `locationProvider` is intentionally
    /// omitted so the widget auto-selects its `BridgeLocationProvider` (native
    /// owns Always/Precise). The bridge is detected via `window.webkit`.
    /// Returns `nil` when no widget source at all resolves — the caller then
    /// fails closed with `WIDGET_BUNDLE_MISSING`.
    func htmlDocument() -> String? {
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
        // Development-only Maps key (ADDRESSIQ_DEV_GOOGLE_MAPS_KEY). Normally the
        // widget provisions its own key — it fetches one from GET /api/v1/widget/config
        // and falls back to the key baked into the vendored bundle — so this is absent
        // in every shipped build. It covers the case that breaks: a local backend with
        // no Maps key configured. `devGoogleMapsKey` traps outside .development.
        //
        // NOTE: inert until addressiq-web's `googleMapsApiKey` field ships and that
        // build is re-vendored here by the fanout; the widget currently reads only the
        // remote value or its own baked literal.
        if let devMapsKey = deployment.devGoogleMapsKey {
            cfg["googleMapsApiKey"] = devMapsKey
        }
        var business: [String: Any] = [:]
        if let businessName { business["displayName"] = businessName }
        if let primaryColorHex { business["primaryColor"] = primaryColorHex }
        if !business.isEmpty { cfg["business"] = business }
        let cfgJSON = (try? JSONSerialization.data(withJSONObject: cfg))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        guard let widgetScript = Self.widgetScriptTag(
            widgetURL: widgetURL,
            deployment: deployment,
            cdnBaseURL: cdnBaseURL,
            widgetVersion: BuildConfig.widgetVersion,
            widgetIntegrity: BuildConfig.widgetIntegrity,
            bundledJS: Self.bundledWidgetJS()
        ) else {
            return nil
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

    /// Builds the `<script>` markup that brings the widget into the page.
    ///
    /// Resolution order (see the model note in AddressIQVerifyView):
    ///   1. `widgetURL` — explicit developer override, wins over everything.
    ///   2. CDN, if every precondition holds: a shippable deployment, a CDN
    ///      base, and BOTH a baked `widgetVersion` and `widgetIntegrity`. The
    ///      tag carries an SRI `integrity` pin, which WebKit enforces: a
    ///      tampered or mismatched bundle refuses to execute and fires
    ///      `onerror`, which drops us to (3). The bundled widget is embedded in
    ///      the same page as `__iqWidgetFallback()` — defined BEFORE the remote
    ///      tag — so a CDN outage, an offline device, or an SRI failure all land
    ///      on the bundle rather than a blank sheet. On a clean CDN load the
    ///      fallback is never invoked.
    ///   3. Bundled widget inline, exactly as before the CDN existed.
    /// Returns `nil` only when nothing is loadable: no override, preconditions
    /// unmet, and no bundle. The caller fails closed.
    ///
    /// A blocking classic `<script>` runs (or errors) before the parser reaches
    /// the next inline script, so by the time the mount script runs, either the
    /// CDN bundle or the fallback has already defined `window.AddressIQ`.
    static func widgetScriptTag(
        widgetURL: URL?,
        deployment: AddressIQDeployment,
        cdnBaseURL: URL?,
        widgetVersion: String,
        widgetIntegrity: String,
        bundledJS: String?
    ) -> String? {
        if let widgetURL {
            return "<script src=\"\(widgetURL.absoluteString)\"></script>"
        }

        // An empty bundle string is a missing bundle, not an empty widget —
        // `<script></script>` would define no `window.AddressIQ` and hang the
        // mount script instead of failing closed.
        let bundledJS = (bundledJS?.isEmpty == false) ? bundledJS : nil

        // The bundle is embedded as base64 rather than raw JS: it is spliced
        // into a JS *string literal*, and the widget bundle legitimately
        // contains quotes, backslashes and `</script>`-alike sequences that
        // would otherwise terminate the literal (or the tag) early.
        let fallback = bundledJS.map { js -> String in
            let b64 = Data(js.utf8).base64EncodedString()
            return """
            <script>
            function __iqWidgetFallback() {
              if (window.AddressIQ) return;
              var src = new TextDecoder().decode(
                Uint8Array.from(atob("\(b64)"), function (c) { return c.charCodeAt(0); })
              );
              var s = document.createElement('script');
              s.textContent = src;
              document.head.appendChild(s);
            }
            </script>
            """
        }

        let cdnBase = cdnBaseURL?.absoluteString.hasSuffix("/") == true
            ? String(cdnBaseURL!.absoluteString.dropLast())
            : cdnBaseURL?.absoluteString
        let cdnUsable = deployment != .development
            && !(cdnBase ?? "").isEmpty
            && !widgetVersion.isEmpty
            && !widgetIntegrity.isEmpty

        if cdnUsable, let cdnBase {
            // `widgetVersion` is stored bare ("0.4.0"); the CDN's immutable
            // paths are /v{x.y.z}/, so re-add the "v" here. Immutability is what
            // makes the SRI pin viable at all — the bytes behind this URL can
            // never change.
            let src = "\(cdnBase)/v\(widgetVersion)/iqcollect.js"
            let onerror = fallback != nil ? " onerror=\"__iqWidgetFallback()\"" : ""
            return """
            \(fallback ?? "")
            <script src="\(src)" integrity="\(widgetIntegrity)" crossorigin="anonymous"\(onerror)></script>
            """
        }

        // No CDN pin (or development): inline the bundle directly.
        guard let bundledJS else { return nil }
        return "<script>\(bundledJS)</script>"
    }

    /// The widget bundle shipped as a package resource, if present.
    ///
    /// The accessor differs by build system: SPM synthesises `Bundle.module`;
    /// CocoaPods does not, and instead ships the `resource_bundles` entry as a
    /// nested `AddressIQ.bundle` located relative to the framework the class
    /// lives in. Referencing `Bundle.module` under CocoaPods is a hard compile
    /// error ("type 'Bundle' has no member 'module'").
    private static func resourceBundle() -> Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        let framework = Bundle(for: Coordinator.self)
        if let url = framework.url(forResource: "AddressIQ", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        // Static-linked pods copy resources straight into the framework bundle.
        return framework
        #endif
    }

    private static func bundledWidgetJS() -> String? {
        guard let url = resourceBundle().url(forResource: "iqcollect", withExtension: "js") else {
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
