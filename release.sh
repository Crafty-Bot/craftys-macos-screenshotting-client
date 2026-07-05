#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${CRAFTYCANNON_NOTARY_PROFILE:-craftycannon-notary}"

echo "Release: building + signing..."

if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  echo "Missing Xcode Command Line Tools (swiftc). Install them and retry." >&2
  exit 2
fi

if ! /usr/bin/xcrun --find notarytool >/dev/null 2>&1; then
  echo "Missing notarytool. Install Xcode Command Line Tools and retry." >&2
  exit 2
fi

# Notarization requires a Developer ID Application identity.
if ! /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -q "Developer ID Application:"; then
  echo "No 'Developer ID Application' signing identity found in Keychain." >&2
  echo "Install your Developer ID cert, then retry." >&2
  exit 2
fi

cd "$ROOT_DIR"

./build.sh

echo
echo "Release: notarizing + stapling (profile: $PROFILE)..."
./notarize.sh

echo
echo "Release complete."
echo "Notarized zip:"
echo "  $ROOT_DIR/dist/releases/CraftyCannon-notarized.zip"
