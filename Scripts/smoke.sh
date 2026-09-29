#!/bin/bash
# End-to-end smoke, pure Command Line Tools (no Xcode): build Tappy,
# launch it windowed (TAPPY_SMOKE=1), then drive the whole interaction
# surface with real synthetic CGEvents — background click, a second
# click that an entity must claim, key bang, scroll flick, swallowed
# ⌘Q, held-S scene cycle, held-P settings, input pass-through while
# settings are open, ⓘ-button About page (open + close), Done-button
# close, keys working again, and the held-Esc exit. The app logs
# spawns, name-badge show/hide, and state changes to a file the script
# asserts on. Needs Accessibility trust (prompts on first run).
# TAPPY_SMOKE_CAPTURE=1 additionally saves build/smoke-about.png (the
# About page) and build/smoke.png (playfield with badges) — best-effort;
# needs Screen Recording, never fatal.

set -u
cd "$(dirname "$0")/.."

failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }

LOG="$(mktemp -t tappy-smoke.XXXXXX)"
OUT="$(mktemp -t tappy-smoke-out.XXXXXX)"
RUN_SECONDS=30          # safety-net self-quit; the real exit is Esc
MAX_ELAPSED=25          # a healthy run finishes well before the timer

# TAPPY_SMOKE_LANG=<bundle code> drives one pass in that language
# (see make smoke-l10n); forwarded to the app as TAPPY_LANG — the
# -AppleLanguages argument does not reach the SwiftPM resource bundle's
# localization resolution. The AX presses are identifier-based —
# language-independent — except the settings Done button, whose label
# set below already covers all seven localizations.
LANG_ENV=""
[ -n "${TAPPY_SMOKE_LANG:-}" ] && LANG_ENV="TAPPY_LANG=$TAPPY_SMOKE_LANG"

LAUNCH_TS=$(date +%s)
TAPPY_SMOKE=1 TAPPY_SMOKE_LOG="$LOG" TAPPY_SMOKE_SECONDS=$RUN_SECONDS \
    env $LANG_ENV .build/debug/Tappy >"$OUT" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null' EXIT

WIN="$(swift Scripts/smoke-events.swift "$PID")"
if [ $? -eq 0 ]; then
    pass "synthetic events delivered"
else
    fail "synthetic events delivered (see message above)"
fi

# The app exits itself on the held Esc; reap it (timing-checked below).
wait "$PID"; STATUS=$?
ELAPSED=$(( $(date +%s) - LAUNCH_TS ))
trap - EXIT

count() { grep -c "$1" "$LOG" 2>/dev/null || true; }

# One tap spawn: the FIRST background click. The second click at the
# same point must be claimed by the entity (react), not spawn again.
[ "$(count '^spawn tap ')" -eq 1 ] && pass "background click spawned; entity claimed the second" || fail "background click spawned; entity claimed the second"
[ "$(count '^spawn key ')" -eq 2 ] && pass "key bangs spawned (before + after settings)" || fail "key bangs spawned (before + after settings)"
[ "$(count '^spawn scroll ')" -eq 1 ] && pass "scroll flick spawned" || fail "scroll flick spawned"
[ "$(count '^spawn ')" -eq 4 ] && pass "4 spawns total (⌘Q and settings-time key spawned nothing)" || fail "4 spawns total (⌘Q and settings-time key spawned nothing)"

[ "$(count '^lang ')" -eq 1 ] && pass "app reported its resolved language" || fail "app reported its resolved language"
if [ -n "${TAPPY_SMOKE_LANG:-}" ]; then
    [ "$(count "^lang $TAPPY_SMOKE_LANG\$")" -eq 1 ] \
        && pass "resolved language is $TAPPY_SMOKE_LANG" \
        || fail "resolved language is $TAPPY_SMOKE_LANG (log: $(grep '^lang ' "$LOG" 2>/dev/null))"
fi

[ "$(count '^settings open$')" -eq 1 ] && pass "hold P opened settings" || fail "hold P opened settings"
[ "$(count '^settings closed$')" -eq 1 ] && pass "Done button closed settings" || fail "Done button closed settings"
[ "$(count '^scene ')" -ge 1 ] && pass "hold S cycled the scene" || fail "hold S cycled the scene"

# Name badges: one show per spawn plus one re-show when the entity
# claims the second click (4 spawns + 1 react = 5). Hides lag 2 s per
# generation; the last entity's hide races the held-Esc exit, so 3 of
# 4 must have fired by then — assert a floor, not equality.
[ "$(count '^badge show$')" -eq 5 ] && pass "name badges shown (4 spawns + entity tap)" || fail "name badges shown (4 spawns + entity tap)"
[ "$(count '^badge hide$')" -ge 3 ] && pass "name badges auto-hide after 2 s" || fail "name badges auto-hide after 2 s"

# About page: the settings ⓘ button opens it, its own Done closes it.
[ "$(count '^about open$')" -eq 1 ] && pass "info button opened About" || fail "info button opened About"
[ "$(count '^about closed$')" -eq 1 ] && pass "About closed via its Done" || fail "About closed via its Done"
# Toddler-lock toggle: verified AX-exposed by the injector (no press —
# its failure surfaces as "synthetic events delivered" with stderr).

if [ "$STATUS" -eq 0 ] && [ "$ELAPSED" -lt "$MAX_ELAPSED" ]; then
    pass "held Esc exited cleanly (status 0, ${ELAPSED}s < ${RUN_SECONDS}s timer)"
else
    fail "held Esc exited cleanly (status $STATUS, ${ELAPSED}s; timer is ${RUN_SECONDS}s)"
fi

if [ "$failures" -gt 0 ]; then
    echo
    echo "--- smoke log ---"
    cat "$LOG"
    echo "--- app output (tail) ---"
    tail -20 "$OUT"
fi
echo
if [ "$failures" -eq 0 ]; then
    echo "All smoke checks passed."
else
    echo "$failures smoke check(s) failed."
    exit 1
fi
