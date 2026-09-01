import XCTest
@testable import AddressIQ

/// Smoke test — guards the release pipeline against a broken build by
/// exercising a pure (Foundation-only) slice of the public surface.
/// Runs under `swift test`. The test target is declared in Package.swift.
final class AddressIQTests: XCTestCase {
    func testDeploymentsResolveDistinctApiUrls() {
        let staging = AddressIQDeployment.staging.defaultApiUrl
        let production = AddressIQDeployment.production.defaultApiUrl

        XCTAssertEqual(staging.scheme, "https")
        XCTAssertEqual(production.scheme, "https")
        XCTAssertNotEqual(staging, production)
    }

    func testConfigResolvesDeploymentUrl() {
        let config = AddressIQConfig(apiKey: "aiq_test_key", deployment: .staging)
        XCTAssertEqual(config.resolvedApiUrl, AddressIQDeployment.staging.defaultApiUrl)
    }

    func testDevelopmentDeploymentResolvesLocalhost() {
        let config = AddressIQConfig(apiKey: "aiq_test_key", deployment: .development)
        XCTAssertEqual(config.resolvedApiUrl, URL(string: "http://localhost:4000")!)
    }

    func testIngestUrlIsDistinctFromApiUrl() {
        let production = AddressIQConfig(apiKey: "aiq_test_key", deployment: .production)
        XCTAssertEqual(production.resolvedIngestUrl.scheme, "https")
        XCTAssertNotEqual(production.resolvedIngestUrl, production.resolvedApiUrl)

        let staging = AddressIQConfig(apiKey: "aiq_test_key", deployment: .staging)
        XCTAssertNotEqual(staging.resolvedIngestUrl, staging.resolvedApiUrl)
    }

    func testDevelopmentIngestResolvesLocalhost() {
        let config = AddressIQConfig(apiKey: "aiq_test_key", deployment: .development)
        // Port 4001, not 4000. Ingest is a separate service from the API in the
        // dev stack (docker-compose.yml: api 4000, ingest 4001), and this used
        // to resolve to 4000 — so transit-event batches were posted at the API,
        // which has no such route. Development was the only deployment where
        // these two collapsed onto one host.
        XCTAssertEqual(config.resolvedIngestUrl, URL(string: "http://localhost:4001")!)
        XCTAssertNotEqual(config.resolvedIngestUrl, config.resolvedApiUrl)
    }

    // MARK: - Per-deployment CDN (baked from PROD_/STAGING_ADDRESSIQ_CDN_BASE_URL)

    /// The CDN host is a resolved config value only — the widget ships bundled
    /// and never loads from here (see AddressIQVerifyView). This just pins that
    /// each deployment resolves its own host rather than sharing one.
    func testCdnUrlResolvesPerDeployment() {
        let staging = AddressIQConfig(apiKey: "aiq_test_key", deployment: .staging)
        let production = AddressIQConfig(apiKey: "aiq_test_key", deployment: .production)

        XCTAssertEqual(staging.resolvedCdnUrl.scheme, "https")
        XCTAssertEqual(production.resolvedCdnUrl.scheme, "https")
        XCTAssertNotEqual(staging.resolvedCdnUrl, production.resolvedCdnUrl)
        XCTAssertNotEqual(production.resolvedCdnUrl, production.resolvedApiUrl)
    }

    // MARK: - `sandbox` is a tenant mode, not a deployment

    /// `"sandbox"` used to resolve to `.staging` via a custom `init?(rawValue:)`,
    /// which asserted that sandbox was a deployment. It is not — sandbox-vs-production
    /// is decided by the API key, server-side. The custom initialiser existed solely
    /// for that alias and is gone; the synthesised one correctly returns nil.
    func testSandboxRawValueIsRejected() {
        XCTAssertNil(AddressIQDeployment(rawValue: "sandbox"))
    }

    func testDeploymentRawValuesResolve() {
        XCTAssertEqual(AddressIQDeployment(rawValue: "staging"), .staging)
        XCTAssertEqual(AddressIQDeployment(rawValue: "production"), .production)
        XCTAssertEqual(AddressIQDeployment(rawValue: "development"), .development)
        XCTAssertNil(AddressIQDeployment(rawValue: "nonsense"))
    }
}
