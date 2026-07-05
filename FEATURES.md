# Feature Catalog

A complete, reference-style catalog of everything CraftyCannon does. For task-oriented instructions see [USER_GUIDE.md](USER_GUIDE.md); for implementation detail see [ARCHITECTURE.md](ARCHITECTURE.md), [TOOLS.md](TOOLS.md), [UPLOAD_BACKENDS.md](UPLOAD_BACKENDS.md), and [REDACTION.md](REDACTION.md).

## Capture

Backed by `/usr/sbin/screencapture` (no `AVFoundation`/`ScreenCaptureKit`):

- **Region** — interactive drag-select. Two flavors: live (`-i -s`) and **frozen-state** (`-i -U -J selection`, Cmd+P), which pauses the screen so you can select against a stable frame.
- **Window** — interactive window picker (`-i -w`).
- **Full screen** — captures everything, no extra flags.
- **Top taskbar** — fixed-region capture of the menu bar plus ~600px below it, sized to catch open dropdown menus.
- **Fixed region** — if configured in Settings (ShareX-style), region capture skips the interactive selector and uses a saved rectangle directly (`-R x,y,w,h`).
- **Screen recording** — up to 30 seconds of video (`screencapture -v -V <seconds>`), uploaded as a `.mov`.
- **Capture options**: include cursor, capture delay (0–5s), fixed region (enable + x/y/width/height), info overlay, snap sizes, custom screenshots folder.

None of these open the editor by default — capture uploads directly. Optionally enable "Open Editor" under After Capture Tasks to open the editor on the freshly-uploaded image afterward.

## Editor

Full-featured raster annotation editor (`EditorWindow.swift`), opened on a captured/uploaded image:

**Annotation tools**: pointer (select/move/delete), freehand pen, freehand arrow, highlighter, eraser, smart eraser (deletes any stroke/overlay it touches), straight line, arrow, rectangle (stroked or filled), ellipse, text (plain, outlined, on a background pill, or as a speech balloon with tail), numbered step markers (auto-incrementing), highlight boxes, a live magnifying-lens overlay, inserted images (from file or a fresh screen capture), stickers, and a cursor-glyph stamp.

**Destructive tools** (drag a region, release to apply): crop, Gaussian blur, pixelate, CIA-style black box redaction.

**Other actions**: Fit to Window / Actual Size, Resize… (with aspect-lock), rotate left/right 90°, flip horizontal/vertical, reset step counter, set default sticker text, **Detect Sensitive** (runs Smart Redaction and pixelates findings — see [REDACTION.md](REDACTION.md)).

**Editing mechanics**: undo/redo (Cmd+Z / Cmd+Shift+Z, up to 50 snapshots), zoom 25%–400% (Cmd+= / Cmd+-), Delete/Backspace removes the selected overlay, Escape clears selection. "Save & Upload" (or Return) flattens everything and uploads as a new history record — the original capture's record is untouched.

## Expiring uploads

A modal prompt (numeric value + minutes/hours/days unit picker, capped at a configurable maximum) lets you attach a remote expiry to a region capture (Cmd+Shift+G) or a manually-chosen file. The backend deletes the link once it expires; locally, the upload behaves exactly like a normal one (same clipboard/notification/history behavior).

## Smart Redaction

Vision-framework-backed detector that finds faces, barcodes/QR codes, and ~18 categories of text PII (emails, phone numbers, credit cards, IPv4/IPv6, MAC addresses, URLs/domains, API keys, AWS access keys, GitHub tokens, OpenAI keys, bearer tokens, JWTs, private key blocks, session cookies, password fields, environment variables, file paths, usernames/hostnames) and redacts them with either pixelation or solid black boxes. Runs either on-demand from the editor ("Detect Sensitive") or automatically before upload, per a configurable policy (Off / Ask before upload / Auto-redact). Fully documented in [REDACTION.md](REDACTION.md).

## Upload destinations

