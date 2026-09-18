#!/usr/bin/env bash
#
# Builds a real .app bundle for macOS.
#
#   ./Scripts/make-macos-app.sh            # release
#   ./Scripts/make-macos-app.sh debug      # debug
#
# Why bundle at all: a bare executable launched with `swift run` is attributed to the
# terminal for the microphone permission prompt. Running from a bundle makes macOS show
# "Guitar Tuner would like to access the microphone" and keeps the grant stable.
set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/guitar-tuner-module-cache}"

build_flags=(-c "$CONFIGURATION" --product GuitarTunerMac)
# SwiftPM's own sandbox cannot be applied inside another sandbox (CI containers, some
# agent shells). Set GUITAR_TUNER_DISABLE_SWIFTPM_SANDBOX=1 in that case.
if [[ "${GUITAR_TUNER_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  build_flags+=(--disable-sandbox)
fi

echo "▸ Building GuitarTunerMac ($CONFIGURATION)…"
swift build "${build_flags[@]}"

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP="$ROOT/build/GuitarTuner.app"

# Guard against ever removing anything outside the repo's build directory.
if [[ -z "$APP" || "$APP" != "$ROOT/build/"* ]]; then
  echo "refusing to remove unexpected path: $APP" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GuitarTunerMac" "$APP/Contents/MacOS/GuitarTuner"
cp "$ROOT/Platforms/macOS/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature: enough for a stable TCC identity on the local machine.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "note: ad-hoc codesign skipped"

echo "▸ Built $APP"
echo "  open \"$APP\""
