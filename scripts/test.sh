#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts
xcodebuild -workspace Dayloft.xcworkspace -scheme Dayloft -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath artifacts/DerivedData \
  CODE_SIGNING_ALLOWED=NO test > artifacts/tests.log 2>&1
python3 scripts/verify-bundle.py artifacts/DerivedData/Build/Products/Debug/Dayloft.app
shasum -a 256 -c docs/validation/original-tests.sha256
printf '%s\n' 'Tests passed. Full output: artifacts/tests.log'
