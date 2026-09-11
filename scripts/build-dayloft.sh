#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
mkdir -p artifacts build
# Supply your Apple Development team for a functional local blocking build.
# With no team, this produces an unsigned UI/test build; privileged blocking fails closed.
options=(CODE_SIGNING_ALLOWED=NO)
if [[ -n "${DAYLOFT_TEAM_ID:-}" ]]; then
  options=("DEVELOPMENT_TEAM=$DAYLOFT_TEAM_ID" "CODE_SIGN_IDENTITY=${DAYLOFT_SIGN_IDENTITY:-Apple Development}")
fi
xcodebuild -workspace Dayloft.xcworkspace -scheme Dayloft \
  -configuration "${DAYLOFT_CONFIGURATION:-Debug}" -destination 'platform=macOS' \
  -derivedDataPath artifacts/DerivedData "${options[@]}" "DAYLOFT_UPDATE_PUBLIC_KEY=${DAYLOFT_UPDATE_PUBLIC_KEY:-}" build > artifacts/build.log 2>&1
# Never merge a new package into an old bundle: stale frameworks would survive.
staging="$(mktemp -d "$project_root/build/.dayloft.XXXXXX")"
# Keep a failed staging directory for diagnosis; successful staging is empty after the move.
ditto "artifacts/DerivedData/Build/Products/${DAYLOFT_CONFIGURATION:-Debug}/Dayloft.app" "$staging/Dayloft.app"
if [[ -n "${DAYLOFT_TEAM_ID:-}" ]]; then codesign --verify --deep --strict "$staging/Dayloft.app"; fi
if [[ -d build/Dayloft.app ]]; then
  previous="$(mktemp -d "$project_root/build/.previous.XXXXXX")"
  mv build/Dayloft.app "$previous/Dayloft.app"
fi
mv "$staging/Dayloft.app" build/Dayloft.app
rmdir "$staging"
python3 scripts/verify-bundle.py build/Dayloft.app
printf '%s\n' "Built: $project_root/build/Dayloft.app"
