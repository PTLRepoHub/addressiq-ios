#if canImport(WebKit) && canImport(UIKit)
import XCTest
import WebKit
@testable import AddressIQ

/// Integration test for the shared-widget WKWebView bridge.
///
/// Loads the REAL bundled widget (`Resources/iqcollect.js`) into a `WKWebView`,
/// drives the flow to the point it needs a location, and asserts the full
/// `HostBridge` round-trip works against a live WebKit engine:
///   1. the bundled widget parses and mounts (`window.AddressIQ.IQCollect`),
///   2. the widget's `BridgeLocationProvider` posts a `getLocation` request to
///      the native `WKScriptMessageHandler` (JS → native),
///   3. a native `window.AddressIQBridge.resolve(...)` reply is accepted by the
///      widget without error (native → JS).
final class AddressIQWebBridgeTests: XCTestCase {

    /// Reads the widget bundle straight from the package Resources dir so the
    /// test exercises the exact JS shipped to partners.
    private func bundledWidgetJS() throws -> String {
        // Read the exact bundle shipped to partners from the source tree
        // (Tests/AddressIQTests/<file> → ../../Sources/AddressIQ/Resources).
        let src = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AddressIQ/Resources/iqcollect.js")
        return try String(contentsOf: src, encoding: .utf8)
    }

    func testBundledWidgetDrivesGetLocationBridgeRoundTrip() throws {
        let widgetJS = try bundledWidgetJS()
        XCTAssertTrue(widgetJS.contains("IQCollect"), "bundle should define IQCollect")

        let gotGetLocation = expectation(description: "native received a getLocation request")

        // Stub the FULL bridge contract, not just `getLocation`. Before the
        // widget offers "Use my current location" it gates on `requestPermission`
        // and blocks with the button stuck on "Checking…" until the host answers.
        // A handler that only served `getLocation` would deadlock there — see
        // AddressIQWebFlowView.Coordinator.handleRequest, which this mirrors.
        let handler = TestBridgeHandler { webView, message in
            guard let dict = Self.decode(message),
                  dict["kind"] as? String == "request",
                  let action = dict["action"] as? String,
                  let id = dict["id"] as? String else { return }

            func resolve(_ literal: String) {
                webView.evaluateJavaScript(
                    "window.AddressIQBridge && window.AddressIQBridge.resolve(\(Self.jsString(id)), \(literal));",
                    completionHandler: nil
                )
            }

            switch action {
            case "getPermissionStatus":
                resolve("\"granted\"")
            case "requestPermission", "getPermissionState":
                resolve("{foreground:true,background:true}")
            case "openSettings":
                resolve("true")
            case "getLocation":
                resolve("{lat:9.0765,lon:7.3986,accuracy:8}")
                gotGetLocation.fulfill()
            default:
                break
            }
        }

        let controller = WKUserContentController()
        controller.add(handler, name: "addressiq")
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 780), configuration: config)
        handler.webView = webView

        // apiUrl points at a closed port so `listAddresses()` fails fast → the
        // widget falls through to the collect flow (no server needed), whose
        // address step exposes "Use my current location" → getLocation.
        let cfg = ##"{"apiKey":"k","apiUrl":"https://127.0.0.1:1","appUserId":"u1","business":{"displayName":"Test Biz","primaryColor":"#111827"}}"##
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body><div id="mount"></div>
        <script>\(widgetJS)</script>
        <script>
          var c = new window.AddressIQ.IQCollect(document.getElementById('mount'), \(cfg));
          c.open();
          // Auto-driver: advance the flow until the address step, then ask for location.
          window.__drive = setInterval(function(){
            try {
              var btns = Array.prototype.slice.call(document.querySelectorAll('.iq-btn'));
              var byText = function(t){ return btns.filter(function(b){ return b.textContent.trim().toLowerCase().indexOf(t) >= 0; })[0]; };
              var useLoc = byText('current location');
              if (useLoc) { clearInterval(window.__drive); useLoc.click(); return; }
              var next = byText('continue') || byText('next');
              if (next) next.click();
            } catch (e) {}
          }, 350);
        </script></body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://127.0.0.1:1"))

        wait(for: [gotGetLocation], timeout: 25)
    }

    // MARK: - helpers

    private static func decode(_ message: WKScriptMessage) -> [String: Any]? {
        if let s = message.body as? String, let data = s.data(using: .utf8) {
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        return message.body as? [String: Any]
    }

    private static func jsString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        let arr = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(arr.dropFirst().dropLast())
    }
}

/// Minimal `WKScriptMessageHandler` that forwards messages to a closure.
private final class TestBridgeHandler: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    private let onMessage: (WKWebView, WKScriptMessage) -> Void
    init(_ onMessage: @escaping (WKWebView, WKScriptMessage) -> Void) { self.onMessage = onMessage }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        if let wv = webView { onMessage(wv, message) }
    }
}
#endif
