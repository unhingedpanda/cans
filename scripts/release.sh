#!/bin/bash
# Build a universal, ad-hoc signed Cans.app and leave release/Cans.zip (+ .sha256).
# Adapted from Roadie's scripts/notarize.sh; once a Developer ID exists, add the
# signing + notarytool + stapler steps from there.
# Usage: scripts/release.sh [marketing-version]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DERIVED="${CANS_DERIVED_DATA:-build}"
APP="$DERIVED/Build/Products/Release/Cans.app"

# Command Line Tools ships no xcodebuild; fall back to Xcode.
if ! xcodebuild -version >/dev/null 2>&1 && [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

command -v xcodegen >/dev/null && xcodegen -q
echo "==> building Release, universal, ad-hoc signed"
xcodebuild -project Cans.xcodeproj -scheme Cans -configuration Release \
  -derivedDataPath "$DERIVED" -arch arm64 -arch x86_64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  ${1:+MARKETING_VERSION="$1"} \
  ${CURRENT_PROJECT_VERSION:+CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION"} \
  build | grep -E "error:|BUILD" || true
codesign --verify --deep --strict "$APP"

mkdir -p release
rm -f release/Cans.zip
# ditto keeps the _CodeSignature layout Gatekeeper validates; plain zip does not.
ditto -c -k --sequesterRsrc --keepParent "$APP" release/Cans.zip
(cd release && shasum -a 256 Cans.zip > Cans.zip.sha256)
echo "==> release/Cans.zip ($(du -h release/Cans.zip | cut -f1)), app $(du -sh "$APP" | cut -f1)"
