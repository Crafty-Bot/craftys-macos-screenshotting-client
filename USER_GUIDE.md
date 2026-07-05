# User Guide

A walkthrough of day-to-day usage. For a full feature reference see [FEATURES.md](FEATURES.md); for deep dives on specific subsystems see [TOOLS.md](TOOLS.md), [UPLOAD_BACKENDS.md](UPLOAD_BACKENDS.md), and [REDACTION.md](REDACTION.md).

## Installing and launching

```bash
./build.sh
open ./dist/CraftyCannon.app
```

CraftyCannon is a **menu-bar app** — it has no Dock icon. Once running, look for its icon in the macOS menu bar; everything starts from there.

The first time you capture or record the screen, macOS will ask for **Screen Recording** permission (CraftyCannon shells out to `/usr/sbin/screencapture`). If capture fails or keeps re-prompting, see [docs/SETUP.md](docs/SETUP.md) — in short: enable CraftyCannon under System Settings → Privacy & Security → Screen Recording, then fully quit and relaunch the app.

## First run: setup wizard

On first launch with no upload destination configured, CraftyCannon walks you through a short setup flow (a sequence of dialogs, not a dedicated window):

1. **Choose a preset** — Zipline v4, S3-compatible, or Custom. (Cancelling here skips setup entirely; you can configure a destination later from Preferences.)
2. **Enter profile details** — a name, the endpoint URL, and credentials (an API token for Zipline; access key, secret key, region, and bucket for S3).
3. **Validation** — CraftyCannon pings the endpoint to confirm it's reachable before saving. If validation fails, you can retry or go back and fix the details.
4. **Optional secondary S3 mirror** (Zipline setups only) — if CraftyCannon finds AWS CLI credentials at `~/.aws/credentials` / `~/.aws/config`, it offers to set up a secondary S3 mirror using one of those profiles, pre-filling region/endpoint/credentials. This is purely a backup copy — see [UPLOAD_BACKENDS.md](UPLOAD_BACKENDS.md#secondary-s3-mirroring) for what it does and doesn't change about your uploads.

Once a profile is saved, it becomes your active destination and the wizard won't run again.

## Capturing

| Action | Default shortcut | What happens |
|---|---|---|
| Region (frozen-screen selector) | **Cmd+P** | Freezes the screen, lets you drag-select a region, uploads, copies URL |
| Region | **Cmd+G** | Drag-select a region, uploads, copies URL |
| Region, expiring | **Cmd+Shift+G** | Drag-select a region, prompts for an expiry duration, uploads, copies URL (+ image) |
| Upload clipboard | **Cmd+Shift+7** | Inspects clipboard contents and uploads/shortens/copies as appropriate (see below) |
| Window | menu bar only | Click a window to capture it |
| Full screen | menu bar only | Captures everything |
| Top taskbar | menu bar only | Captures the menu bar plus the area below it (useful for screenshotting open dropdown menus) |
| Record screen | menu bar only | Records up to 30 seconds of screen video and uploads the `.mov` |

All shortcuts except Cmd+P are reassignable from Settings → Hotkeys in the main window. None of the capture actions open the image editor automatically — captures upload directly. If you want the editor to open after every capture, turn on **"Open Editor"** under After Capture Tasks in preferences (it opens on the already-uploaded image, so you're touching up a copy, not delaying the upload).

By default, after a successful capture the URL is copied to your clipboard and a notification confirms the upload. You can also configure CraftyCannon to copy the image itself (or both) instead — see After Capture Tasks in Settings.

## Uploading without capturing

The status-bar menu and the main window's Upload section let you push content without taking a screenshot:

- **Clipboard** — image, file, folder, URL, or plain text, auto-detected.
- **File picker** — pick any image or file from disk.
- **Folder picker** — uploads every file in a folder as a batch (or generates a text manifest, depending on the action chosen).
- **URL entry** — type or paste a URL; CraftyCannon downloads it and re-uploads it to your configured destination.
- **Text** — pastes/types straight to a `.txt` file upload.

### What "Upload Clipboard" actually does

Pressing Cmd+Shift+7 (or choosing it from the menu) inspects the clipboard in this priority order:

1. **Image data** present → uploads it as an image.
2. **A file or folder** on the pasteboard → uploads the file, or (if "auto-index folder" is enabled in Clipboard rules) generates and uploads a folder index instead of uploading every file.
3. **Text that looks like a URL** → depending on your Clipboard rules, either shortens it, downloads-and-reuploads it, or just copies it back unchanged.
4. **Plain text** → uploaded as a `.txt` file, if "upload text contents" is enabled.

If nothing matches, you'll see a "Clipboard has no uploadable content" notification.

### Discord paste behavior

If Discord (the desktop app, or discord.com in a browser tab) is frontmost when an upload finishes, CraftyCannon copies the **uploaded URL as text** instead of the raw image bytes — pasting into Discord then shares a link to the already-hosted image instead of triggering Discord to upload a fresh attachment.

## Expiring uploads

Choosing an expiring capture or upload (Cmd+Shift+G for region capture, or the equivalent file action) shows a prompt asking how long the link should stay valid — enter a number and pick a unit (minutes/hours/days), up to a configurable maximum (default ceiling set by your Zipline/S3 profile). Cancel discards the temp file without uploading. Everything else about the upload (clipboard copy, notification, history record) is identical to a normal upload — only the link's expiry differs.

## Editing a capture

Open the editor on the most recent image via the status-bar menu's **"Open Latest Image In Editor"**, or have it open automatically after every capture (After Capture Tasks → Open Editor). The editor offers:

- **Annotation tools**: freehand pen, freehand arrow, highlighter, eraser, smart eraser, straight line, arrow, rectangle (stroked/filled), ellipse, plain/outlined/background/speech-balloon text, numbered step markers, highlight boxes, a magnifying-lens overlay, inserted images (from file or a fresh screen capture), stickers, and a cursor stamp.
- **Destructive tools**: crop, Gaussian blur, pixelate, and CIA-style black box redaction — drag a region and release to apply.
- **Detect Sensitive** — runs Smart Redaction on the current image and pixelates anything it finds (faces, barcodes, emails, API keys, etc.). See [REDACTION.md](REDACTION.md) for the full detector list.
- **Undo/redo** (Cmd+Z / Cmd+Shift+Z, up to 50 steps), zoom (Cmd+= / Cmd+-, 25%–400%), and a "Resize…" dialog with aspect-ratio lock.
- **Save & Upload** (or Return) renders everything into the final image and uploads it as a *new* history entry, leaving the original capture's record untouched.

## Keeping things private: Smart Redaction

Before any upload leaves your machine, CraftyCannon can scan it for faces, barcodes, and a long list of text-based PII (emails, phone numbers, credit card numbers, API keys, AWS/GitHub/OpenAI tokens, private key blocks, session cookies, IP/MAC addresses, file paths, and more). Set the policy in Settings → Advanced → "Before image upload":

- **Off** — no scanning.
- **Ask before upload** (default) — if anything is found, you'll see a summary and can choose to redact-and-upload, upload the original anyway, or cancel.
- **Auto-redact** — redacts automatically, no prompt.

Per-detector toggles, the redaction style (Pixelate or Black box), a confidence threshold, and a fast-vs-accurate OCR mode are all configurable in the same Settings pane. Full details, including exactly which patterns are matched, live in [REDACTION.md](REDACTION.md).

## Utility tools

Reached from the status-bar menu's **Tools** submenu: Color Picker (screen eyedropper + hex/RGBA output), QR Code (generate and decode), Hash Checker (MD5/SHA-1/SHA-256, with checksum verification), Directory Indexer (generates a plain-text folder manifest), and Pin Clipboard Image / Pin Image File (floating always-on-top reference windows). Full walkthrough in [TOOLS.md](TOOLS.md).

## Searching past uploads

Open **"Open History Workspace"** from the status-bar menu to browse every past upload: filter by status (uploaded/failed/uploading/pending) and search by filename, URL, profile, or — if OCR indexing is enabled — **text found inside the image itself**. Selecting a record shows a preview, its S3-mirror status (if configured), OCR status, and action buttons to copy/open the URL, reveal the local file, shorten the URL, re-upload, or edit it again in the editor.

## Configuring CraftyCannon

Two separate places hold settings:

- **Preferences window** (status-bar menu → Preferences, or Cmd+,) — manages upload-destination **profiles**: add/edit/remove Zipline or S3-compatible endpoints, credentials, and the secondary S3 mirror link. This is the only place to add a new destination after onboarding.
- **Main window → Settings rail** — everything else: capture options (cursor, delay, fixed region), after-capture/after-upload behavior, image upload format (PNG, JPEG, GIF, or TIFF), file naming patterns, clipboard rules, watch folders, hotkeys, the URL shortener, the Cloudflare allowlist, appearance/theme, OCR indexing controls, and Smart Redaction.

See [FEATURES.md](FEATURES.md) for the full settings catalog and [UPLOAD_BACKENDS.md](UPLOAD_BACKENDS.md) for backend-specific configuration (Zipline, S3, Cloudflare allowlisting).

## Troubleshooting

- **Capture fails or keeps asking for permission** — see [docs/SETUP.md](docs/SETUP.md). Usually a code-signing-identity or Screen Recording permission issue; quitting and relaunching after granting permission is often required.
- **Upload fails** — check the history record's error message in the History Workspace; the Preferences window's "Validate" button will re-test your endpoint and credentials.
- **"It keeps asking again" for permissions** — likely multiple app copies enabled in System Settings, or an ad-hoc-signed build; see [docs/SETUP.md](docs/SETUP.md) for the reset procedure.
