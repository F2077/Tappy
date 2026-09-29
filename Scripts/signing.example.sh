# Template for local signing configuration.
# Copy OUTSIDE the repo to ~/.config/tappy/signing.sh (chmod 600) and
# fill in your values. bundle.sh sources that file if present; without
# it, builds fall back to an ad-hoc signature for local development.
# See docs/signing.md for the full setup.
# Override the config location with TAPPY_SIGNING_CONFIG if needed.
#
# Assignments use the `: "${VAR:=default}"` idiom so callers (e.g.
# make-pkg.sh) can override any value via the environment.

# Bundle ID registered in the Apple Developer portal. Must match the
# App ID inside the provisioning profile.
#: "${TAPPY_BUNDLE_ID:=com.github.f2077.tappy}"

# Signing identity, exactly as listed by:
#   security find-identity -v -p codesigning
# Leave unset for ad-hoc signing.
#: "${TAPPY_SIGN_IDENTITY:=Apple Development: Your Name (XXXXXXXXXX)}"

# Path to a downloaded .provisionprofile. When set, it is embedded into
# the app as Contents/embedded.provisionprofile before signing.
#: "${TAPPY_PROVISION_PROFILE:=$HOME/Documents/Tappy_macOS_Development.provisionprofile}"

# --- Mac App Store distribution (make pkg) ---

# "Apple Distribution" cert (or legacy "3rd Party Mac Developer
# Application"), listed by:
#   security find-identity -v
#: "${TAPPY_APPSTORE_IDENTITY:=Apple Distribution: Your Name (XXXXXXXXXX)}"

# "Mac Installer Distribution" cert, signs the .pkg wrapper.
#: "${TAPPY_INSTALLER_IDENTITY:=3rd Party Mac Developer Installer: Your Name (XXXXXXXXXX)}"

# Distribution provisioning profile of type "Mac App Store Connect".
#: "${TAPPY_APPSTORE_PROFILE:=$HOME/Documents/Tappy_macOS_App_Store.mobileprovision}"

