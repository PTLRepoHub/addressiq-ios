# Changelog

## [0.8.1](https://github.com/PTLRepoHub/addressiq-ios/compare/v0.8.0...v0.8.1) (2026-09-04)


### Bug Fixes

* **ios:** a response we cannot read is an error, not an empty result ([#25](https://github.com/PTLRepoHub/addressiq-ios/issues/25)) ([52ce82b](https://github.com/PTLRepoHub/addressiq-ios/commit/52ce82b16b97541055d993b827acf676d310aa66))

## [0.8.0](https://github.com/PTLRepoHub/addressiq-ios/compare/v0.7.0...v0.8.0) (2026-09-01)


### ⚠ BREAKING CHANGES

* `AddressIQEnvironment` is renamed to `AddressIQDeployment` and `.sandbox` is removed. Integrators referencing the old type or case must update.
* The SDK no longer ships a vendored `iqcollect.js`. The widget is loaded from the CDN at runtime against a pinned version and SRI hash.

### Features

* **config:** rename `AddressIQEnvironment` to `AddressIQDeployment`; drop `.sandbox`
* **config:** dev-only env overrides for hosts and the Maps key
* **widget:** drop the vendored bundle; the pinned CDN copy is the only source

### Bug Fixes

* **telemetry:** copy bound text into SQLite. `sqlite3_bind_text` passed a nil destructor, promising that a bridged Swift `String` outlives the statement; it does not, so queued payloads were read from freed memory and usually stored empty.
* **telemetry:** acknowledge any 2xx, not only 200. The ingest batch endpoint answers 201, so uploaded rows were never deleted and the same batch re-uploaded on every flush for the life of the install.
* **config:** resolve development ingest to port 4001. It resolved to 4000, which is the API — development was the only deployment where the two hosts collapsed onto one.
* **location:** release stale geofence regions before monitoring a new one, and report registration failures. CoreLocation caps an app at 20 regions and keeps them across launches, so collection stopped silently once the cap was reached.

## [0.7.0](https://github.com/PTLRepoHub/addressiq-ios/compare/v0.6.0...v0.7.0) (2026-07-12)


### Features

* **widget:** re-vendor iqcollect.js from web v0.5.3 ([#18](https://github.com/PTLRepoHub/addressiq-ios/issues/18)) ([6d3112f](https://github.com/PTLRepoHub/addressiq-ios/commit/6d3112f6b532ce989c9a9d9d8a9d4182cb239703))

## [0.6.0](https://github.com/PTLRepoHub/addressiq-ios/compare/v0.5.0...v0.6.0) (2026-07-12)


### ⚠ BREAKING CHANGES

* `AddressIQEnvironment.sandbox` is renamed to `.staging`. The old name is retained as a deprecated alias, and `init(rawValue: "sandbox")` still resolves to `.staging`, so existing integrators keep compiling.

### Features

* per-environment build config and CDN widget loading ([#13](https://github.com/PTLRepoHub/addressiq-ios/issues/13)) ([03c7b1f](https://github.com/PTLRepoHub/addressiq-ios/commit/03c7b1f8e2ecdba5a70230dc6ed034ed65bbf5a4))
* **widget:** re-vendor iqcollect.js from web v0.5.1 ([#16](https://github.com/PTLRepoHub/addressiq-ios/issues/16)) ([6af9018](https://github.com/PTLRepoHub/addressiq-ios/commit/6af90187c4b444104ba74abf55adfac0bcd50dc7))

## [0.5.0](https://github.com/PTLRepoHub/addressiq-ios/compare/v0.4.0...v0.5.0) (2026-07-12)


### Features

* **widget:** re-vendor iqcollect.js from web v0.4.2 ([#11](https://github.com/PTLRepoHub/addressiq-ios/issues/11)) ([3ea8021](https://github.com/PTLRepoHub/addressiq-ios/commit/3ea8021de03ac200cfb549cb665188ab66e3ca5e))

## [0.4.0](https://github.com/PTLRepoHub/addressiq-ios/compare/v0.3.0...v0.4.0) (2026-07-12)


### Features

* **widget:** re-vendor iqcollect.js from web v0.4.1 ([#9](https://github.com/PTLRepoHub/addressiq-ios/issues/9)) ([c700748](https://github.com/PTLRepoHub/addressiq-ios/commit/c70074853dda80f6c5246c77a08ac2aa224c5dcb))

## [0.3.0](https://github.com/PTLRepoHub/addressiq-ios/compare/v0.2.0...v0.3.0) (2026-07-12)


### ⚠ BREAKING CHANGES

* removed AddressIQConfig.apiUrl and the AddressIQVerifyView apiUrlOverride parameter. Select a host via `environment` (production | sandbox | development); production is provisioned at build time.

### Features

* provision API URL (+ web: Maps key) at build time from GH env ([#6](https://github.com/PTLRepoHub/addressiq-ios/issues/6)) ([c180970](https://github.com/PTLRepoHub/addressiq-ios/commit/c180970b6de01c62852381db635529e857cfcfd9))

## [0.2.0](https://github.com/PTLRepoHub/addressiq-ios/compare/v0.1.0...v0.2.0) (2026-07-12)


### ⚠ BREAKING CHANGES

* removed the googleMapsApiKey parameter from AddressIQVerifyView.init. The key is provisioned automatically by the platform; there is nothing to pass.

### Features

* **proto:** regen against proto v0.1.0 ([#2](https://github.com/PTLRepoHub/addressiq-ios/issues/2)) ([3f2958a](https://github.com/PTLRepoHub/addressiq-ios/commit/3f2958ad3bae49b12d779388bc285317cc2a6a00))
* provision Google Maps key automatically; remove googleMapsApiKey ([#4](https://github.com/PTLRepoHub/addressiq-ios/issues/4)) ([1a34bde](https://github.com/PTLRepoHub/addressiq-ios/commit/1a34bde1e2a005d00028ec9382a14a46b18f9cd0))


### Bug Fixes

* **core:** host the test WKWebView in a key window ([d85d0fd](https://github.com/PTLRepoHub/addressiq-ios/commit/d85d0fddbf12e3cff5031c1159479ea9133a728b))
* **core:** resolve the widget bundle under CocoaPods, not just SPM ([266e67b](https://github.com/PTLRepoHub/addressiq-ios/commit/266e67be6fcfe16ab0fdb6796b6d5ddd1fc86f7f))
* **core:** stub the full bridge contract in the WebView round-trip test ([c04c3ff](https://github.com/PTLRepoHub/addressiq-ios/commit/c04c3ff76987758f270443c201aea23d77bcc253))

## 0.1.0 (2026-07-10)


### ⚠ BREAKING CHANGES

* a missing widget bundle now fails via onFailed instead of silently fetching from a CDN. `widgetURL` still works as a dev override.

### Features

* AddressIQ iOS SDK + example + CI/CD ([68e731d](https://github.com/PTLRepoHub/addressiq-ios/commit/68e731dfbfff84ad0319cb607f544a15ab244c93))
* fail closed when the bundled widget is missing ([7e28b1e](https://github.com/PTLRepoHub/addressiq-ios/commit/7e28b1e0704984e55772ca9bd4cc2a8716431bfa))
* **ios:** collect→verify split + SwiftUI sample demoing all 3 verification types ([f8eec3b](https://github.com/PTLRepoHub/addressiq-ios/commit/f8eec3b2519303bffe9a71d6127066f39c7b9cea))
* **ios:** maps address-capture + Street View refinements in Collect UI ([3fac6ba](https://github.com/PTLRepoHub/addressiq-ios/commit/3fac6ba3623b07b5c53a49dcf81e0a65a290af05))
* **proto:** generate wire-contract bindings from AddressIq-proto ([874ccdb](https://github.com/PTLRepoHub/addressiq-ios/commit/874ccdb5a235616a4ad790024892474efba40b58))


### Bug Fixes

* **ci:** pick an available iOS simulator instead of hardcoding iPhone 16 ([7c966c7](https://github.com/PTLRepoHub/addressiq-ios/commit/7c966c7106c0ac39fe8da8abd0ac2b4e3d0d433f))
* **ci:** set bump-minor-pre-major in release-please config ([fe8bbc3](https://github.com/PTLRepoHub/addressiq-ios/commit/fe8bbc3b35de6f2075bb2fef5f873f8afc75a5d8))
* **podspec:** declare SwiftProtobuf and the widget resource bundle ([89edcbe](https://github.com/PTLRepoHub/addressiq-ios/commit/89edcbec204f6d2db3693b7b1976d1bc12cc4262))
* re-vendor iqcollect.js with addressiqpro.com URLs ([ea6be1d](https://github.com/PTLRepoHub/addressiq-ios/commit/ea6be1d8fb2b2fcc06da5d059a46f220370c6967))


### Miscellaneous Chores

* cut the first release as 0.1.0 ([afac6f6](https://github.com/PTLRepoHub/addressiq-ios/commit/afac6f6408fb7675474530ffc0ee67a6261f77d5))
