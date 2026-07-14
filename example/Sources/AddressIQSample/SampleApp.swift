// AddressIQ iOS SDK — sample app.
//
// Imports `AddressIQ`, linked to the LOCAL SDK at the repo root via
// `.package(path: "..")`. Demonstrates the OkHi-style §6 screen canon:
//
//   Login → Verification hub → Helpers → Addresses → Developer → Settings
//
// Human labels live on the hub; raw SDK method names appear only on the
// Developer screen. Drives the real `AddressIQ.shared` lifecycle.
import SwiftUI
import AddressIQ

@main
struct AddressIQSampleApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}

/// Shared app state. Holds the chosen deployment + appUserId, the
/// in-memory list of collected location codes, and a derived lifecycle
/// label. The SDK itself is the source of truth (`AddressIQ.shared`); this
/// model just mirrors what the UI needs.
@MainActor
final class AppModel: ObservableObject {
    // Login inputs.
    @Published var apiKey: String = "aiq_test_demo_bank_seed01"
    @Published var deployment: AddressIQDeployment = .staging
    @Published var appUserId: String = "cust_sample_001"

    // Demo / local-dev options.
    /// Fallback business name shown if the backend doesn't provide one. The
    /// widget normally fetches name/logo/colour from the backend.
    @Published var businessName: String = "Kuda Business"

    // Session state.
    @Published var isLoggedIn: Bool = false
    @Published var lifecycle: String = "uninitialized"

    /// Collected location codes (P1-1 Addresses screen). In-memory only.
    @Published var locationCodes: [String] = []

    /// Most recent result/error to show in a modal (P1-4).
    @Published var modal: ResultModal?

    func refreshLifecycle() {
        lifecycle = AddressIQ.shared.getVerificationState().state.rawValue
    }

    func login() async {
        AddressIQ.shared.initialize(
            config: AddressIQConfig(apiKey: apiKey, deployment: deployment)
        )
        do {
            try await AddressIQ.shared.setUser(SDKUser(appUserId: appUserId))
            isLoggedIn = true
            refreshLifecycle()
        } catch {
            modal = ResultModal(title: "setUser failed", error: error)
        }
    }

    func logout() async {
        try? await AddressIQ.shared.logout()
        isLoggedIn = false
        refreshLifecycle()
    }

    func reset() async {
        await AddressIQ.shared.reset()
        isLoggedIn = false
        locationCodes = []
        refreshLifecycle()
    }

    /// Record a collected location code, de-duplicating.
    func remember(locationCode: String) {
        guard !locationCode.isEmpty, !locationCodes.contains(locationCode) else { return }
        locationCodes.append(locationCode)
    }

    func present(_ modal: ResultModal) { self.modal = modal }
}

/// Payload shown in the result modal (P1-4). Either a success body
/// (verification/location/status + optional raw JSON) or an error.
struct ResultModal: Identifiable {
    let id = UUID()
    let title: String
    /// Resulting verification type — DIGITAL / PHYSICAL / COMBINED.
    var type: String?
    var verificationCode: String?
    var locationCode: String?
    var status: String?
    var rawJSON: String?
    var errorText: String?

    init(
        title: String,
        type: String? = nil,
        verificationCode: String? = nil,
        locationCode: String? = nil,
        status: String? = nil,
        rawJSON: String? = nil
    ) {
        self.title = title
        self.type = type
        self.verificationCode = verificationCode
        self.locationCode = locationCode
        self.status = status
        self.rawJSON = rawJSON
    }

    init(title: String, error: Error) {
        self.title = title
        if let iqError = error as? AddressIQError {
            self.errorText = "[\(iqError.code)] \(iqError.description)"
        } else if let verifyError = error as? AddressIQVerifyError {
            self.errorText = "[\(verifyError.code)] \(verifyError.message)"
                + (verifyError.httpStatus.map { " (HTTP \($0))" } ?? "")
        } else {
            self.errorText = "\(error)"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .sheet(item: $model.modal) { ResultModalView(modal: $0) }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationView { HubView() }
                .tabItem { Label("Verify", systemImage: "checkmark.shield") }
            NavigationView { HelpersView() }
                .tabItem { Label("Helpers", systemImage: "hand.raised") }
            NavigationView { AddressesView() }
                .tabItem { Label("Addresses", systemImage: "list.bullet") }
            NavigationView { DeveloperView() }
                .tabItem { Label("Developer", systemImage: "hammer") }
            NavigationView { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

/// Shared result/error modal (P1-4). Renders the verificationCode /
/// locationCode / status, optional raw JSON, or the error text.
struct ResultModalView: View {
    let modal: ResultModal
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let error = modal.errorText {
                        Label("Error", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        if let type = modal.type { TypeChip(type: type) }
                        if let code = modal.verificationCode { row("verificationCode", code) }
                        if let code = modal.locationCode { row("locationCode", code) }
                        if let status = modal.status { row("status", status) }
                        if let json = modal.rawJSON {
                            Text("Raw response").font(.headline)
                            Text(json)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(modal.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(.body, design: .monospaced))
        }
    }
}

/// Coloured chip for the resulting verification type (DIGITAL / PHYSICAL / COMBINED).
struct TypeChip: View {
    let type: String

    private var color: Color {
        switch type {
        case "DIGITAL": return .blue
        case "PHYSICAL": return .purple
        case "COMBINED": return .teal
        default: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(type).font(.caption.weight(.bold)).foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }
}

/// Pretty-print a `[String: Any]` JSON-ish dictionary for the result modal.
func prettyJSON(_ dict: [String: Any]) -> String {
    let sanitized = JSONSanitize(dict)
    guard
        JSONSerialization.isValidJSONObject(sanitized),
        let data = try? JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys]),
        let string = String(data: data, encoding: .utf8)
    else {
        return "\(dict)"
    }
    return string
}

/// Drop values JSONSerialization can't encode so prettyJSON never throws.
private func JSONSanitize(_ value: Any) -> Any {
    switch value {
    case let dict as [String: Any]:
        return dict.mapValues { JSONSanitize($0) }
    case let array as [Any]:
        return array.map { JSONSanitize($0) }
    case is String, is NSNumber, is Bool, is Int, is Double:
        return value
    case is NSNull:
        return value
    default:
        return "\(value)"
    }
}
