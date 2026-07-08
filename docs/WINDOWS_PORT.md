# Windows Port Plan

This is the working implementation plan for a 1:1 Windows port of CraftyCannon's GUI, features, and security behavior.

## Non-negotiable parity targets

- Preserve the tray-first app model: every command must be reachable from the tray menu and the ShareX-style main workspace.
- Preserve the three-pane main workspace: command rail, context tree/list, and detail router.
- Preserve upload behavior across captures, clipboard, files, folders, URLs, text, expiring uploads, reuploads, editor saves, watch folders, and folder indexing.
- Preserve all upload destinations and routing: Zipline v4, S3-compatible, secondary S3 mirroring, extension routing, and content-kind routing.
- Preserve local-only Smart Redaction before upload, including Off / Ask before upload / Auto-redact policy.
- Preserve secret handling: API tokens, S3 keys, S3 session tokens, and Cloudflare tokens must never be written to JSON settings, history, logs, exports, or temp artifacts.
- Preserve profile export behavior: metadata may export, secrets must be nulled.
- Preserve upload history search, including OCR text search.
- Preserve editor tool coverage and coordinate correctness for blur, pixelate, black-box redaction, and Smart Redaction findings.

## Windows implementation choices

- GUI: WPF on .NET, because this app needs mature tray behavior, custom windows, topmost pinned image panels, global hotkeys, and custom editor surfaces.
- Tray: `NotifyIcon` with Windows Forms interop, later wrapped behind an app service.
- Secrets: Windows Credential Manager, user-scoped generic credentials, wrapped by `ISecretStore`.
- Settings/history: JSON under `%APPDATA%\CraftyCannon` or `%LOCALAPPDATA%\CraftyCannon`; never secrets.
- Capture: staged implementation. Full-screen and fixed-region fallback start with GDI capture; region/window/frozen-state capture uses GDI overlays today; recording is wired as bounded MJPEG AVI capture and can later move to Windows Graphics Capture or DXGI Desktop Duplication.
- Hotkeys: Win32 `RegisterHotKey` on a hidden WPF `HwndSource`.
- Clipboard: WPF clipboard APIs plus Win32 format handling where exact image/file/drop-list behavior requires it.
- Notifications: local notification parity through tray/in-app fallback for unpackaged dev builds; native Windows toast packaging remains a release-hardening improvement.
- OCR/redaction: keep the PII detector contract independent. OCR indexing/admin plumbing is wired behind a recognizer abstraction; native extraction uses Windows OCR, `Windows.Media.FaceAnalysis` for faces, and ZXing.Net for QR/barcodes.
- Packaging: `Windows\build-release.ps1` validates the signing certificate, cleans publish output, publishes the WPF app, Authenticode-signs and timestamp-verifies produced executables/libraries with a supplied production certificate, verifies each signature, emits SHA-256 signed-file/package manifests, and creates a signed zip; the CI throwaway-certificate smoke signs/verifies embedded signatures without external timestamping or trust-store import, and installer/MSIX wrapping remains a release distribution choice.

## Current scaffold

The initial Windows solution lives under `Windows/`:

- `CraftyCannon.App`
- `CraftyCannon.Core`
- `CraftyCannon.Security`
- `CraftyCannon.Upload`
- `CraftyCannon.Capture`
- `CraftyCannon.Editor`
- `CraftyCannon.Ocr`
- `CraftyCannon.Tests`

The solution currently includes:

