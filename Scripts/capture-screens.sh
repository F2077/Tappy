#!/bin/bash
# App Store screenshot set: for each language, launches the windowed
# app at 1440×900 (TAPPY_WINDOW), drives four staged scenes via
# capture-screens.swift, then resamples every grab to the exact ASC
# listing sizes (2880×1800 / 2560×1600 / 1440×900 / 1280×800, all
# 16:10). Output: build/screens/<lang>/0*.png — local files only.
# Usage: Scripts/capture-screens.sh [langs]   (default "zh-Hans en")
set -u
cd "$(dirname "$0")/.."

swift build -c release 2>&1 | tail -1

LANGS=${1:-"zh-Hans en"}
OUT=build/screens
mkdir -p "$OUT"

for lang in $LANGS; do
    dir="$OUT/$lang"
    rm -rf "$dir"
    mkdir -p "$dir"
    echo "=== capturing $lang ==="
    TAPPY_SMOKE=1 TAPPY_WINDOW=1440x900 TAPPY_LANG=$lang TAPPY_SMOKE_SECONDS=90 \
        .build/release/Tappy >/dev/null 2>&1 &
    PID=$!
    trap 'kill "$PID" 2>/dev/null' EXIT
    if swift Scripts/capture-screens.swift "$PID" "$dir"; then
        wait "$PID" 2>/dev/null || true
    else
        kill "$PID" 2>/dev/null
        wait "$PID" 2>/dev/null || true
        trap - EXIT
        echo "capture failed for $lang" >&2
        exit 1
    fi
    trap - EXIT
done

# Normalize to exact ASC sizes (window may have been clamped by the
# physical screen; nearest 16:10 listing size wins). Retina-native
# 2880×1800 grabs are kept as-is — downsampling would soften text.
for f in "$OUT"/*/*.png; do
    w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
    h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')
    if [ "$w" = 2880 ] && [ "$h" = 1800 ]; then continue; fi
    if   [ "$w" -ge 2870 ]; then sips -z 1800 2880 "$f" >/dev/null
    elif [ "$w" -ge 2550 ]; then sips -z 1600 2560 "$f" >/dev/null
    elif [ "$w" -ge 1430 ]; then sips -z  900 1440 "$f" >/dev/null
    else                         sips -z  800 1280 "$f" >/dev/null
    fi
done

# ASC rejects alpha; ship flattened JPEGs (quality 100, RGB only).
for f in "$OUT"/*/*.png; do
    sips -s format jpeg -s formatOptions best "$f" --out "${f%.png}.jpg" >/dev/null
    rm "$f"
done

echo
for f in "$OUT"/*/*.jpg; do
    printf '%s  %sx%s\n' "$f" \
        "$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')" \
        "$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')"
done
