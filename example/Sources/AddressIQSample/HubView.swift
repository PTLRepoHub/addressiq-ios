// Verification hub (§6 canon): human-labelled actions.
//
// - "Collect Address" opens the SDK Collect UI (`AddressIQVerifyView`) as
//   a sheet; on completion we remember the locationCode and show a result
//   modal (P1-4).
// - "Digital / Physical / Combined" call the SDK API directly and surface
//   their result/error in a modal.
// - A status chip shows the current lifecycle state.
import SwiftUI
import AddressIQ

struct HubView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showCollect = false
    @State private var busy = false

    /// Location code the manual start* buttons act on. Defaults to the
    /// most-recently collected one, falling back to a sample code.
    private var workingLocationCode: String {
        model.locationCodes.last ?? "loc_sample_001"
    }

    var body: some View {
        Form {
            Section {
                StatusChip(state: model.lifecycle)
            }

            Section {
                Button {
                    showCollect = true
                } label: {
                    Label("Collect Address", systemImage: "mappin.and.ellipse")
                }
            } header: {
                Text("Collect")
            } footer: {
                Text("Opens the AddressIQ collect + verify UI.")
            }

            Section {
                actionButton("Digital verification", systemImage: "antenna.radiowaves.left.and.right") {
                    await runDigital()
                }
                actionButton("Physical verification", systemImage: "person.fill.checkmark") {
                    await runPhysical()
                }
                actionButton("Digital + Physical", systemImage: "square.stack.3d.up") {
                    await runCombined()
                }
            } header: {
                Text("Verify an address")
            } footer: {
                Text("Acts on location code \(workingLocationCode).")
            }
        }
        .navigationTitle("Verify")
        .onAppear { model.refreshLifecycle() }
        .sheet(isPresented: $showCollect) { collectSheet }
    }

    @ViewBuilder
    private var collectSheet: some View {
        if #available(iOS 15, *) {
            AddressIQVerifyView(
                apiKey: model.apiKey,
                appUserId: model.appUserId,
                deployment: model.deployment,
                // Fallback name if the backend doesn't supply one; the widget
                // fetches the real business identity from the backend.
                businessName: model.businessName.isEmpty ? nil : model.businessName,
                onCompleted: { result in
                    showCollect = false
                    model.remember(locationCode: result.locationCode)
                    // The widget runs the full collect flow and returns a
                    // locationCode; the host starts digital verification here.
                    Task {
                        do {
                            let v = try await AddressIQ.shared.startVerification(
                                StartDigitalArgs(locationCode: result.locationCode)
                            )
                            model.refreshLifecycle()
                            model.present(ResultModal(
                                title: "Address collected → verification started",
                                type: "DIGITAL",
                                verificationCode: v.verificationCode,
                                locationCode: result.locationCode,
                                status: v.status
                            ))
                        } catch {
                            model.present(ResultModal(title: "Collected · verification failed", error: error))
                        }
                    }
                },
                onCancelled: { showCollect = false },
                onFailed: { error in
                    showCollect = false
                    model.present(ResultModal(title: "Collect failed", error: error))
                }
            )
        } else {
            VStack(spacing: 12) {
                Text("The Collect UI requires iOS 15 or later.")
                Button("Close") { showCollect = false }
            }
            .padding()
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            busy = true
            Task { await action(); busy = false }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                if busy { Spacer(); ProgressView() }
            }
        }
        .disabled(busy)
    }

    // MARK: - SDK calls

    private func runDigital() async {
        do {
            let result = try await AddressIQ.shared.startVerification(
                StartDigitalArgs(locationCode: workingLocationCode)
            )
            model.remember(locationCode: workingLocationCode)
            model.refreshLifecycle()
            model.present(ResultModal(
                title: "Digital started",
                type: "DIGITAL",
                verificationCode: result.verificationCode,
                status: result.status
            ))
        } catch {
            model.present(ResultModal(title: "Digital failed", error: error))
        }
    }

    private func runPhysical() async {
        do {
            let json = try await AddressIQ.shared.startPhysicalVerification(
                StartPhysicalArgs(locationCode: workingLocationCode, provider: "internal_agents")
            )
            model.remember(locationCode: workingLocationCode)
            model.refreshLifecycle()
            model.present(ResultModal(
                title: "Physical started",
                type: "PHYSICAL",
                verificationCode: json["verificationCode"] as? String,
                status: json["status"] as? String,
                rawJSON: prettyJSON(json)
            ))
        } catch {
            model.present(ResultModal(title: "Physical failed", error: error))
        }
    }

    private func runCombined() async {
        do {
            let json = try await AddressIQ.shared.startDigitalAndPhysicalVerification(
                StartCombinedArgs(locationCode: workingLocationCode, physicalProvider: "internal_agents")
            )
            model.remember(locationCode: workingLocationCode)
            model.refreshLifecycle()
            model.present(ResultModal(
                title: "Combined started",
                type: "COMBINED",
                verificationCode: json["verificationCode"] as? String,
                status: json["status"] as? String,
                rawJSON: prettyJSON(json)
            ))
        } catch {
            model.present(ResultModal(title: "Combined failed", error: error))
        }
    }
}

/// Lifecycle status chip.
struct StatusChip: View {
    let state: String

    private var color: Color {
        switch state {
        case "collecting": return .green
        case "paused": return .orange
        case "terminated": return .red
        case "idle": return .blue
        default: return .gray
        }
    }

    var body: some View {
        HStack {
            Text("Lifecycle")
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(state).font(.system(.subheadline, design: .monospaced))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
        }
    }
}
