#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="CraftyCannon"
DIST_DIR="$ROOT_DIR/dist"
FINAL_APP_DIR="$DIST_DIR/$APP_NAME.app"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/craftycannon-build.XXXXXX")"
APP_DIR="$STAGING_ROOT/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
BUILD_CACHE_DIR="$ROOT_DIR/.build"
MODULE_CACHE_DIR="$BUILD_CACHE_DIR/module-cache"
DEV_LINK_NAME="craftycannon-dev.app"
DEV_LINK_PATH="/Applications/$DEV_LINK_NAME"
INFO_PLIST_SRC="$ROOT_DIR/Resources/Info.plist"
INFO_PLIST_DST="$APP_DIR/Contents/Info.plist"
cleanup() { rm -rf "$STAGING_ROOT"; }
trap cleanup EXIT

# Avoid stale signatures/xattrs from prior builds.
rm -rf "$FINAL_APP_DIR"
mkdir -p "$DIST_DIR" "$MACOS_DIR" "$RES_DIR" "$MODULE_CACHE_DIR"

sanitize_metadata() {
  local target="$1"
  xattr -c "$target" 2>/dev/null || true
  xattr -r -d com.apple.provenance "$target" 2>/dev/null || true
  xattr -r -d com.apple.quarantine "$target" 2>/dev/null || true
  xattr -r -d com.apple.macl "$target" 2>/dev/null || true
}

strip_codesign_detritus() {
  local target="$1"
  # Some environments (notably file providers and Finder) can attach xattrs like
  # FinderInfo or fpfs markers to .app bundles, which make codesign/verify fail.
  # Remove them explicitly and keep this close to the codesign invocation to
  # reduce the chance they get re-attached mid-sign.
  xattr -cr "$target" 2>/dev/null || true
  xattr -r -d com.apple.FinderInfo "$target" 2>/dev/null || true
  xattr -r -d com.apple.fileprovider.fpfs#P "$target" 2>/dev/null || true
  xattr -r -d com.apple.FinderInfo "$target" 2>/dev/null || true
}

ARCH="$(uname -m)"
TARGET="$ARCH-apple-macos13.0"
SWIFTC="$(/usr/bin/xcrun --find swiftc 2>/dev/null || echo /usr/bin/swiftc)"
SDKROOT_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"

SWIFT_ARGS=(
  -O
  -target "$TARGET"
  -framework Cocoa
  -framework SwiftUI
  -framework Combine
  -framework Carbon
  -framework CoreGraphics
  -framework CoreText
  -framework CoreImage
  -framework ImageIO
  -framework Security
  -framework UserNotifications
  -framework Vision
  -o "$MACOS_DIR/$APP_NAME"
  "$ROOT_DIR/Sources"/*.swift
)

if [[ -n "$SDKROOT_PATH" ]]; then
  SWIFT_ARGS=(-sdk "$SDKROOT_PATH" "${SWIFT_ARGS[@]}")
fi

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
"$SWIFTC" "${SWIFT_ARGS[@]}"

# Copy resources into the app bundle.
# Info.plist must live at Contents/Info.plist for a valid .app bundle signature.
if [[ ! -f "$INFO_PLIST_SRC" ]]; then
  echo "Missing Info.plist at: $INFO_PLIST_SRC" >&2
  exit 2
fi
# Copy resources into the app bundle. Prefer cp over ditto so this script works
# in more restricted/sandboxed environments.
cp -R "$ROOT_DIR/Resources/." "$RES_DIR/"
sanitize_metadata "$RES_DIR"
cp "$INFO_PLIST_SRC" "$INFO_PLIST_DST"
rm -f "$RES_DIR/Info.plist"
sanitize_metadata "$APP_DIR"

echo -n 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# Remove Finder/file-provider metadata and AppleDouble detritus that breaks codesign.
xattr -cr "$APP_DIR"
find "$APP_DIR" -name '.DS_Store' -delete
find "$APP_DIR" -name '._*' -delete

SIGN_IDENTITY="${CRAFTYCANNON_CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  # Prefer Developer ID for production-style signing (required for notarization).
  SIGN_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/awk -F\" '/Developer ID Application:/ {print $2; exit}' || true)"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  # Pick a stable local development identity when available.
  SIGN_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/awk -F\" '/Apple Development:/ {print $2; exit}' || true)"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  # Xcode often provides this identity even when Apple Development certs are not installed.
  SIGN_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/awk -F\" '/Sign to Run Locally/ {print $2; exit}' || true)"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  # Fallback for older setups.
  SIGN_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/awk -F\" '/Mac Development:/ {print $2; exit}' || true)"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Codesigning with identity: $SIGN_IDENTITY"
  strip_codesign_detritus "$APP_DIR"
  # Use hardened runtime + timestamp so the result can be notarized when using
  # a Developer ID Application identity.
  /usr/bin/codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" --timestamp "$APP_DIR"
  strip_codesign_detritus "$APP_DIR"
  /usr/bin/codesign --verify --deep --strict --verbose "$APP_DIR" >/dev/null
else
  # Always codesign the app bundle even when no identity is installed, so Info.plist
  # is bound and the bundle has a consistent identifier. This reduces flakiness for
  # some macOS permission prompts, but a real signing identity is still recommended.
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST_DST" 2>/dev/null || true)"
  if [[ -z "$BUNDLE_ID" ]]; then
    BUNDLE_ID="com.crafty599.craftycannon"
  fi
  echo "Warning: no local macOS signing identity found; using ad-hoc codesign."
  strip_codesign_detritus "$APP_DIR"
  /usr/bin/codesign --force --deep --sign - --timestamp=none --identifier "$BUNDLE_ID" "$APP_DIR"
  strip_codesign_detritus "$APP_DIR"
  /usr/bin/codesign --verify --deep --strict --verbose "$APP_DIR" >/dev/null
  echo "Hint: install a Developer ID Application certificate for notarization, or set CRAFTYCANNON_CODESIGN_IDENTITY for stable macOS privacy permissions."
fi

# Copy build to the workspace output directory after signing in staging (avoids file-provider xattr races).
cp -R "$APP_DIR" "$FINAL_APP_DIR"
sanitize_metadata "$FINAL_APP_DIR"
strip_codesign_detritus "$FINAL_APP_DIR"

# Best-effort verify: file provider metadata may reattach in synced folders.
/usr/bin/codesign --verify --deep --strict --verbose "$FINAL_APP_DIR" >/dev/null 2>&1 || true

echo "Built: $FINAL_APP_DIR"

if [[ -w "/Applications" ]]; then
  ln -sfn "$FINAL_APP_DIR" "$DEV_LINK_PATH"
  echo "Dev shortcut: $DEV_LINK_PATH"
elif [[ -w "$HOME" ]]; then
  mkdir -p "$HOME/Applications"
  ln -sfn "$FINAL_APP_DIR" "$HOME/Applications/$DEV_LINK_NAME"
  echo "Dev shortcut: $HOME/Applications/$DEV_LINK_NAME"
else
  echo "Skipping dev shortcut: no writable Applications location."
fi
