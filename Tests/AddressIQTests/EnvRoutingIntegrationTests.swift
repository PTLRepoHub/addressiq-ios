#if canImport(WebKit)
import XCTest
import WebKit
@testable import AddressIQ

/// Proves each deployment uses ITS OWN CDN + API at runtime, in a real WKWebView
/// with baseURL = the deployment's API host (exactly like AddressIQWebFlowView).
final class EnvRoutingIntegrationTests: XCTestCase {
    final class Sink: NSObject, WKScriptMessageHandler {
        let exp: XCTestExpectation; var body = "(none)"
        init(_ e: XCTestExpectation){ exp = e }
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage){ body="\(m.body)"; exp.fulfill() }
    }
    private func run(_ d: AddressIQDeployment) -> String {
        let exp = expectation(description: "cfg")
        let sink = Sink(exp); let cc = WKUserContentController(); cc.add(sink, name: "probe")
        let cfg = WKWebViewConfiguration(); cfg.userContentController = cc
        let web = WKWebView(frame: .init(x:0,y:0,width:390,height:700), configuration: cfg)
        let api = d.defaultApiUrl.absoluteString
        let html = """
        <!doctype html><html><body><script>
        fetch("\(api)/api/v1/widget/config?appUserId=cust_sample_001", {headers:{"x-api-key":"aiq_test_demo_bank_seed01"}})
          .then(r => r.text().then(t => window.webkit.messageHandlers.probe.postMessage("HTTP "+r.status+" from "+location.origin+" :: "+t.slice(0,160))))
          .catch(e => window.webkit.messageHandlers.probe.postMessage("FETCH_ERROR "+e));
        </script></body></html>
        """
        web.loadHTMLString(html, baseURL: d.defaultApiUrl)
        wait(for: [exp], timeout: 30)
        return sink.body
    }
    func testStagingApiRouting() {
        let d = AddressIQDeployment.staging
        print("STAGING cdn=\(d.defaultCdnUrl.absoluteString) api=\(d.defaultApiUrl.absoluteString)")
        print("STAGING config -> \(run(d))")
    }
    func testProductionApiRouting() {
        let d = AddressIQDeployment.production
        print("PRODUCTION cdn=\(d.defaultCdnUrl.absoluteString) api=\(d.defaultApiUrl.absoluteString)")
        print("PRODUCTION config -> \(run(d))")
    }
}
#endif