- **Zipline v4** — self-hosted file/image host; the default/primary backend.
- **S3-compatible** — any S3-compatible object store (AWS S3, MinIO, Cloudflare R2, etc.), signed with hand-rolled SigV4 (no AWS SDK).
- **Multi-profile support** — switch between any number of saved destinations; per-extension or per-content-kind routing rules can auto-select a profile.
- **Secondary S3 mirroring** — an optional, non-canonical backup copy uploaded alongside a primary Zipline upload.
- **Endpoint validation** — a "Validate" check in Preferences confirms a profile's reachability/credentials before you rely on it.

Full details in [UPLOAD_BACKENDS.md](UPLOAD_BACKENDS.md).

## Utility tools

Color Picker (screen eyedropper + hex/RGBA), QR Code (generate from text, decode from clipboard/file), Hash Checker (MD5/SHA-1/SHA-256 with checksum verification), Directory Indexer (plain-text folder manifest), Pin Clipboard Image / Pin Image File (floating always-on-top viewers). Full walkthrough in [TOOLS.md](TOOLS.md).

## OCR indexing and search

Every uploaded image is OCR'd in the background (Vision, accurate or fast mode) and the extracted text is stored on its history record. The History Workspace's single search box matches filenames, URLs, profile names, status text, **and OCR'd text inside images**, with a highlighted snippet shown for OCR matches. Indexing can be paused/resumed/cancelled/rebuilt/cleared from Settings → Advanced, or scripted via CLI subcommands (`index-existing`, `rebuild-index`, `index-status`, `clear-index`).

## Watch folders

Configure one or more folders for CraftyCannon to poll (every 2 seconds) and auto-upload new or changed files from, once they've been stable (same size/mtime) for at least 1.5 seconds. Each rule has its own path, recursive-subdirectory toggle, extension filter, mode (auto-detect image vs. file, image-only, or file-only), and optional expiry.

## Upload history

Every upload (capture, clipboard, file, folder, URL, text, watch-folder, re-upload) is recorded with status, timestamps, destination profile, remote/local paths, expiry, S3-mirror status, and OCR status/text. Browse, filter by status, search, and act on records (copy/open URL, shorten, reveal in Finder, re-upload, edit, delete the local managed copy) from the History Workspace.

## Cloudflare allowlist automation

Keeps a Cloudflare-managed IP list updated with this Mac's current public IP, so a Cloudflare-protected origin (e.g. a self-hosted Zipline instance) stays reachable as your IP changes across networks. Runs on an interval timer and also reacts immediately to network-path changes (new Wi-Fi, wake on a different connection). Configured under Settings → Cloudflare allowlist. Details in [UPLOAD_BACKENDS.md](UPLOAD_BACKENDS.md#cloudflare-allowlist-automation).

## URL shortener

Shortens any URL via TinyURL or a custom GET-template endpoint you configure. Reachable from the clipboard-dispatch flow (when clipboard text is a URL and "shorten URL" is the active rule) or directly on any history record's URL.

## Themes

Eight built-in palettes (Classic, Nord, Gruvbox, Mono, Mega Dark, **OLED Black** — true-black backgrounds for OLED displays, Rainbow, and a fully user-editable Custom palette), each tinting the main window's rail sections distinctly. An independent "Rainbow overlay" toggle layers animated hue-rotating gradients over any palette. Switch from the status-bar menu's Appearance submenu or Settings → Appearance.

## Notifications

Local notifications confirm or report on: upload success/failure/cancellation, folder upload/index operations, URL shortening, clipboard-dispatch outcomes, copy-to-clipboard confirmations (from every tool), redaction events (both pre-upload and in-editor), and S3-mirror failures. Capture failures and Screen Recording permission errors use blocking alerts instead, since they need immediate user action.

## Hotkeys

Global, system-wide (via Carbon, work even when CraftyCannon isn't focused): Cmd+P (frozen region capture, fixed), Cmd+G (region capture+upload), Cmd+Shift+G (expiring region capture), Cmd+Shift+7 (upload clipboard) — all but Cmd+P are reassignable in Settings → Hotkeys.

## File naming, format, and routing

Customizable upload filename patterns (`{date} {time} {datetime} {rand} {name} {inc}` tokens, auto-increment counter, problematic-character replacement), selectable image upload format (PNG, JPEG, GIF, or TIFF), optional URL regex rewriting, ShareX-style extension-based uploader filters, and per-content-kind (image/file/text/shortener) destination routing overrides.
