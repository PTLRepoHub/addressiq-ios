#!/usr/bin/env bash
# Regenerates Sources/AddressIQ/Generated/BuildConfig.swift from the environment.
#
# Reads six GitHub repository variables — three per shippable environment:
#
#   STAGING_ADDRESSIQ_API_BASE_URL          PROD_ADDRESSIQ_API_BASE_URL
#   STAGING_ADDRESSIQ_INGEST_BASE_URL   PROD_ADDRESSIQ_INGEST_BASE_URL
#   STAGING_ADDRESSIQ_CDN_BASE_URL          PROD_ADDRESSIQ_CDN_BASE_URL
#
# `development` is NOT baked: it points at the host machine's backend, so it is
# a local concern and stays a literal in AddressIQEnvironment.
#
# It also bakes TWO widget pins, which do NOT come from the environment — they
# come from files at the repo root, written by the web repo's widget-fanout
# workflow on every web release:
#
#   .widget-version    e.g. "v0.4.0"      → BuildConfig.widgetVersion   ("0.4.0")
#   .widget-integrity  e.g. "sha384-abc…" → BuildConfig.widgetIntegrity
#
# Version form: the file may carry a leading "v"; we strip it and store the BARE
# version ("0.4.0"). The CDN publishes immutable paths under /v{x.y.z}/, so the
# consumer re-adds the "v" when building the URL:
#   {cdnBaseUrl}/v{widgetVersion}/iqcollect.js
#
# A missing or empty file bakes an empty string, which disables the CDN path
# entirely (the SDK then inlines the bundled widget). That is the pre-release
# state and is intentional — never invent a version or a hash here, an integrity
# pin that does not match the published asset would break every verify flow.
# These are NOT covered by --strict for the same reason.
#
# Usage:
#   scripts/bake-build-config.sh            # unset vars keep their defaults (local)
#   scripts/bake-build-config.sh --strict   # unset vars are a hard error (release)
#
# --strict is what release.yml uses. The old workflow sed'd each key and printed
# "unset; keeping checked-in default" — which meant a misconfigured release
# published a pod pointing at whatever was committed, silently. A release that
# cannot see its config should fail, not guess.

set -euo pipefail

cd "$(dirname "$0")/.."
OUT="Sources/AddressIQ/Generated/BuildConfig.swift"

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

# name|default — defaults mirror the checked-in file and are the public hosts.
DEFAULTS="
STAGING_ADDRESSIQ_API_BASE_URL|https://api-staging.addressiqpro.com
STAGING_ADDRESSIQ_INGEST_BASE_URL|https://ingest-api-staging.addressiqpro.com
STAGING_ADDRESSIQ_CDN_BASE_URL|https://cdn-staging.addressiqpro.com
PROD_ADDRESSIQ_API_BASE_URL|https://api.addressiqpro.com
PROD_ADDRESSIQ_INGEST_BASE_URL|https://ingest-api.addressiqpro.com
PROD_ADDRESSIQ_CDN_BASE_URL|https://cdn.addressiqpro.com
"

missing=""

# NB: assign into V_<NAME> directly rather than via `$(resolve …)`. A command
# substitution runs in a subshell, so a `missing` recorded inside one is thrown
# away — which silently turned --strict into a no-op that baked empty strings.
while IFS='|' read -r name default; do
  [ -n "$name" ] || continue
  val="${!name:-}"
  if [ -z "$val" ]; then
    if [ "$STRICT" = "1" ]; then
      missing="$missing $name"
      continue
    fi
    val="$default"
  fi
  # A base URL with a trailing slash concatenates into `//path`; normalise.
  eval "V_$name=\"\${val%/}\""
done <<< "$DEFAULTS"

if [ -n "$missing" ]; then
  echo "::error::--strict: required build variables are unset:$missing" >&2
  echo "A release must not fall back to checked-in defaults. Set them as GitHub repository variables." >&2
  exit 1
