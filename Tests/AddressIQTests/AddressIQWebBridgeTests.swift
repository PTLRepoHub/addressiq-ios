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

        // The widget legitimately asks for a fix MORE THAN ONCE in a single run:
        // collect-form auto-locates when the map step opens (guarded by
        // `autoLocateTried`), and "Use my current location" asks again. Two
        // requests arriving is correct behaviour, not a regression.
        //
        // XCTestExpectation traps on over-fulfilment by default, so the second
        // request crashed the test with
        //   *** Assertion failure in -[XCTestExpectation fulfill]
        // even though the bridge round-trip had already succeeded. What this test
        // asserts is "at least one getLocation round-trip works", so say that.
        gotGetLocation.assertForOverFulfill = false

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

        // Put the web view in a key, visible window. WebKit throttles timers and
        // rendering for a view that is not in a window hierarchy — the widget's
        // flow is driven by a setInterval, so offscreen it simply never advances.
        // This passes on a dev machine either way but deadlocks on a headless CI
        // runner, which is exactly where it was failing.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 780))
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(webView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        // This test exercises the BRIDGE, not the network — so stub `fetch` to
        // reject immediately instead of pointing `apiUrl` at a closed port and
        // hoping the connection fails fast.
        //
        // The old approach relied on `https://127.0.0.1:1` refusing instantly, so
        // `listAddresses()` would fail and the widget would fall through to the
        // collect flow. That holds on a dev machine but NOT on the CI runner, where
        // the connection does not fail fast: the widget sat waiting, never reached
        // the map step, never asked for a location, and the test timed out at 25s.
        // (The earlier `XCTestExpectation fulfill` assertion was the same bug — a
        // late request landing after the wait had already expired.)
        //
        // Rejecting every request makes the flow deterministic in any environment:
        // no saved addresses → collect flow → map step → auto-locate → getLocation.
        // Reference data (countries/states) also fails here, which is fine: the
        // form degrades to free text by design (collect-form.ts:299-303).
        let cfg = ##"{"apiKey":"k","apiUrl":"https://127.0.0.1:1","appUserId":"u1","business":{"displayName":"Test Biz","primaryColor":"#111827"}}"##
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body><div id="mount"></div>
        <script>
          window.__errs = [];
          window.__calls = [];
          window.onerror = function (m, s, l) { window.__errs.push(m + ' @' + l); };
          window.addEventListener('unhandledrejection', function (e) {
            window.__errs.push('unhandledrejection: ' + (e.reason && e.reason.message || e.reason));
          });
          window.fetch = function (u) {
            window.__calls.push('fetch ' + u);
            return Promise.reject(new Error('network disabled in AddressIQWebBridgeTests'));
          };
        </script>
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

        let result = XCTWaiter().wait(for: [gotGetLocation], timeout: 25)
        if result != .completed {
            // The flow stalled. Dump what the widget actually rendered — guessing
            // from a bare "timed out" has already cost several CI round-trips.
            let dump = expectation(description: "diagnostic dump")
            webView.evaluateJavaScript(
                """
                (function () {
                  var btns = Array.prototype.slice.call(document.querySelectorAll('.iq-btn'))
                    .map(function (b) { return b.textContent.trim(); });
                  return JSON.stringify({
                    mounted: !!(window.AddressIQ && window.AddressIQ.IQCollect),
                    errors: window.__errs || [],
                    bridgeCalls: window.__calls || [],
                    buttons: btns,
                    bodyText: (document.body.innerText || '').slice(0, 400)
                  });
                })()
                """
            ) { value, error in
                XCTFail("""
                getLocation never arrived. Widget state:
                \(value.map { "\($0)" } ?? "evaluateJavaScript failed: \(String(describing: error))")
                """)
                dump.fulfill()
            }
            wait(for: [dump], timeout: 10)
        }
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
