// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AddressIQSample",
    platforms: [.iOS(.v15)],
    products: [
        .executable(name: "AddressIQSample", targets: ["AddressIQSample"])
    ],
    dependencies: [
        // Linked to the local SDK at the repo root.
        .package(path: "..")
    ],
    targets: [
        .executableTarget(
            name: "AddressIQSample",
            dependencies: [.product(name: "AddressIQ", package: "addressiq-ios")],
            path: "Sources/AddressIQSample"
        )
    ]
)
