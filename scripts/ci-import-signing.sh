#!/bin/bash
# Used only on the isolated GitHub Actions release runner. Never enable shell tracing here.
set -euo pipefail
: "${RUNNER_TEMP:?This script is for GitHub Actions}"
: "${DAYLOFT_CERTIFICATE_BASE64:?Missing Developer ID certificate}"
: "${DAYLOFT_CERTIFICATE_PASSWORD:?Missing certificate password}"
: "${DAYLOFT_TEAM_ID:?Missing signing team}"
: "${DAYLOFT_NOTARY_APPLE_ID:?Missing notarization account}"
: "${DAYLOFT_NOTARY_PASSWORD:?Missing app-specific notarization password}"
keychain_path="$RUNNER_TEMP/dayloft-signing.keychain-db"
keychain_password="$(openssl rand -hex 32)"
certificate_path="$RUNNER_TEMP/dayloft-signing.p12"
umask 077
trap 'rm -f "$certificate_path"' EXIT
printf '%s' "$DAYLOFT_CERTIFICATE_BASE64" | base64 --decode > "$certificate_path"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$certificate_path" -P "$DAYLOFT_CERTIFICATE_PASSWORD" -k "$keychain_path" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain_path" > /dev/null
security list-keychains -d user -s "$keychain_path" "$HOME/Library/Keychains/login.keychain-db"
xcrun notarytool store-credentials dayloft-ci --apple-id "$DAYLOFT_NOTARY_APPLE_ID" \
  --team-id "$DAYLOFT_TEAM_ID" --password "$DAYLOFT_NOTARY_PASSWORD"
