#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${1:-"$ROOT_DIR/dist/CraftyCannon.app"}"
PROFILE="${CRAFTYCANNON_NOTARY_PROFILE:-craftycannon-notary}"
OUT_ZIP="${CRAFTYCANNON_NOTARIZED_ZIP:-"$ROOT_DIR/dist/releases/CraftyCannon-notarized.zip"}"
INSTALL_APP_PATH="${CRAFTYCANNON_INSTALL_APP_PATH:-}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/craftycannon-notarize.XXXXXX")"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  echo "Usage: $0 /path/to/CraftyCannon.app" >&2
  exit 2
fi

if ! /usr/bin/xcrun --find notarytool >/dev/null 2>&1; then
  echo "notarytool not found. Install Xcode Command Line Tools." >&2
  exit 2
fi

WORK_APP="$WORK_DIR/$(basename "$APP_PATH")"
echo "Preparing clean copy for notarization: $WORK_APP"
/usr/bin/ditto "$APP_PATH" "$WORK_APP"

# Some directories (notably cloud-synced / file-provider-backed locations) attach xattrs
# that cause codesign verification to fail even when the signature is otherwise valid.
# Notarize the clean temp copy so the submission is deterministic.
/usr/bin/xattr -cr "$WORK_APP" || true
find "$WORK_APP" -name '.DS_Store' -delete 2>/dev/null || true
find "$WORK_APP" -name '._*' -delete 2>/dev/null || true

echo "Checking signature..."
if ! /usr/bin/codesign --verify --deep --strict --verbose "$WORK_APP" >/dev/null 2>&1; then
  echo "codesign verification failed for: $WORK_APP" >&2
  exit 2
fi

# Notarization requires a Developer ID Application signature.
SIGN_DETAILS="$(/usr/bin/codesign -dv --verbose=4 "$WORK_APP" 2>&1 || true)"
if ! /bin/echo "$SIGN_DETAILS" | /usr/bin/grep -q "Authority=Developer ID Application"; then
  echo "App is not signed with 'Developer ID Application'. Notarization will fail." >&2
  /bin/echo "$SIGN_DETAILS" | /usr/bin/grep -E '^(Authority=|TeamIdentifier=|Identifier=|Timestamp=)' >&2 || true
  echo "Build with Developer ID, e.g.:" >&2
  echo "  CRAFTYCANNON_CODESIGN_IDENTITY=\"Developer ID Application: ...\" ./build.sh" >&2
  exit 2
fi

ZIP_PATH="${WORK_APP%.app}.zip"
rm -f "$ZIP_PATH"

echo "Creating notarization zip: $ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$WORK_APP" "$ZIP_PATH"

echo "Submitting to Apple notary service (profile: $PROFILE)..."
echo "If you haven't stored credentials yet, run:"
echo "  xcrun notarytool store-credentials \"$PROFILE\" --apple-id \"you@example.com\" --team-id \"TEAMID\" --password \"APP_SPECIFIC_PASSWORD\""

/usr/bin/xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$PROFILE" --wait

echo "Stapling ticket..."
/usr/bin/xcrun stapler staple -v "$WORK_APP"

echo "Assessing gatekeeper..."
/usr/sbin/spctl -a -vv --type execute "$WORK_APP" || true

if [[ -z "$INSTALL_APP_PATH" ]]; then
  APP_NAME="$(basename "$WORK_APP")"
  if [[ -d "/Applications" && -w "/Applications" ]]; then
    INSTALL_APP_PATH="/Applications/$APP_NAME"
  else
    mkdir -p "$HOME/Applications"
    if [[ -w "$HOME/Applications" ]]; then
      INSTALL_APP_PATH="$HOME/Applications/$APP_NAME"
    fi
  fi
fi

if [[ -n "$INSTALL_APP_PATH" ]]; then
  echo "Installing notarized app: $INSTALL_APP_PATH"
  if rm -rf "$INSTALL_APP_PATH" && /usr/bin/ditto "$WORK_APP" "$INSTALL_APP_PATH"; then
    echo "Installed notarized app: $INSTALL_APP_PATH"
  else
    echo "Warning: failed to install notarized app at $INSTALL_APP_PATH" >&2
  fi
else
  echo "Skipping app install: no writable Applications folder found."
fi

mkdir -p "$(dirname "$OUT_ZIP")"
rm -f "$OUT_ZIP"
echo "Exporting notarized zip: $OUT_ZIP"
/usr/bin/ditto "$ZIP_PATH" "$OUT_ZIP"

echo "Notarization complete."
echo "Notarized zip: $OUT_ZIP"
