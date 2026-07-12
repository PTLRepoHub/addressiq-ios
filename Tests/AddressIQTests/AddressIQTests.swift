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

    func testConfigResolvesEnvironmentUrl() {
        let config = AddressIQConfig(apiKey: "aiq_test_key", environment: .sandbox)
        XCTAssertEqual(config.resolvedApiUrl, AddressIQEnvironment.sandbox.defaultApiUrl)
    }

    func testDevelopmentEnvironmentResolvesLocalhost() {
        let config = AddressIQConfig(apiKey: "aiq_test_key", environment: .development)
        XCTAssertEqual(config.resolvedApiUrl, URL(string: "http://localhost:3355")!)
    }

    func testIngestUrlIsDistinctFromApiUrl() {
        let production = AddressIQConfig(apiKey: "aiq_test_key", environment: .production)
        XCTAssertEqual(production.resolvedIngestUrl.scheme, "https")
        XCTAssertNotEqual(production.resolvedIngestUrl, production.resolvedApiUrl)

        let sandbox = AddressIQConfig(apiKey: "aiq_test_key", environment: .sandbox)
        XCTAssertNotEqual(sandbox.resolvedIngestUrl, sandbox.resolvedApiUrl)
    }

    func testDevelopmentIngestResolvesLocalhost() {
        let config = AddressIQConfig(apiKey: "aiq_test_key", environment: .development)
        XCTAssertEqual(config.resolvedIngestUrl, URL(string: "http://localhost:3355")!)
    }
}
