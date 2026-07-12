import XCTest
@testable import AddressIQ

/// Smoke test — guards the release pipeline against a broken build by
/// exercising a pure (Foundation-only) slice of the public surface.
/// Runs under `swift test`. The test target is declared in Package.swift.
final class AddressIQTests: XCTestCase {
    func testEnvironmentsResolveDistinctApiUrls() {
        let staging = AddressIQEnvironment.staging.defaultApiUrl
        let production = AddressIQEnvironment.production.defaultApiUrl

        XCTAssertEqual(staging.scheme, "https")
        XCTAssertEqual(production.scheme, "https")
        XCTAssertNotEqual(staging, production)
    }

    func testConfigResolvesEnvironmentUrl() {
        let config = AddressIQConfig(apiKey: "aiq_test_key", environment: .staging)
        XCTAssertEqual(config.resolvedApiUrl, AddressIQEnvironment.staging.defaultApiUrl)
    }

    func testDevelopmentEnvironmentResolvesLocalhost() {
        let config = AddressIQConfig(apiKey: "aiq_test_key", environment: .development)
        XCTAssertEqual(config.resolvedApiUrl, URL(string: "http://localhost:4000")!)
    }

    func testIngestUrlIsDistinctFromApiUrl() {
        let production = AddressIQConfig(apiKey: "aiq_test_key", environment: .production)
        XCTAssertEqual(production.resolvedIngestUrl.scheme, "https")
        XCTAssertNotEqual(production.resolvedIngestUrl, production.resolvedApiUrl)

        let staging = AddressIQConfig(apiKey: "aiq_test_key", environment: .staging)
        XCTAssertNotEqual(staging.resolvedIngestUrl, staging.resolvedApiUrl)
    }

    func testDevelopmentIngestResolvesLocalhost() {
        let config = AddressIQConfig(apiKey: "aiq_test_key", environment: .development)
        XCTAssertEqual(config.resolvedIngestUrl, URL(string: "http://localhost:4000")!)
    }

    // MARK: - Per-environment CDN (baked from PROD_/STAGING_ADDRESSIQ_CDN_BASE_URL)

    /// The CDN host is a resolved config value only — the widget ships bundled
    /// and never loads from here (see AddressIQVerifyView). This just pins that
    /// each environment resolves its own host rather than sharing one.
    func testCdnUrlResolvesPerEnvironment() {
        let staging = AddressIQConfig(apiKey: "aiq_test_key", environment: .staging)
        let production = AddressIQConfig(apiKey: "aiq_test_key", environment: .production)

        XCTAssertEqual(staging.resolvedCdnUrl.scheme, "https")
        XCTAssertEqual(production.resolvedCdnUrl.scheme, "https")
        XCTAssertNotEqual(staging.resolvedCdnUrl, production.resolvedCdnUrl)
        XCTAssertNotEqual(production.resolvedCdnUrl, production.resolvedApiUrl)
    }

    // MARK: - `sandbox` → `staging` rename back-compat

    /// The rename must not break integrators who reconstruct the environment
    /// from a string (decoded config, plist, JS bridge). Before the custom
    /// `init?(rawValue:)`, `"sandbox"` returned nil after the rename.
    func testLegacySandboxRawValueStillResolvesToStaging() {
        XCTAssertEqual(AddressIQEnvironment(rawValue: "sandbox"), .staging)
        XCTAssertEqual(AddressIQEnvironment(rawValue: "staging"), .staging)
        XCTAssertEqual(AddressIQEnvironment(rawValue: "production"), .production)
        XCTAssertEqual(AddressIQEnvironment(rawValue: "development"), .development)
        XCTAssertNil(AddressIQEnvironment(rawValue: "nonsense"))
    }
}
