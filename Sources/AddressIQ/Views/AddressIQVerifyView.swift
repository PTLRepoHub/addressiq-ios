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
    let googleMapsApiKey: String?
    let theme: AddressIQThemeOverrides?
    let privacyPolicyUrl: URL?
    let termsUrl: URL?
    let onCompleted: (AddressIQVerifyResult) -> Void
    let onCancelled: () -> Void
    let onFailed: (AddressIQVerifyError) -> Void

    public init(
        apiKey: String,
        appUserId: String,
        environment: AddressIQEnvironment = .production,
        phone: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        googleMapsApiKey: String? = nil,
        theme: AddressIQThemeOverrides? = nil,
        privacyPolicyUrl: URL? = nil,
        termsUrl: URL? = nil,
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
        self.googleMapsApiKey = googleMapsApiKey
        self.theme = theme
        self.privacyPolicyUrl = privacyPolicyUrl
        self.termsUrl = termsUrl
        self.onCompleted = onCompleted
        self.onCancelled = onCancelled
        self.onFailed = onFailed
    }

    public var body: some View {
        AddressIQVerifyOrchestrator(
            apiKey: apiKey,
            appUserId: appUserId,
            environment: environment,
            phone: phone,
            firstName: firstName,
            lastName: lastName,
            email: email,
            googleMapsApiKey: googleMapsApiKey,
            privacyPolicyUrl: privacyPolicyUrl,
            termsUrl: termsUrl,
            onCompleted: onCompleted,
            onCancelled: onCancelled,
            onFailed: onFailed
        )
        .environment(\.addressIQTheme, mergeTheme(theme))
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
