# Changes Since Last Commit

Base commit: `a1694ca Fix review findings across capture/upload pipeline; add random filenames and docs`

Generated: 2026-07-05

## Summary

- 15 tracked files modified, plus 2 untracked files.
- Tracked diff size is approximately 850+ insertions and 59 deletions after the changelog entry.
- Main themes: auto-redaction style control, black-box redaction support, upload image preparation controls, Zipline filename headers, release automation, and expanded tests/docs.

## User-Facing Changes

### Smart redaction can use black boxes

- Added a `SmartRedactionRenderMode` setting with pixelation as the default and black-box rendering as the alternate mode.
- Added a Settings -> Advanced checkbox: `Use black boxes for auto redaction`.
- Auto-redaction now applies the selected style before upload.
- The editor's `Detect Sensitive` action now uses the same selected redaction style.
- The manual editor toolbox now includes `Black Redact`, a destructive drag-to-apply solid black box tool.

### Image upload preparation controls

- Added optional image metadata stripping before upload.
- Added selectable image upload format support: PNG, JPEG, GIF, and TIFF.
- File naming preview now reflects the selected image upload format extension.
- Image upload preparation now tracks whether a temporary prepared file was created, so redacted, metadata-stripped, or transcoded files are preserved or cleaned up consistently.
- Re-upload flow now uses the prepared image file for mirroring, upload, post-upload tasks, and secondary S3 copies.

### Zipline filename preservation

- Zipline uploads now send `x-zipline-filename` and `x-zipline-file-extension` headers derived from the sanitized upload filename.
- This helps keep server-side generated names aligned with CraftyCannon's chosen filename.

### Release automation

- Added `release_app.py`, a full local release helper for building, signing, notarizing, installing, and restarting CraftyCannon.
- Documented the release script in `README.md`, including the default `craftycannon-notary` profile and override options.

## Implementation Notes

### Redaction rendering

- `SmartRedactionImageProcessor.redactedTemporaryPNG` now accepts a render mode.
- Added `SmartRedactionImageProcessor.redactedImage(...)` to route between pixelation and black-box rendering.
- Added `blackBoxedImage(...)` and a shared black fill path using the same top-left normalized redaction coordinates.
- Upload-time and editor-time smart redaction both read `RuntimePreferences.shared.smartRedactionRenderMode`.

### Runtime preferences and UI state

- Added persisted keys for:
  - Smart redaction render mode.
  - Strip image metadata before upload.
  - Image upload format.
- Added matching `MainShellViewModel` published properties and sync logic.
- Added UI controls in the main Settings rail for metadata stripping, image format selection, and black-box auto redaction.

### Image processing

- Added `ImageUploadTranscoder` for temporary format conversion.
- Added `ImageUploadMetadataStripper` for temporary metadata-stripped image copies.
- JPEG conversion uses an opaque white background when needed.
- GIF metadata stripping is skipped to avoid flattening or damaging animated content.

## Tests Added Or Expanded

- Black-box redaction lands on the intended top-left normalized region.
- Temporary PNG redaction supports black-box mode.
- Metadata stripping removes EXIF, GPS, and TIFF metadata.
- Metadata stripping normalizes EXIF orientation.
- Image upload transcoding writes the selected output format.
- Zipline filename headers are derived from sanitized filenames.

Verification run:

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -scheme CraftyCannon -project CraftyCannon.xcodeproj -derivedDataPath .build/DerivedData
```

Result: 56 tests passed, 0 failures.

Also checked:

```bash
git diff --check
```

Result: no whitespace errors.

## Changed Files

### Modified tracked files

- `CHANGELOG.md`
- `FEATURES.md`
- `README.md`
- `REDACTION.md`
- `USER_GUIDE.md`
- `Sources/EditorWindow.swift`
- `Sources/ImageRaster.swift`
- `Sources/Models.swift`
- `Sources/RuntimePreferences.swift`
- `Sources/ShareXMainShellView.swift`
- `Sources/ShareXMainViewModel.swift`
- `Sources/SmartRedactionImageProcessor.swift`
- `Sources/UploadService.swift`
- `Sources/Uploader.swift`
- `Tests/CraftyCannonTests.swift`

### Untracked files

- `CHANGES_SINCE_LAST_COMMIT.md`
- `release_app.py`
