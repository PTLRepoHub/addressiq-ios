#if canImport(UIKit)
import SwiftUI
import UIKit
import Foundation

/// UIKit bridge for partners not yet on SwiftUI. Presents the
/// `AddressIQVerifyView` inside a `UIHostingController` so partners
/// can call:
///
///   ```swift
///   let vc = AddressIQVerifyViewController(
///       apiKey: "aiq_live_...",
///       appUserId: customer.id
///   ) { result in
///       switch result {
///       case .completed(let r): print("Started:", r.verificationCode)
///       case .cancelled: break
///       case .failed(let e): showError(e)
///       }
///   }
///   present(vc, animated: true)
///   ```
@available(iOS 15.0, *)
public final class AddressIQVerifyViewController: UIViewController {
    public enum Outcome {
        case completed(AddressIQVerifyResult)
        case cancelled
        case failed(AddressIQVerifyError)
    }

    private let hosting: UIHostingController<AnyView>

    public init(
        apiKey: String,
        appUserId: String,
        deployment: AddressIQDeployment = .production,
        phone: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        theme: AddressIQThemeOverrides? = nil,
        privacyPolicyUrl: URL? = nil,
        termsUrl: URL? = nil,
        onOutcome: @escaping (Outcome) -> Void
    ) {
        let view = AddressIQVerifyView(
            apiKey: apiKey,
            appUserId: appUserId,
            deployment: deployment,
            phone: phone,
            firstName: firstName,
            lastName: lastName,
            email: email,
            theme: theme,
            privacyPolicyUrl: privacyPolicyUrl,
            termsUrl: termsUrl,
            onCompleted: { onOutcome(.completed($0)) },
            onCancelled: { onOutcome(.cancelled) },
            onFailed: { onOutcome(.failed($0)) }
        )
        self.hosting = UIHostingController(rootView: AnyView(view))
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported — use the designated initializer")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)
    }
}
#endif
