# CraftyCannon Windows Port

This folder contains the native Windows port scaffold for CraftyCannon.

The port is intentionally organized around the same behavior boundaries as the macOS app:

- `CraftyCannon.App` - WPF tray app, main ShareX-style shell, dialogs, and window orchestration.
- `CraftyCannon.Core` - shared models, preferences contracts, profile/history persistence, storage paths, and command catalogs.
- `CraftyCannon.Security` - Windows-native secret storage. Current implementation targets Windows Credential Manager.
- `CraftyCannon.Upload` - upload endpoint normalization, Zipline/S3 helpers, URL rewrite, and shortener primitives.
- `CraftyCannon.Capture` - Windows capture and recording services.
- `CraftyCannon.Editor` - annotation/redaction editor contracts and WPF editor surface.
- `CraftyCannon.Ocr` - OCR, barcode, face, and PII redaction contracts.
- `CraftyCannon.Tests` - dependency-free console test runner for core parity/security/upload behavior.

Build:

```powershell
dotnet build .\CraftyCannon.Windows.slnx
```

Run current tests:

```powershell
dotnet run --project .\CraftyCannon.Tests\CraftyCannon.Tests.csproj
```

Implemented foundation slices:

- WPF tray/main shell with the macOS ShareX-style command groups.
- Core profile/history/preference models, including after-upload copy/open preferences, URL shortener and URL regex rewrite settings, Cloudflare allowlist configuration, and first-run onboarding state.
- Credential Manager-backed secret store.
- JSON profile store with redacted export, opt-in secret import, merge/replace import, secret-free metadata backup restore, corrupt-primary fallback, raw-array and single-profile legacy migration, removed-backend fallback to Zipline, and unconfigured active-profile fallback.
- JSON upload history store with wrapper and raw-array loading support, surfaced through a WPF History workspace v1 with existing-record URL shortening, in-place reupload, and local-image edit entry.
- Upload helper layer for Zipline endpoint/response/header parity, S3 key/signing parity, URL rewrite, and shortener request/response parsing.
- Fakeable Zipline, S3, and shortener clients, plus upload history orchestration for primary uploads and secondary S3 mirrors.
- Core clipboard dispatch and post-upload action planning, including Discord URL-paste override, action executor ports, and shortened-URL history preference.
- WPF clipboard adapter, HTTP/HTTPS shell launcher, and tray/main-window Upload Clipboard status wiring.
- Upload payload preparer for local file/image classification, text upload temp files, remote URL temp downloads, folder batch enumeration, and folder index manifests.
- Upload workflow service for clipboard/file/folder/text/remote URL/shortener/reupload execution through upload clients, history, post-upload tasks, batch IDs, URL regex rewriting, normal image upload and reupload face/QR/barcode smart redaction, and safe temp cleanup.
- Tray/main-window clipboard, manual file, expiring manual file, manual URL, URL shortening, manual text, folder batch, folder index, watch folders, Cloudflare allowlist background refresh, full-screen capture, tray capture options, grouped Tools submenu, Appearance palette menu, After Upload task toggles, Color Picker, QR Code, Hash Checker, Directory Indexer, utility/editor local notifications, pinned image windows, and History Workspace execution through persisted profiles, Windows Credential Manager secrets, runtime preferences, and upload history.
- First-run onboarding for Zipline/S3/custom setup, plus Preferences window for Zipline/S3 profile CRUD, active profile selection, Credential Manager secrets, secondary S3 mirrors, URL regex rewrite settings, Cloudflare allowlist controls, clipboard smart rules, after-capture/default-expiry/image-preprocessing/filename-pattern/redaction/OCR/palette preferences, and endpoint validation.
- Storage path service and guarded temp deletion.
- Capture contracts plus full-screen/fixed-region PNG fallback, interactive region/window/top-taskbar/frozen captures, configurable region info overlay, Shift-drag snap-size presets, screenshots-folder mirroring with normalized foreground-window/capture-mode filenames, and bounded screen recording wired to upload.
- Editor and OCR/redaction parity contracts plus the text PII pattern classifier, native face detection, and QR/barcode redaction geometry, plus shared BGRA renderer and real PNG upload-redaction coordinate tests, plus a WPF editor shell for selected/latest history images, Pen/freehand strokes, Freehand Arrow, Highlighter, Eraser, Smart Eraser, line/arrow/shape/highlight/magnifier/text/text-outline/text-background/speech/step/sticker/cursor/image-file/screen-capture-image overlays, destructive crop/blur/pixelate/black-redaction tools, resize/rotate/flip transforms, pointer selection/move/delete, undo/redo, keyboard shortcuts, composite export, Detect Sensitive face/QR/barcode redaction rendering pipeline, upload-time/reupload-time face/QR/barcode redaction with persisted detector toggles and minimum confidence, image metadata stripping/format conversion, and managed Save & Upload of the rendered preview.

Feature work should preserve 1:1 behavior with the macOS documentation in the repository root.
Signed release build:

```powershell
# Store certificate by thumbprint
.\Windows\build-release.ps1 -CertificateThumbprint "THUMBPRINT" -ExpectedPublisherSubject "Your Publisher"

# Or PFX, with password read from CRAFTYCANNON_SIGNING_PFX_PASSWORD unless passed explicitly
.\Windows\build-release.ps1 -CertificatePath "C:\path\codesign.pfx" -ExpectedPublisherSubject "Your Publisher"
```

The release script validates the signing certificate private key, validity window, Code Signing EKU, optional publisher subject, and non-self-signed production status; cleans the publish output; publishes `CraftyCannon.App` without embedded debug symbols unless requested; signs every produced `.exe` and `.dll` with SHA-256 Authenticode; requests and verifies an RFC 3161 timestamp; writes SHA-256 signed-file/package manifests; and only then creates the signed zip under `Windows\dist\artifacts`. Use `-AllowTestCertificate` only for non-production test artifacts.


CI also runs a non-production smoke test that creates a short-lived self-signed Code Signing certificate, trusts it only for the runner user, executes this release script with `-AllowTestCertificate`, and removes the certificate and temporary artifacts afterward.
