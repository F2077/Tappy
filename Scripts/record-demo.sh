#!/bin/bash
# Records a demo video for App Store review: wraps the debug build in
# a minimal launcher .app (LSEnvironment carries the smoke/window env
# that a shell launch would set), puts an alias to it on the Desktop,
# records the full screen with ffmpeg, then double-clicks the icon on
# camera — Apple's "recording must begin with launching the app".
# The app window is pinned to 960x540 logical points (= 1920x1080
# physical pixels on Retina) and moved to the top-left; the crop is
# 1:1, no scaling, no black bars. A few seconds of desktop stay at the
# tail so reviewers see the app fully exited.
#
# Needs Accessibility trust (same as make smoke) and Screen Recording
# permission for the terminal app, plus Automation consent for Finder
# (the desktop alias) — macOS prompts on first run.

set -eu
cd "$(dirname "$0")/.."

# Build first so the binary exists before we wrap it. Debug, same as
# make smoke — `make build` produces the release binary, which this
# script does not use.
make patch
swift build

RECORD_EVENTS="Scripts/record-events.swift"
RAW="build/Tappy-demo-raw.mov"
OUT="build/Tappy-demo.mov"
rm -f "$RAW" "$OUT"

PID=""
FFMPEG_PID=""
ALIAS_PATH=""

cleanup() {
    # Never leave the alias on the user's desktop.
    [ -n "$ALIAS_PATH" ] && osascript -e "tell application \"Finder\" to delete (POSIX file \"$ALIAS_PATH\" as alias)" >/dev/null 2>&1 || true
}
on_abort() {
    [ -n "$FFMPEG_PID" ] && kill -INT "$FFMPEG_PID" 2>/dev/null || true
    [ -n "$PID" ] && kill "$PID" 2>/dev/null || true
    exit 1
}
trap on_abort INT TERM
trap cleanup EXIT

# --- Launcher app -----------------------------------------------------
# A minimal unsigned .app around the debug binary. LSEnvironment bakes
# in what `make smoke` passes on the command line, so LaunchServices
# (the desktop double-click) starts the app in the same harness mode.
APP="build/Pat-a-Pet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/debug/Tappy "$APP/Contents/MacOS/Tappy"
cp -R .build/debug/Tappy_TappyCore.bundle "$APP/Contents/Resources/"

# Fresh preferences: the launcher has its own defaults domain, and the
# theme/scene choices persist across runs — reset so every recording
# starts from the same state (Animals theme, first scene).
defaults delete com.github.f2077.tappy.rec 2>/dev/null || true

# Real icon, so the desktop alias and the Dock bounce look right.
ICONSET="$(mktemp -d -t tappy-iconset)/Tappy.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z "$s" "$s" Assets/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Assets/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Tappy</string>
    <key>CFBundleIdentifier</key><string>com.github.f2077.tappy.rec</string>
    <key>CFBundleName</key><string>Pat-a-Pet</string>
    <key>CFBundleDisplayName</key><string>Pat-a-Pet</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSEnvironment</key>
    <dict>
        <key>TAPPY_SMOKE</key><string>1</string>
        <key>TAPPY_SMOKE_SECONDS</key><string>120</string>
        <key>TAPPY_WINDOW</key><string>960x540</string>
    </dict>
</dict>
</plist>
PLIST

# --- Desktop icon -----------------------------------------------------
# Alias at a fixed spot inside the future crop region (the app window
# lands at 0,30/960x540, so 180,140 is well within frame). The read-back
# position is where the synthetic double-click lands.
echo "Placing a temporary launch icon on the Desktop…"
ALIAS_INFO=$(TAPPY_REC_APP="$PWD/$APP" osascript <<'APPLESCRIPT'
tell application "Finder"
    set theAlias to make new alias file at desktop to (POSIX file (system attribute "TAPPY_REC_APP"))
    set desktop position of theAlias to {180, 140}
    delay 0.5
    set p to desktop position of theAlias
    set pth to POSIX path of (theAlias as alias)
    return (item 1 of p as string) & "," & (item 2 of p as string) & "|" & pth
end tell
APPLESCRIPT
)
ICON_XY="${ALIAS_INFO%%|*}"
ALIAS_PATH="${ALIAS_INFO#*|}"
[ -n "$ICON_XY" ] && [ "$ICON_XY" != "$ALIAS_PATH" ] || {
    echo "error: could not create the desktop alias — grant Finder automation when prompted" >&2
    exit 1
}
echo "Icon at: $ICON_XY ($ALIAS_PATH)"

