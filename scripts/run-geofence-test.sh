#!/usr/bin/env bash
#
# The device-side geofence trigger, run against a booted simulator.
#
# CoreLocation region monitoring only fires with location authorization, and
# authorization is granted per *app bundle id* — so the test is hosted in the
# sample app (see example/project.yml) and the grant is made out-of-band here,
# before the test runs. Running the test straight from Xcode without this grant
# makes it skip, loudly, rather than pass vacuously.
#
#   ./scripts/run-geofence-test.sh [device-name]
#
# This is the iOS counterpart of the Android GeofenceTriggerInstrumentedTest,
# which needs the equivalent out-of-band grant:
#   adb shell pm grant com.addressiq.android.test android.permission.ACCESS_BACKGROUND_LOCATION
#
set -euo pipefail

cd "$(dirname "$0")/../example"

DEVICE="${1:-iPhone 17}"
BUNDLE_ID=com.addressiqpro.sample
# Lagos, matching the fixtures the backend tests use.
LAT=6.5244
LON=3.3792

command -v xcodegen >/dev/null || { echo "need: brew install xcodegen"; exit 1; }

echo "==> generating the sample project (includes the hosted test target)"
xcodegen generate >/dev/null

echo "==> booting ${DEVICE}"
xcrun simctl boot "${DEVICE}" 2>/dev/null || true
xcrun simctl bootstatus "${DEVICE}" -b >/dev/null

# Placing the device BEFORE the test matters: startMonitoring follows
# startMonitoring(for:) with requestState(for:), so an already-inside device
# resolves to .inside immediately instead of waiting for a real crossing.
echo "==> placing the device inside the geofence (${LAT},${LON})"
xcrun simctl location "${DEVICE}" set "${LAT},${LON}"

echo "==> granting location-always to ${BUNDLE_ID}"
xcrun simctl privacy "${DEVICE}" grant location-always "${BUNDLE_ID}" 2>/dev/null \
  || echo "    (grant refused — install the app once, then re-run)"

echo "==> running GeofenceTriggerTests"
xcodebuild \
  -project AddressIQSample.xcodeproj \
  -scheme AddressIQSample \
  -destination "platform=iOS Simulator,name=${DEVICE}" \
  -only-testing:AddressIQSampleTests/GeofenceTriggerTests \
  test
