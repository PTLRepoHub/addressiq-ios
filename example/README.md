# AddressIQ iOS — Sample App

A small SwiftUI app that exercises the **native iOS SDK** end to end: log in, open
the address widget, and start a verification.

The UI is the shared AddressIQ **web widget** hosted in a `WKWebView`. This app
supplies only what a webview can't — location permission and the API config — and
reads back the result. It's a **SwiftPM executable** that links the local SDK at
the repo root (`.package(path: "..")`), so your SDK changes show up here on the
next build.

> This is a separate app from the React Native example (`addressiq-react-native/
> examples/core`, product `AddressIQCore`). This one is product **`AddressIQSample`**
> with a different bundle id, so the two never collide — both can be installed on
> the same simulator.

---

## 1. Prerequisites

- **Xcode** (+ command-line tools) — iOS 15+ simulator or device. SwiftPM resolves
  the SDK and its deps; no CocoaPods needed.
- **A running AddressIQ backend** — the `geo-tagging` API on `http://localhost:4000`
  (see §4). On the simulator, `localhost` reaches your Mac, so no host swap is
  needed (unlike the Android emulator's `10.0.2.2`).

---

## 2. Run it (recommended — Xcode)

```bash
cd addressiq-ios/example
open Package.swift        # opens the package in Xcode
```

Then pick the **`AddressIQSample`** scheme + a simulator and press **Run**. Xcode
wraps the iOS executable target into an app bundle for you.

The **map** key is provisioned automatically by the platform: the SDK fetches it
from the backend via `GET /api/v1/widget/config` at widget open. Integrators do
**not** supply a Maps key — there is nothing to set in the scheme.

> **Location permission keys (required).** A bare SwiftPM executable ships without
> location usage strings, so the OS silently ignores the permission request and the
> widget's "verify where you live" step can't advance (the SDK now logs a warning
> instead of hanging). When running from Xcode, add these to the target's Info
> settings (Build Settings → *Info.plist Values*, or a generated Info.plist):
> `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`,
> and `NSLocationTemporaryUsageDescriptionDictionary` → `AddressVerification`. The
> CLI wrapper in §3 already includes them.

---

## 3. Run it from the command line (headless / CI)

`open Package.swift` needs the Xcode GUI. To build and launch without it, note
that `xcodebuild` compiles the SwiftPM **executable** but does **not** wrap it into
an `.app` (only Xcode's Run does). So build, then assemble a minimal app bundle:

```bash
cd addressiq-ios/example
SIM_ID=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)   # boot one first if none
DD=/tmp/aiq-ios-native

# 1. build the SwiftPM executable for the simulator
xcodebuild -scheme AddressIQSample \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath "$DD" build

# 2. wrap the binary + its SwiftPM resource bundles into a .app
PROD="$DD/Build/Products/Debug-iphonesimulator"
APP=/tmp/AddressIQSample.app
rm -rf "$APP"; mkdir -p "$APP"
cp "$PROD/AddressIQSample" "$APP/"
cp -R "$PROD/AddressIQ_AddressIQ.bundle" "$APP/"          # widget assets (iqcollect.js) live here
cp -R "$PROD/SwiftProtobuf_SwiftProtobuf.bundle" "$APP/" 2>/dev/null || true
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>AddressIQSample</string>
  <key>CFBundleIdentifier</key><string>com.addressiq.sample</string>
  <key>CFBundleName</key><string>AddressIQSample</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>15.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
  <key>UILaunchScreen</key><dict/>
  <key>NSLocationWhenInUseUsageDescription</key><string>Verify your address.</string>
  <key>NSLocationAlwaysAndWhenInUseUsageDescription</key><string>Verify your address in the background.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"

# 3. install + launch
xcrun simctl install "$SIM_ID" "$APP"
xcrun simctl launch "$SIM_ID" com.addressiq.sample
```

> The `NSLocation…UsageDescription` keys are required — without them the app
> crashes when the SDK requests location. Use **Xcode** (§2) for day-to-day work;
> this path is for automated/headless runs.

---

## 4. Configure — the login screen

On launch you land on **AddressIQ Sample** with:

- **API key** and **App user ID** — your test credentials (defaults:
  `aiq_test_demo_bank_seed01` / `cust_sample_001`).
- **Environment** — Development (local backend on `http://localhost:3355`),
  Sandbox, or Production (the hosted APIs). See §5 for local runs.
- **Business name** — a **fallback only**; branding (name, logo, colours, button
  style, corner radius) normally comes from the backend via `/widget/config`,
  set in the dashboard under **Settings → Branding → Widget**.

**Log in** calls `AddressIQ.shared.initialize(config:)` then `setUser(_:)`, and
opens the Hub.

---

## 5. Run against the local backend

Select the **Development** environment on the login screen. The SDK resolves it
to the compiled-in `http://localhost:3355`, so start a backend on that port:

- **The sample Node server** (`addressiq-node-backend`) on `:3355`:
  ```bash
  cd addressiq-node-backend
  node server.js               # proxies to the real API on :4000
  MOCK_UPSTREAM=1 node server.js   # …or fully offline canned data
  ```
  (The real API itself runs on `:4000` — `cd geo-tagging && docker compose up -d`.)

> On the **simulator**, `localhost` reaches your Mac, so this works as-is. On a
> **real device**, `localhost` will not reach your Mac; expose the backend on
> your Mac's LAN IP. Because the environment URL is compiled in, a device run
> against a non-localhost host is out of scope for this sample.

---

## 6. What the buttons do

- **Collect Address** — opens the widget (intro → business consent → verify where
  you live → pick a saved address or add a new one). On success the app calls
  `AddressIQ.shared.startVerification(...)` and shows the result.
- **Addresses / Developer / Settings** — inspect collected codes, call the raw
  verification APIs, and manage the session.

---

## 7. Working on the web widget

The widget UI is the shared **web** widget, shipped as
`Sources/AddressIQ/Resources/iqcollect.js` (loaded via `Bundle.module`). After
changing `addressiq-web`, rebuild and re-embed it, then rebuild the app:

```bash
cd addressiq-web && npx rollup -c                                   # → dist/iqcollect.js
cp dist/iqcollect.js ../addressiq-ios/Sources/AddressIQ/Resources/iqcollect.js
```

---

## 8. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| **Map: "Oops! Something went wrong… Google Maps"** | Invalid/missing platform Maps key. The key is provisioned by the backend via `/widget/config` — ensure the platform has a valid Maps key configured (with the **Maps JavaScript API** enabled). Integrators do not set a key on the client. |
| **Network / verification calls fail** | Backend not reachable. Confirm the API is up on `:4000`; on the simulator use `localhost` (no `10.0.2.2`). For a real device use the LAN IP + ATS exception. |
| **Widget branding doesn't reflect dashboard changes** | The widget fetches `/widget/config` **on each open** — close and reopen it. Ensure you saved under **Settings → Branding → Widget** (persists to `settings.widget`). |
| **Focusing an input zooms the page** | Fixed — widget inputs are `font-size: 16px` and the webview sets `maximum-scale=1`. If it recurs, you have a stale `iqcollect.js`; re-embed (§7) and rebuild. |
| **App crashes on launch (CLI wrap)** | Missing `NSLocation…UsageDescription` in `Info.plist`, or the resource bundles weren't copied into the `.app`. See §3. |
| **"Verify where you live" stuck on "Checking…" / never reaches the permission screen** | The app has no location usage strings, so the OS ignores the request. Add the `NSLocation…UsageDescription` keys (§2). The SDK now logs a warning instead of hanging, but the prompt won't appear without them. |
| **"Open settings" lands on general Settings, not the app's Location page** | iOS only exposes **one** App-Store-safe deep link — `UIApplication.openSettingsURLString` — and it targets the app's *settings root* (Settings → AddressIQSample), where **Location** is one tap down. There is **no public API to deep-link straight to the Location sub-page** (the private `App-Prefs:root=Privacy&path=LOCATION/…` / `prefs:root=…` schemes risk App Store rejection and break between iOS versions, so the SDK deliberately does not use them). On the **simulator with the CLI-wrapped `.app` (§3)** the deep link is flaky and may drop you at *general* Settings; on a **real device / normal Xcode install** it lands on the app's own page. This is an iOS limitation, not a bug — the widget's Location-permission screen shows a mockup + step-by-step copy to cover that last tap. |
| **`xcodebuild` produced only a binary, no `.app`** | Expected for a SwiftPM iOS executable — wrap it manually (§3), or just Run from Xcode (§2). |
