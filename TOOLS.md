# Utility Tools

CraftyCannon bundles several small standalone tools, all reachable from the status-bar menu's **Tools** submenu. Each opens as its own floating window; reopening a tool from the menu re-shows the same window instance rather than spawning a duplicate (the exception is Pinned Images, where multiple instances are expected and supported).

## Color Picker

`ColorTool.swift` · window 520×320

- Pick a color via a native color well, or click **"Pick From Screen"** to sample any pixel on screen using the system eyedropper (`NSColorSampler`).
- Outputs three formats simultaneously, each with its own **Copy** button:
  - `#RRGGBB` hex
  - `#RRGGBBAA` hex with alpha
  - `rgba(r, g, b, a)` CSS-style string
- All conversions go through sRGB color space.

## QR Code

`QRCodeTool.swift` · window 720×680

**Generate**: type or paste any text/URL into the input field — the QR image regenerates live on every keystroke (medium error correction). **Copy QR Image** copies it to the clipboard; **Save PNG…** writes it to disk.

**Decode**: two entry points, both using Vision's high-accuracy QR detector —
- **Decode Clipboard Image** — reads whatever image is currently on the pasteboard.
- **Decode Image File…** — pick an image file from disk.

Decoded text appears in an editable field (multiple QR codes in one image are joined by newlines) with its own **Copy Decoded** button. Errors are shown inline ("Clipboard has no image", "No QR code found").

## Hash Checker

`HashCheckerTool.swift` · window 720×620

Computes **MD5, SHA-1, and SHA-256** simultaneously (via CryptoKit) for either:
- A **file** chosen via "Choose File..." — streamed in 1 MB chunks so large files don't need to fit in memory, and
- **Typed/pasted text**, hashed as UTF-8.

Choosing a file takes priority over typed text. Recomputation runs off the main thread and re-fires on every keystroke, with stale in-flight jobs discarded. An optional **"Expected hash"** field is compared case-insensitively against all three computed hashes — the standard "verify a download's checksum" workflow. Each hash has its own Copy button.

## Directory Indexer

`DirectoryIndexerTool.swift` + `FolderIndexer.swift` · window 820×720

Generates a **plain-text manifest** of a folder's contents — file paths and sizes, with a header noting the root path and generation timestamp. Pick a folder, optionally toggle "Include subdirectories", click "Generate Index". The result appears in an editable text view with **Copy Text** and **Reveal File** (opens the generated `.txt` in Finder) buttons.

This tool does **not** read file contents, perform OCR, or build a searchable index — it's a simple listing. For text-searchable indexing of uploaded *images*, see [OCR indexing and search](#ocr-indexing-and-search) below — a related but functionally distinct system, despite the similar name.

## Pinned Image / File

`PinnedImageTool.swift`

Creates a small, borderless, always-on-top floating window showing an image — like a sticky note for a screenshot or reference image. Two ways to create one:

- **Pin Clipboard Image** — pins whatever image is currently on the clipboard.
- **Pin Image File** — pick an image from disk to pin.

Pinned windows stay above normal windows, are visible across Spaces and full-screen apps, and can be dragged anywhere by their background. Hovering reveals **Copy** (puts the image back on the clipboard) and **Close** buttons. Unlike the other tools, you can have several pinned windows open at once, each tracked independently.

## OCR indexing and search

`OCRIndexManager.swift`, `OCRAdminCommands.swift`

Distinct from the Directory Indexer above: this system runs Vision OCR over every **uploaded image** in your history (not arbitrary folders) and stores the extracted text on that upload's history record, so it becomes searchable.

- Runs automatically after each image upload, if **OCR indexing** is enabled (Settings → Advanced).
- Skips re-OCRing a file whose size/modification date haven't changed since it was last indexed (unless a rebuild is forced).
- Batch operations — index only un-indexed/changed images, fully rebuild, or clear the index — are available from Settings → Advanced, with live progress (phase, completed/skipped/failed counts, current filename, ETA) and pause/resume/cancel support.
- **Searching**: the single search field at the top of the History Workspace matches against filename, URL, profile name, status, and OCR'd text together — no separate "search images" UI. A matching record shows a highlighted ~48-character snippet of the matched OCR text in its preview pane, plus an OCR status line ("OCR: indexed N word(s)", "OCR: pending", "OCR: failed", "OCR: local image missing", etc.).
- **CLI access** (no GUI required): launching the app binary with one of `index-existing`, `rebuild-index`, `index-status`, or `clear-index` as the first argument runs that operation synchronously, prints results to stdout, and exits — useful for scripting or automation (e.g. `CraftyCannon rebuild-index` from a terminal/cron job).

## Watch folders

`WatchFolderManager.swift` — configured under Settings, not in the Tools submenu, but documented here as it's a hands-off "tool" in spirit.

A watch folder is a directory CraftyCannon polls every 2 seconds for new or changed files, auto-uploading anything that's been stable (same size and modification time) for at least 1.5 seconds — long enough to avoid uploading a file mid-copy. Each rule configures:

- **Path** and whether to include subdirectories.
- **File filter** (extensions, or `*` for everything).
- **Mode**: auto-detect image vs. generic file, image-only, or file-only.
- **Optional expiry**, applied the same way as a manual expiring upload.

Uploads from a watch folder are tagged with their own source kind in history for traceability, and route through the same redaction/profile-routing/post-upload pipeline as any other upload.

## Upload history viewer

`UploadHistoryPaneView.swift` — opened via the status-bar menu's **"Open History Workspace"**, or by selecting **History** in the main window's command rail.

A two-pane browser: a searchable, status-filterable table on the left (filename, status, URL, and ShareX-style progress columns), and a detail/preview pane on the right showing the selected record's thumbnail, status, S3-mirror status, OCR status and match snippet, and the URL (or error). Action buttons let you **Copy**/**Open** the URL, **Shorten** it, reveal the local file in **Finder**, **Reupload**, **Edit** (reopens the editor), or **Delete** the local copy (only for app-managed copies). Search matches filename, URL, shortened URL, profile, status, error text, S3-mirror URL/error, and OCR'd text all at once.

## Clipboard upload dispatcher (behind the scenes)

`ClipboardUploadDispatcher.swift` — not a tool window, but worth understanding since it powers "Upload Clipboard" (Cmd+Shift+7) and any clipboard-triggered action. It inspects the pasteboard in priority order — image, then file/folder, then URL-shaped text, then plain text — and resolves to exactly one action based on your configured Clipboard rules (upload URL contents, shorten URL, share URL after upload, auto-index folder, upload text contents). See [USER_GUIDE.md](USER_GUIDE.md#what-upload-clipboard-actually-does) for the user-facing behavior.
