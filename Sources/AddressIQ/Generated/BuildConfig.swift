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
// The widget pins come from FILES at the repo root — `.widget-version-staging`,
// `.widget-integrity-staging`, `.widget-version-prod`, `.widget-integrity-prod`
// — which the web repo's widget-fanout workflow writes on every web release.
// staging and prod are pinned SEPARATELY: their bundles differ byte-for-byte
// (per-environment Maps key) so the SRI hashes differ. `widgetVersion` is
// stored BARE ("0.5.3", any leading "v" stripped); the CDN serves immutable
// paths under /v{x.y.z}/, so the URL is built as
// "\(cdn)/v\(widgetVersion)/iqcollect.js". Empty strings mean "no pin published
// yet" and disable the CDN path for that deployment. Never hand-write a hash.
enum BuildConfig {
    /// This SDK's version, from `version.txt`. Sent as x-sdk-version and used
    /// for the telemetry envelope, so neither can drift from the release.
    static let sdkVersion = "0.8.0"

    static let stagingApiURL = "https://api-staging.addressiqpro.com"
    static let stagingIngestURL = "https://ingest-api-staging.addressiqpro.com"
    static let stagingCdnURL = "https://cdn-staging.addressiqpro.com"

    static let prodApiURL = "https://api.addressiqpro.com"
    static let prodIngestURL = "https://ingest-api.addressiqpro.com"
    static let prodCdnURL = "https://cdn.addressiqpro.com"

    /// Bare semver of the STAGING web widget, e.g. "0.5.3". Empty ⇒ no CDN pin.
    static let stagingWidgetVersion = "0.5.3"
    /// SRI hash of the staging widget, e.g. "sha384-…". Empty ⇒ no CDN pin.
    static let stagingWidgetIntegrity = "sha384-Q7LZd2vji9K0ulAu866ywpCzIj0aoaZAl9n9Ghw1lkf8aT84y++RT/9rHcAIuYJB"
    /// Bare semver of the PRODUCTION web widget, e.g. "0.5.3". Empty ⇒ no CDN pin.
    static let prodWidgetVersion = "0.5.3"
    /// SRI hash of the production widget, e.g. "sha384-…". Empty ⇒ no CDN pin.
    static let prodWidgetIntegrity = "sha384-wUErWmll1WWgesjXvSN93KLxHTDLNXdZ4FMR9nT2tQ7tpdBdEuQCDMkHgdssRvkb"
}
