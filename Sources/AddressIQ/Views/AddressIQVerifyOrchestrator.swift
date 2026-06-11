import SwiftUI
import CoreLocation

private enum Stage: Equatable {
    case loading, permission, address, details, consent, submitting, success, error
}

/// State machine + backend wiring for the verify flow. Holds the
/// widget-session token, drives view transitions, and surfaces typed
/// results back to `AddressIQVerifyView`.
@available(iOS 15.0, *)
struct AddressIQVerifyOrchestrator: View {
    let apiKey: String
    let appUserId: String
    let environment: AddressIQEnvironment
    let phone: String?
    let firstName: String?
    let lastName: String?
    let email: String?
    let googleMapsApiKey: String?
    let privacyPolicyUrl: URL?
    let termsUrl: URL?
    let onCompleted: (AddressIQVerifyResult) -> Void
    let onCancelled: () -> Void
    let onFailed: (AddressIQVerifyError) -> Void

    @Environment(\.addressIQTheme) private var theme
    @State private var stage: Stage = .loading
    @State private var sessionToken: String?
    @State private var address = AddressDraft()
    @State private var submitting = false
    @State private var lastResult: AddressIQVerifyResult?
    @State private var errorMessage: String?

    private var apiBase: URL { environment.defaultApiUrl }

    /// Step index for the indicator (P1-2). `loading` / `submitting` /
    /// `success` / `error` are not numbered steps → `nil`.
    private var stepIndex: Int? {
        switch stage {
        case .permission: return 0
        case .address: return 1
        case .details: return 2
        case .consent: return 3
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let i = stepIndex {
                StepIndicatorView(current: i, total: 4)
            }
            Group {
            switch stage {
            case .loading:
                LoadingView()
            case .permission:
                LocationPermissionView(onGranted: { stage = .address }, onCancel: onCancelled)
            case .address:
                AddressView(
                    initial: address,
                    googleMapsApiKey: googleMapsApiKey,
                    onNext: { draft in address = draft; stage = .details },
                    onCancel: onCancelled
                )
            case .details:
                PropertyDetailsView(
                    initial: address,
                    onNext: { draft in address = draft; stage = .consent },
                    onBack: { stage = .address },
                    onCancel: onCancelled
                )
            case .consent:
                ConsentView(
                    address: address,
                    submitting: submitting,
                    privacyPolicyUrl: privacyPolicyUrl,
                    termsUrl: termsUrl,
                    onSubmit: { Task { await submit() } },
                    onBack: { stage = .details },
                    onCancel: onCancelled
                )
            case .submitting:
                LoadingView(message: "Submitting…")
            case .success:
                if let r = lastResult {
                    SuccessView(locationCode: r.locationCode, onDone: { onCompleted(r) })
                } else {
                    LoadingView()
                }
            case .error:
                ErrorView(
                    message: errorMessage ?? "Something went wrong",
                    onRetry: { Task { await createSession() } },
                    onCancel: onCancelled
                )
            }
            }
        }
        .task {
            if sessionToken == nil { await createSession() }
        }
    }

