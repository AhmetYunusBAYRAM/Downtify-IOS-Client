#!/usr/bin/env bash
# Builds the app for the iOS Simulator and fails if debug-harness markers are present in the binary.
# Usage: scripts/verify_release_omits_debug_hooks.sh [Release|Debug]
#   Release (default): expected to contain no markers; exit 0 when clean, 1 when markers found.
#   Debug: negative control; the harness must be present, so exit 1 is expected to be reported as "markers found".
# Never prints marker-matching source lines or any configuration values.
set -euo pipefail

CONFIGURATION="${1:-Release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="${DERIVED_DATA_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/downtify-omit-XXXXXX")}"
mkdir -p "$DERIVED"
MARKERS=("DowntifyHarness" "debug.state" "DebugFixtureTransport" "DOWNTIFY_TEST_")

echo "Building Downtify ($CONFIGURATION, iphonesimulator, signing off)..."
xcodebuild build -project "$ROOT/Downtify.xcodeproj" -scheme Downtify -configuration "$CONFIGURATION" \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" > "$DERIVED/build.log" 2>&1 \
  || { echo "BUILD FAILED (see $DERIVED/build.log)"; exit 2; }

APP="$DERIVED/Build/Products/$CONFIGURATION-iphonesimulator/Downtify.app"
BINARY="$APP/Downtify"
[[ -f "$BINARY" ]] || { echo "Binary not found at $BINARY"; exit 2; }

found=0
# Debug builds may place code in Downtify.debug.dylib (previews), so check every executable and dylib in the bundle.
MACHO_FILES=$(find "$APP" -type f \( -name 'Downtify*' -o -name '*.dylib' \) | while read -r f; do file -b "$f" | grep -q 'Mach-O' && echo "$f"; done)
for marker in "${MARKERS[@]}"; do
  total=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    c1=$(strings -a "$f" | grep -c -F -- "$marker") || c1=0
    c2=$(nm -gU "$f" 2>/dev/null | grep -c -F -- "$marker") || c2=0
    total=$((total + c1 + c2))
  done <<< "$MACHO_FILES"
  if [[ "$total" -gt 0 ]]; then
    echo "marker present: '$marker' (strings/symbol matches: $total)"
    found=1
  fi
done

# Also check non-binary bundle contents (plists, resources).
if grep -rlF "DowntifyHarness" "$APP" --exclude-dir=_CodeSignature >/dev/null 2>&1 && [[ "$found" -eq 0 ]]; then
  echo "marker present in app bundle resources"
  found=1
fi

if [[ "$found" -eq 0 ]]; then
  echo "OK: $CONFIGURATION build contains no debug-harness markers."
  exit 0
fi
echo "RESULT: debug-harness markers found in $CONFIGURATION build."
exit 1
