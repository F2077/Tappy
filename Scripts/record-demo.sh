#!/bin/bash
# Records a demo video for App Store review: launches Tappy in
# smoke mode (windowed, sounds muted), drives it with synthetic
# CGEvents, and captures the full screen with screencapture -v.
# Output: build/Tappy-demo.mov
#
# Needs Accessibility trust (same as make smoke) and Screen
# Recording permission for the terminal app.
#
# Note: screencapture -l <windowID> fails silently on macOS 27,
# so we record the full screen instead. Tappy launches fullscreen
# in production; the smoke window is centered and the recording
# shows the whole desktop, which is acceptable for review.

set -eu
cd "$(dirname "$0")/.."

# Build first so the binary exists before we try to launch it.
make build

RECORD_EVENTS="Scripts/record-events.swift"
OUT="build/Tappy-demo.mov"
rm -f "$OUT"

echo "Launching Tappy in demo mode…"
TAPPY_SMOKE=1 TAPPY_SMOKE_SECONDS=45 .build/debug/Tappy &
PID=$!
trap 'kill "$PID" 2>/dev/null; exit 1' INT TERM

# Wait for the window to appear, then get its id (for logging only;
# we record full screen).
WIN=""
for _ in $(seq 1 30); do
    WIN=$(swift "$RECORD_EVENTS" --find-window "$PID" 2>/dev/null) && break
    sleep 0.5
done
[ -n "$WIN" ] || { echo "error: no window found for pid $PID" >&2; kill "$PID"; exit 1; }
echo "Window id: $WIN (recording full screen)"

# Start recording. No -V flag: screencapture only writes the file
# when it reaches the -V duration; killing early produces nothing.
# We record until the demo script finishes, then stop it.
echo "Recording to $OUT …"
screencapture -v "$OUT" &
CAP_PID=$!

# Give screencapture a moment to initialize before driving the app.
sleep 1

# Run the scripted interaction (slower than smoke, for viewers).
swift "$RECORD_EVENTS" "$PID"

# Stop recording and the app. screencapture -v without -V writes
# the file only on SIGINT (not SIGTERM), so send INT and wait.
kill -INT "$CAP_PID" 2>/dev/null || true
for _ in $(seq 1 10); do
    [ -f "$OUT" ] && break
    sleep 0.5
done
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

if [ -f "$OUT" ]; then
    echo "Done: $OUT ($(ls -lh "$OUT" | awk '{print $5}'))"
    echo "Duration target: 30–40 s. Trim in QuickTime if needed."
else
    echo "error: recording not produced — check Screen Recording permission" >&2
    echo "  System Settings → Privacy & Security → Screen Recording → enable your terminal app" >&2
    exit 1
fi
