# Windows Parity Checklist

This checklist tracks the 1:1 Windows port against the current macOS app behavior.

## GUI surfaces

- [x] Tray app shell with commands for Open GUI, Open History Workspace, capture, manual/clipboard upload including expiring files, URL shortening, Preferences, and Quit; grouped Capture Options, Tools, Appearance palette, and After Upload task toggles are wired to runtime preferences.
- [x] Initial ShareX-style main window scaffold with rail sections: Capture, Upload, Workflows, Tools, After capture tasks, After upload tasks, Destinations, Settings, History.
- [x] Tray Upload Clipboard command reads live clipboard, loads persisted profile/secrets/preferences, executes the upload workflow when configured, and reports status.
- [x] Dedicated Preferences window for upload profile management with Zipline/S3 fields, active profile selection, secondary S3 mirror selection, validation, and Credential Manager-backed secrets.
- [x] History workspace v1 with searchable/status-filtered upload table, details pane, preferred-URL copy/open, existing-record Shorten, in-place Reupload, local-image Edit, Explorer reveal, and guarded managed-copy delete.
- [x] Editor entry/window shell opens selected or latest local history images with the parity tool catalog, zoomable preview, Pen/freehand strokes, Freehand Arrow, Highlighter, Eraser, Smart Eraser, shape/magnifier/text outline/text background/speech/step/sticker/cursor overlays, pointer selection/delete, undo/redo, composite export, and Save & Upload pipeline.
- [x] Editor annotation tool/style controls and destructive-edit parity slice: Text Outline/Text Background tools, live arrow overlay arrowheads, color/stroke/font/filter-strength controls, Reset Step Counter, and Set Sticker are wired.
- [x] Cached Hash Checker tool window with tray and main-shell entry points.
- [x] Cached Directory Indexer tool window with recursive preview/copy/reveal actions.
- [x] Cached QR Code tool window with generate/copy/save/decode actions.
- [x] Cached Color Picker tool window with palette, screen sampler, and copy formats.
- [x] Multiple pinned always-on-top image windows with clipboard/file entry points, hover copy/close controls, and close cleanup.
- [x] First-run onboarding dialog/wizard with Zipline/S3/custom presets, required-field validation, Zipline endpoint probe, Credential Manager secret storage, profile activation, Preferences fallback on cancel, and pending/completed state.

## Capture

- [x] Region capture with interactive drag overlay, Escape/right-click cancellation, and upload workflow wiring.
- [x] Frozen-state region capture with pre-selection snapshot and cropped frozen PNG output.
- [x] Expiring region capture with expiry prompt and file/expiry upload routing.
- [x] Window capture uses an interactive click-to-select overlay with hover outline, cancellation, DWM visual bounds, and upload workflow wiring.
- [x] Interactive click-to-select window capture overlay.
- [x] Full-screen capture fallback wired to tray/main-window upload workflow.
- [x] Top taskbar capture with top-aligned Windows taskbar bounds plus dropdown depth fallback to top strip.
- [x] Fixed-region capture fallback wired through persisted region-capture preferences.
- [x] Up-to-30-second screen recording with tray/main entry points, capture delay/cursor/fixed-region preferences, screenshots-folder output, and file-upload routing.
- [x] Include cursor option persisted in Preferences and rendered into still captures when enabled.
- [x] Capture delay option in capture contract, persisted preferences, Preferences UI, and still-capture request mapping.
- [x] Basic region size info overlay while dragging.
- [x] Snap-size preference surface and advanced capture overlay affordances: persisted `WIDTHxHEIGHT` presets, configurable region info overlay, Shift-drag snap sizing, crosshair guide lines, and frozen/live overlay support.
- [x] Custom screenshots folder preference with browse/reset-by-empty behavior, custom-or-default `Documents\\images` resolution, dated mirror copies, frontmost-window-aware normalized mirror filenames, and still-capture upload temp cleanup separation.

## Uploads and destinations

