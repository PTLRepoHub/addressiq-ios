# AddressIQ — iOS SDK

[![CI](https://github.com/PTLRepoHub/addressiq-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/PTLRepoHub/addressiq-ios/actions/workflows/ci.yml)

`AddressIQ` is the native iOS SDK — address collection + verification lifecycle
(`AddressIQ.shared`), with a SwiftUI drop-in verify UI. Core API is iOS 13+; the
bundled SwiftUI UI is iOS 15+.

## Repository layout

```
.                      ← the SDK (SwiftPM package "AddressIQ")
  Package.swift        at the repo ROOT → SwiftPM-consumable by URL + tag
  Sources/AddressIQ/   SDK source
  Tests/AddressIQTests smoke test (XCTest)
  AddressIQ.podspec    CocoaPods spec
  example/             minimal example, linked to the LOCAL SDK (path: ..)
```

## Install (SPM)

**Swift Package Manager** — add the package:

```swift
.package(url: "https://github.com/PTLRepoHub/addressiq-ios.git", from: "0.1.0")
```

**CocoaPods** — `pod 'AddressIQ', '~> 0.1'`.

## Quick start

```swift
import AddressIQ

// 1. Initialize once at launch.
AddressIQ.shared.initialize(
    config: AddressIQConfig(apiKey: "aiq_live_…", deployment: .production)
)

// 2. Identify the user (appUserId is the canonical key).
try await AddressIQ.shared.setUser(SDKUser(appUserId: "user_123"))

// 3. Request location permissions, then start a verification.
_ = await AddressIQ.shared.requestPermissions()
let result = try await AddressIQ.shared.startVerification(
    StartDigitalArgs(locationCode: "loc_abc")
)
print(result.verificationCode, result.status)
```

## Collect UI (`AddressIQVerifyView`)

Drop-in SwiftUI collect + verify widget (iOS 15+). Present it as a sheet or
full-screen cover. On success the `onCompleted` closure receives an
`AddressIQVerifyResult` carrying the public **`verificationCode`** +
**`locationCode`** (not internal UUIDs), plus `status`. The SDK wires
background collection automatically once the widget completes.

```swift
AddressIQVerifyView(
    apiKey: "aiq_live_…",
    appUserId: "user_123",
    deployment: .production,
    onCompleted: { result in
        // result.verificationCode, result.locationCode, result.status
    },
    onCancelled: { /* user dismissed */ },
    onFailed: { error in /* error.code, error.message, error.httpStatus */ }
)
```

A UIKit bridge is available via `AddressIQVerifyViewController`.

## SDK API (`AddressIQ.shared`)

| Method | Purpose |
| --- | --- |
| `initialize(config:)` | One-time setup. |
| `setUser(_:)` | Identify the user (`appUserId` is the canonical key). |
| `startVerification(_:) -> StartDigitalResult` | Start a **digital** verification (`POST /verifications/digital`, `digitalProvider` defaults to `internal_ai`). Returns `verificationCode` + `status` (+ optional geofence). |
| `startPhysicalVerification(_:)` | Start a physical (agent-visit) verification. |
| `startDigitalAndPhysicalVerification(_:)` | Start a combined digital + physical verification. |
| `cancelVerification(_:)` | Cancel an in-flight verification. |
| `getVerificationState()` | Current lifecycle snapshot. |
| `statePublisher` | Combine publisher of lifecycle transitions. |

Every `start*` call gates on granted location permissions and, on success,
activates background collection + geofence monitoring for the returned
`locationCode` / `verificationCode`.

## Permissions

The app decides *when* verification begins; the SDK owns every step after.

```swift
let state = AddressIQ.shared.getPermissionState()
// { foregroundLocation, backgroundLocation, notifications } ∈
// { GRANTED, DENIED, NOT_DETERMINED, BLOCKED, UNAVAILABLE }

let final = await AddressIQ.shared.requestPermissions()  // drives OS prompts
```

`start*` throws `AddressIQError.permissionDenied` (code `PERMISSION_DENIED`)
when foreground or background location is not `GRANTED`. Use
`canRequestPermission(scope:)` to decide between rationale UI and an
`openSettings()` deep-link.

## Errors

`AddressIQError` exposes a stable cross-SDK `.code` string:

| Code | When |
| --- | --- |
| `NOT_INITIALIZED` | `initialize` was not called. |
| `NO_ACTIVE_SESSION` | No active verification to resume/operate on. |
| `PERMISSION_DENIED` | Foreground/background location not granted at `start*`. |
| `HTTP_ERROR` (or server `code`) | Non-2xx backend response. |

The collect UI surfaces `AddressIQVerifyError` (`code`, `message`,
`httpStatus`) via `onFailed`.

## Deployment vs sandbox — two different things

These are orthogonal, and conflating them is the most common integration mistake:

| | What it selects | How you set it |
|---|---|---|
| **Deployment** | Which AddressIQ **hosts** you talk to | `AddressIQConfig.deployment` |
| **Tenant mode** | Whether your data is **sandbox or production** | **Which API key you paste** |

`AddressIQDeployment` offers `.production`, `.staging`, and `.development`.
Integrators simply choose one; `.development` targets a backend running on your
host machine (the iOS simulator reaches it via `localhost`).

**`.sandbox` no longer exists**, and `AddressIQDeployment(rawValue: "sandbox")`
returns `nil`. It was an alias for `.staging`, which asserted that sandbox was a
deployment — it is not. Sandbox-vs-production is a property of your **API key**:
`aiq_test_…` resolves to a sandbox tenant server-side, `aiq_live_…` to a
production one. The SDK never sends a mode and cannot override the key's.

The two combine freely: an `aiq_test_…` key on `.production` is still sandbox
data; an `aiq_live_…` key on `.staging` is still production-mode data.

> **Migrating from `environment:`?** `environment: .sandbox` → drop the argument
> and use a sandbox key (`aiq_test_…`), which is almost certainly what you meant.
> Use `deployment: .staging` only if you specifically wanted the pre-production
> *hosts*. Anything decoding `"sandbox"` from a plist/JSON now gets `nil` — that
> is deliberate, and loud.

The base URLs — including the dedicated host used for transit-event batch
ingestion — are resolved entirely from `deployment`; integrators never pass a
URL (`resolvedApiUrl` / `resolvedIngestUrl`, `AddressIQ.swift:47-56`). The
`production` and `staging` hosts are baked in at publish time from six GitHub
repository variables (see [`docs/RELEASE.md` §3](docs/RELEASE.md)); `development`
is a compile-time literal (`http://localhost:4000`). Use `.development` to run
against a local backend; never ship a `.development` build.

`AddressIQConfig.resolvedCdnUrl` (`AddressIQ.swift:64`) exposes the CDN base URL
for the deployment, and the verify webview **does** load the widget from it —
under an SRI pin. `Sources/AddressIQ/Views/AddressIQWebFlowView.swift:138-199`
resolves the widget source in this order:

1. **`widgetURL`** — explicit developer override, wins over everything.
2. **Pinned CDN build** — `{cdn}/v{widgetVersion}/iqcollect.js` loaded with
   `integrity="{widgetIntegrity}" crossorigin="anonymous"`
   (`AddressIQWebFlowView.swift:184-195`). WebKit **enforces** `integrity`, so
   the CDN can only ever execute the exact bytes hashed at build time — the
   version/hash pair is baked from `.widget-version` / `.widget-integrity`
   (`Generated/BuildConfig.swift`), which the web repo's release fanout writes
   from the same build the CDN serves. The CDN publishes immutable `/v{x.y.z}/`
   paths and no floating alias, precisely because a mutable URL cannot be
   SRI-pinned.
3. **Bundled widget** (`Resources/iqcollect.js`) — the *fallback*, injected by
   `onerror="__iqWidgetFallback()"`. That covers a CDN outage, an offline
   device, **and** an SRI mismatch, so verification never depends on CDN uptime.
   It is also the only source when the CDN path is off: `.development` never
   uses the CDN, and an unbaked (empty) version or integrity disables it
   (`AddressIQWebFlowView.swift:179-182`).

If **neither** a pinned CDN build nor the bundle is available, the SDK still
**fails closed** with `WIDGET_BUNDLE_MISSING` via `onFailed`
(`AddressIQWebFlowView.swift:54-63`). An unpinned remote script is never loaded.

Three details in that markup are load-bearing — each fails *silently* toward
"looks fine, but never actually uses the CDN":

- `crossorigin="anonymous"` is **mandatory**. Without it the cross-origin
  response is opaque, `integrity` cannot be evaluated, and every load hard-fails
  into the fallback.
- **Script order.** A blocking classic `<script>` fires `onerror` before the
  parser reaches the next inline script, so `__iqWidgetFallback()` must be
  defined *before* the remote tag (and the tag must not be `defer`/`async`).
- The inlined fallback bundle must be **escaped** — it contains
  `</script>`-alike sequences that would otherwise terminate the tag.

## Example app

A SwiftUI sample (iOS 15+) demonstrating the full screen canon. After
**Login**, the app shows a five-tab interface:

- **Login** — deployment picker (development/staging/production) + appUserId
  field → `initialize(config:)` + `setUser(_:)`.
- **Verify** — human-labelled hub: a **Collect Address** button that opens the
  `AddressIQVerifyView` collect UI as a sheet, plus **Digital / Physical /
  Digital + Physical** buttons that call the SDK API. A lifecycle status chip
  reflects the current state. Completing collect or a `start*` call surfaces a
  result modal with the verificationCode / locationCode / status (and raw JSON
  where applicable).
- **Helpers** — `getPermissionState()` (the five states), a **Request
  permissions** button, and **Open settings**.
- **Addresses** — the in-memory list of collected location codes; tapping one
  re-verifies it via `startVerification(_:)`.
- **Developer** — raw `start*` buttons + `getVerificationState()` /
  `cancelVerification(_:)`, each opening a result/error modal. Raw SDK method
  names appear only here.
- **Settings** — `logout()` / `reset()`.

**Compile-check** the sample against the local SDK:

```bash
cd example
xcodebuild build -scheme AddressIQSample -destination 'generic/platform=iOS Simulator'
```

`example/Package.swift` depends on `.package(path: "..")`, so it always builds
against this repo's SDK source.

> ⚠️ **A successful build does NOT produce a runnable app.** `AddressIQSample`
> is a SwiftPM `.executableTarget`, and SwiftPM has no iOS-application product
> type — `xcodebuild build` compiles a bare Mach-O with **no `.app` bundle**, so
> `simctl install`/`launch` and "Run" in Xcode won't work for the simulator.

**Run it live on a simulator** — wrap the SwiftPM sample in a throwaway app
target with [`xcodegen`](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`):

```bash
cd example
# project.yml: type: application, deploymentTarget iOS 15.1, a packages entry
# pointing at the local SDK (../), a target depending on
# { package: AddressIQ, product: AddressIQ }, and an info.properties block with
# the NSLocation*UsageDescription keys (incl. the Always-usage string).
xcodegen generate
xcodebuild -project AddressIQSample.xcodeproj -scheme AddressIQSample \
  -destination 'platform=iOS Simulator,name=iPhone 15' build

# Install + launch (the Maps key is provisioned by the platform via
# `GET /api/v1/widget/config` — nothing to inject on the client)
xcrun simctl boot 'iPhone 15' 2>/dev/null || true
xcrun simctl install booted <path-to>.app
xcrun simctl launch booted com.addressiq.example

# Grant location + feed a fix (the sim has no real GPS)
xcrun simctl privacy booted grant location-always com.addressiq.example
xcrun simctl location booted set 6.5244,3.3792
```

The map key is provisioned by the platform and delivered to the widget via
`GET /api/v1/widget/config` — integrators do not supply a Google Maps key. The
API key comes from the **Login** screen (pre-filled with
`aiq_test_demo_bank_seed01`, staging). The
generated app's `Info.plist` **must** include
`NSLocationWhenInUseUsageDescription`,
`NSLocationAlwaysAndWhenInUseUsageDescription` and `UIBackgroundModes: [location]`
— without the Always-usage key the permission step hangs (iOS silently no-ops
`requestAlwaysAuthorization`).

## Develop

```bash
# SDK build + test on a simulator
xcodebuild test -scheme AddressIQ -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Release

Push a semver tag (`.github/workflows/release.yml`):

```bash
git tag v0.1.0 && git push origin v0.1.0
```

- **SwiftPM:** the tag is the release — nothing to publish.
- **CocoaPods:** the workflow runs `pod trunk push` (needs the
  `COCOAPODS_TRUNK_TOKEN` secret). Run manually with `dry_run: true` to lint.

## Related docs

- Cross-SDK contract: [`../../geo-tagging/docs/sdk-contract.md`](../../geo-tagging/docs/sdk-contract.md)
- iOS integration guide: [`../../geo-tagging/apps/docs/docs/sdk/ios.md`](../../geo-tagging/apps/docs/docs/sdk/ios.md)

## Contributing

Fork, branch, PR. CI builds + tests the SDK and builds the example against the
local SDK on every push/PR.

## Running the SDK locally, end to end

Everything below is **development-only**. Every override is honoured solely under
the `development` deployment and **throws** on a staging or production build, even
if the variable is set — a build-time value must never be able to point a shipped
app at an arbitrary host.

### 1. Start the backend

```sh
cd addressiq-node-backend
cp .env.example .env          # set GOOGLE_MAPS_API_KEY if you want the map to load
npm install && npm start      # http://localhost:4000
```

It must bind `0.0.0.0`, not `127.0.0.1`, or nothing off-machine can reach it.

### 2. (Optional) Serve the widget yourself

Only needed if you are **changing the widget**. Otherwise the SDK uses the widget
it already ships.

```sh
cd addressiq-web
npx rollup -c                 # → dist/iqcollect.js
npx serve dist -p 5173
```

Then set `ADDRESSIQ_DEV_WIDGET_URL` to `http://<host>:5173/iqcollect.js` for live
reload without re-vendoring. Point it at a **published** URL
(`https://cdn.addressiqpro.com/v0.5.3/iqcollect.js`) instead to exercise the
remote-load + SRI + `onerror`-fallback paths, which `development` otherwise never
takes because it inlines the bundled asset.

A `file://` path will **not** work: the Android emulator is a separate VM and
cannot see your filesystem, and a physical device certainly cannot. It has to be
served over HTTP.

### 3. Point the SDK at your machine

```sh
cp .env.example .env
```

**Which host do I use?**

| Running on | Host |
|---|---|
| Android emulator | `10.0.2.2` — a special alias for your machine's localhost |
| iOS simulator | `localhost` — it shares your Mac's network |
| **Physical device (either OS)** | your **LAN IP** — `ipconfig getifaddr en0` |

The default is the emulator/simulator literal, which is exactly why these
overrides exist: **a physical device cannot reach `10.0.2.2` or `localhost`.**

Xcode does not read a `.env`. Either paste the values into
**Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables**, or
export them for a command-line run:

```sh
set -a; source .env; set +a
swift test
```

### 4. Android only: allow plain HTTP

A LAN IP over plain `http://` is blocked by default. In your **debug** manifest:

```xml
<application android:usesCleartextTraffic="true" …>
```

Debug only — never in a release. (A `network_security_config` scoped to that one
host is the tighter version.)

### Troubleshooting

- **Requests hang / connection refused on a real device** — the backend is bound to
  `127.0.0.1`. Bind `0.0.0.0`.
- **Works on the emulator, fails on a device** — you are still on `10.0.2.2`. Set a
  LAN IP.
- **Android: `net::ERR_CLEARTEXT_NOT_PERMITTED`** — step 4.
- **The map is blank** — your backend has no Maps key. `GET /api/v1/widget/config`
  supplies it; set `GOOGLE_MAPS_API_KEY` in the backend's `.env`. (The key is
  platform-provisioned; no native SDK accepts one, because the key is used by the
  widget, not by native code.)
- **An override "does nothing"** — check `deployment` is `development`. Anywhere
  else it throws rather than being silently ignored, so you would have seen an error.
