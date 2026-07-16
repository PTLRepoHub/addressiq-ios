// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AddressIQ",
    // Minimum supported: iOS 13 — required for Swift concurrency
    // back-deployment (`async`/`await` is used across the SDK's
    // public surface). iOS 15+ is the recommended floor for
    // production verification confidence. iOS 12 partners use the
    // legacy 0.2.x SDK with completion-handler APIs.
    // See docs/sdk-contract.md §0.5.
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "AddressIQ",
            targets: ["AddressIQ"]
        ),
    ],
    dependencies: [
        // Runtime for the generated wire-contract bindings under
        // Sources/AddressIQ/Generated (source: PTLRepoHub/AddressIq-proto).
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.38.0"),
    ],
    targets: [
        .target(
            name: "AddressIQ",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources/AddressIQ"
            // No bundled resources: the collect/verify widget is loaded from the
            // SRI-pinned CDN, not shipped. (Removing `resources:` also un-synthesises
            // Bundle.module, which is why the resourceBundle()/bundledWidgetJS()
            // accessors were deleted in the same change.)
        ),
        .testTarget(
            name: "AddressIQTests",
            dependencies: ["AddressIQ"],
            path: "Tests/AddressIQTests"
        ),
    ]
)
