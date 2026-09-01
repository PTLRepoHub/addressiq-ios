#if canImport(WebKit) && canImport(UIKit)
import XCTest
@testable import AddressIQ

/// What the WebView actually hands `new AddressIQ.IQCollect(mount, cfg)`.
///
/// The widget resolves its own API/ingest hosts from an ENVIRONMENT NAME
/// (`resolveEnvironmentUrls`); it never reads a URL out of its config, and an
/// absent `environment` silently defaults it to production. So a `.staging`
/// build used to load the staging bundle off the staging CDN and then call the
/// PRODUCTION API — the deployment was honoured everywhere except the requests
/// that actually carry data. Nothing covered this config object before.
@available(iOS 15.0, *)
final class AddressIQWidgetCfgTests: XCTestCase {

    private func document(deployment: AddressIQDeployment) -> String? {
        AddressIQWebFlowView(
            apiKey: "pk_1",
            appUserId: "u1",
            apiURL: URL(string: "https://api-staging.addressiqpro.com")!,
            widgetURL: nil,
            deployment: deployment,
            cdnBaseURL: URL(string: "https://cdn.addressiqpro.com")!,
            businessName: nil,
            primaryColorHex: nil,
            onCompleted: { _ in },
            onCancelled: {},
            onFailed: { _ in }
        ).htmlDocument()
    }

    func testTellsTheWidgetWhichEnvironmentToCall() throws {
        for deployment in [AddressIQDeployment.staging, .production, .development] {
            let html = try XCTUnwrap(document(deployment: deployment))
            XCTAssertTrue(
                html.contains("\"environment\":\"\(deployment.rawValue)\""),
                "missing environment for \(deployment); got: \(html)"
            )
        }
    }

    /// A URL here is silently ignored by the widget, which is exactly how the
    /// production-API-from-staging bug stayed invisible.
    func testNeverHandsTheWidgetAHostUrl() throws {
        let html = try XCTUnwrap(document(deployment: .staging))
        XCTAssertFalse(html.contains("\"apiUrl\""), "got: \(html)")
    }
}
#endif
