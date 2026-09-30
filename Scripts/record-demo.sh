#!/bin/bash
# Records a demo video for App Store review: launches Tappy in
# smoke mode (windowed, sounds muted), drives it with synthetic
# CGEvents, records the full screen with ffmpeg, then crops to
# the app window's bounds.
# Output: build/Tappy-demo.mov
#
# Needs Accessibility trust (same as make smoke) and Screen
# Recording permission for the terminal app.

set -eu
cd "$(dirname "$0")/.."

# Build first so the binary exists before we try to launch it.
make build

RECORD_EVENTS="Scripts/record-events.swift"
RAW="build/Tappy-demo-raw.mov"
OUT="build/Tappy-demo.mov"
rm -f "$RAW" "$OUT"

echo "Launching Tappy in demo mode…"
TAPPY_SMOKE=1 TAPPY_SMOKE_SECONDS=45 .build/debug/Tappy &
PID=$!
trap 'kill "$PID" 2>/dev/null; exit 1' INT TERM

# Wait for the window and get its bounds for cropping.
WIN=""
for _ in $(seq 1 30); do
    WIN=$(swift "$RECORD_EVENTS" --find-window "$PID" 2>/dev/null) && break
    sleep 0.5
done
[ -n "$WIN" ] || { echo "error: no window found for pid $PID" >&2; kill "$PID"; exit 1; }
echo "Window id: $WIN"

# Get window bounds as "x,y,w,h" for ffmpeg crop.
BOUNDS=$(swift "$RECORD_EVENTS" --window-bounds "$PID" 2>/dev/null)
[ -n "$BOUNDS" ] || { echo "error: no window bounds" >&2; kill "$PID"; exit 1; }
echo "Window bounds: $BOUNDS"

# Start ffmpeg screen recording (no audio, no cursor).
echo "Recording full screen to $RAW …"
FFMPEG_START=$(date +%s)
ffmpeg -f avfoundation -i "Capture screen 0" -c:v libx264 -preset ultrafast -crf 28 -y "$RAW" &
FFMPEG_PID=$!
sleep 1  # let ffmpeg initialize

# Run the scripted interaction (slower than smoke, for viewers).
# The injector prints EXIT_AT=<unix-timestamp> just before it sends
# the final Esc; we use it to trim the recording.
EVENTS_OUT=$(mktemp -t tappy-events.XXXXXX)
swift "$RECORD_EVENTS" "$PID" > "$EVENTS_OUT" 2>&1

# Stop ffmpeg (SIGINT = finish and close file). Wait for it to
# finish writing before cropping.
kill -INT "$FFMPEG_PID" 2>/dev/null || true
wait "$FFMPEG_PID" 2>/dev/null || true
for _ in $(seq 1 20); do
    [ -f "$RAW" ] && [ "$(stat -f%z "$RAW" 2>/dev/null || echo 0)" -gt 10000 ] && break
    sleep 0.5
done
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

if [ ! -f "$RAW" ]; then
    echo "error: raw recording not produced — check Screen Recording permission" >&2
    echo "  System Settings → Privacy & Security → Screen Recording → enable your terminal app" >&2
    exit 1
fi

# Compute trim duration: EXIT_AT - FFMPEG_START, clamped to ≥1 s.
EXIT_AT=$(grep '^EXIT_AT=' "$EVENTS_OUT" | cut -d= -f2 || true)
TRIM_DUR=""
if [ -n "$EXIT_AT" ]; then
    EXIT_INT=$(echo "$EXIT_AT" | cut -d. -f1)
    TRIM_DUR=$((EXIT_INT - FFMPEG_START))
    [ "$TRIM_DUR" -lt 1 ] && TRIM_DUR=1
    echo "Trimming to ${TRIM_DUR}s (ends at Esc)"
fi
rm -f "$EVENTS_OUT"

# Crop to the app window and trim to the Esc moment. Bounds are
# "x,y,w,h" in points; ffmpeg crop uses pixels, and on Retina the
# screen recording is at 2x scale, so multiply by 2.
X=$(echo "$BOUNDS" | cut -d, -f1)
Y=$(echo "$BOUNDS" | cut -d, -f2)
W=$(echo "$BOUNDS" | cut -d, -f3)
H=$(echo "$BOUNDS" | cut -d, -f4)
echo "Cropping to ${W}x${H} at (${X},${Y}) …"
if [ -n "$TRIM_DUR" ]; then
    ffmpeg -i "$RAW" -t "$TRIM_DUR" -vf "crop=$W*2:$H*2:$X*2:$Y*2" -c:v libx264 -preset medium -crf 20 -y "$OUT" 2>&1 | tail -3
else
    ffmpeg -i "$RAW" -vf "crop=$W*2:$H*2:$X*2:$Y*2" -c:v libx264 -preset medium -crf 20 -y "$OUT" 2>&1 | tail -3
fi
rm -f "$RAW"

echo "Done: $OUT ($(ls -lh "$OUT" | awk '{print $5}'))"
echo "Duration target: 30–40 s. Trim in QuickTime if needed."
