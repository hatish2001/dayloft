#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DAYLOFT_TEAM_ID:?Set DAYLOFT_TEAM_ID to your Apple developer team}"
: "${DAYLOFT_SIGN_IDENTITY:?Set DAYLOFT_SIGN_IDENTITY to your Developer ID Application identity}"
: "${DAYLOFT_UPDATE_PUBLIC_KEY:?Set the Sparkle Ed25519 public key}"
: "${DAYLOFT_UPDATE_PRIVATE_KEY_FILE:?Set the path to the protected Sparkle private key file}"
swift scripts/verify-update-key.swift
: "${DAYLOFT_NOTARY_PROFILE:?Set DAYLOFT_NOTARY_PROFILE to a stored notarytool keychain profile}"
case "$DAYLOFT_SIGN_IDENTITY" in
  'Developer ID Application:'*) ;;
  *) printf '%s\n' 'Public releases require Developer ID Application signing.' >&2; exit 1 ;;
esac
if [[ -n "$(git status --porcelain)" ]]; then
  printf '%s\n' 'Commit the exact source before producing a public release.' >&2; exit 1
fi
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' SelfControl/Info.plist)"
python3 scripts/verify-versions.py
mkdir -p artifacts dist
xcodebuild -workspace Dayloft.xcworkspace -scheme Dayloft -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath artifacts/ReleaseDerivedData \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  "DEVELOPMENT_TEAM=$DAYLOFT_TEAM_ID" "CODE_SIGN_IDENTITY=$DAYLOFT_SIGN_IDENTITY" \
  "DAYLOFT_UPDATE_PUBLIC_KEY=$DAYLOFT_UPDATE_PUBLIC_KEY" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS='--timestamp --options runtime' \
  build > artifacts/release-build.log 2>&1
stage="$(mktemp -d "${TMPDIR:-/tmp}/dayloft-release.XXXXXX")"
printf '%s\n' "Packaging workspace: $stage"
ditto artifacts/ReleaseDerivedData/Build/Products/Release/Dayloft.app "$stage/Dayloft.app"
python3 scripts/verify-bundle.py "$stage/Dayloft.app"
codesign --verify --deep --strict "$stage/Dayloft.app"
while IFS= read -r -d '' binary; do
  if file "$binary" | /usr/bin/grep -q 'Mach-O'; then
    lipo "$binary" -verify_arch arm64 x86_64
  fi
done < <(find "$stage/Dayloft.app" -type f -print0)
# Notarize the application and staple its ticket before placing it in the DMG.
ditto -c -k --keepParent "$stage/Dayloft.app" "$stage/Dayloft.zip"
xcrun notarytool submit "$stage/Dayloft.zip" --keychain-profile "$DAYLOFT_NOTARY_PROFILE" --wait
xcrun stapler staple "$stage/Dayloft.app"
xcrun stapler validate "$stage/Dayloft.app"
spctl --assess --type execute --verbose=2 "$stage/Dayloft.app"
mkdir "$stage/dmg"
ditto "$stage/Dayloft.app" "$stage/dmg/Dayloft.app"
ln -s /Applications "$stage/dmg/Applications"
cp LICENSE NOTICE.md "$stage/dmg/"
hdiutil create -volname Dayloft -srcfolder "$stage/dmg" -format UDZO "dist/Dayloft-$version.dmg"
codesign --sign "$DAYLOFT_SIGN_IDENTITY" --timestamp "dist/Dayloft-$version.dmg"
xcrun notarytool submit "dist/Dayloft-$version.dmg" --keychain-profile "$DAYLOFT_NOTARY_PROFILE" --wait
xcrun stapler staple "dist/Dayloft-$version.dmg"
xcrun stapler validate "dist/Dayloft-$version.dmg"
# Generate a signed full-update feed from the notarized installer only.
mkdir "$stage/feed"
cp "dist/Dayloft-$version.dmg" "$stage/feed/"
SelfControl/Pods/Sparkle/bin/generate_appcast \
  --ed-key-file "$DAYLOFT_UPDATE_PRIVATE_KEY_FILE" --maximum-deltas 0 \
  --download-url-prefix "https://github.com/hatish2001/dayloft/releases/download/v$version/" \
  --link https://github.com/hatish2001/dayloft \
  -o "$stage/feed/appcast.xml" "$stage/feed"
cp "$stage/feed/appcast.xml" dist/appcast.xml
python3 scripts/verify-appcast.py dist/appcast.xml "$stage/Dayloft.app" "dist/Dayloft-$version.dmg"
# Ship the corresponding source, including the resolved dependency source.
mkdir "$stage/source"
git archive HEAD | tar -xf - -C "$stage/source"
ditto SelfControl/Pods "$stage/source/SelfControl/Pods"
# The Sparkle pod ships a binary, so also include its exact upstream source.
curl --fail --location --proto '=https' --tlsv1.2 \
  https://github.com/sparkle-project/Sparkle/archive/refs/tags/2.9.6.tar.gz \
  -o "$stage/Sparkle-2.9.6.tar.gz"
mkdir "$stage/source/SparkleSource"
tar -xzf "$stage/Sparkle-2.9.6.tar.gz" -C "$stage/source/SparkleSource" --strip-components=1
tar --exclude='.DS_Store' --exclude='xcuserdata' --exclude='*.xcuserstate' \
  -czf "dist/Dayloft-$version-source.tar.gz" -C "$stage/source" .
(cd dist && shasum -a 256 "Dayloft-$version.dmg" "Dayloft-$version-source.tar.gz" appcast.xml > SHA256SUMS)
printf '%s\n' "Release packages created in dist/. Publish the DMG, source archive, appcast.xml, and SHA256SUMS together."
