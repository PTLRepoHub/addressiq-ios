import XCTest
@testable import AddressIQ

/// Smoke test — guards the release pipeline against a broken build by
/// exercising a pure (Foundation-only) slice of the public surface.
/// Runs under `swift test`. The test target is declared in Package.swift.
final class AddressIQTests: XCTestCase {
    func testEnvironmentsResolveDistinctApiUrls() {
        let sandbox = AddressIQEnvironment.sandbox.defaultApiUrl
        let production = AddressIQEnvironment.production.defaultApiUrl

        XCTAssertEqual(sandbox.scheme, "https")
        XCTAssertEqual(production.scheme, "https")
        XCTAssertNotEqual(sandbox, production)
    }

    func testConfigResolvesEnvironmentUrlWhenNoOverride() {
        let config = AddressIQConfig(apiKey: "aiq_test_key", environment: .sandbox)
        XCTAssertEqual(config.resolvedApiUrl, AddressIQEnvironment.sandbox.defaultApiUrl)
    }

    func testConfigHonorsExplicitOverride() {
        let override = URL(string: "https://proxy.partner.example")!
        let config = AddressIQConfig(apiKey: "aiq_test_key", environment: .production, apiUrl: override)
        XCTAssertEqual(config.resolvedApiUrl, override)
    }
}
