#!/bin/sh
# Patches SwiftDraw so it builds with plain Command Line Tools (no Xcode):
#  1. strips the `#if DEBUG` / `#Preview` block in SVGView.swift
#     (PreviewsMacros plugin ships with Xcode only);
#  2. replaces the `@Entry` macro in AsyncSVGView.swift with a plain
#     EnvironmentKey (SwiftUIMacros plugin ships with Xcode only).
# Idempotent — safe to run before every build; re-run after
# `swift package update`.
set -eu

DIR=.build/checkouts/SwiftDraw/SwiftDraw/Sources
[ -d "$DIR" ] || exit 0

SVGVIEW="$DIR/SVGView.swift"
if [ -f "$SVGVIEW" ] && grep -q '#Preview' "$SVGVIEW"; then
    chmod u+w "$SVGVIEW"
    python3 - "$SVGVIEW" <<'EOF'
import sys

path = sys.argv[1]
lines = open(path).read().splitlines(keepends=True)

out = []
skipping = False
for line in lines:
    if not skipping and line.startswith("#if DEBUG"):
        skipping = True
        continue
    if skipping and line.startswith("#endif"):
        skipping = False
        continue
    if not skipping:
        out.append(line)

open(path, "w").write("".join(out))
EOF
    echo "Patched $SVGVIEW"
fi

ASYNC="$DIR/AsyncSVGView.swift"
if [ -f "$ASYNC" ] && grep -q '@Entry' "$ASYNC"; then
    chmod u+w "$ASYNC"
    python3 - "$ASYNC" <<'EOF'
import sys

path = sys.argv[1]
src = open(path).read()

old = """private extension EnvironmentValues {
    @Entry var asyncSVGURLSession: URLSession = .shared
}"""
new = """private struct AsyncSVGURLSessionKey: EnvironmentKey {
    static let defaultValue: URLSession = .shared
}

private extension EnvironmentValues {
    var asyncSVGURLSession: URLSession {
        get { self[AsyncSVGURLSessionKey.self] }
        set { self[AsyncSVGURLSessionKey.self] = newValue }
    }
}"""
assert old in src, "unexpected AsyncSVGView.swift content"
open(path, "w").write(src.replace(old, new))
EOF
    echo "Patched $ASYNC"
fi
