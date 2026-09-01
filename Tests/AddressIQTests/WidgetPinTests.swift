import XCTest
@testable import AddressIQ

/// Per-deployment widget pin selection.
///
/// staging and prod publish the widget independently — their bundles differ
/// byte-for-byte (per-environment Maps key) → different SRI hashes. Each
/// deployment must resolve its OWN version + integrity, matched to its CDN host.
final class WidgetPinTests: XCTestCase {

    func testStagingResolvesStagingPin() {
        XCTAssertEqual(AddressIQDeployment.staging.defaultWidgetVersion, BuildConfig.stagingWidgetVersion)
        XCTAssertEqual(AddressIQDeployment.staging.defaultWidgetIntegrity, BuildConfig.stagingWidgetIntegrity)
        XCTAssertTrue(AddressIQDeployment.staging.defaultCdnUrl.absoluteString.contains("cdn-staging"))
    }

    func testProductionResolvesProdPin() {
        XCTAssertEqual(AddressIQDeployment.production.defaultWidgetVersion, BuildConfig.prodWidgetVersion)
        XCTAssertEqual(AddressIQDeployment.production.defaultWidgetIntegrity, BuildConfig.prodWidgetIntegrity)
        XCTAssertFalse(AddressIQDeployment.production.defaultCdnUrl.absoluteString.contains("cdn-staging"))
    }

    func testDevelopmentReusesProdPinAndCdn() {
        XCTAssertEqual(AddressIQDeployment.development.defaultWidgetVersion, BuildConfig.prodWidgetVersion)
        XCTAssertEqual(AddressIQDeployment.development.defaultWidgetIntegrity, BuildConfig.prodWidgetIntegrity)
        XCTAssertFalse(AddressIQDeployment.development.defaultCdnUrl.absoluteString.contains("cdn-staging"))
    }

    // NOTE: staging and prod pins MAY currently coincide (the staging CDN object
    // is not reliably a distinct bundle — see the CDN encoding-divergence issue),
    // which is allowed. The contract is that each deployment resolves to ITS OWN
    // configured pin, not that the two values always differ.
}
