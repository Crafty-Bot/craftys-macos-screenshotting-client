# CraftyCannon Setup (macOS)

This document covers the minimal steps to build, sign, and run CraftyCannon on macOS, including how to deal with macOS privacy permissions (Screen Recording).

## Prereqs

- macOS 13+ recommended (build target is `macos13.0`).
- Xcode or Command Line Tools installed:
  - `xcode-select --install`

## Build (Terminal)

Build the app bundle:

```bash
cd "mac/CraftyCannon"
./build.sh
```

Output:

- `mac/CraftyCannon/dist/CraftyCannon.app`

## Signing (recommended)

macOS privacy permissions (notably Screen Recording) are tied to the app’s signing identity. If you rebuild with a different identity (or ad-hoc), macOS may treat it as a different app and re-prompt.

### 1) Find available signing identities

```bash
security find-identity -v -p codesigning
```

### 2) Build with a specific identity

Pass the identity name to `build.sh`:

```bash
cd "mac/CraftyCannon"
CRAFTYCANNON_CODESIGN_IDENTITY="Developer ID Application: <Your Name> (<TEAMID>)" ./build.sh
```

Notes:

- For local development, `Apple Development: ...` is also fine.
- For stable permission behavior across machines and installs, a consistent identity matters more than which Apple-issued identity you pick.
- If no identity is available, `build.sh` falls back to ad-hoc signing, which is more likely to trigger repeated privacy prompts.

## First Run Permissions

CraftyCannon uses `/usr/sbin/screencapture` for captures. On macOS, region/window capture requires Screen Recording permission.

### Screen Recording

If capture fails or the app prompts repeatedly:

1. Open **System Settings → Privacy & Security → Screen Recording**
2. Enable **CraftyCannon**
3. Quit CraftyCannon completely and relaunch it
   - macOS can require a relaunch after granting Screen Recording

### Reset Screen Recording permission (if the system gets confused)

If you have multiple builds/copies and toggled the wrong one, or permissions got stuck:

```bash
tccutil reset ScreenCapture com.crafty599.craftycannon
```

Then re-enable CraftyCannon in **Screen Recording** and relaunch.

## Troubleshooting

### “It keeps asking again”

Common causes:

- The app isn’t being signed with a stable identity (ad-hoc or identity changed).
- You have multiple copies of the app (e.g. an older `FerretsUploader.app` and `CraftyCannon.app`) and you enabled the wrong entry in System Settings.

Verify the current app signature:

```bash
codesign -dv --verbose=4 "mac/CraftyCannon/dist/CraftyCannon.app" 2>&1 | grep -E "Identifier=|Authority=|TeamIdentifier=|Signature="
```

Expected shape for stable signing:

- `Identifier=com.crafty599.craftycannon`
- `Authority=...` present (not just `Signature=adhoc`)
- `TeamIdentifier=...` present

### Capture still fails after enabling Screen Recording

- Quit and reopen CraftyCannon.
- If it still fails, try resetting Screen Recording permission (above), then grant again.
