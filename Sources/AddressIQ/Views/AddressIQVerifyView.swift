import SwiftUI
import Foundation

/// Public SwiftUI verify-flow view. Drop-in collect + verify widget
/// matching the React Native and Flutter widgets at the visual + UX
/// level. Partners present this as a sheet, full-screen cover, or via
/// the `AddressIQVerifyViewController` UIKit bridge.
///
/// Identity contract: `appUserId` is the primary identifier — your
/// stable customer ID. The AddressIQ backend uses it as the canonical
/// user key for dedup, push routing, and session lookup. `phone` and
/// `email` are optional contact info.
@available(iOS 15.0, *)
public struct AddressIQVerifyView: View {
    let apiKey: String
    let appUserId: String
    let environment: AddressIQEnvironment
    let phone: String?
    let firstName: String?
    let lastName: String?
    let email: String?
    let theme: AddressIQThemeOverrides?
    let privacyPolicyUrl: URL?
    let termsUrl: URL?
    let businessName: String?
    let widgetURL: URL?
    let onCompleted: (AddressIQVerifyResult) -> Void
    let onCancelled: () -> Void
    let onFailed: (AddressIQVerifyError) -> Void

    // How the widget is loaded: CDN-first, SRI-pinned, bundled fallback.
    //
    // The widget is fetched from the per-environment CDN at the immutable path
    // `{cdn}/v{x.y.z}/iqcollect.js`, with a Subresource Integrity `integrity`
    // pin on the <script> tag. Both the version and the hash are baked into
    // BuildConfig at publish time from `.widget-version` / `.widget-integrity`,
    // which the web repo writes into this repo on every web release. WKWebView
    // enforces SRI, so bytes that do not match the pin do not execute: the CDN
    // is a delivery channel, not a trust boundary, and a compromised or swapped
    // asset is inert rather than remote code execution. This is precisely why
    // the CDN publishes immutable /v{x.y.z}/ paths — a mutable "latest" URL
    // could not carry a build-time hash.
    //
    // The bundled widget (SPM resource / pod resource bundle,
    // Resources/iqcollect.js) is still embedded in the page and is injected by
    // `__iqWidgetFallback()` if the remote script fails for ANY reason — CDN
    // outage, offline device, or a failed integrity check. Users are never
    // stranded on a blank sheet.
    //
    // If no pin has been published yet (empty version/integrity) or the
    // environment is `.development`, the bundle is inlined directly — the
    // pre-CDN behaviour, unchanged. If neither source is available the SDK
    // still fails closed, surfacing WIDGET_BUNDLE_MISSING via `onFailed`; it
    // will not load an unpinned remote script.
    //
    // `widgetURL` remains supported as an explicit developer override, taking
    // precedence over both, for serving a local bundle during development (see
    // docs — run the demo proxy with `MOCK_UPSTREAM=1` and serve
    // `dist/iqcollect.js`).

    public init(
        apiKey: String,
        appUserId: String,
        environment: AddressIQEnvironment = .production,
        phone: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        theme: AddressIQThemeOverrides? = nil,
        privacyPolicyUrl: URL? = nil,
        termsUrl: URL? = nil,
        businessName: String? = nil,
        widgetURL: URL? = nil,
        onCompleted: @escaping (AddressIQVerifyResult) -> Void,
        onCancelled: @escaping () -> Void = {},
        onFailed: @escaping (AddressIQVerifyError) -> Void = { _ in }
    ) {
        self.apiKey = apiKey
        self.appUserId = appUserId
        self.environment = environment
        self.phone = phone
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.theme = theme
        self.privacyPolicyUrl = privacyPolicyUrl
        self.termsUrl = termsUrl
        self.businessName = businessName
        self.widgetURL = widgetURL
        self.onCompleted = onCompleted
        self.onCancelled = onCancelled
        self.onFailed = onFailed
    }

    public var body: some View {
        // The UI is now the shared web widget (single cross-platform source of
        // truth) hosted in a WKWebView. This native shell owns only the parts a
        // webview cannot: Always/Precise permission and the location fix.
        AddressIQWebFlowView(
            apiKey: apiKey,
            appUserId: appUserId,
            apiURL: environment.defaultApiUrl,
            widgetURL: widgetURL,
            environment: environment,
            cdnBaseURL: environment.defaultCdnUrl,
            businessName: businessName,
            primaryColorHex: nil,
            onCompleted: onCompleted,
            onCancelled: onCancelled,
            onFailed: onFailed
        )
        .environment(\.addressIQTheme, mergeTheme(theme))
        .ignoresSafeArea(edges: .bottom)
    }
}

/// Result delivered to the partner via `onCompleted`.
///
/// The Collect UI **collects only** — it saves the address and returns its
/// `locationCode`. It does NOT start a verification. Start verification from the
/// `onCompleted` callback with `AddressIQ.shared.startVerification(...)`.
/// Mirrors the cross-SDK `CollectResult` shape.
public struct AddressIQVerifyResult: Equatable {
    public let locationCode: String
    public let formattedAddress: String?
    public let lat: Double
    public let lon: Double
    public let placeId: String?
}

/// Typed error delivered via `onFailed`. Code maps to the cross-SDK
/// error closed set; `httpStatus` is set when the failure originated
/// from a non-2xx response.
public struct AddressIQVerifyError: Error {
    public let code: String
    public let message: String
    public let httpStatus: Int?
}