# Minimize all other windows so the recording shows only the desktop
# and the app.
echo "⚠️  如果还有窗口没最小化，请手动处理，3 秒后开始录屏…"
echo "   (If any windows remain, minimize them now; recording in 3 s)"
sleep 3
echo "Minimizing other windows…"
osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
    set allProcs to every process whose visible is true and name is not "Tappy"
    repeat with proc in allProcs
        try
            tell proc to set value of attribute "AXMinimized" of every window to true
        end try
    end repeat
end tell
APPLESCRIPT
sleep 1

# --- Record + launch --------------------------------------------------
echo "Recording full screen to $RAW …"
FFMPEG_START=$(date +%s)
ffmpeg -f avfoundation -i "Capture screen 0" -c:v libx264 -preset ultrafast -crf 28 -y "$RAW" &
FFMPEG_PID=$!
sleep 1  # let ffmpeg initialize

# The launch moment, on camera: double-click the desktop icon.
swift "$RECORD_EVENTS" --double-click "$ICON_XY"

PID=""
for _ in $(seq 1 30); do
    PID=$(pgrep -nf "Pat-a-Pet.app/Contents/MacOS/Tappy" 2>/dev/null || true)
    [ -n "$PID" ] && break
    sleep 0.5
done
[ -n "$PID" ] || { echo "error: app did not launch from the icon" >&2; exit 1; }
echo "Launched, pid: $PID"

# Wait for the window and get its bounds for cropping.
WIN=""
for _ in $(seq 1 30); do
    WIN=$(swift "$RECORD_EVENTS" --find-window "$PID" 2>/dev/null) && break
    sleep 0.5
done
[ -n "$WIN" ] || { echo "error: no window found for pid $PID" >&2; exit 1; }
echo "Window id: $WIN"

# Move the window to the top-left (macOS clamps y=0 to just under the
# menu bar, ~y=30); the crop then captures exactly the app with no
# desktop margin. PID-based: the process name is not "Tappy" here.
osascript <<APPLESCRIPT 2>/dev/null || true
tell application "System Events"
    tell (first process whose unix id is $PID)
        set position of window 1 to {0, 0}
    end tell
end tell
APPLESCRIPT
sleep 1

# Get window bounds as "x,y,w,h" for ffmpeg crop.
BOUNDS=$(swift "$RECORD_EVENTS" --window-bounds "$PID" 2>/dev/null)
[ -n "$BOUNDS" ] || { echo "error: no window bounds" >&2; exit 1; }
echo "Window bounds: $BOUNDS (logical points)"

# Run the scripted interaction (slower than smoke, for viewers).
# The injector prints EXIT_AT=<unix-timestamp> just before it sends
# the final Esc; we use it to trim the recording.
EVENTS_OUT=$(mktemp -t tappy-events.XXXXXX)
swift "$RECORD_EVENTS" "$PID" > "$EVENTS_OUT" 2>&1

# Keep rolling ~4 s past the final Esc hold so the tail of the video
# shows the desktop after the app has fully exited — reviewers should
# see that the app closes cleanly.
sleep 4

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

# Trim: EXIT_AT (just before the final Esc hold) plus a 4 s tail, so
# the last frames show the desktop again — proof the app fully exited.
# Clamped to ≥1 s.
EXIT_AT=$(grep '^EXIT_AT=' "$EVENTS_OUT" | cut -d= -f2 || true)
TRIM_DUR=""
if [ -n "$EXIT_AT" ]; then
    EXIT_INT=$(echo "$EXIT_AT" | cut -d. -f1)
    TRIM_DUR=$((EXIT_INT - FFMPEG_START + 4))
    [ "$TRIM_DUR" -lt 1 ] && TRIM_DUR=1
    echo "Trimming to ${TRIM_DUR}s (4 s of desktop after exit)"
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
