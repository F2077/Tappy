#!/bin/sh
# Builds build/Tappy.dmg: the app, both theme packs as loose
# drag-installable archives, and the usual /Applications link.
# Run after Scripts/bundle.sh (make app).
set -eu

APP=build/Tappy.app
PACKS_SRC=Sources/TappyCore/Resources/Packs
STAGING=build/dmg
DMG=build/Tappy.dmg

test -d "$APP" || { echo "error: $APP missing; run 'make app' first" >&2; exit 1; }

rm -rf "$STAGING"
mkdir -p "$STAGING/Packs"
cp -R "$APP" "$STAGING/"
ln -sf /Applications "$STAGING/Applications"

# Each pack also ships as a standalone zip archive: parents can drag it
# into ~/Library/Application Support/Tappy/Packs/ for any Tappy install.
for pack in "$PACKS_SRC"/*.tappypack; do
    name=$(basename "$pack")
    (cd "$PACKS_SRC" && ditto -c -k --keepParent "$name" "$OLDPWD/$STAGING/Packs/$name")
done

rm -f "$DMG"
hdiutil create -volname Tappy -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
echo "Built $DMG"
