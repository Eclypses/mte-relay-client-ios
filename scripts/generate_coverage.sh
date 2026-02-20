#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/artifacts/coverage"
mkdir -p "$ARTIFACT_DIR"

IOS_TEST_DESTINATION="${IOS_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=18.5}"
RESULT_BUNDLE_PATH="$ARTIFACT_DIR/MteRelayTests.xcresult"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild is required but not found on PATH."
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "Error: xcrun is required but not found on PATH."
  exit 1
fi

SUMMARY_TXT="$ARTIFACT_DIR/coverage-summary.txt"
SUMMARY_JSON="$ARTIFACT_DIR/coverage-summary.json"

rm -rf "$RESULT_BUNDLE_PATH"

echo "Running xcodebuild tests with code coverage enabled..."
xcodebuild test \
  -scheme MteRelay \
  -destination "$IOS_TEST_DESTINATION" \
  -enableCodeCoverage YES \
  -resultBundlePath "$RESULT_BUNDLE_PATH"

xcrun xccov view --report "$RESULT_BUNDLE_PATH" > "$SUMMARY_TXT"
xcrun xccov view --report --json "$RESULT_BUNDLE_PATH" > "$SUMMARY_JSON"

echo "Coverage summary written to: $SUMMARY_TXT"
echo "Coverage summary JSON written to: $SUMMARY_JSON"
echo "Coverage result bundle written to: $RESULT_BUNDLE_PATH"
