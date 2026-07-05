# Changelog

All notable changes to CraftyCannon are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Smart Redaction can now render detected regions as either pixelation or solid
  black boxes. Settings -> Advanced includes a `Use black boxes for auto
  redaction` toggle; leaving it off keeps the existing pixelated behavior.
- The editor includes a manual `Black Redact` destructive tool for dragging a
  CIA-style black box over known-sensitive regions.
- Image upload preparation can strip metadata before upload and transcode images
  to a selected output format: PNG, JPEG, GIF, or TIFF.
- Added `release_app.py`, a local release helper that builds, signs, notarizes,
  installs, and restarts CraftyCannon.

### Changed
- Upload-time auto-redaction and the editor's `Detect Sensitive` action now use
  the shared redaction render-mode preference.
- Image upload preparation now tracks temporary prepared files consistently
  across redaction, metadata stripping, transcoding, re-upload, local mirroring,
  post-upload tasks, and secondary S3 copies.
- File naming previews now reflect the selected image upload format extension.
- Zipline uploads send `x-zipline-filename` and `x-zipline-file-extension`
  headers derived from CraftyCannon's sanitized upload filename.
- Updated feature, user-guide, redaction, and README documentation for black-box
  redaction, image format controls, metadata stripping, and release automation.

### Tests
- Added coverage for black-box redaction placement and temporary PNG rendering.
- Added coverage for image metadata stripping, EXIF orientation normalization,
  upload format transcoding, and Zipline filename headers.

### Fixed
- Smart Redaction and the manual blur/pixelate tools applied the filter to a
  vertically **mirrored** region, leaving the sensitive content visible. Two
  separate bugs compounded here:
  - **Detection:** Vision reports text observation bounding boxes in
    bottom-left-origin coordinates (like faces and barcodes), but they were
    treated as top-left, double-flipping the box.
  - **Rendering:** `filterRegion` drew the filtered patch into the y-up bitmap
    context using a raw top-left `y`, mirroring it vertically.
  Both are fixed; the redaction now lands on the detected/selected region.
  Verified end-to-end against a rendered email capture, and the processor test
  now exercises the real PNG-load path (the previous test built its image with a
  hand-flipped buffer that masked the mirror).

### Build
- Add GitHub Actions CI that builds and runs the test suite via `xcodebuild`
  (XcodeGen-generated project) and verifies the `build.sh` distribution path on
  every push and pull request.
- Define an explicit shared `CraftyCannon` scheme in `project.yml` so the test
  target is reproducibly discoverable by `xcodebuild`.

## [0.2.0] - 2026-06-27

### Added
- **Smart Redaction** — a Vision/ImageIO-backed detector that finds sensitive
  regions in a capture and pixelates them. Detects faces, barcodes, and a wide
  range of text PII via OCR: email addresses, phone numbers, credit card
  numbers, IPv4/IPv6 and MAC addresses, URLs/domains, API keys, AWS access keys,
  GitHub tokens, OpenAI keys, bearer tokens, JWTs, private-key blocks, session
  cookies, password fields, environment variables, file paths, and
  usernames/hostnames.
- **"Detect Sensitive" editor action** that runs detection on the current image
  and applies redactions in place.
- **Upload redaction policy** (`Off`, `Ask before upload`, `Auto-redact`) so
  captures can be scanned and redacted before they leave the machine.
- **Redaction settings UI**: per-detector toggles, a minimum-confidence slider,
  a fast-OCR mode, an option to allow raw match previews, and a reset-to-defaults
  control.
- Persisted redaction detector settings and upload policy in runtime preferences.

### Build
- Link `ImageIO.framework` (build script and Xcode project) for redaction image
  handling.

## [0.1.0]

### Added
- Initial CraftyCannon snapshot: screen capture, image editor, and upload
  destinations.
- Local OCR indexing and search.
- OLED theme and Zipline S3 mirroring.
- AWS CLI S3 mirror onboarding.
- Cloudflare allowlist automation and endpoint validation.
- Paste links for Discord targets.

[Unreleased]: https://github.com/OWNER/CraftyCannon/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/OWNER/CraftyCannon/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/OWNER/CraftyCannon/releases/tag/v0.1.0
