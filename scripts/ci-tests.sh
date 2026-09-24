#!/usr/bin/env bash
# Tests unitarios (TrajetTests) y de interfaz (TrajetUITests) sobre lo que ya
# compilo el paso «Compilar todo» (build/sim).
set -euo pipefail
cd "$(dirname "$0")/.."
UDID=$(bash scripts/ci-sim.sh "iPhone 16" Trajet-tests)
xcrun simctl boot "$UDID" 2>/dev/null || true
xcodebuild test-without-building \
  -project Trajet.xcodeproj -scheme Trajet \
  -destination "id=$UDID" \
  -derivedDataPath build/sim \
  -resultBundlePath build/tests.xcresult \
  > build/tests.log 2>&1 || { grep -E "error:|failed|Failing tests|\*\* TEST" build/tests.log | head -120; exit 1; }
grep -E "Executed [0-9]+ tests|\*\* TEST" build/tests.log | tail -5
