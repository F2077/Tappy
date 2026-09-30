#!/bin/bash
# Records a demo video for App Store review: launches Tappy at
# 960x540 logical points (= 1920x1080 physical pixels on Retina),
# records the full screen with ffmpeg, then crops 1:1 to the app
# window. Output is exactly 1920x1080, no scaling, no black bars.
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

echo "Launching Tappy at 960x540 (= 1920x1080 physical)…"
TAPPY_SMOKE=1 TAPPY_SMOKE_SECONDS=45 TAPPY_WINDOW=960x540 .build/debug/Tappy &
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
echo "Window bounds: $BOUNDS (logical points)"

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

# Crop 1:1 to the app window. Bounds are logical points; ffmpeg
# records physical pixels on Retina, so multiply by 2. No scaling,
# no padding — the window is exactly 1920x1080 physical pixels.
X=$(echo "$BOUNDS" | cut -d, -f1)
Y=$(echo "$BOUNDS" | cut -d, -f2)
W=$(echo "$BOUNDS" | cut -d, -f3)
H=$(echo "$BOUNDS" | cut -d, -f4)
echo "Cropping 1:1 to ${W}x${H} logical = $((W*2))x$((H*2)) physical …"
if [ -n "$TRIM_DUR" ]; then
    ffmpeg -i "$RAW" -t "$TRIM_DUR" -vf "crop=$((W*2)):$((H*2)):$((X*2)):$((Y*2))" -c:v libx264 -preset medium -crf 20 -y "$OUT" 2>&1 | tail -3
else
    ffmpeg -i "$RAW" -vf "crop=$((W*2)):$((H*2)):$((X*2)):$((Y*2))" -c:v libx264 -preset medium -crf 20 -y "$OUT" 2>&1 | tail -3
fi
rm -f "$RAW"

echo "Done: $OUT ($(ls -lh "$OUT" | awk '{print $5}'))"
echo "Dimensions: $(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$OUT" 2>/dev/null || echo 'unknown')"
