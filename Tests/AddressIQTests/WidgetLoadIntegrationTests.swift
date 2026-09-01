#if canImport(WebKit)
import XCTest
import WebKit
@testable import AddressIQ

/// REAL end-to-end: load each deployment's actual CDN widget (URL + SRI pin) in a
/// live WKWebView and confirm the script executes (window.AddressIQ present) rather
/// than failing SRI/network → blank screen.
final class WidgetLoadIntegrationTests: XCTestCase {

    final class Sink: NSObject, WKScriptMessageHandler {
        let exp: XCTestExpectation
        var result: String = "(none)"
        init(_ e: XCTestExpectation) { exp = e }
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            result = "\(m.body)"; exp.fulfill()
        }
    }

    /// Loads `cdn/vVER/iqcollect.js` with `integrity=hash` and reports OK/FAIL.
    private func loadResult(cdn: URL, version: String, integrity: String, apiBase: URL) -> String {
        let exp = expectation(description: "widget load")
        let sink = Sink(exp)
        let cc = WKUserContentController()
        cc.add(sink, name: "probe")
        let cfg = WKWebViewConfiguration(); cfg.userContentController = cc
        let web = WKWebView(frame: .init(x: 0, y: 0, width: 390, height: 700), configuration: cfg)
        let html = """
        <!doctype html><html><head><meta charset="utf-8"></head><body>
        <script>function ok(){window.webkit.messageHandlers.probe.postMessage('OK:'+(typeof window.AddressIQ))}
        function bad(){window.webkit.messageHandlers.probe.postMessage('FAIL_SRI_OR_NETWORK')}</script>
        <script src="\(cdn.absoluteString)/v\(version)/iqcollect.js" integrity="\(integrity)" crossorigin="anonymous" onload="ok()" onerror="bad()"></script>
        </body></html>
        """
        web.loadHTMLString(html, baseURL: apiBase)
        wait(for: [exp], timeout: 30)
        return sink.result
    }

    func testStagingWidgetLoads() {
        let d = AddressIQDeployment.staging
        let r = loadResult(cdn: d.defaultCdnUrl, version: d.defaultWidgetVersion, integrity: d.defaultWidgetIntegrity, apiBase: d.defaultApiUrl)
        print("STAGING(\(d.defaultWidgetIntegrity.prefix(16))…) -> \(r)")
        XCTAssertTrue(r.hasPrefix("OK:object"), "staging widget did not load (blank): \(r)")
    }

    func testProductionWidgetLoads() {
        let d = AddressIQDeployment.production
        let r = loadResult(cdn: d.defaultCdnUrl, version: d.defaultWidgetVersion, integrity: d.defaultWidgetIntegrity, apiBase: d.defaultApiUrl)
        print("PRODUCTION(\(d.defaultWidgetIntegrity.prefix(16))…) -> \(r)")
        XCTAssertTrue(r.hasPrefix("OK:object"), "production widget did not load (blank): \(r)")
    }

    /// Diagnostic: which staging hash does THIS WebView actually accept?
    func testStagingWhichHashLoads() {
        let cdn = AddressIQDeployment.staging.defaultCdnUrl
        let ver = AddressIQDeployment.staging.defaultWidgetVersion
        let api = AddressIQDeployment.staging.defaultApiUrl
        let wUEr = "sha384-wUErWmll1WWgesjXvSN93KLxHTDLNXdZ4FMR9nT2tQ7tpdBdEuQCDMkHgdssRvkb"
        let q7lz = "sha384-Q7LZd2vji9K0ulAu866ywpCzIj0aoaZAl9n9Ghw1lkf8aT84y++RT/9rHcAIuYJB"
        print("STAGING wUEr -> \(loadResult(cdn: cdn, version: ver, integrity: wUEr, apiBase: api))")
        print("STAGING Q7LZ -> \(loadResult(cdn: cdn, version: ver, integrity: q7lz, apiBase: api))")
    }
}
#endif
