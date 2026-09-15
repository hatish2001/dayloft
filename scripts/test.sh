#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts
test_host="$PWD/artifacts/DerivedData/Build/Products/Debug/Dayloft.app/Contents/MacOS/Dayloft"
cleanup_test_host() {
  /usr/bin/pkill -f "^${test_host}$" 2>/dev/null || true
}
trap cleanup_test_host EXIT
xcodebuild -workspace Dayloft.xcworkspace -scheme Dayloft -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath artifacts/DerivedData \
  CODE_SIGNING_ALLOWED=NO test > artifacts/tests.log 2>&1
python3 scripts/verify-bundle.py artifacts/DerivedData/Build/Products/Debug/Dayloft.app
shasum -a 256 -c docs/validation/original-tests.sha256
printf '%s\n' 'Tests passed. Full output: artifacts/tests.log'