- [x] Core clipboard image/file/folder/URL/text dispatch priority and routing rules with macOS-default URL/text/folder settings.
- [x] Local payload classifier distinguishes image files by extension/MIME for upload routing.
- [x] Upload workflow service executes prepared image payloads through upload clients, history, post-upload tasks, and temp cleanup.
- [x] Clipboard image upload is wired from tray through persisted active profile/secrets.
- [x] Manual image file upload wired to Windows main window/tray/profile selection with manual-file upload context.
- [x] Upload workflow service executes prepared generic file payloads with default expiry and history records.
- [x] Clipboard file upload is wired from tray through persisted active profile/secrets.
- [x] Manual generic file upload wired to Windows main window/tray/profile selection.
- [x] Expiring file upload command prompts for up-to-5-day expiry and forces selected files, including images, through the file/expiry path.
- [x] Remote URL payload materialization with HTTP/HTTPS validation, 20s GET, 2xx/empty/150 MiB checks, MIME extension inference, and managed temp output.
- [x] Upload workflow service executes clipboard remote URL upload, raw copy-only URL, and shortener actions.
- [x] Clipboard remote URL upload/share execution is wired from tray through persisted active profile/secrets.
- [x] Manual remote URL upload/share execution wired to Windows main window/tray/profile selection.
- [x] Text upload payload materialization trims text, rejects empty content, and writes managed temp `.txt` files.
- [x] Upload workflow service executes text upload payloads, default expiry, post-upload copy, and safe temp cleanup.
- [x] Clipboard text upload execution is wired from tray when the opt-in clipboard text rule is enabled.
- [x] Manual text upload execution wired to Windows main window/tray/profile selection.
- [x] Folder batch preparation enumerates non-hidden regular files, supports recursive/nonrecursive modes, sorts batch uploads by path, and classifies image/file payloads.
- [x] Folder index preparation writes macOS-format temp manifests with root path, ISO timestamp, relative paths, byte sizes, and no-files marker.
- [x] Upload workflow service executes folder batches with shared batch IDs and folder index uploads as single text payloads.
- [x] Clipboard folder index execution is wired from tray when the opt-in auto-index folder rule is enabled.
- [x] Manual folder batch upload and folder indexing execution wired to Windows main window/tray/profile selection with distinct source kinds.
- [x] Preferences UI can create and edit Zipline v4 profiles including HTTPS endpoint, API token, active profile selection, and secondary S3 mirror selection.
- [x] Zipline v4 backend wired to clipboard, capture fallback, and manual upload UI flows.
- [x] Fakeable Zipline upload client with multipart request, raw Authorization token, expiry header, sanitized filename headers, response parsing, and HEAD validation.
- [x] Zipline endpoint normalization, response parsing, filename header sanitization, and validation classification helpers.
- [x] Preferences UI can create and edit S3-compatible profiles including endpoint, region, bucket, key prefix, path-style/public/signed URL options, access key, secret key, and session token.
- [x] S3-compatible backend wired to clipboard, capture fallback, and manual upload UI flows.
- [x] Fakeable S3 upload client with SigV4 PUT, public/signed/raw return URL selection, and probe PUT plus best-effort DELETE.
- [x] S3 endpoint parsing, safe filename/key generation, object URL building, AWS percent encoding, canonical query sorting, expiry clamping, and SigV4 signing helpers.
- [x] Secondary S3 mirroring wired through workflow options and upload orchestrator.
- [x] Upload orchestrator records secondary S3 mirror pending/uploaded status without replacing the primary URL.
- [x] Zipline HEAD validation and S3 probe validation clients.
- [x] Extension-based uploader filters with Preferences UI add/update/delete controls, normalized extension rules, first-match precedence, persisted runtime settings, and workflow routing.
- [x] Content-kind destination routing Preferences UI for image/file/text/shortener profile picks, plus workflow routing for image/file/text uploads with active-profile fallback and routed secondary S3 mirror preservation.
- [x] URL regex rewriting helper, persisted RuntimePreferences fields, Preferences UI, and upload workflow application with invalid-regex fail-open behavior.
- [x] Upload workflow service can run TinyURL/custom-template shortening and copy the shortened result.
- [x] TinyURL/custom-template URL shortener wired to Windows main window/tray commands, runtime preferences, history records, and clipboard copy.
- [x] Fakeable URL shortener client for TinyURL/custom-template providers.
- [x] TinyURL/custom-template request construction and response parsing helpers.
- [x] Post-upload planner covers copy-image priority, URL fallback, Open URL, capture-only Open Editor, and Discord URL-paste override.
- [x] Post-upload action executor routes copy text/image, Open URL, and Open Editor through platform ports.
- [x] WPF clipboard adapter reads image, file drop-list, URL/plain text and writes text/image on the STA UI thread.
- [x] Windows shell Open URL adapter validates http/https before `UseShellExecute` launch.

