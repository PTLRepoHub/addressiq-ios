# Releasing the AddressIQ iOS SDK

How versions of the AddressIQ iOS SDK are cut and published. The pipeline is
automated end to end — **you never create a git tag by hand**. Merging the
release-please PR does that, and the tag is what publishes.

## 1. What this repo publishes

One SDK, two distribution channels:

- **CocoaPods** — pod name `AddressIQ` (`AddressIQ.podspec:2`), pushed to the
  public CocoaPods trunk by CI.
- **Swift Package Manager** — there is no separate "publish" for SPM. The **git
  tag itself is the release** (`.github/workflows/release.yml:3-6`). The package
  is defined in `Package.swift` (product `AddressIQ`, `Package.swift:13-17`).

SPM consumers point at the git remote and pin a semver/tag, e.g.:

```swift
.package(url: "https://github.com/PTLRepoHub/addressiq-ios.git", from: "0.1.0")
```

`from: "0.1.0"` resolves against the pushed tag `v0.1.0`. To pin an exact
release, use `.exact("0.1.0")`. The remote must match the podspec source
(`AddressIQ.podspec:16`, `https://github.com/PTLRepoHub/addressiq-ios.git`).

Current released version: `0.1.0` (`.release-please-manifest.json:2`,
`version.txt:1`).

## 2. Release flow