- A WPF main shell with command groups matching the macOS ShareX-style sections.
- A tray icon and tray context menu with Open, Open History Workspace, full-screen capture, clipboard upload, manual upload, URL shortening, Preferences, and Quit commands.
- Core models for upload profiles, S3 config, upload history records, capture modes, and redaction policy.
- A Windows Credential Manager-backed `ISecretStore`.
- JSON profile persistence with secret-redacted export, opt-in secret import, secret-free metadata backup restore, corrupt-primary fallback, raw-array legacy profile migration, legacy single-profile endpoint/API-key migration, and removed-backend fallback to Zipline.
- JSON upload history persistence with secondary S3, OCR, record kind, and operation kind fields in the record model, plus a WPF History workspace v1 for search/filter/details/actions including existing-record shortening, in-place reupload, and local-image edit entry.
- Runtime preference snapshot persistence with redaction/OCR defaults, smart redaction render mode, after-upload copy/open switches, after-capture defaults, clipboard smart rules, default expiry, URL shortener provider/template settings, URL regex rewrite settings, palette selection, custom palette data, Cloudflare allowlist configuration, and first-run onboarding state.
- App storage paths and guarded temp deletion.
- Capture contracts plus full-screen/fixed-region PNG capture fallback.
- Editor tool catalog matching the current documented editor tool list, plus a WPF editor shell for selected/latest history images, normalized Pen/freehand strokes, Freehand Arrow, Highlighter, Eraser, Smart Eraser, line/arrow/shape/highlight/magnifier/text/text-outline/text-background/speech/step/sticker/cursor/image-file/screen-capture-image overlays, destructive crop/blur/pixelate/black-redaction tools, resize/rotate/flip transforms, pointer selection/move/delete, undo/redo, keyboard shortcuts, composite export, Detect Sensitive redaction rendering pipeline, and managed Save & Upload of the rendered preview.
- OCR/redaction detector contracts, text PII pattern classifier matching the current detector categories, OCR indexing service, and OCR admin commands for index/status/clear workflows.
- Upload helper primitives for Zipline endpoint/response/header behavior, S3 key/signing behavior, URL rewrite, and shortener parsing.
- Fakeable Zipline, S3, and shortener clients, plus a primary-upload/secondary-mirror history orchestrator.
- Core clipboard dispatch rules for image/file/folder/URL/text priority, post-upload action planning for copy/open/editor/Discord behavior, and platform-port executor coverage.
- WPF clipboard and shell-open adapters wired to the tray Upload Clipboard scaffold command.
- Upload payload preparer for local file classification, text-to-temp-file upload, remote URL download-to-temp upload with size/status/MIME checks, folder batch enumeration, and folder index manifests.
- Upload workflow service that maps clipboard/file/folder/text/remote URL/shortener/reupload actions into upload clients, history records, post-upload tasks, batch IDs, extension/content-kind destination routing, URL regex rewriting, routed secondary S3 mirroring, upload-time smart redaction for normal image uploads and reuploads, and safe temp cleanup.
- WPF tray/main-window Upload Clipboard, manual file, expiring manual file, manual URL, URL shortening, manual text, folder batch, folder index, capture commands with tray cursor/delay options, grouped Tools submenu, Appearance palette menu, After Upload task toggles, latest-image editor, Color Picker, QR Code, Hash Checker, Directory Indexer, utility/editor local notifications, and History Workspace wiring that loads profile metadata, Credential Manager secrets, runtime preferences, upload history, and executes the workflow when a destination is configured, including selected-record reupload and local-image edit.
- WPF first-run onboarding window for Zipline/S3/custom setup, plus Preferences window for Zipline and S3 profile CRUD, active profile selection, Credential Manager secret editing, secondary S3 mirror selection, extension filters, content-kind destination routing, Cloudflare allowlist token/config/manual update controls, runtime upload image-preprocessing/filename-pattern/capture snap-size/info-overlay/shortener/URL-rewrite/hotkey/clipboard/after-capture/default-expiry/redaction/OCR/palette/custom-palette preferences, and endpoint validation.
- A dependency-free console test runner for core parity/security/upload helper checks.

## Milestones

