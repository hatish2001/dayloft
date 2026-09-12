#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts
python3 scripts/verify-versions.py
xcodebuild -workspace Dayloft.xcworkspace -scheme Dayloft -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath artifacts/UniversalDerivedData \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  build > artifacts/universal-build.log 2>&1
python3 scripts/verify-bundle.py artifacts/UniversalDerivedData/Build/Products/Release/Dayloft.app --universal
