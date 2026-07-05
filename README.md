# CraftyCannon (macOS menubar client)

CraftyCannon is the macOS menu-bar app. You can capture images or upload content from
clipboard, files, folders, URLs, and text.

## Getting started

Start here for app-specific workflows and preferences. For a full walkthrough, see [USER_GUIDE.md](USER_GUIDE.md).

## Documentation

- [USER_GUIDE.md](USER_GUIDE.md) — step-by-step usage: onboarding, capturing, editing, uploading, redaction, history
- [FEATURES.md](FEATURES.md) — complete feature catalog
- [TOOLS.md](TOOLS.md) — Color Picker, QR Code, Hash Checker, Directory Indexer, OCR search, pinned images, watch folders
- [UPLOAD_BACKENDS.md](UPLOAD_BACKENDS.md) — Zipline/S3 profiles, credential storage, S3 mirroring, Cloudflare allowlist, URL shortener
- [REDACTION.md](REDACTION.md) — Smart Redaction detectors, detection pipeline, policy, and a coordinate-system gotcha worth knowing
- [ARCHITECTURE.md](ARCHITECTURE.md) — technical overview: app structure, state management, persistence, source file map

## What this app can do

- Capture and upload:
  - Region
  - Window
  - Full screen
  - Top taskbar
- Upload from:
  - Clipboard (image/file/folder/URL/text)
  - File picker (images and files)
  - Folder picker
  - URL entry
- Tools:
  - URL shortener
  - Color picker
  - QR code tool
  - Hash checker
  - Directory indexer
  - Clipboard image/file pin tools
- Expiring uploads:
  - Expiring screenshot uploads
  - Expiring file links

## Common shortcuts

- `Cmd+P` — capture region with frozen-state selector, upload, copy URL
- `Cmd+G` — capture region, upload, copy URL
- `Cmd+Shift+G` — capture region, expiring image upload, copy URL + image
- `Cmd+Shift+7` — upload clipboard image, copy URL

## Build and launch

From this folder:

```bash
./build.sh
open ./dist/CraftyCannon.app
```

For a full local release that builds, signs, notarizes, installs into Applications, and restarts the app:

```bash
./release_app.py
```

The release script uses the `craftycannon-notary` keychain profile by default. You can override it with `--notary-profile` or `CRAFTYCANNON_NOTARY_PROFILE`.

For stable screen-recording prompts and signing behavior:

- [docs/SETUP.md](docs/SETUP.md)

For recent app changes:

- [docs/UPDATE_NOTES.md](docs/UPDATE_NOTES.md)

## Where settings and behavior live

- Configure upload backend and credentials in Preferences.
- Use the main app menu for upload options, tools, and after-upload defaults.
- Keep app-specific setup and release notes in `docs/`.

## Output folders

- `dist/releases/` - notarized release zips.
- `dist/backups/` - project archive backups.
