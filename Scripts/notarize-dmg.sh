#!/bin/sh
# Builds build/Tappy.dmg for direct distribution (GitHub Releases):
# the app is signed with the Developer ID Application identity
# (hardened runtime, sandbox entitlements, no provisioning profile —
# those are App Store concepts), wrapped in a DMG, and the DMG is
# signed, notarized, and stapled. Gatekeeper on a downloader's Mac
# then opens it with no warning at all.
#
# Run via `make release-dmg`. Configuration comes from the environment
# or ~/.config/tappy/signing.sh (see Scripts/signing.example.sh and
# docs/release.md):
#   TAPPY_DEVELOPER_ID_IDENTITY  e.g. "Developer ID Application: …"
#   TAPPY_NOTARY_KEY             path to the App Store Connect API .p8
#   TAPPY_NOTARY_KEY_ID          API key id
#   TAPPY_NOTARY_ISSUER_ID       API key issuer UUID
set -eu

SIGNING_CONFIG=${TAPPY_SIGNING_CONFIG:-$HOME/.config/tappy/signing.sh}
if [ -f "$SIGNING_CONFIG" ]; then
    . "$SIGNING_CONFIG"
fi

: "${TAPPY_DEVELOPER_ID_IDENTITY:?set TAPPY_DEVELOPER_ID_IDENTITY (see docs/release.md)}"
: "${TAPPY_NOTARY_KEY:?set TAPPY_NOTARY_KEY (see docs/release.md)}"
: "${TAPPY_NOTARY_KEY_ID:?set TAPPY_NOTARY_KEY_ID (see docs/release.md)}"
: "${TAPPY_NOTARY_ISSUER_ID:?set TAPPY_NOTARY_ISSUER_ID (see docs/release.md)}"

test -f "$TAPPY_NOTARY_KEY" || {
    echo "error: notary API key not found: $TAPPY_NOTARY_KEY" >&2; exit 1; }

# Developer ID distribution carries no provisioning profile; the
# sandbox entitlements are the same set the App Store build uses.
TAPPY_SIGN_IDENTITY=$TAPPY_DEVELOPER_ID_IDENTITY \
TAPPY_ENTITLEMENTS=Scripts/Tappy.entitlements \
./Scripts/bundle.sh

./Scripts/make-dmg.sh

# Sign the DMG itself, so the artifact Gatekeeper first sees is
# already attributable to the Developer ID.
codesign --force --sign "$TAPPY_DEVELOPER_ID_IDENTITY" build/Tappy.dmg

# Notarize the DMG (covers the app inside) and staple the ticket so
# offline machines still verify.
echo "Submitting build/Tappy.dmg for notarization (may take minutes)…"
xcrun notarytool submit build/Tappy.dmg \
    --key "$TAPPY_NOTARY_KEY" \
    --key-id "$TAPPY_NOTARY_KEY_ID" \
    --issuer "$TAPPY_NOTARY_ISSUER_ID" \
    --wait
xcrun stapler staple build/Tappy.dmg

# Gatekeeper's own verdict — the whole point of the exercise.
spctl -a -vv build/Tappy.dmg

echo "Built notarized build/Tappy.dmg"
