// Helpers screen (§6 canon): permission state (5 states), request
// permissions, and open settings.
import SwiftUI
import AddressIQ

struct HelpersView: View {
    @EnvironmentObject private var model: AppModel
    @State private var permissions: [String: String] = [:]
    @State private var busy = false

    private let scopes = ["foregroundLocation", "backgroundLocation", "notifications"]

    var body: some View {
        Form {
            Section("Permission state") {
                ForEach(scopes, id: \.self) { scope in
                    HStack {
                        Text(scope)
                        Spacer()
                        PermissionBadge(value: permissions[scope] ?? "—")
                    }
                }
            }
            Section {
                Button {
                    busy = true
                    Task {
                        let final = await AddressIQ.shared.requestPermissions()
                        permissions = final
                        busy = false
                    }
                } label: {
                    HStack {
                        Label("Request permissions", systemImage: "location.fill")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(busy)

                Button {
                    Task { _ = await AddressIQ.shared.openSettings() }
                } label: {
                    Label("Open settings", systemImage: "gearshape.fill")
                }
            } footer: {
                Text("Values ∈ { GRANTED, DENIED, NOT_DETERMINED, BLOCKED, UNAVAILABLE }.")
            }
        }
        .navigationTitle("Helpers")
        .onAppear { permissions = AddressIQ.shared.getPermissionState() }
    }
}

struct PermissionBadge: View {
    let value: String

    private var color: Color {
        switch value {
        case "GRANTED": return .green
        case "DENIED", "BLOCKED": return .red
        case "NOT_DETERMINED": return .orange
        case "UNAVAILABLE": return .gray
        default: return .secondary
        }
    }

    var body: some View {
        Text(value)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}
