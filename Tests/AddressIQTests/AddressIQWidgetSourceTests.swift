#if canImport(WebKit) && canImport(UIKit)
import XCTest
@testable import AddressIQ

/// Covers how `AddressIQWebFlowView` decides where the widget comes from:
/// CDN-first with an SRI pin, bundled fallback, fail-closed if neither.
///
/// The pins (`widgetVersion` / `widgetIntegrity`) are baked from files that do
/// not exist until the next web release, so `BuildConfig` currently carries
/// empty strings and the CDN path is dormant. These tests therefore pass the
/// pins in explicitly rather than reading BuildConfig — they describe the
/// behaviour the moment a pin lands, and keep passing before it does.
@available(iOS 15.0, *)
final class AddressIQWidgetSourceTests: XCTestCase {

    private static let cdn = URL(string: "https://cdn.addressiqpro.com")!
    private static let bundle = "window.AddressIQ = { IQCollect: function () {} };"
    private var bundle: String { Self.bundle }

    private func tag(
        widgetURL: URL? = nil,
        deployment: AddressIQDeployment = .production,
        cdnBaseURL: URL? = AddressIQWidgetSourceTests.cdn,
        version: String = "0.4.0",
        integrity: String = "sha384-abc123",
        bundledJS: String? = AddressIQWidgetSourceTests.bundle
    ) -> String? {
        AddressIQWebFlowView.widgetScriptTag(
            widgetURL: widgetURL,
            deployment: deployment,
            cdnBaseURL: cdnBaseURL,
            widgetVersion: version,
            widgetIntegrity: integrity,
            bundledJS: bundledJS
        )
    }

    /// Preconditions met: remote tag with the versioned path, the SRI pin, and
    /// `crossorigin` (without which the browser cannot verify a cross-origin
    /// response at all and the integrity check would hard-fail).
    func testCdnPreconditionsMetEmitsPinnedRemoteScript() throws {
        let html = try XCTUnwrap(tag())
        XCTAssertTrue(
            html.contains(#"src="https://cdn.addressiqpro.com/v0.4.0/iqcollect.js""#),
            "should load the immutable /v{x.y.z}/ path; got: \(html)"
        )
        XCTAssertTrue(html.contains(#"integrity="sha384-abc123""#))
        XCTAssertTrue(html.contains(#"crossorigin="anonymous""#))
        XCTAssertTrue(html.contains(#"onerror="__iqWidgetFallback()""#))
    }

    /// The bundle must still ride along, and its fallback must be DEFINED before
    /// the remote tag — an onerror that fires against an undefined function is
    /// a blank sheet on every CDN outage.
    func testCdnPathStillEmbedsBundleAsFallbackDefinedFirst() throws {
        let html = try XCTUnwrap(tag())
        let fallbackDef = try XCTUnwrap(html.range(of: "function __iqWidgetFallback()"))
        let remoteTag = try XCTUnwrap(html.range(of: "<script src="))
        XCTAssertTrue(fallbackDef.lowerBound < remoteTag.lowerBound,
                      "__iqWidgetFallback must be defined before the remote <script>")
        // The bundle is spliced into a JS string literal, so it is base64'd —
        // raw JS would break out of the literal on its first quote.
        XCTAssertTrue(html.contains(Data(bundle.utf8).base64EncodedString()))
        XCTAssertFalse(html.contains(bundle), "bundle must not be inlined raw on the CDN path")
    }

    /// `.development` points at a local backend; never reach for a remote host.
    func testDevelopmentDeploymentInlinesBundleAndNeverLoadsRemotely() throws {
        let html = try XCTUnwrap(tag(deployment: .development))
        XCTAssertEqual(html, "<script>\(bundle)</script>")
        XCTAssertFalse(html.contains("src="))
        XCTAssertFalse(html.contains("integrity="))
    }

    /// No pin published yet (today's state): behave exactly as before the CDN.
    func testEmptyVersionOrIntegrityInlinesBundle() throws {
        let expected = "<script>\(bundle)</script>"
        XCTAssertEqual(tag(version: ""), expected)
        XCTAssertEqual(tag(integrity: ""), expected)
        XCTAssertEqual(tag(version: "", integrity: ""), expected)
        // …and an unset CDN base is equally disqualifying.
        XCTAssertEqual(tag(cdnBaseURL: nil), expected)
    }

    /// The explicit developer override beats both the CDN and the bundle.
    func testWidgetURLOverrideWins() throws {
        let html = try XCTUnwrap(tag(widgetURL: URL(string: "http://localhost:5173/iqcollect.js")!))
        XCTAssertEqual(html, #"<script src="http://localhost:5173/iqcollect.js"></script>"#)
        XCTAssertFalse(html.contains("cdn.addressiqpro.com"))
    }

    /// Nothing loadable ⇒ nil, which the caller turns into WIDGET_BUNDLE_MISSING.
    /// Silently rendering an empty webview would be worse than a typed error.
    func testNoBundleAndNoPinFailsClosed() {
        XCTAssertNil(tag(version: "", integrity: "", bundledJS: nil))
        XCTAssertNil(tag(deployment: .development, bundledJS: nil))
    }

    /// A missing bundle is still fine on the CDN path — the pin makes the remote
    /// script trustworthy on its own; there is just nothing to fall back to.
    func testCdnPathWorksWithoutABundle() throws {
        let html = try XCTUnwrap(tag(bundledJS: nil))
        XCTAssertTrue(html.contains("/v0.4.0/iqcollect.js"))
        XCTAssertFalse(html.contains("onerror"), "no bundle ⇒ no fallback to call")
    }

    /// A trailing slash on the CDN base would produce `//v0.4.0/…`, which is a
    /// different path and would miss the asset.
    func testTrailingSlashOnCdnBaseIsNormalised() throws {
        let html = try XCTUnwrap(tag(cdnBaseURL: URL(string: "https://cdn.addressiqpro.com/")!))
        XCTAssertTrue(html.contains("https://cdn.addressiqpro.com/v0.4.0/iqcollect.js"))
        XCTAssertFalse(html.contains("//v0.4.0"))
    }
}
#endif