    private func createSession() async {
        stage = .loading
        do {
            var body: [String: Any] = ["appUserId": appUserId]
            if let phone = phone { body["phone"] = phone }
            if let firstName = firstName { body["firstName"] = firstName }
            if let lastName = lastName { body["lastName"] = lastName }
            if let email = email { body["email"] = email }
            let data = try JSONSerialization.data(withJSONObject: body)
            var request = URLRequest(url: apiBase.appendingPathComponent("/api/v1/widget/sessions/create"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.httpBody = data

            let (respData, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status >= 400 {
                throw AddressIQVerifyError(code: "HTTP_ERROR", message: "Session create failed (\(status))", httpStatus: status)
            }
            let json = try JSONSerialization.jsonObject(with: respData) as? [String: Any] ?? [:]
            guard let token = json["sessionToken"] as? String else {
                throw AddressIQVerifyError(code: "INVALID_RESPONSE", message: "Session token missing", httpStatus: status)
            }
            sessionToken = token
            stage = .permission
        } catch {
            let typed = error as? AddressIQVerifyError ?? AddressIQVerifyError(code: "NETWORK_ERROR", message: error.localizedDescription, httpStatus: nil)
            errorMessage = typed.message
            stage = .error
            onFailed(typed)
        }
    }

    private func submit() async {
        guard let token = sessionToken else {
            errorMessage = "No session token"
            stage = .error
            return
        }
        submitting = true
        defer { submitting = false }
        do {
            var body: [String: Any] = ["placeId": address.placeId ?? "sdk_ios_manual"]
            if let v = address.lat { body["lat"] = v }
            if let v = address.lon { body["lon"] = v }
            if let v = address.formattedAddress { body["formattedAddress"] = v }
            if let v = address.propertyNumber { body["propertyNumber"] = v }
            if let v = address.streetName { body["streetName"] = v }
            if let v = address.buildingColor { body["buildingColor"] = v }
            if let v = address.directions { body["directions"] = v }
            if let v = address.streetviewPanoId { body["streetviewPanoId"] = v }
            if let v = address.streetviewHeading { body["streetviewHeading"] = v }
            let data = try JSONSerialization.data(withJSONObject: body)
            // Collect-only endpoint: creates the Location and returns its
            // `locationCode`. It does NOT start a verification or wire
            // collection — the host owns that via `startVerification(...)`
            // from the `onCompleted` callback (contract §collect-verify split).
            var request = URLRequest(url: apiBase.appendingPathComponent("/api/v1/widget/collect"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = data
            let (respData, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status >= 400 {
                throw AddressIQVerifyError(code: "HTTP_ERROR", message: "Collect failed (\(status))", httpStatus: status)
            }
            let json = try JSONSerialization.jsonObject(with: respData) as? [String: Any] ?? [:]
            guard let locationCode = json["locationCode"] as? String else {
                throw AddressIQVerifyError(code: "INVALID_RESPONSE", message: "locationCode missing", httpStatus: status)
            }
            let r = AddressIQVerifyResult(
                locationCode: locationCode,
                formattedAddress: (json["formattedAddress"] as? String) ?? address.formattedAddress,
                lat: address.lat ?? 0,
                lon: address.lon ?? 0,
                placeId: address.placeId
            )
            lastResult = r

            // No collection wiring here — verification (and its geofence +
            // background collection) is started by the host from `onCompleted`.
            stage = .success
        } catch {
            let typed = error as? AddressIQVerifyError ?? AddressIQVerifyError(code: "NETWORK_ERROR", message: error.localizedDescription, httpStatus: nil)
            errorMessage = typed.message
            stage = .error
            onFailed(typed)
        }
    }
}

@available(iOS 15.0, *)
private struct LoadingView: View {
    var message: String = "Setting up…"
    @Environment(\.addressIQTheme) private var theme
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().tint(theme.primary)
            Text(message).font(.system(size: 14)).foregroundColor(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
    }
}

@available(iOS 15.0, *)
private struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onCancel: () -> Void

    @Environment(\.addressIQTheme) private var theme

    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 120)
            Text("Something went wrong")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(theme.error)
            Text(message)
                .font(.system(size: 15))
                .foregroundColor(theme.text)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 8)
            AddressIQButton(title: "Try again", action: onRetry)
            AddressIQButton(title: "Close", action: onCancel, variant: .outline)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
    }
}

/// Slim progress indicator shown atop the Collect UI multi-step flow (P1-2).
/// A dot per step (the active dot widens) plus a "Step X of N" label, themed
/// via `EnvironmentValues.addressIQTheme`. Mirrors the React Native
/// `<IQLocationManager>` and Flutter `AddressIQVerify` indicators.
@available(iOS 15.0, *)
private struct StepIndicatorView: View {
    let current: Int
    let total: Int
    @Environment(\.addressIQTheme) private var theme

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { i in
                    Capsule()
                        .fill(i <= current ? theme.primary : theme.textSecondary.opacity(0.25))
                        .frame(width: i == current ? 20 : 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: current)
                }
            }
            Spacer()
            Text("Step \(current + 1) of \(total)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}
