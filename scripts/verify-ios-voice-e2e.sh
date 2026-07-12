#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  for xcode in /Applications/Xcode.app /Applications/Xcode-*.app; do
    if [[ -x "$xcode/Contents/Developer/usr/bin/xcodebuild" ]]; then
      export DEVELOPER_DIR="$xcode/Contents/Developer"
      break
    fi
  done
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT="$REPO_ROOT/scarf/scarf.xcodeproj"
SCHEME="Clawdia iOS"
LIVE_SCHEME="Clawdia Voice E2E"
RUN_LIVE=0
DEVICE_ID="${CLAWDIA_VOICE_E2E_DEVICE_ID:-}"

usage() {
  cat <<'EOF'
Usage: scripts/verify-ios-voice-e2e.sh [--live] [--device <simulator-udid>]

Without --live, runs the hermetic iOS voice/protocol regression suite.

With --live, also performs an API-backed UI round trip against the server and
OpenAI key already saved in the selected simulator. The app synthesizes the
test phrase internally and feeds its PCM into the production Realtime path, so
no person needs to speak and laptop room acoustics do not affect the result.

The live run sends one real Hermes message and uses the OpenAI Realtime API.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --live) RUN_LIVE=1; shift ;;
    --device)
      [[ $# -ge 2 ]] || { printf 'error: --device needs a simulator UDID\n' >&2; exit 2; }
      DEVICE_ID="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'error: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v xcodebuild >/dev/null 2>&1 || { printf 'error: xcodebuild not found\n' >&2; exit 1; }
command -v xcrun >/dev/null 2>&1 || { printf 'error: xcrun not found\n' >&2; exit 1; }

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(xcrun simctl list devices booted -j | /usr/bin/python3 -c '
import json, sys
devices = json.load(sys.stdin).get("devices", {})
for runtime in devices.values():
    for device in runtime:
        if device.get("state") == "Booted" and device.get("isAvailable", True):
            print(device["udid"])
            raise SystemExit
')"
fi

if [[ -z "$DEVICE_ID" ]]; then
  printf 'error: no booted iOS Simulator. Boot the Clawdia test simulator first.\n' >&2
  exit 1
fi

DESTINATION="platform=iOS Simulator,id=$DEVICE_ID"
RESULTS_DIR="$REPO_ROOT/build/voice-e2e"
mkdir -p "$RESULTS_DIR"
rm -rf "$RESULTS_DIR/hermetic.xcresult" "$RESULTS_DIR/live.xcresult"

printf '==> Hermetic Clawdia voice tests (%s)\n' "$DEVICE_ID"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -resultBundlePath "$RESULTS_DIR/hermetic.xcresult" \
  test \
  -only-testing:'Scarf iOSTests'

if [[ $RUN_LIVE -eq 0 ]]; then
  printf '\nVoice verification passed (hermetic).\n'
  printf 'Run %s --live before a TestFlight candidate for the full Realtime/Hermes round trip.\n' "$0"
  exit 0
fi

printf '==> Live Clawdia voice round trip (sends one test message)\n'
CLAWDIA_VOICE_E2E_PHRASE='Reply with exactly: CLAWDIA VOICE E2E OK.' \
xcodebuild \
  -project "$PROJECT" \
  -scheme "$LIVE_SCHEME" \
  -destination "$DESTINATION" \
  -resultBundlePath "$RESULTS_DIR/live.xcresult" \
  test \
  -only-testing:'Scarf iOSUITests/Scarf_iOSUITests/testLiveVoiceRoundTripFromSyntheticSpeech'

printf '\nVoice verification passed (hermetic + live Realtime/Hermes round trip).\n'
printf 'Artifacts: %s\n' "$RESULTS_DIR"
