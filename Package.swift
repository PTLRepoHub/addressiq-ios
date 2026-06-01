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
    targets: [
        .target(
            name: "AddressIQ",
            dependencies: [],
            path: "Sources/AddressIQ"
        ),
        .testTarget(
            name: "AddressIQTests",
            dependencies: ["AddressIQ"],
            path: "Tests/AddressIQTests"
        ),
    ]
)
