// Developer screen (§6 canon): raw `start*` buttons + `getVerificationState`,
// each showing a result/error modal. Raw SDK method names only appear here.
import SwiftUI
import AddressIQ

struct DeveloperView: View {
    @EnvironmentObject private var model: AppModel
    @State private var busy = false

    private var locationCode: String { model.locationCodes.last ?? "loc_sample_001" }

    var body: some View {
        Form {
            Section("locationCode") {
                Text(locationCode).font(.system(.body, design: .monospaced))
            }

            Section("Raw start* calls") {
                rawButton("startVerification(_:)") { await callStartDigital() }
                rawButton("startPhysicalVerification(_:)") { await callStartPhysical() }
                rawButton("startDigitalAndPhysicalVerification(_:)") { await callStartCombined() }
            }

            Section("Lifecycle") {
                rawButton("getVerificationState()") { callGetState() }
                rawButton("cancelVerification(_:)") { await callCancel() }
            }
        }
        .navigationTitle("Developer")
    }

    private func rawButton(_ name: String, action: @escaping () async -> Void) -> some View {
        Button {
            busy = true
            Task { await action(); busy = false }
        } label: {
            HStack {
                Text(name).font(.system(.body, design: .monospaced))
                if busy { Spacer(); ProgressView() }
            }
        }
        .disabled(busy)
    }

    // MARK: - Raw calls

    private func callStartDigital() async {
        do {
            let result = try await AddressIQ.shared.startVerification(
                StartDigitalArgs(locationCode: locationCode)
            )
            model.refreshLifecycle()
            model.present(ResultModal(
                title: "startVerification",
                type: "DIGITAL",
                verificationCode: result.verificationCode,
                status: result.status
            ))
        } catch {
            model.present(ResultModal(title: "startVerification error", error: error))
        }
    }

    private func callStartPhysical() async {
        do {
            let json = try await AddressIQ.shared.startPhysicalVerification(
                StartPhysicalArgs(locationCode: locationCode, provider: "internal_agents")
            )
            model.refreshLifecycle()
            model.present(ResultModal(
                title: "startPhysicalVerification",
                type: "PHYSICAL",
                verificationCode: json["verificationCode"] as? String,
                status: json["status"] as? String,
                rawJSON: prettyJSON(json)
            ))
        } catch {
            model.present(ResultModal(title: "startPhysicalVerification error", error: error))
        }
    }

    private func callStartCombined() async {
        do {
            let json = try await AddressIQ.shared.startDigitalAndPhysicalVerification(
                StartCombinedArgs(locationCode: locationCode, physicalProvider: "internal_agents")
            )
            model.refreshLifecycle()
            model.present(ResultModal(
                title: "startDigitalAndPhysicalVerification",
                type: "COMBINED",
                verificationCode: json["verificationCode"] as? String,
                status: json["status"] as? String,
                rawJSON: prettyJSON(json)
            ))
        } catch {
            model.present(ResultModal(title: "startDigitalAndPhysicalVerification error", error: error))
        }
    }

    private func callGetState() {
        let state = AddressIQ.shared.getVerificationState()
        model.lifecycle = state.state.rawValue
        var json: [String: Any] = ["state": state.state.rawValue]
        if let appUserId = state.appUserId { json["appUserId"] = appUserId }
        if let verificationId = state.verificationId { json["verificationId"] = verificationId }
        if let locationCode = state.locationCode { json["locationCode"] = locationCode }
        if let pausedFor = state.pausedFor { json["pausedFor"] = pausedFor }
        model.present(ResultModal(
            title: "getVerificationState",
            locationCode: state.locationCode,
            status: state.state.rawValue,
            rawJSON: prettyJSON(json)
        ))
    }

    private func callCancel() async {
        let state = AddressIQ.shared.getVerificationState()
        guard let code = state.verificationId else {
            model.present(ResultModal(
                title: "cancelVerification",
                error: AddressIQError.noActiveSession
            ))
            return
        }
        do {
            let json = try await AddressIQ.shared.cancelVerification(code)
            model.refreshLifecycle()
            model.present(ResultModal(
                title: "cancelVerification",
                status: json["status"] as? String,
                rawJSON: prettyJSON(json)
            ))
        } catch {
            model.present(ResultModal(title: "cancelVerification error", error: error))
        }
    }
}