1. Buildable shell and contracts. Complete.
2. Profile store, settings persistence, history persistence, Credential Manager integration, first-run onboarding, and profile Preferences UI complete; profile metadata backup restore, profile legacy migration, and URL regex rewrite RuntimePreferences are wired; RuntimePreferences surface, clamping, migration defaults, and custom palette data/editor are wired.
3. Zipline and S3 upload ports, including endpoint validation, UI wiring, routing, and secondary S3 mirroring are complete at the app/workflow layer.
4. Clipboard dispatch, manual uploads, routing, and post-upload tasks. Core behavior layer, WPF clipboard/shell adapters, payload preparation, workflow execution, extension filters, content-kind destination routing with Preferences UI, URL regex rewriting, tray/main clipboard execution, manual file/expiring file/URL/text/folder commands, selected-history reupload, grouped tray Tools/Appearance/After Upload toggles, and URL shortener commands through persisted settings/profile/secrets are complete.
5. Capture. Full-screen and fixed-region fallback services exist, and full-screen capture is wired to upload; capture overlay, window capture, top taskbar, frozen-state region, custom screenshots folder, and bounded screen recording are wired.
6. Editor rendering and annotation parity. Editor entry/window shell, Pen/freehand strokes, Freehand Arrow, Highlighter, Eraser, Smart Eraser, simple shape, magnifier, text, speech balloon, step marker, sticker, and cursor stamp overlays, destructive crop/blur/pixelate/black-redaction tools, resize/rotate/flip transforms, pointer selection/move/delete, undo/redo, keyboard shortcuts, composite export, screen-capture image insertion using the current full-screen capture source, Detect Sensitive redaction rendering pipeline, face/QR/barcode detector wiring with persisted face/barcode/minimum-confidence controls, and managed Save & Upload pipeline are wired.
7. Smart Redaction and OCR indexing parity. Text PII classifier parity, editor face/QR/barcode detection/redaction, normal image upload and reupload face/QR/barcode ask/auto redaction, native Windows OCR extraction, and OCR indexing/admin workflows are wired.
8. Utility tools: Color Picker, QR Code, Hash Checker, Directory Indexer, and multiple pinned image windows are wired.
9. Watch folders are wired with persisted rules, stability debounce, and upload workflow routing. Cloudflare allowlist automation is wired with Credential Manager token storage, managed IP-list replacement, interval refresh, network-change refresh, Preferences controls, and utility/editor local notification parity via tray fallback.
10. Signed release packaging and migration/import documentation. Certificate preflight, Authenticode signing/timestamp verification for production, SHA-256 manifest generation, Windows CI build/test gates, and a temporary-cert signed-release CI smoke test are wired; the CI smoke skips external timestamping and trust-store import by guarded test-only switches, and production release still requires an issued code-signing certificate and installer/MSIX decision.

## High-risk areas

- Capture parity: Windows must replicate region, frozen-region, window, full-screen, fixed-region, top-taskbar, and recording behavior currently backed by macOS `screencapture`.
- Redaction/editor coordinates: the port needs one canonical coordinate model and rendered-image verification so sensitive regions are not mirrored or shifted by DPI/origin differences.
- Clipboard formats: core dispatch priority is tested with macOS-default folder/text opt-ins; live Windows clipboard adapters must preserve image, file/folder, URL text, plain text, and Discord/frontmost-app behavior.
- Vision replacement: OCR, face, and barcode confidence/box behavior differs from Apple Vision and must stay normalized behind tests; face and barcode geometry now have focused coverage.
- Secret import/export: exported profiles must omit secrets; imported secret-bearing bundles need an explicit warning and must write only to Credential Manager.
- Temp cleanup: deletion must be restricted to canonical paths under `%TEMP%` or app-managed local directories, with junction/symlink escapes guarded.
- S3 SigV4: .NET URI escaping must not alter canonical request behavior for spaces, plus signs, endpoint base paths, session tokens, or custom ports.

## Verification gates

- `dotnet build Windows/CraftyCannon.Windows.slnx` must pass before merging Windows work.
- `dotnet run --project Windows/CraftyCannon.Tests/CraftyCannon.Tests.csproj` must pass for core persistence/security/upload helper work.
- Unit tests must cover profile secret export, Credential Manager storage boundaries, S3 SigV4 signing, endpoint validation, upload routing, clipboard dispatch priority, post-upload copy/open planning, file naming tokens, temp cleanup path safety, and watch-folder debounce.
- Visual tests must cover the main workspace, preferences, editor, history, tool windows, and pinned image windows.
- Redaction tests include real PNG upload-redaction output coverage for normalized Y-coordinate placement and shared BGRA renderer pixel-bound checks; broader visual coverage is still needed for editor/manual blur, pixelate, and black redaction flows plus future OCR detections.