## Persistence

- [x] App storage path service for roaming settings, local history/images, temp, and screenshots fallback.
- [x] Runtime preferences snapshot persistence with current redaction/OCR defaults, after-upload copy/open switches, after-capture defaults, clipboard smart rules, default expiry, palette selection, URL rewrite, routing/filter settings, Cloudflare allowlist, hotkeys, capture options including snap sizes/info overlay, and onboarding state.
- [x] Profile metadata JSON persistence.
- [x] Active-profile fallback to a neutral Unconfigured profile.
- [x] Profile export with secrets nulled.
- [x] Profile import with merge/replace mode and opt-in secret import.
- [x] Upload history JSON persistence with insert/update/delete.
- [x] Upload history record model includes secondary S3, OCR, managed local copy, record kind, and operation kind fields.
- [x] Upload history can load wrapped Windows history and raw record arrays.
- [x] Upload history action helpers prefer shortened URLs without replacing original remote URLs and mark reuploads in place.
- [x] Full RuntimePreferences surface, clamping, migration, and remaining settings. Persisted/clamped Windows coverage now includes shortener provider/template, URL regex rewrite, destination routing/filter settings, Cloudflare allowlist, hotkeys, capture options, clipboard smart rules, after-capture defaults, default expiry, palette selection plus custom palette data/editor and WPF shell application, OCR enable, redaction policy, image metadata stripping, image upload format conversion, upload filename pattern/random-name settings, local mirror naming, supported face/QR smart-redaction detector tuning, and onboarding state.
- [x] Profile metadata backup restore, corrupt-primary fallback, raw-array legacy profile migration, legacy single-profile endpoint/API-key migration, and removed-backend fallback to Zipline.

## Security

- [x] API tokens, S3 keys, S3 session tokens, and Cloudflare tokens have a Windows Credential Manager storage implementation.
- [x] Exported profiles null all secret fields.
- [x] Secret-bearing imports are opt-in at the persistence layer.
- [x] Settings/history JSON tests assert profile secrets are not written.
- [x] Redaction policy defaults to Ask before upload.
- [x] Upload blocks image uploads/reuploads when redaction policy requires scanning but Windows smart redaction detection is unavailable, so configured protection does not silently bypass; normal image uploads and reuploads now run face and QR/barcode ask/auto redaction when the detector is available.
- [x] Temp cleanup deletes only canonical files under `%TEMP%` or app-managed directories and rejects reparse-point/symlink/junction escape paths.
- [ ] Release artifacts are Authenticode-signed and timestamped. `Windows\build-release.ps1` now cleans stale publish output, validates production certificate shape, enforces Authenticode signing, RFC 3161 timestamp verification, signature verification, and SHA-256 signed/package manifests for production publish outputs. CI smoke coverage signs/verifies embedded signatures through a temporary test certificate with external timestamping and trust-store import skipped by guarded test-only switches, but this remains unchecked until run with a production certificate for actual release artifacts.

## Editor

