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
# Release metadata: CI stamps the tag version + run number.
VERSION=${TAPPY_VERSION:-1.0}
BUILD_NUMBER=${TAPPY_BUILD_NUMBER:-1}

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
# this location at runtime. SwiftPM's generated Info.plist lacks
# CFBundleIdentifier, which App Store validation rejects (error 90276),
# so inject one derived from the bundle's directory name.
for bundle in .build/release/*.bundle; do
    cp -R "$bundle" "$APP/Contents/Resources/"
    dest="$APP/Contents/Resources/$(basename "$bundle")"
    slug=$(basename "$bundle" .bundle | tr 'A-Z_' 'a-z-')
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID.$slug" \
        "$dest/Info.plist"
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
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleExecutable</key><string>Tappy</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
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

# Downloaded ingredients (e.g. the provisioning profile) may carry
# com.apple.quarantine; App Store validation rejects any xattrs inside
# the bundle (error 91109), so strip them all before signing.
xattr -cr "$APP"

# When a profile is embedded, the signature must claim the same
# application identifier the profile authorizes, or App Store upload
# fails with error 90886. Derive it from the profile at build time so
# no team ID is hardcoded in the repo.
SIGN_ENTITLEMENTS=$ENTITLEMENTS
if [ -n "$PROFILE" ]; then
    # Note: PlistBuddy (not plutil -extract) — its ":" keypath syntax
    # survives entitlement keys that themselves contain dots.
    PROFILE_PLIST=$(mktemp -t tappy-profile)
    security cms -D -i "$PROFILE" 2>/dev/null > "$PROFILE_PLIST"
    APP_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$PROFILE_PLIST")
    rm -f "$PROFILE_PLIST"
    case "$APP_ID" in
        *."$BUNDLE_ID") : ;;
        *) echo "error: profile App ID $APP_ID does not match bundle id $BUNDLE_ID" >&2; exit 1 ;;
    esac
    SIGN_ENTITLEMENTS=$(mktemp -t tappy-entitlements)
    if [ -n "$ENTITLEMENTS" ]; then
        cp "$ENTITLEMENTS" "$SIGN_ENTITLEMENTS"
    else
        printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
            '<plist version="1.0"><dict/></plist>' > "$SIGN_ENTITLEMENTS"
    fi
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APP_ID" "$SIGN_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string ${APP_ID%%.*}" "$SIGN_ENTITLEMENTS"
fi

# Sign with the configured identity, or ad-hoc ("-") for local builds.
if [ -n "$SIGN_ENTITLEMENTS" ]; then
    codesign --force --options runtime --entitlements "$SIGN_ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
fi

echo "Built $APP (bundle id: $BUNDLE_ID, identity: $SIGN_IDENTITY)"
