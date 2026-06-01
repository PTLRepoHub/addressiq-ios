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

## Install (consumers)

**Swift Package Manager** — add the package:

```swift
.package(url: "https://github.com/PTLRepoHub/addressiq-ios.git", from: "0.1.0")
```

**CocoaPods** — `pod 'AddressIQ', '~> 0.1'`.

## Develop

```bash
# SDK build + test on a simulator
xcodebuild test -scheme AddressIQ -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Example against your local SDK

```bash
cd example
xcodebuild build -scheme AddressIQSample -destination 'generic/platform=iOS'
# or: open Package.swift in Xcode and run on a simulator
```

`example/Package.swift` depends on `.package(path: "..")`, so it always builds
against this repo's SDK source.

## Release

Push a semver tag (`.github/workflows/release.yml`):

```bash
git tag v0.1.0 && git push origin v0.1.0
```

- **SwiftPM:** the tag is the release — nothing to publish.
- **CocoaPods:** the workflow runs `pod trunk push` (needs the
  `COCOAPODS_TRUNK_TOKEN` secret). Run manually with `dry_run: true` to lint.

## Contributing

Fork, branch, PR. CI builds + tests the SDK and builds the example against the
local SDK on every push/PR.