- [x] Editor tool catalog covers documented tools.
- [x] Pointer select/move/delete for overlays with one undo checkpoint per drag.
- [x] Pen/freehand drawing with normalized coordinates and rendered export.
- [x] Freehand arrow with live/exported arrowheads.
- [x] Highlighter with alpha-blended ink rendering.
- [x] Eraser as clear-blend ink stroke with rendered export.
- [x] Smart Eraser removes intersecting ink strokes with one undo checkpoint per gesture.
- [x] Line, arrow, rectangle, filled rectangle, ellipse overlays with live preview and rendered export.
- [x] Text, Text Outline, Text Background, and speech balloon overlays with rendered export.
- [x] Numbered step markers with undo-tracked counter state.
- [x] Highlight boxes with alpha fill and rendered export.
- [x] Magnifier overlay with purple drag preview, oval lens rendering, and exported magnification.
- [x] Insert image from file as movable/exported aspect-fit overlay.
- [x] Insert image from screen capture using the current full-screen capture source; interactive region-source selection remains under Capture parity.
- [x] Stickers and cursor stamp.
- [x] Crop, blur, pixelate, black redaction with destructive base-image commits and undo snapshots.
- [x] Resize, rotate, flip with base-image flattening, undo snapshots, and fit-to-view after transforms.
- [x] Redo, Ctrl+Z/Ctrl+Shift+Z, Ctrl+zoom, Escape, and Return Save & Upload keyboard handling.
- [x] Delete/Backspace selected overlay removal with Pointer tool.
- [x] Detect Sensitive editor action pipeline: renders the current composite, applies face and QR/barcode detector findings as pixelate/black-box base-image redaction, clears overlays/strokes, and preserves undo.

## Smart Redaction and OCR

- [x] OCR indexing pipeline after image uploads with pending/indexed/disabled/missing/failed/skipped history states and native Windows OCR text extraction backend wiring.
- [x] OCR admin commands: `index-existing`, `rebuild-index`, `index-status`, `clear-index`.
- [x] History workspace search includes OCR text fields on upload history records.
- [x] Face detection via `Windows.Media.FaceAnalysis`, normalized top-left bounds, minimum-confidence filtering, Preferences toggles, and shared editor/upload detector wiring.
- [x] Barcode/QR detection for editor Detect Sensitive, normal image upload redaction, and image reupload redaction via ZXing QR decoding, normalized top-left redaction bounds, Preferences toggle, and empty-by-default payload previews; the Windows detector combines these findings with native face boxes.
- [x] Redaction detector contract covers current categories with separate IPv4/IPv6 entries.
- [x] Text PII pattern classifier: email, phone, credit card/Luhn, IPv4, IPv6, MAC, URL/domain, API keys, AWS, GitHub, OpenAI, bearer, JWT, private keys, session cookies, password fields, environment variables, file paths, usernames/hostnames, OCR compaction, defaults, and overlap priority.
- [x] Raw match previews remain off by default for face and QR/barcode findings and upload prompts.
- [x] Coordinate tests render real PNG upload-redaction output and assert normalized Y-coordinate placement, with shared BGRA renderer pixel-bound coverage.

## Tools and automation

- [x] Color Picker with eyedropper and hex/RGBA copy formats.
- [x] QR generate, copy, save, decode clipboard, decode file.
- [x] Hash Checker for file/text MD5/SHA-1/SHA-256 with expected-hash comparison and copy actions.
- [x] Core folder index manifest generation for Directory Indexer parity.
- [x] Directory Indexer UI with recursive option, copy text, reveal file.
- [x] Watch folders with recursive/filter/mode/expiry options, persisted rules, timer scan, baseline, stability debounce, dedupe, and upload workflow routing.
- [x] Cloudflare allowlist automation with Credential Manager token storage, Preferences controls, manual update, interval refresh, managed-entry preservation, and network-change refresh.
- [x] Local upload completion/failure notifications with tray fallback and after-upload preference toggle.
- [x] Blocking no-destination/profile, capture failure, and redaction-block alerts.
- [x] Utility/editor local notifications for copy/save/pin failures, editor smart-redaction progress/outcomes, editor render/export/image-capture failures, and S3 mirror failure warnings via tray fallback.
- [x] Global hotkey persistence, Preferences reassignment UI, Windows modifier mapping, Win32 registration, and execution for the four macOS actions.
