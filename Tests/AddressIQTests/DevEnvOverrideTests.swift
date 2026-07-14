import XCTest
@testable import AddressIQ

/// Development-only host + Maps-key overrides, read from the process environment
/// (Xcode scheme → Run → Arguments → Environment Variables).
///
/// They exist because the `.development` hosts are hardcoded to `localhost:4000`,
/// with no way to reach a backend on another machine.
///
/// The load-bearing property is the gate: an override is honoured ONLY in
/// `.development`. Supplied anywhere else it is a fatal misconfiguration, not a
/// value to be quietly ignored — an environment variable must never be able to
/// point a shipped app at an arbitrary host.
final class DevEnvOverrideTests: XCTestCase {
    private let lan = "http://192.168.1.5:4000"

    func testApiOverrideIsHonouredInDevelopment() {
        let value = AddressIQDeployment.development.devOverride(
            "ADDRESSIQ_DEV_API_URL",
            env: ["ADDRESSIQ_DEV_API_URL": lan]
        )
        XCTAssertEqual(value, lan)
    }

    func testUnsetOverrideReturnsNil() {
        XCTAssertNil(
            AddressIQDeployment.development.devOverride("ADDRESSIQ_DEV_API_URL", env: [:])
        )
        // An empty string is "unset", not "override with empty".
        XCTAssertNil(
            AddressIQDeployment.development.devOverride(
                "ADDRESSIQ_DEV_API_URL", env: ["ADDRESSIQ_DEV_API_URL": ""]
            )
        )
    }

    func testAShippedDeploymentWithNoOverrideIsUnaffected() {
        // The trap must fire only when someone actually sets one — never on the
        // ordinary path.
        XCTAssertNil(
            AddressIQDeployment.production.devOverride("ADDRESSIQ_DEV_API_URL", env: [:])
        )
        XCTAssertEqual(AddressIQDeployment.production.defaultApiUrl.scheme, "https")
    }

    func testEachOverrideIsIndependent() {
        // Overriding the API host must not drag the ingest or CDN host along.
        let env = ["ADDRESSIQ_DEV_API_URL": lan]
        XCTAssertEqual(
            AddressIQDeployment.development.devOverride("ADDRESSIQ_DEV_API_URL", env: env),
            lan
        )
        XCTAssertNil(
            AddressIQDeployment.development.devOverride("ADDRESSIQ_DEV_INGEST_URL", env: env)
        )
        XCTAssertNil(
            AddressIQDeployment.development.devOverride("ADDRESSIQ_DEV_CDN_URL", env: env)
        )
    }

    func testMapsKeyOverrideIsHonouredInDevelopment() {
        // Normally the widget provisions its own key from GET /api/v1/widget/config.
        // This covers a local backend that has none.
        XCTAssertEqual(
            AddressIQDeployment.development.devOverride(
                "ADDRESSIQ_DEV_GOOGLE_MAPS_KEY", env: ["ADDRESSIQ_DEV_GOOGLE_MAPS_KEY": "AIzaDEV"]
            ),
            "AIzaDEV"
        )
    }

    // NOTE: the "throws on a shipped deployment" half of the gate is a
    // `preconditionFailure`, which traps the process rather than throwing — it is
    // a programmer error, not a recoverable condition, and XCTest cannot catch it
    // without spawning a subprocess. The Flutter and web SDKs assert the same gate
    // with a catchable error, and the Swift branch is a straight-line `guard`
    // against `self == .development`.
}
