# Architecture

A technical overview of how CraftyCannon is put together, for anyone reading or modifying the source.

## App shape

CraftyCannon is a macOS **menu-bar app**: `Resources/Info.plist` sets `LSUIElement = true`, so it has no Dock icon and no app-switcher entry by default. Bundle ID `com.crafty599.craftycannon`, minimum deployment target macOS 13.0 (Ventura), current version `0.1.0`. The project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen); it links `Vision.framework` and `ImageIO.framework` in addition to standard AppKit/SwiftUI frameworks.

The entry point is `AppDelegate` in `Sources/App.swift`. On launch it:

1. Detects whether it's running as the XCTest host (`XCTestConfigurationFilePath`/`XCTestBundlePath` env vars or `XCTestCase` class presence) and, if so, skips the full UI boot (status item, hotkeys, onboarding) so the test runner isn't blocked.
2. Checks `OCRAdminCommands.runIfNeeded(arguments:)` for CLI subcommands (`index-existing`, `rebuild-index`, `index-status`, `clear-index`) — if one matches, it runs synchronously, prints to stdout, and exits before any GUI launches. This gives a scripting path to manage the OCR index without opening the app.
3. Builds the status-bar item and its dropdown menu.
4. Requests notification authorization (`Notifier`).
5. Registers global hotkeys (`HotKeyManager`).
6. Runs first-run onboarding if no upload profile is configured yet.

There is no Dock icon and no traditional "main window that opens on launch" — everything is reached through the status-bar menu, except during onboarding, when the app temporarily switches `NSApp.activationPolicy` to `.regular` so modal alerts can reliably become key.

## Windows and surfaces

| Surface | Controller | Built with | Purpose |
|---|---|---|---|
| Status-bar menu | `AppDelegate` (`App.swift`) | `NSMenu` | Primary entry point: capture/upload commands, Tools submenu, Appearance, After Upload Tasks, Preferences, Quit |
| Main window ("the GUI") | `MainWindowController` (`MainWindow.swift`) | SwiftUI `ShareXMainShellView`, hosted via `NSHostingController` | The full ShareX-style command browser + history workspace (see below) |
| Preferences window | `PreferencesWindowController` (`PreferencesWindow.swift`) | AppKit (no SwiftUI) | **Only** manages upload-destination profiles — Zipline/S3 endpoints, credentials, secondary S3 mirror linkage. Distinct from the main window's "Settings" rail. |
| Editor window | `EditorWindowController` / `EditorCoordinator` (`EditorWindow.swift`, `EditorCoordinator.swift`) | AppKit | Annotate, blur/pixelate, crop, and redact a captured image before re-uploading |
| Tool windows | `ToolsCoordinator` (`ToolsCoordinator.swift`, `ToolWindows.swift`) | SwiftUI hosted in AppKit windows (`HostingToolWindowController`) | Color Picker, QR Code, Hash Checker, Directory Indexer — one cached window instance per tool, reused on reopen |
| Pinned image windows | `PinnedImageWindowController` (`PinnedImageTool.swift`) | AppKit `NSPanel` | Floating always-on-top image viewers; unlike other tools, multiple instances can be open at once |
| Onboarding dialogs | `OnboardingWindow.swift` | Chained `NSAlert.runModal()` calls | First-run setup (no dedicated window — see [USER_GUIDE.md](USER_GUIDE.md)) |

The main window (`ShareXMainShellView`, `Sources/ShareXMainShellView.swift`) is explicitly modeled on ShareX's `MainForm` (the popular Windows screenshot tool) — comments in the source call this out directly. It's a three-pane `HSplitView`:

1. **Command Rail** — fixed list of top-level sections: Capture, Upload, Workflows, Tools, After capture tasks, After upload tasks, Destinations, Settings, History.
2. **Context Tree** — an `OutlineGroup` tree of commands/settings scoped to the selected rail section, filterable via a search field.
3. **Detail Router** — renders the selected leaf node's controls, built from a reusable `ShareXSectionCard` component. Selecting the History section swaps in `UploadHistoryPaneView` instead of the generic renderer.

## State management

There's no single app-wide coordinator object; instead a handful of singletons own specific concerns and notify each other via `NotificationCenter`:

