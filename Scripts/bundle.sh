#!/bin/sh
# Bundles the release binary into a minimal Tappy.app.
#
# Signing is configured via ~/.config/tappy/signing.sh (outside the
# repo; see docs/signing.md and Scripts/signing.example.sh). With no
# local config the app is ad-hoc signed, which is enough to run and
# develop on the local machine.
set -eu

SIGNING_CONFIG=${TAPPY_SIGNING_CONFIG:-$HOME/.config/tappy/signing.sh}
if [ -f "$SIGNING_CONFIG" ]; then
    . "$SIGNING_CONFIG"
fi

BUNDLE_ID=${TAPPY_BUNDLE_ID:-com.github.f2077.tappy}
SIGN_IDENTITY=${TAPPY_SIGN_IDENTITY:--}
PROFILE=${TAPPY_PROVISION_PROFILE:-}
ENTITLEMENTS=${TAPPY_ENTITLEMENTS:-}

APP=build/Tappy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Tappy "$APP/Contents/MacOS/Tappy"

# App icon: rebuild the .icns from the single source PNG so the bundle
# icon always matches Assets/AppIcon.png.
ICON_SRC=Assets/AppIcon.png
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" \
            "512 icon_512x512" "1024 icon_512x512@2x"; do
    set -- $spec
    sips -z "$1" "$1" "$ICON_SRC" --out "$ICONSET/$2.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"
# SwiftPM resource bundles (SVG artwork, sounds, localizations) ship in
# Contents/Resources — the app root cannot hold them because codesign
# refuses to seal unsealed root contents. TappyResources.bundle resolves
# this location at runtime.
for bundle in .build/release/*.bundle; do
    cp -R "$bundle" "$APP/Contents/Resources/"
done
# Third-party notices ship inside the app so CC-BY attribution travels
# with the binary, not just the source tree.
cp NOTICE "$APP/Contents/Resources/NOTICE.txt"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Pat-a-Pet</string>
    <key>CFBundleDisplayName</key><string>Pat-a-Pet</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>Tappy</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
        <string>ja</string>
        <string>ko</string>
        <string>es</string>
        <string>fr</string>
        <string>de</string>
    </array>
    <key>ITSAppUsesNonExemptEncryption</key><false/>
</dict>
</plist>
EOF

# Embed the provisioning profile (if configured) before signing; the
# profile's App ID must match CFBundleIdentifier above.
if [ -n "$PROFILE" ]; then
    test -f "$PROFILE" || { echo "error: profile not found: $PROFILE" >&2; exit 1; }
    cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
fi

# Sign with the configured identity, or ad-hoc ("-") for local builds.
if [ -n "$ENTITLEMENTS" ]; then
    codesign --force --options runtime --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
fi

echo "Built $APP (bundle id: $BUNDLE_ID, identity: $SIGN_IDENTITY)"
