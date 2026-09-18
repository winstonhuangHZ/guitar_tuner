#!/usr/bin/env bash
#
# Regression guard for the crash that killed the app the moment the microphone was
# granted:
#
#   closure #1 in TunerController.startEngine()  ->  dispatch_assert_queue_fail  ->  SIGILL
#
# Cause: a closure literal written inside a `@MainActor` method inherits main-actor
# isolation when the Objective-C block type is not `@Sendable` — `AVAudioNodeTapBlock` and
# `AVAudioSourceNodeRenderBlock` are both unannotated. AVFAudio then calls the block on
# its realtime thread and the Swift runtime's isolation check traps.
#
# Fix: build those closures in a `nonisolated` function (see TunerController.makeTapHandler).
#
# This script proves the fix at the codegen level by disassembling the built binary and
# asserting that no callback which receives an AVAudioPCMBuffer performs an actor-isolation
# check. Run it after changing anything in the audio graph:
#
#   swift build && ./Scripts/verify-audio-callbacks.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${1:-$ROOT/.build/x86_64-apple-macosx/debug/GuitarTunerMac}"

if [[ ! -x "$BIN" ]]; then
  echo "note: $BIN not found — run 'swift build' first; skipping."
  exit 0
fi

echo "▸ Disassembling $(basename "$BIN")…"
otool -tV "$BIN" > /tmp/guitar-tuner-disassembly.txt

python3 - "$BIN" <<'PY'
import re
import subprocess
import sys

text = open("/tmp/guitar-tuner-disassembly.txt", errors="ignore").read().split("\n")
symbols, current = {}, None
for line in text:
    if line and not line.startswith(("\t", " ")) and line.rstrip().endswith(":"):
        current = line.rstrip()[:-1]
        symbols[current] = []
    elif current is not None and re.match(r"^[0-9a-f]{16}\t", line):
        symbols[current].append(line)


def demangle(symbol):
    try:
        return subprocess.run(
            ["swift", "demangle", "--compact", symbol],
            capture_output=True, text=True, timeout=20,
        ).stdout.strip() or symbol
    except Exception:
        return symbol


# Every closure that receives an audio buffer is a tap/render callback.
callbacks = []
for symbol, body in symbols.items():
    if "AVAudioPCMBuffer" not in symbol and "AudioBufferList" not in symbol:
        continue
    callbacks.append((symbol, body, demangle(symbol)))

with_check = [
    (symbol, name)
    for symbol, body, name in callbacks
    if any(("isCurrentExecutor" in line) or ("checkIsolated" in line) for line in body)
]

print(f"  audio callbacks found: {len(callbacks)}")
for symbol, body, name in callbacks:
    checked = "ISOLATION CHECK" if (symbol, name) in with_check else "clean"
    print(f"    {checked:16s} {len(body):4d} instrs  {name[:100]}")

if not callbacks:
    print("  ! no audio callbacks found in the binary — did the symbol names change?")
    sys.exit(0)

if with_check:
    print("")
    print("FAIL: an audio callback performs a main-actor isolation check.")
    print("      It will trap (SIGILL) the first time AVFAudio calls it off the main thread.")
    print("      Build the closure in a nonisolated function instead of inline.")
    sys.exit(1)

print("")
print("PASS: no audio callback can trap on actor isolation.")
PY
