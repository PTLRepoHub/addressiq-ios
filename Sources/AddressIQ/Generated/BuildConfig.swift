// Generated build-time configuration — DO NOT EDIT BY HAND.
//
// Rewritten wholesale by `scripts/bake-build-config.sh` at publish time from
// the GitHub repository variables (see .github/workflows/release.yml):
//
//   STAGING_ADDRESSIQ_API_BASE_URL          PROD_ADDRESSIQ_API_BASE_URL
//   STAGING_ADDRESSIQ_INGEST_BASE_URL   PROD_ADDRESSIQ_INGEST_BASE_URL
//   STAGING_ADDRESSIQ_CDN_BASE_URL          PROD_ADDRESSIQ_CDN_BASE_URL
//
// The checked-in values below are the safe public defaults, so a local
// `swift build` and the test suite resolve real hosts with no substitution.
// On a real release the baker runs with --strict and REQUIRES every variable
// above — a published pod must never silently carry a developer's default.
//
// `development` is deliberately NOT baked from CI: it points at the host
// machine's backend, so it is a local-only concern and stays a compile-time
// literal in AddressIQEnvironment. Never ship a build configured for
// `.development`.
//
// The two widget pins come from FILES at the repo root — `.widget-version` and
// `.widget-integrity` — which the web repo's widget-fanout workflow writes on
// every web release. `widgetVersion` is stored BARE ("0.4.0", any leading "v"
// stripped); the CDN serves immutable paths under /v{x.y.z}/, so the URL is
// built as "\(cdn)/v\(widgetVersion)/iqcollect.js". Empty strings mean "no pin
// published yet" and disable the CDN path — the SDK then inlines the bundled
// widget. Never hand-write a hash here.
enum BuildConfig {
    static let stagingApiURL = "https://api-staging.addressiqpro.com"
    static let stagingIngestURL = "https://ingest-api-staging.addressiqpro.com"
    static let stagingCdnURL = "https://cdn-staging.addressiqpro.com"

    static let prodApiURL = "https://api.addressiqpro.com"
    static let prodIngestURL = "https://ingest-api.addressiqpro.com"
    static let prodCdnURL = "https://cdn.addressiqpro.com"

    /// Bare semver of the published web widget, e.g. "0.4.0". Empty ⇒ no CDN pin.
    static let widgetVersion = ""
    /// Subresource-integrity hash of that widget, e.g. "sha384-…". Empty ⇒ no CDN pin.
    static let widgetIntegrity = ""
}