The flow spans two workflows and is driven entirely by
[Conventional Commits](https://www.conventionalcommits.org/):

1. Land Conventional-Commit changes on `main` (`fix:`, `feat:`, `feat!:`, …).
2. `release-please.yml` runs on every push to `main`
   (`.github/workflows/release-please.yml:13-16`) and maintains an open
   **`chore: release X.Y.Z`** PR (title pattern from
   `release-please-config.json:5`).
3. **Merging that PR** writes `CHANGELOG.md`, bumps the version in `version.txt`
   / `.release-please-manifest.json`, and **pushes tag `vX.Y.Z`**
   (`release-please.yml:3-9`).
4. The tag push triggers `release.yml` (`on: push: tags: ["v*.*.*"]`,
   `release.yml:11-13`), which **bakes the build config** (`release.yml:34-42`,
   see §3), then lints and runs `pod trunk push AddressIQ.podspec`
   (`release.yml:43-56`). SPM needs no publish step — the tag is already the
   release (`release.yml:57-58`).

**Do not tag manually.** Tags come only from merging the release PR. A key
detail: GitHub does not fire workflows for events made with the default
`GITHUB_TOKEN`, so `release-please.yml` mints a **GitHub App token** and pushes
the tag with it — an App-authored tag push *does* trigger `release.yml`
(`release-please.yml:6-11, 29-38`). A hand-pushed tag bypasses the version/
changelog bump and can desync `version.txt`.

`release.yml` also supports a manual `workflow_dispatch` **dry run** that only
runs `pod lib lint` (`release.yml:14-19, 47-53`).

## 3. Build-time configuration (the six repo variables)

The hosts the SDK talks to are **baked into the source at publish time**, not
read at runtime. `scripts/bake-build-config.sh` regenerates
`Sources/AddressIQ/Generated/BuildConfig.swift` **wholesale** from six GitHub
**repository variables** — three per shippable environment:

| Staging | Production |
|---|---|
| `STAGING_ADDRESSIQ_API_BASE_URL` | `PROD_ADDRESSIQ_API_BASE_URL` |
| `STAGING_ADDRESSIQ_INGEST_BASE_URL` | `PROD_ADDRESSIQ_INGEST_BASE_URL` |
| `STAGING_ADDRESSIQ_CDN_BASE_URL` | `PROD_ADDRESSIQ_CDN_BASE_URL` |

These **replace** the old `ADDRESSIQ_API_URL` / `ADDRESSIQ_INGEST_URL` pair.
They produce the six constants in `BuildConfig.swift`
(`bake-build-config.sh:85-91`), which `AddressIQEnvironment` reads
(`Sources/AddressIQ/AddressIQ.swift:107-145`).

`development` is **not** baked: it points at a backend on the host machine
(`http://localhost:4000`) and stays a compile-time literal
(`AddressIQ.swift:113-114`). Never ship a `.development` build.

### The two widget pins (files, not repo variables)

`BuildConfig.swift` also carries `widgetVersion` and `widgetIntegrity`. These
are **not** repository variables: the baker reads them from two files at the
repo root — `.widget-version` and `.widget-integrity`
(`bake-build-config.sh:90-92`) — which addressiq-web's `widget-fanout.yml`
commits on every web release, from **the same build** `cdn.yml` uploads. The
hash therefore cannot drift from the bytes on the CDN.

They pin the widget the verify webview loads:
`{cdn}/v{widgetVersion}/iqcollect.js` with `integrity="{widgetIntegrity}"`
(`Sources/AddressIQ/Views/AddressIQWebFlowView.swift:184-195`). WebKit enforces
the pin, and the bundled `Resources/iqcollect.js` is inlined as an `onerror`
fallback, so a CDN outage or an integrity failure degrades to the shipped
bundle rather than a blank sheet.

If either file is empty/absent, both constants bake to `""`, the CDN path is
disabled and the SDK is bundled-only (`bake-build-config.sh:99-102`). They are
deliberately **not** covered by `--strict` — a release must not fail just
because no web widget has been fanned out yet. Never hand-write a hash.

### ⚠️ Behaviour change: a release now FAILS on missing config

The old step `sed`'d each key and, when a variable was unset, printed
`"unset; keeping checked-in default"` **and published anyway** — so a
misconfigured release shipped a pod pointing at whatever URL happened to be
committed. CI now runs the baker with `--strict`
(`release.yml:34-42`), which **hard-fails the release** if *any* of the six
variables is unset (`bake-build-config.sh:59-63`).

**Action required:** all six variables must be set as GitHub repository
variables *before the next release*, or the release job errors out.

### Local vs CI

| | Command | Unset variable |
|---|---|---|
| **Local** | `scripts/bake-build-config.sh` | falls back to the checked-in safe public defaults (`bake-build-config.sh:31-38`) |
| **CI (release)** | `scripts/bake-build-config.sh --strict` | **hard error**, release fails |

The values checked into `BuildConfig.swift` are those same public defaults, so a
plain `swift build` / `swift test` resolves real hosts with no substitution —
you only need to run the baker locally if you want to point a build elsewhere.
Trailing slashes on a variable are stripped (`bake-build-config.sh:55-56`).

### `sandbox` → `staging`

The pre-production environment is now canonically **`staging`**
(`AddressIQ.swift:73`), matching the `STAGING_*` variables and the other
AddressIQ SDKs. `.sandbox` still compiles — it is a deprecated alias
(`AddressIQ.swift:83-84`) — and the legacy `"sandbox"` raw string is still
accepted by a custom `init?(rawValue:)` (`AddressIQ.swift:93-100`), so anything
reconstructing an environment from a string keeps working.

## 4. Required secrets

| Secret | Used by | Source |
|---|---|---|
| `ADDRESSIQ_BOT_APP_ID` | `release-please.yml:33` | GitHub App on `PTLRepoHub` (App ID) |
| `ADDRESSIQ_BOT_PRIVATE_KEY` | `release-please.yml:34` | GitHub App private key (`.pem`) |
| `COCOAPODS_TRUNK_TOKEN` | `release.yml:45` | `pod trunk register <email>` token |

The GitHub App is **one** org-owned App on `PTLRepoHub`, installed on the release
repos, with only `contents: write` + `pull_requests: write`
(`RELEASE-ENGINEERING.md §4.A`). It exists so the release-please tag actually
triggers `release.yml`; do **not** substitute a `gh auth token`.

The CocoaPods token comes from `pod trunk register <email>` on a developer
machine, then stored as the repo secret (`RELEASE-ENGINEERING.md §4.E`).

## 5. Versioning rules

release-please derives the bump from commit types (`release-type: simple`,
`release-please-config.json:8`):

- `fix:` → **patch** (0.1.0 → 0.1.1)
- `feat:` → **minor** (0.1.0 → 0.2.0)
- `feat!:` / `BREAKING CHANGE:` → **minor while pre-1.0**, because
  `bump-minor-pre-major: true` (`release-please-config.json:10`) keeps breaking
  changes as minor bumps until 1.0.0.

`include-component-in-tag: false` (`config.json:3`) keeps tags plain `vX.Y.Z`,
matching the `v*.*.*` trigger in `release.yml:13`.

Because both channels resolve from the git tag:

- The podspec `source` URL (`AddressIQ.podspec:15-18`) **must** point at the real
  git remote (`github.com/PTLRepoHub/addressiq-ios.git`), and the tag `v#{version}`
  must exist, or `pod install` / SPM resolution fails to fetch.
- The podspec version is injected by CI from the tag
  (`POD_VERSION="${GITHUB_REF_NAME#v}"`, `release.yml:48`), read at
  `AddressIQ.podspec:5`. It falls back to `0.0.0` for local lint.

## 6. Local validation

Before relying on CI you can lint the pod locally (this is exactly what the
dry-run path runs, `release.yml:53`):

```sh
pod lib lint AddressIQ.podspec --allow-warnings
```

Note the podspec depends on `SwiftProtobuf ~> 1.38` (`AddressIQ.podspec:30`,
mirroring `Package.swift:22`) and ships the `iqcollect.js` resource bundle
(`AddressIQ.podspec:37`); a full (non-`--quick`) lint is what catches
compilation gaps in those. For SPM, `swift build` / `swift test` validates the
package.

## 7. One-time setup

- **CocoaPods trunk**: `pod trunk register <email>`, then store the resulting
  token as `COCOAPODS_TRUNK_TOKEN`. The pod name `AddressIQ` must be unclaimed on
  trunk. Note the podspec declares a **`Proprietary`** license
  (`AddressIQ.podspec:13`) — confirm trunk accepts it; if trunk requires an OSI
  license the pod needs a private spec repo instead (`RELEASE-ENGINEERING.md §4.E`).
- **GitHub App**: create the org App and set `ADDRESSIQ_BOT_APP_ID` /
  `ADDRESSIQ_BOT_PRIVATE_KEY` before the first release
  (`RELEASE-ENGINEERING.md §4.A`).
- **SPM**: no registration — publishing the first `vX.Y.Z` tag is all consumers
  need to resolve the package.
