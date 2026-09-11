#!/bin/bash
# Exercise the pinned updater tools with a disposable key, never a release key.
set -euo pipefail
cd "$(dirname "$0")/.."
stage="$(mktemp -d "${TMPDIR:-/tmp}/dayloft-update-test.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
umask 077
cat > "$stage/key.swift" <<'SWIFT'
import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
print(key.publicKey.rawRepresentation.base64EncodedString())
SWIFT
export DAYLOFT_UPDATE_PRIVATE_KEY_FILE="$stage/disposable.key"
export DAYLOFT_UPDATE_PUBLIC_KEY="$(swift "$stage/key.swift" "$DAYLOFT_UPDATE_PRIVATE_KEY_FILE")"
swift scripts/verify-update-key.swift
printf '%s\n' 'Disposable update payload' > "$stage/update.zip"
signer=SelfControl/Pods/Sparkle/bin/sign_update
signature="$("$signer" --ed-key-file "$DAYLOFT_UPDATE_PRIVATE_KEY_FILE" -p "$stage/update.zip")"
"$signer" --verify --ed-key-file "$DAYLOFT_UPDATE_PRIVATE_KEY_FILE" "$stage/update.zip" "$signature"
printf '%s\n' 'tampered' >> "$stage/update.zip"
if "$signer" --verify --ed-key-file "$DAYLOFT_UPDATE_PRIVATE_KEY_FILE" "$stage/update.zip" "$signature" > "$stage/rejection.log" 2>&1; then
  printf '%s\n' 'ERROR: Tampered update was accepted.' >&2
  exit 1
fi
DAYLOFT_UPDATE_PUBLIC_KEY=invalid
export DAYLOFT_UPDATE_PUBLIC_KEY
if swift scripts/verify-update-key.swift > "$stage/key-rejection.log" 2>&1; then
  printf '%s\n' 'ERROR: Incorrect update key pair was accepted.' >&2
  exit 1
fi
printf '%s\n' 'Update signatures verify; tampered payloads and mismatched keys are rejected.'
