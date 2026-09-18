#!/usr/bin/env bash
# Full verification loop for the Barry iPhone app: clean build, full test
# suite (unit + live-API integration + UI) against a real booted simulator,
# talking to the real locally-running Barry API. No mocks.
set -euo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${BARRY_IOS_SIM:-iPhone 16 Pro}"
SCHEME="Barry"

export PATH="/opt/homebrew/bin:$PATH"

echo "==> Checking Barry API is reachable (127.0.0.1:9429)..."
if ! curl -sf -m 3 http://127.0.0.1:9429/health >/dev/null; then
  echo "!! barry.works proxy not reachable on :9429 — integration/UI tests will skip, not fail."
  echo "   Start it with: launchctl kickstart -k gui/\$(id -u)/com.barry.bag.barry.works.web"
fi

echo "==> Regenerating Xcode project from project.yml..."
xcodegen generate

echo "==> Running full test suite on simulator: ${SIM_NAME}..."
set +e
# -derivedDataPath pins the output where `barry ios build` also writes. Without
# it xcodebuild uses Xcode's shared DerivedData, and `simctl install` from the
# other path silently installs a STALE app — which cost three rounds of
# screenshots in a sibling bag chasing a feature that was never in the binary
# under test.
xcodebuild -project "${SCHEME}.xcodeproj" -scheme "${SCHEME}" \
  -destination "platform=iOS Simulator,name=${SIM_NAME}" \
  -derivedDataPath .build-barry-ios \
  test 2>&1 | tee /tmp/barry-iphone-test.log \
  | grep -E "Test Case|Test Suite '(All tests|${SCHEME}Tests\.xctest|${SCHEME}UITests\.xctest)'|error:|\*\* TEST"
STATUS=${PIPESTATUS[0]}
set -e

echo ""
if [ "$STATUS" -eq 0 ]; then
  # A skip reads identically to a pass in the summary line, so say the count out
  # loud rather than letting a suite that ran nothing look green.
  echo "✅ All tests passed. Skipped: $(grep -c 'was skipped' /tmp/barry-iphone-test.log)"
else
  echo "❌ Tests failed. Full log: /tmp/barry-iphone-test.log"
  echo "   To inspect a UI test failure visually, see QA.md § Debugging a UI test failure."
fi
exit "$STATUS"
