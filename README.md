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
    config: AddressIQConfig(apiKey: "aiq_live_…", environment: .production)
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
    environment: .production,
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

## Environment

`AddressIQEnvironment.production` → `https://api.addressiqpro.com`;
`.sandbox` → `https://api-staging.addressiqpro.com`. Override the base URL only
for a partner proxy or hermetic test backend via `AddressIQConfig(apiUrl:)`.

## Example app

A SwiftUI sample (iOS 15+) demonstrating the full screen canon. After
**Login**, the app shows a five-tab interface:

- **Login** — environment picker (sandbox/production) + appUserId field →
  `initialize(config:)` + `setUser(_:)`.
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
`aiq_test_demo_bank_seed01`, `.sandbox`). The
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
