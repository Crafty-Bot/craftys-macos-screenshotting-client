# Smart Redaction

CraftyCannon can automatically find and pixelate sensitive content in a screenshot before it leaves your machine — faces, barcodes, and a long list of text-based PII. This document covers what it detects, how detection works, the policy options, the settings UI, and a coordinate-system bug that's worth understanding if you touch this code.

## What it detects

`enum RedactionDetectorType` (`SmartRedactionDetector.swift`):

**Visual detectors** (no OCR involved):
- **Faces** — Vision's `VNDetectFaceRectanglesRequest`.
- **Barcodes / QR codes** — Vision's `VNDetectBarcodesRequest`; stores the symbology and a (optionally redacted) payload preview.

**Text/PII detectors** — matched against OCR'd text (Vision `VNRecognizeTextRequest`):

- Email addresses
- Phone numbers
- Credit card numbers (checksum-validated to cut false positives)
- IPv4 and IPv6 addresses
- MAC addresses
- URLs / domains
- Generic API keys and password/secret fields
- Cloud and developer-platform access tokens (AWS, GitHub, OpenAI, and similar)
- Bearer tokens and JWTs
- Private key blocks (PEM-style)
- Session cookies
- Environment variables
- File paths
- Usernames / hostnames

Each category is independently toggleable, with a curated set of defaults tuned to balance catching real PII against false-positive noise — see Settings below to review and adjust which ones are active for your use case.

`Text OCR` is itself a master switch: if it's off, no OCR runs at all and none of the text detectors can fire, regardless of their individual toggles.

When multiple detectors match overlapping text, CraftyCannon keeps the most specific category rather than double-counting the same token under several detectors at once.

## How detection works

`VisionSmartRedactionRecognizer` runs up to three independent Vision passes per image, each gated by your detector settings:

- **OCR** only runs if "Text OCR" is enabled and at least one text detector is enabled. Recognition level is **accurate** or **fast**, your choice (a latency/accuracy tradeoff). Language correction is deliberately turned **off** so Vision doesn't "fix" tokens that aren't real words, and recognition is biased toward catching common credential-like token shapes. Small captures are upscaled before OCR to improve accuracy.
- **Faces** and **Barcodes** each run their own Vision request.

Every observation — text, face, or barcode — is filtered by a single **minimum confidence** threshold (tuned conservatively to favor catching more over missing something) before being counted as a finding.

Matched text is shown in the "ask before upload" prompt as either the full text (if you've enabled "allow raw match previews") or a redacted preview (`[redacted]` for short matches, `prefix...suffix` for longer ones).

Nearby/overlapping findings are padded slightly and merged into single redaction blocks, so a multi-line block of text (like a private key) becomes one redaction region instead of several small ones.

## Policy: when redaction runs

Set under Settings → Advanced → "Before image upload" (`UploadRedactionPolicy`):

- **Off** — no scanning, ever, at upload time.
- **Ask before upload** (default) — scans before every upload; if anything is found, shows a summary (counts per category) and three choices: **Redact & Upload**, **Upload Original**, **Cancel**.
- **Auto-redact** — scans and redacts automatically, no prompt.

This check runs **at upload time**, not at capture time — a raw capture is always saved/copied normally; redaction only intervenes right before content would leave the machine. If detection itself fails (e.g. Vision throws), the upload is blocked rather than silently sent unredacted.

The same detector and processor are also available **on demand** from the image editor's **"Detect Sensitive"** toolbar action (eye-slash icon) — this lets you redact an image you're about to share by any means, not just CraftyCannon's built-in uploader. It runs detection on the current composite, applies the selected redaction style to any findings, and the result becomes the new editable base image (further edits/undo apply on top of it). Unlike the upload-time check, it's entirely manual and has no policy gate.

## Settings

All under Settings → Advanced in the main window (not the Preferences window, which only manages upload profiles):

- **Upload policy picker** — Off / Ask before upload / Auto-redact.
- **"Use black boxes for auto redaction"** toggle — off uses pixelation; on uses solid black boxes.
- **Redaction confidence slider** — adjusts how strict matching is, applied to every Vision observation.
- **"Use fast OCR mode"** toggle — trades accuracy for speed.
- **"Allow raw match previews"** toggle — shows the actual matched text (rather than a masked preview) in the pre-upload prompt.
- **Per-detector toggles**, grouped as Visual detectors, Text detectors, and Additional detectors — review and enable any category relevant to what you typically share.
- **Reset Redaction Defaults** button.

If you regularly share screenshots containing a category that's off by default, turn it on — don't assume every kind of sensitive text is caught out of the box.

## Manual blur/pixelate (the editor's own tools)

Independent of Smart Redaction, the image editor also has plain **Blur**, **Pixelate**, and **Black Redact** tools: drag a region, release, and that region gets Gaussian-blurred, pixelated, or filled with a solid black box. These are useful when you know exactly what to hide and don't need automatic detection. Pixelate and Black Redact share the same underlying rendering path as Smart Redaction (`SmartRedactionImageProcessor`), so the coordinate-system note below applies equally to both.

## Coordinate systems — read this before changing detection or rendering code

This is the single most bug-prone part of the codebase. Two independent, compounding bugs existed here until recently (see the `[Unreleased]` section of [CHANGELOG.md](CHANGELOG.md) and commits `c1e2320`, `69f5997`, `ac9b913`): Smart Redaction and the manual blur/pixelate tools were applying their filter to a **vertically mirrored** region, leaving the actual sensitive content fully visible while pixelating the wrong area.

**Bug 1 — detection-side double-flip.** Vision reports *all* bounding boxes (text, face, barcode) in **normalized, bottom-left-origin** coordinates. The app's internal model (`RedactionBoundingBox`) stores this canonical form and exposes a `topLeftNormalizedRect` that flips Y exactly once (`y' = 1.0 - rect.maxY`). The bug: text observations were being wrapped as if their raw Vision rect were *already* top-left, silently re-flipping (and thus double-flipping) the box. Face and barcode findings were unaffected, since they already went through the correct single-flip path. Fixed by routing text observations through the exact same conversion as faces/barcodes.

**Bug 2 — rendering-side write-back mismatch.** `SmartRedactionImageProcessor.filterRegion` correctly flips Y once when *cropping* the region to pixelate (Core Image is also bottom-left-origin), but was then drawing the pixelated patch back into the bitmap using a separately (and incorrectly) computed Y, rather than reusing the exact same flipped rect it cropped from. Fixed by reusing the crop rect's Y for the write-back.

**Why tests didn't catch this**: the processor's test built its fixture image with a hand-flipped buffer, which happened to mask the mirror. The test was rewritten to exercise the real PNG-load path instead, and the fix was verified against an actual rendered capture, not just unit tests.

**Takeaway for future changes**: this codebase mixes a top-left-origin coordinate space (the editor's overlay model and its AppKit views, which override `isFlipped`) with a bottom-left-origin space (Core Graphics bitmap contexts, Core Image, and every Vision observation). Convert between them **exactly once** per crossing — and when verifying a change here, **look at an actual rendered PNG**, not just test output, since a test can have the same blind spot this one did. See [ARCHITECTURE.md](ARCHITECTURE.md#coordinate-systems-read-this-before-touching-captureeditorredaction-code) for the broader pattern across the app.