- **`RuntimePreferences.shared`** (`Sources/RuntimePreferences.swift`, ~1000 lines) — the central settings store, backed by `UserDefaults` with versioned keys (`...v1` suffixes). Covers capture options, after-capture/after-upload behavior, file naming, uploader filters, destination routing, clipboard rules, watch folders, hotkeys, Cloudflare allowlist config, theme/palette, OCR toggle, and all redaction detector settings. Every setter diffs old vs. new value and posts `.runtimePreferencesDidChange` (hotkey changes additionally post `.hotKeyPreferencesDidChange`), so the menu bar, main shell view model, watch-folder manager, and Cloudflare manager all resync automatically.
- **`Settings.shared`** (`Sources/Settings.swift`) — thin façade over `ProfileStore.shared` for upload-destination profiles and their Keychain-backed secrets.
- **`ProfileStore`** (`Sources/ProfileStore.swift`) — owns the `[UploadProfile]` array (JSON in `UserDefaults`, mirrored to a backup file via `AppSupport`), active-profile selection, and profile import/export.
- **`MainShellViewModel`** (`ShareXMainViewModel.swift`, `@ObservableObject`) — drives the entire main-window UI. Reads from `RuntimePreferences`/`Settings` on init and on `.runtimePreferencesDidChange`; writes back to `RuntimePreferences` on every `@Published` property's `didSet`, guarded by a re-entrancy flag to prevent feedback loops.
- **`UploadHistoryStore.shared`** (`Sources/UploadHistoryStore.swift`) — persists the upload history array as JSON, serializes mutations on a private queue, posts `.uploadHistoryDidChange`.
- Other singletons: `Uploader.shared` / `UploadService.shared` (upload orchestration), `WatchFolderManager.shared`, `CloudflareAllowlistManager.shared`, `OCRIndexManager.shared`, `Notifier.shared`, `HotKeyManager`, `EditorCoordinator.shared`, `ToolsCoordinator.shared`.

## Persistence

- **`UserDefaults`** — almost all preferences (`RuntimePreferences`), profile metadata (`ProfileStore`, key `upload_profiles_v1`), active profile ID.
- **JSON files under `AppSupport`** (`Sources/AppSupport.swift`) — upload history, and a backup copy of the profiles array (`AppSupport.profilesConfigPath()`) restored automatically if `UserDefaults` is empty or corrupted.
- **Keychain** (`Sources/Keychain.swift`) — every secret: Zipline API tokens, S3 access key/secret/session token, the Cloudflare API token. Never written to `UserDefaults` or the JSON backups (profile export deliberately nulls out secret fields). Each profile's secrets are stored under their own distinct Keychain entry, and items use `kSecAttrAccessibleAfterFirstUnlock` (readable once the Mac has been unlocked since boot — appropriate for a background app that uploads without the user actively present).
- A one-time migration (`ProfileStore.migrateIfNeeded()`) upgrades pre-multi-profile (v0.1.0) installs that used a flat `upload_endpoint` default and a single legacy Keychain service.

## Coordinate systems — read this before touching capture/editor/redaction code

This codebase mixes **three different 2D coordinate conventions**, and mismatches here have caused real bugs (see the `[Unreleased]` section of [CHANGELOG.md](CHANGELOG.md) and commits `c1e2320`, `69f5997`, `ac9b913`, where Smart Redaction and the manual blur/pixelate tools both mirrored their target region vertically).

1. **Editor overlay model** (`OverlayItem`, `InkStroke` in `EditorWindow.swift`) — normalized `0...1`, **top-left origin**.
2. **AppKit drawing views** (`InkView`, `OverlayView`) — both override `isFlipped { true }`, so their local coordinate space is also top-left-origin and matches #1 directly with no flip needed.
3. **Core Graphics bitmap contexts, `CIImage`, and Vision framework observations** — native macOS convention, **bottom-left origin**, y-up. `ImageRaster.swift`'s `makeTopLeftBitmapContext` deliberately does *not* flip the CTM (the comment there warns against it), so every caller that crosses from the overlay model into CG/CI/Vision space must flip manually, exactly once: `(1 - ny) * h` for points, `h - (ry + rh)` for rects.

The historical bug was applying that flip **twice** — once when reading a Vision text observation's bounding box, again when rendering the pixelated patch back into the bitmap — which cancelled out the intended single flip and mirrored the redacted region vertically. Both sites (`SmartRedactionDetector.textObservationBoundingBox` and `SmartRedactionImageProcessor.filterRegion`) now carry explicit comments warning against regressing this. See [REDACTION.md](REDACTION.md) for the full story.

**Rule of thumb for new code:** normalized overlay/editor-view space is top-left; everything touching `CGContext`/`CIImage`/Vision is bottom-left; convert exactly once per crossing, and verify visually against a rendered PNG rather than trusting a unit test alone (a prior test built its fixture image with a hand-flipped buffer that masked this exact bug).

## Frameworks in use

