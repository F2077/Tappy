#!/bin/sh
# Builds build/Tappy.pkg for Mac App Store upload:
#   1. bundle.sh signs the app with the Mac App Distribution identity,
#      sandbox entitlements, and the App Store provisioning profile
#   2. productbuild wraps it in an installer package signed with the
#      Mac Installer Distribution identity
# Upload the result with Transporter or:
#   xcrun altool --upload-app -f build/Tappy.pkg --type macos \
#       --apiKey <key-id> --apiIssuer <issuer-id>
set -eu

SIGNING_CONFIG=${TAPPY_SIGNING_CONFIG:-$HOME/.config/tappy/signing.sh}
if [ -f "$SIGNING_CONFIG" ]; then
    . "$SIGNING_CONFIG"
fi

: "${TAPPY_APPSTORE_IDENTITY:?set TAPPY_APPSTORE_IDENTITY in $SIGNING_CONFIG}"
: "${TAPPY_INSTALLER_IDENTITY:?set TAPPY_INSTALLER_IDENTITY in $SIGNING_CONFIG}"
: "${TAPPY_APPSTORE_PROFILE:?set TAPPY_APPSTORE_PROFILE in $SIGNING_CONFIG}"

test -f "$TAPPY_APPSTORE_PROFILE" || {
    echo "error: profile not found: $TAPPY_APPSTORE_PROFILE" >&2; exit 1; }

TAPPY_SIGN_IDENTITY=$TAPPY_APPSTORE_IDENTITY \
TAPPY_PROVISION_PROFILE=$TAPPY_APPSTORE_PROFILE \
TAPPY_ENTITLEMENTS=Scripts/Tappy.entitlements \
./Scripts/bundle.sh

rm -f build/Tappy.pkg
productbuild --component build/Tappy.app /Applications \
    --sign "$TAPPY_INSTALLER_IDENTITY" build/Tappy.pkg

echo "Built build/Tappy.pkg"
