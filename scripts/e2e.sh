#!/bin/bash
# End-to-end suite against real headphones. Needs a paired, powered-on, connected WH-1000XM4
# and nothing else holding Sony's control channel (quit Cans; close Sound Connect on the phone).
#   scripts/e2e.sh            hardware protocol suite + UI suite
#   CANS_E2E_MULTIPOINT=1 …   also toggle multipoint (headphones may restart)
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null && xcodegen -q
pkill -x Cans 2>/dev/null || true
sleep 2
xcodebuild -project Cans.xcodeproj -scheme "Cans E2E" -derivedDataPath build \
  -resultBundlePath "build/e2e-$(date +%Y%m%d-%H%M%S).xcresult" test 2>&1 \
  | grep -E "Test Case .*(passed|failed|skipped)|error:|Executed|\*\* TEST" | grep -v "^$"