- **AppKit** — virtually all UI except the main window and tool windows, which are SwiftUI hosted via `NSHostingController`.
- **Core Graphics / Core Image** — bitmap compositing, blur/pixelate/crop/rotate/flip.
- **Core Text** — text-overlay rendering in the final exported composite (the live on-screen preview uses simpler `NSString` drawing).
- **Vision** — OCR (`VNRecognizeTextRequest`), face detection (`VNDetectFaceRectanglesRequest`), barcode detection (`VNDetectBarcodesRequest`) — all used by Smart Redaction and the OCR search index.
- **Carbon** (`HotKeys.swift`) — `RegisterEventHotKey`/`InstallEventHandler` for true system-wide global hotkeys (still required on macOS for hotkeys that fire outside the app's own event loop).
- **CryptoKit** — MD5/SHA-1/SHA-256 hashing (Hash Checker tool) and AWS SigV4 request signing (S3 uploads).
- No `AVFoundation`/`ScreenCaptureKit` — capture and screen recording both shell out to `/usr/sbin/screencapture`.

## Threading

- `screencapture` subprocess calls are synchronous (`Process` + `waitUntilExit`); callers dispatch them onto a background queue and hop back to the main queue for UI/`NSImage` work.
- "Detect Sensitive" and OCR indexing use Swift structured concurrency (`Task { ... }`), applying results back via `await MainActor.run { ... }`.
- The editor itself (drawing, undo stack, overlay editing) is entirely main-thread/AppKit-event-driven.
- `OCRIndexManager` batch operations run on a dedicated utility-QoS `DispatchQueue` with pause/resume/cancel support.
- `WatchFolderManager` and `CloudflareAllowlistManager` each run on their own repeating `DispatchSourceTimer`.

## Source file map

| File | Responsibility |
|---|---|
| `App.swift` | App delegate, status-bar menu, hotkey/hub action wiring, onboarding trigger |
| `AppSupport.swift` | Application Support directory paths (history, profile backups, images) |
| `Clipboard.swift` | Clipboard image export helpers |
| `ClipboardUploadDispatcher.swift` | Decides what "Upload Clipboard" should do based on pasteboard contents + rules |
| `CloudflareAllowlistManager.swift` | Keeps a Cloudflare IP list updated with this Mac's public IP |
| `ColorTool.swift` | Color Picker tool |
| `DirectoryIndexerTool.swift` | Directory Indexer tool UI |
| `EditorCoordinator.swift` | Opens/reuses the editor window for a given upload record |
| `EditorWindow.swift` | The full image editor (annotation, crop, blur/pixelate, redaction integration) |
| `ExpiryPrompt.swift` | Modal prompt for expiring-upload duration |
| `FolderIndexer.swift` | Generates plain-text folder manifests (Directory Indexer's logic) |
| `HashCheckerTool.swift` | Hash Checker tool (MD5/SHA-1/SHA-256) |
| `HotKeys.swift` | Global hotkey registration (Carbon) |
| `ImageRaster.swift` | Bitmap context helpers, EXIF-aware upright rasterization |
| `Keychain.swift` | Minimal Security.framework wrapper for secret storage |
| `MainWindow.swift` | Main window controller, `MainHubActions` |
| `Models.swift` | Core data models: `UploadProfile`, `UploadRecord`, enums |
| `Notifications.swift` | `Notifier` — local notification wrapper |
| `OCRAdminCommands.swift` | CLI subcommands for managing the OCR index |
| `OCRIndexManager.swift` | OCRs uploaded images and indexes them for search |
| `OnboardingWindow.swift` | First-run setup flow |
| `PinnedImageTool.swift` | Floating always-on-top pinned image windows |
| `PreferencesWindow.swift` | Upload-profile management window |
| `ProfileStore.swift` | Upload profile persistence, routing, import/export |
| `QRCodeTool.swift` | QR code generate/decode tool |
| `RuntimePreferences.swift` | Central settings store |
| `S3Uploader.swift` | S3-compatible upload, SigV4 signing, endpoint probing |
| `Screenshot.swift` | Wraps `/usr/sbin/screencapture` for captures and screen recording |
| `Settings.swift` | Façade over `ProfileStore` |
| `ShareXMainShellView.swift` | Main window SwiftUI view (rail/tree/detail layout) |
| `ShareXMainViewModel.swift` | Main window view model |
| `SmartRedactionDetector.swift` | Vision-based PII/face/barcode detection |
| `SmartRedactionImageProcessor.swift` | Applies pixelation to detected/selected regions |
| `ToolWindows.swift` | Generic SwiftUI-hosted tool window shell, clipboard helpers |
| `ToolsCoordinator.swift` | Opens/caches tool windows |
| `UIPalette.swift` | Theme definitions (Classic, Nord, Gruvbox, Mono, Mega Dark, OLED Black, Rainbow, Custom) |
| `UploadHistoryPaneView.swift` | Upload history browser UI |
| `UploadHistoryStore.swift` | Upload history persistence |
| `UploadService.swift` | Upload orchestration: redaction checks, profile routing, post-upload tasks |
| `Uploader.swift` | Dispatches to Zipline or S3 upload paths, endpoint validation |
| `URLShortenerService.swift` | TinyURL / custom-template URL shortening |
| `WatchFolderManager.swift` | Polls configured folders and auto-uploads new files |

## Build, test, and CI

```bash
./build.sh              # builds dist/CraftyCannon.app
open ./dist/CraftyCannon.app
```

- `project.yml` defines two targets: `CraftyCannon` (the app) and `CraftyCannonTests` (unit tests, depends on the app target). A shared `CraftyCannon` scheme builds the app and runs tests so `xcodebuild` can discover it reproducibly.
- `Tests/CraftyCannonTests.swift` and `Tests/UIPaletteTests.swift` hold the unit tests — notably including tests for endpoint validation status handling and the redaction coordinate pipeline.
- GitHub Actions CI builds and runs the test suite via `xcodebuild` against the XcodeGen-generated project, and separately verifies the `build.sh` distribution path, on every push and pull request.
- See [docs/SETUP.md](docs/SETUP.md) for code-signing and Screen Recording permission setup, which affects local development.
