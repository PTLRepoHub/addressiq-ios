// Generated build-time configuration.
//
// The production API URL is baked into published pods at publish time: CI
// replaces the placeholder below with the value of the GitHub `ADDRESSIQ_API_URL`
// variable (see .github/workflows/release.yml). The checked-in default keeps
// local builds and tests working when no substitution has run.
enum BuildConfig {
    static let apiURL = "https://api.addressiqpro.com"
}
