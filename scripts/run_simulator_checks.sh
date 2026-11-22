#!/usr/bin/env bash
# Runs the repeatable simulator checks for issue #48 and then scans the artifacts for secrets.
#
# Modes:
#   fixture (default): no network, canned JSON API and generated audio. Needs nothing local.
#   staging: used only when .local/test-server.txt exists and holds SERVER_URL, USERNAME and PASSWORD.
#            The real staging scenario then runs read-only. Credentials are exported in-process, never echoed.
#
# Environment overrides:
#   DOWNTIFY_SIM_DESTINATION  xcodebuild destination (default: the first booted simulator)
#   DOWNTIFY_SIM_ARTIFACTS    directory for result bundles and logs (default: a new temp directory)
#   DOWNTIFY_SIM_MODE         set to "fixture" to ignore .local/test-server.txt even when it exists
#
# Never run with `set -x`: it would print the credentials exported below.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/.local/test-server.txt"
if [[ -n "${DOWNTIFY_SIM_DESTINATION:-}" ]]; then
  DESTINATION="$DOWNTIFY_SIM_DESTINATION"
else
  booted="$(xcrun simctl list devices booted -j | python3 -c 'import json,sys
d=json.load(sys.stdin)["devices"]
ids=[x["udid"] for runtimes in d.values() for x in runtimes if x.get("state")=="Booted"]
print(ids[0] if ids else "")')"
  if [[ -z "$booted" ]]; then
    echo "No booted simulator. Boot one in Simulator.app or set DOWNTIFY_SIM_DESTINATION." >&2
    exit 2
  fi
  DESTINATION="platform=iOS Simulator,id=$booted"
fi
ARTIFACTS="${DOWNTIFY_SIM_ARTIFACTS:-$(mktemp -d "${TMPDIR:-/tmp}/downtify-simulator-checks-XXXXXX")}"
mkdir -p "$ARTIFACTS"

# Load staging values without printing them. Prints only shell assignments to eval.
MODE="fixture"
if [[ -f "$CONFIG" && "${DOWNTIFY_SIM_MODE:-}" != "fixture" ]]; then
  assignments="$(python3 - "$CONFIG" <<'PY'
import shlex, sys
values = {}
for raw in open(sys.argv[1], encoding="utf-8"):
    line = raw.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    values[key.strip()] = value.strip()
needed = ["SERVER_URL", "USERNAME", "PASSWORD"]
if all(values.get(k) for k in needed):
    print("MODE=staging")
    print("export TEST_RUNNER_DOWNTIFY_TEST_SERVER=" + shlex.quote(values["SERVER_URL"]))
    print("export TEST_RUNNER_DOWNTIFY_TEST_USER=" + shlex.quote(values["USERNAME"]))
    print("export TEST_RUNNER_DOWNTIFY_TEST_PASSWORD=" + shlex.quote(values["PASSWORD"]))
PY
)"
  eval "$assignments"
fi
echo "Simulator checks: mode=$MODE artifacts=$ARTIFACTS"

run() {
  local name="$1"; shift
  echo "--- $name"
  xcodebuild test -project "$ROOT/Downtify.xcodeproj" -scheme Downtify -destination "$DESTINATION" \
    -resultBundlePath "$ARTIFACTS/$name.xcresult" "$@" > "$ARTIFACTS/$name.log" 2>&1 \
    || { echo "FAILED: $name (see $ARTIFACTS/$name.log)"; return 1; }
  grep -E "Executed [0-9]+ tests, with" "$ARTIFACTS/$name.log" | tail -1 || true
}

status=0
# Catalog and player logic (unit level, fixture data).
run catalog-player-unit -only-testing:DowntifyTests/CatalogPlaybackIntegrationTests \
  -only-testing:DowntifyTests/CatalogPlaybackStreamTests -only-testing:DowntifyTests/DebugHarnessTests \
  -only-testing:DowntifyTests/LyricsPresentationTests -only-testing:DowntifyTests/SimilarFeedTests \
  -only-testing:DowntifyTests/SimilarContinuationModelTests || status=1
# End-to-end fixture scenarios: playback success and controlled stream failure (network/player paths).
run fixture-ui -only-testing:DowntifyUITests/DebugHarnessUITests/testFixtureLibraryPlaybackEndToEnd \
  -only-testing:DowntifyUITests/DebugHarnessUITests/testInjectedStreamFaultReportsFailure \
  -only-testing:DowntifyUITests/DebugHarnessUITests/testCurrentSongHighlightFollowsQueue \
  -only-testing:DowntifyUITests/DebugHarnessUITests/testNowPlayingActionsAreDiscoverable \
  -only-testing:DowntifyUITests/DebugHarnessUITests/testPlayNextAndAddToQueueFromLibrarySongMenu \
  -only-testing:DowntifyUITests/DebugHarnessUITests/testQueueHandleDragReordersUpcomingSongs || status=1
# Issue #71 (lyrics seek, display modes, timing reset) and #72 (Similar load-more), fixture mode.
run lyrics-similar-ui -only-testing:DowntifyUITests/LyricsUITests -only-testing:DowntifyUITests/SimilarUITests || status=1
if [[ "$MODE" == "staging" ]]; then
  run staging-ui -only-testing:DowntifyUITests/DebugHarnessUITests/testRealStagingLibraryLoadsReadOnly || status=1
fi

echo "--- secret scan"
"$ROOT/scripts/check_no_secrets_in_artifacts.sh" "$ARTIFACTS" || status=1

if [[ "$status" -eq 0 ]]; then echo "All simulator checks passed ($MODE mode)."; else echo "Simulator checks FAILED ($MODE mode)."; fi
exit "$status"