fi

# Widget pins — read from files, not the environment. Absent/empty ⇒ "".
read_pin() {
  [ -f "$1" ] || { printf ''; return; }
  # Trim surrounding whitespace/newlines; take the first line only.
  head -n1 "$1" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

WIDGET_VERSION="$(read_pin .widget-version)"
WIDGET_VERSION="${WIDGET_VERSION#v}"   # store bare "0.4.0"; the CDN path re-adds "v"
WIDGET_INTEGRITY="$(read_pin .widget-integrity)"

# Both pins are required together: a version with no hash would load an
# unverified script, a hash with no version has nothing to pin. Either one
# missing disables the CDN path.
if [ -z "$WIDGET_VERSION" ] || [ -z "$WIDGET_INTEGRITY" ]; then
  if [ -n "$WIDGET_VERSION$WIDGET_INTEGRITY" ]; then
    echo "[bake] warning: only one of .widget-version/.widget-integrity is set; disabling the CDN widget path" >&2
  fi
  WIDGET_VERSION=""
  WIDGET_INTEGRITY=""
fi

cat > "$OUT" <<EOF
// Generated build-time configuration — DO NOT EDIT BY HAND.
//
// Rewritten wholesale by \`scripts/bake-build-config.sh\` at publish time from
// the GitHub repository variables (see .github/workflows/release.yml):
//
//   STAGING_ADDRESSIQ_API_BASE_URL          PROD_ADDRESSIQ_API_BASE_URL
//   STAGING_ADDRESSIQ_INGEST_BASE_URL   PROD_ADDRESSIQ_INGEST_BASE_URL
//   STAGING_ADDRESSIQ_CDN_BASE_URL          PROD_ADDRESSIQ_CDN_BASE_URL
//
// The checked-in values below are the safe public defaults, so a local
// \`swift build\` and the test suite resolve real hosts with no substitution.
// On a real release the baker runs with --strict and REQUIRES every variable
// above — a published pod must never silently carry a developer's default.
//
// \`development\` is deliberately NOT baked from CI: it points at the host
// machine's backend, so it is a local-only concern and stays a compile-time
// literal in AddressIQEnvironment. Never ship a build configured for
// \`.development\`.
//
// The two widget pins come from FILES at the repo root — \`.widget-version\` and
// \`.widget-integrity\` — which the web repo's widget-fanout workflow writes on
// every web release. \`widgetVersion\` is stored BARE ("0.4.0", any leading "v"
// stripped); the CDN serves immutable paths under /v{x.y.z}/, so the URL is
// built as "\(cdn)/v\(widgetVersion)/iqcollect.js". Empty strings mean "no pin
// published yet" and disable the CDN path — the SDK then inlines the bundled
// widget. Never hand-write a hash here.
enum BuildConfig {
    static let stagingApiURL = "$V_STAGING_ADDRESSIQ_API_BASE_URL"
    static let stagingIngestURL = "$V_STAGING_ADDRESSIQ_INGEST_BASE_URL"
    static let stagingCdnURL = "$V_STAGING_ADDRESSIQ_CDN_BASE_URL"

    static let prodApiURL = "$V_PROD_ADDRESSIQ_API_BASE_URL"
    static let prodIngestURL = "$V_PROD_ADDRESSIQ_INGEST_BASE_URL"
    static let prodCdnURL = "$V_PROD_ADDRESSIQ_CDN_BASE_URL"

    /// Bare semver of the published web widget, e.g. "0.4.0". Empty ⇒ no CDN pin.
    static let widgetVersion = "$WIDGET_VERSION"
    /// Subresource-integrity hash of that widget, e.g. "sha384-…". Empty ⇒ no CDN pin.
    static let widgetIntegrity = "$WIDGET_INTEGRITY"
}
EOF

echo "[bake] wrote $OUT"
grep -E 'static let' "$OUT" | sed 's/^/  /'
