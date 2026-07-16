#if canImport(WebKit) && canImport(UIKit)
import XCTest
@testable import AddressIQ

/// Covers how `AddressIQWebFlowView` decides where the widget comes from.
///
/// The SRI-pinned CDN copy is now the ONLY source — the SDK no longer vendors a
/// bundle. Several of these tests previously asserted the opposite (bundle
/// embedded as fallback, `.development` inlines it, an unbaked pin inlines it);
/// they are inverted, not deleted.
@available(iOS 15.0, *)
final class AddressIQWidgetSourceTests: XCTestCase {

    private static let cdn = URL(string: "https://cdn.addressiqpro.com")!

    private func tag(
        widgetURL: URL? = nil,
        deployment: AddressIQDeployment = .production,
        cdnBaseURL: URL? = AddressIQWidgetSourceTests.cdn,
        version: String = "0.4.0",
        integrity: String = "sha384-abc123"
    ) -> String? {
        AddressIQWebFlowView.widgetScriptTag(
            widgetURL: widgetURL,
            deployment: deployment,
            cdnBaseURL: cdnBaseURL,
            widgetVersion: version,
            widgetIntegrity: integrity
        )
    }

    /// Remote tag with the versioned path, the SRI pin, and `crossorigin`
    /// (without which the browser cannot verify a cross-origin response and the
    /// integrity check hard-fails).
    func testEmitsPinnedRemoteScript() throws {
        let html = try XCTUnwrap(tag())
        XCTAssertTrue(html.contains(#"src="https://cdn.addressiqpro.com/v0.4.0/iqcollect.js""#),
                      "should load the immutable /v{x.y.z}/ path; got: \(html)")
        XCTAssertTrue(html.contains(#"integrity="sha384-abc123""#))
        XCTAssertTrue(html.contains(#"crossorigin="anonymous""#))
    }

    /// `.development` is no longer excluded — it loads the same pinned CDN bundle.
    /// (Its cdnBaseURL resolves to the prod CDN upstream; here we just prove the
    /// method does not special-case the deployment.)
    func testDevelopmentAlsoLoadsFromTheCdn() throws {
        let html = try XCTUnwrap(tag(deployment: .development))
        XCTAssertTrue(html.contains(#"src="https://cdn.addressiqpro.com/v0.4.0/iqcollect.js""#))
        XCTAssertTrue(html.contains(#"integrity="sha384-abc123""#))
    }

    /// No bundle, no fallback machinery — a failure reports WIDGET_LOAD_FAILED.
    func testNoFallbackAndFailureIsReported() throws {
        let html = try XCTUnwrap(tag())
        XCTAssertFalse(html.contains("__iqWidgetFallback"), "the vendored fallback is gone")
        XCTAssertTrue(html.contains(#"onerror="__iqWidgetLoadFailed()""#))
        XCTAssertTrue(html.contains("WIDGET_LOAD_FAILED"))
        XCTAssertTrue(html.contains("window.webkit.messageHandlers.addressiq.postMessage"))
    }

    /// The developer override beats the CDN — unpinned, since a widget you are
    /// rebuilding cannot satisfy a fixed hash.
    func testWidgetURLOverrideWins() throws {
        let html = try XCTUnwrap(tag(widgetURL: URL(string: "http://localhost:5173/iqcollect.js")!))
        XCTAssertEqual(html, #"<script src="http://localhost:5173/iqcollect.js"></script>"#)
        XCTAssertFalse(html.contains("cdn.addressiqpro.com"))
        XCTAssertFalse(html.contains("integrity="))
    }

    /// No usable pin ⇒ nil, which the caller turns into WIDGET_PIN_MISSING. There
    /// is nothing to inline, and an unpinned remote script would be RCE.
    func testNoPinFailsClosed() {
        XCTAssertNil(tag(version: ""))
        XCTAssertNil(tag(integrity: ""))
        XCTAssertNil(tag(version: "", integrity: ""))
        XCTAssertNil(tag(cdnBaseURL: nil))
    }

    /// A trailing slash on the CDN base would produce `//v0.4.0/…`, a different
    /// path that would miss the asset.
    func testTrailingSlashOnCdnBaseIsNormalised() throws {
        let html = try XCTUnwrap(tag(cdnBaseURL: URL(string: "https://cdn.addressiqpro.com/")!))
        XCTAssertTrue(html.contains("https://cdn.addressiqpro.com/v0.4.0/iqcollect.js"))
        XCTAssertFalse(html.contains("//v0.4.0"))
    }
}
#endif
