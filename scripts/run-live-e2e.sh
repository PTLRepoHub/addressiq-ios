#!/usr/bin/env bash
#
# The whole chain against a running local stack: create a verification the way
# a partner would, collect it on a real simulator, and upload through the real
# ingest.
#
# Needs the dev stack up (docker compose up -d in the geo-tagging repo):
#   api 4000, ingest 4001.
#
#   ./scripts/run-live-e2e.sh [device-name]
#
set -euo pipefail
cd "$(dirname "$0")/../example"

DEVICE="${1:-iPhone 17}"
BUNDLE_ID=com.addressiqpro.sample
API=http://localhost:4000
KEY=aiq_test_demo_bank_seed01
LAT=6.5244
LON=3.3792

curl -fsS -m 10 "$API/health" >/dev/null || { echo "stack not up at $API"; exit 1; }

echo "==> collecting an address"
LOC=$(curl -fsS -X POST "$API/api/v1/locations/collect" \
  -H "x-api-key: $KEY" -H 'content-type: application/json' \
  -H "Idempotency-Key: iqidem_$(uuidgen)" \
  -d "{\"appUserId\":\"cust_live_e2e\",\"firstName\":\"Live\",\"lastName\":\"Probe\",\"phone\":\"+2348030000009\",\"lat\":$LAT,\"lon\":$LON,\"geofenceRadiusM\":150,\"locationType\":\"HOME\",\"formattedAddress\":\"Live e2e probe\"}" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["locationCode"])')

echo "==> starting the digital verification"
VER=$(curl -fsS -X POST "$API/api/v1/verifications/start" \
  -H "x-api-key: $KEY" -H 'content-type: application/json' \
  -d "{\"locationCode\":\"$LOC\"}" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["verificationCode"])')
echo "    location=$LOC verification=$VER"

xcodegen generate >/dev/null

# Erase first. The simulator's CoreLocation daemon accumulates state across
# repeated automated runs and stops delivering region callbacks entirely —
# reinstalling the app is not enough, only a full erase clears it. Without this
# the test passes once on a fresh simulator and fails on every run after.
echo "==> erasing and booting ${DEVICE}"
xcrun simctl shutdown "$DEVICE" 2>/dev/null || true
xcrun simctl erase "$DEVICE"
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b >/dev/null

# Build and install BEFORE granting: TCC grants attach to an installed bundle,
# and a grant made against a missing app is silently discarded (the test then
# skips for want of authorization).
# Install by running the suite once. `simctl install` of a build-for-testing
# product is not equivalent — going through xcodebuild is what leaves the
# simulator in a state where CoreLocation actually delivers region callbacks.
# This first pass is expected to SKIP (no authorization yet); it exists to
# install the app so the TCC grant below has a bundle to attach to.
echo "==> installing (first pass skips, by design)"
xcodebuild -project AddressIQSample.xcodeproj -scheme AddressIQSample \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -only-testing:AddressIQSampleTests/LiveEndToEndTests test >/dev/null 2>&1 || true

echo "==> granting location-always and placing the device"
xcrun simctl privacy "$DEVICE" grant location-always "$BUNDLE_ID"
xcrun simctl location "$DEVICE" set "$LAT,$LON"

echo "==> collecting on the device and uploading"
# TEST_RUNNER_ prefix: xcodebuild forwards only these into the test process
# running on the simulator, stripping the prefix. A plain env var set here
# would stay on the host and never reach the test.
TEST_RUNNER_AIQ_E2E_LOCATION_CODE="$LOC" TEST_RUNNER_AIQ_E2E_VERIFICATION_CODE="$VER" \
xcodebuild -project AddressIQSample.xcodeproj -scheme AddressIQSample \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -only-testing:AddressIQSampleTests/LiveEndToEndTests test

echo
echo "==> what the server stored"
echo "    curl -s -H 'x-api-key: $KEY' $API/api/v1/verifications/$VER/summary"
