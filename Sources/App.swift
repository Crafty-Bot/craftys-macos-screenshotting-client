import AppKit
import Foundation
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private let hotKeys = HotKeyManager()
  private var prefs: PreferencesWindowController?
  private var mainWindow: MainWindowController?
  private var showCursorMenuItem: NSMenuItem?
  private var screenshotDelayMenuItems: [Int: NSMenuItem] = [:]
  private var afterUploadCopyURLMenuItem: NSMenuItem?
  private var afterUploadCopyImageMenuItem: NSMenuItem?
  private var afterUploadOpenURLMenuItem: NSMenuItem?
  private var uiPaletteMenuItems: [UIPaletteID: NSMenuItem] = [:]
  private var uiRainbowOverlayMenuItem: NSMenuItem?
  private var resizableWindowObserver: NSObjectProtocol?

  func applicationDidFinishLaunching(_ notification: Notification) {
    Notifier.shared.requestAuthIfNeeded()

    let needsOnboarding = (!ProfileStore.shared.hasConfiguredProfiles() &&
                           RuntimePreferences.shared.onboardingState == .pending)

    // Menubar-only app (also set in Info.plist via LSUIElement).
    // During first-run onboarding, use a regular activation policy so modal UI
    // (NSAlert runModal) reliably appears and accepts input.
    NSApp.setActivationPolicy(needsOnboarding ? .regular : .accessory)

    // Provide a minimal main menu so standard text editing shortcuts (Cmd+C/V/X/A)
    // work in text fields (notably the API key field in Preferences).
    NSApp.mainMenu = buildMainMenu()

    // User preference: make every window/panel resizable, including NSAlert-backed panels.
    // Apply once for existing windows and then for any future windows that become key.
    for w in NSApp.windows {
      w.ensureResizable()
    }
    resizableWindowObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification,
      object: nil,
      queue: .main
    ) { note in
      (note.object as? NSWindow)?.ensureResizable()
    }

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let btn = statusItem.button {
      if let logoImage = BrandAssets.statusBarLogo() {
        btn.image = logoImage
        btn.image?.isTemplate = false
      } else {
        btn.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "CraftyCannon")
        btn.image?.isTemplate = true
      }
    }

    if let appIcon = BrandAssets.logoImage() {
      NSApp.applicationIconImage = appIcon
    }

    let menu = NSMenu()

    menu.addItem(NSMenuItem(title: "Open the GUI", action: #selector(openMainWindow), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Open History Workspace", action: #selector(openHistoryWorkspace), keyEquivalent: ""))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Capture Region + Upload", action: #selector(captureRegionUpload), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Capture Region + Expiring Upload", action: #selector(captureRegionExpiringUpload), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Capture Window + Upload", action: #selector(captureWindowUpload), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Capture Full Screen + Upload", action: #selector(captureFullUpload), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Capture Top Taskbar + Upload", action: #selector(captureTopTaskbarUpload), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Record Screen (Max 30s) + Upload", action: #selector(recordScreenUpload), keyEquivalent: ""))
    menu.addItem(NSMenuItem.separator())
    addCaptureOptionsMenu(to: menu)
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Upload Clipboard Image", action: #selector(uploadClipboard), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Upload Image File...", action: #selector(uploadFile), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Upload File (Expiring Link)...", action: #selector(uploadAnyFile), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Upload from URL...", action: #selector(uploadFromURL), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Upload Text...", action: #selector(uploadText), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Upload Folder...", action: #selector(uploadFolder), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Shorten URL...", action: #selector(shortenURL), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Watch Folders...", action: #selector(openWatchFolders), keyEquivalent: ""))
    menu.addItem(NSMenuItem.separator())
    addToolsMenu(to: menu)
    menu.addItem(NSMenuItem.separator())
    addAppearanceMenu(to: menu)
    menu.addItem(NSMenuItem.separator())
    addAfterUploadTasksMenu(to: menu)
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openSettingsWindow), keyEquivalent: ","))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

    // Wire targets.
    for item in menu.items {
      item.target = self
    }

    NotificationCenter.default.addObserver(
      forName: .runtimePreferencesDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.refreshRuntimeMenuState()
      WatchFolderManager.shared.applyCurrentPreferences()
      CloudflareAllowlistManager.shared.applyCurrentPreferences()
    }
    NotificationCenter.default.addObserver(
      forName: .hotKeyPreferencesDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.hotKeys.updateBindings(RuntimePreferences.shared.hotKeyBindings)
    }

    refreshRuntimeMenuState()
    statusItem.menu = menu

    hotKeys.onAction = { [weak self] action in
      DispatchQueue.main.async {
        switch action {
        case .captureRegionUpload:
          self?.captureRegionUpload()
        case .captureRegionUploadFrozen:
          self?.captureRegionUploadFrozen()
        case .uploadClipboard:
          self?.uploadClipboard()
        case .captureRegionUploadExpiring:
          self?.captureRegionExpiringUpload()
        }
      }
    }
    hotKeys.install(bindings: RuntimePreferences.shared.hotKeyBindings)

    WatchFolderManager.shared.applyCurrentPreferences()
    CloudflareAllowlistManager.shared.applyCurrentPreferences()

    // Show onboarding and first window on a subsequent run loop turn so modal UI
    // can reliably become key/front during launch.
    DispatchQueue.main.async { [weak self] in
      self?.runOnboardingIfNeeded()
      self?.openMainWindow()

      // Avoid forcing .accessory after an onboarding cancel, as it can cause the
      // just-opened window to disappear in LSUIElement agent configurations.
      if !needsOnboarding {
        NSApp.setActivationPolicy(.accessory)
      }
    }
  }

  private func buildMainMenu() -> NSMenu {
    let main = NSMenu()

    // App menu (required by some system behaviors even for accessory apps).
    let appMenuItem = NSMenuItem()
    main.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenuItem.submenu = appMenu
    appMenu.addItem(withTitle: "Quit CraftyCannon", action: #selector(quit), keyEquivalent: "q").target = self

    // Edit menu: enables standard shortcuts like Cmd+V in NSTextField/NSSecureTextField.
    let editMenuItem = NSMenuItem()
    main.addItem(editMenuItem)
    let editMenu = NSMenu(title: "Edit")
    editMenuItem.submenu = editMenu
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(NSMenuItem.separator())
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    return main
  }

  private func addCaptureOptionsMenu(to menu: NSMenu) {
    let showCursor = NSMenuItem(title: "Show Cursor", action: #selector(toggleShowCursor), keyEquivalent: "")
    showCursor.target = self
    showCursorMenuItem = showCursor
    menu.addItem(showCursor)

    let delayParent = NSMenuItem(title: "Screenshot Delay", action: nil, keyEquivalent: "")
    let delayMenu = NSMenu()
    screenshotDelayMenuItems.removeAll()
    for seconds in 0...5 {
      let item = NSMenuItem(title: "\(seconds) sec", action: #selector(selectScreenshotDelay(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = seconds
      delayMenu.addItem(item)
      screenshotDelayMenuItems[seconds] = item
    }
    delayParent.submenu = delayMenu
    menu.addItem(delayParent)
  }

  private func addAfterUploadTasksMenu(to menu: NSMenu) {
    let parent = NSMenuItem(title: "After Upload Tasks", action: nil, keyEquivalent: "")
    let submenu = NSMenu()

    let copyUrlItem = NSMenuItem(title: "Copy URL to clipboard", action: #selector(toggleAfterUploadCopyURL), keyEquivalent: "")
    copyUrlItem.target = self
    afterUploadCopyURLMenuItem = copyUrlItem
    submenu.addItem(copyUrlItem)

    let copyImageItem = NSMenuItem(title: "Copy image to clipboard", action: #selector(toggleAfterUploadCopyImage), keyEquivalent: "")
    copyImageItem.target = self
    afterUploadCopyImageMenuItem = copyImageItem
    submenu.addItem(copyImageItem)

    let openItem = NSMenuItem(title: "Open URL", action: #selector(toggleAfterUploadOpenURL), keyEquivalent: "")
    openItem.target = self
    afterUploadOpenURLMenuItem = openItem
    submenu.addItem(openItem)

    parent.submenu = submenu
    menu.addItem(parent)
  }

  private func addToolsMenu(to menu: NSMenu) {
    let parent = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
    let submenu = NSMenu()

    let color = NSMenuItem(title: "Color Picker...", action: #selector(openColorPickerTool), keyEquivalent: "")
    color.target = self
    submenu.addItem(color)

    let qr = NSMenuItem(title: "QR Code...", action: #selector(openQRCodeTool), keyEquivalent: "")
    qr.target = self
    submenu.addItem(qr)

    let hash = NSMenuItem(title: "Hash Checker...", action: #selector(openHashCheckerTool), keyEquivalent: "")
    hash.target = self
    submenu.addItem(hash)

    let indexer = NSMenuItem(title: "Directory Indexer...", action: #selector(openDirectoryIndexerTool), keyEquivalent: "")
    indexer.target = self
    submenu.addItem(indexer)

    submenu.addItem(NSMenuItem.separator())

    let pinClipboard = NSMenuItem(title: "Pin Clipboard Image", action: #selector(pinClipboardImageTool), keyEquivalent: "")
    pinClipboard.target = self
    submenu.addItem(pinClipboard)

    let pinFile = NSMenuItem(title: "Pin Image File...", action: #selector(pinImageFileTool), keyEquivalent: "")
    pinFile.target = self
    submenu.addItem(pinFile)

    submenu.addItem(NSMenuItem.separator())

    let editor = NSMenuItem(title: "Open Latest Image In Editor", action: #selector(openLatestInEditor), keyEquivalent: "")
    editor.target = self
    submenu.addItem(editor)

    parent.submenu = submenu
    menu.addItem(parent)
  }

  private func addAppearanceMenu(to menu: NSMenu) {
    let parent = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
    let submenu = NSMenu()

    let paletteParent = NSMenuItem(title: "Palette", action: nil, keyEquivalent: "")
    let paletteMenu = NSMenu()
    uiPaletteMenuItems.removeAll()
    for id in UIPaletteID.allCases {
      let item = NSMenuItem(title: id.displayName, action: #selector(selectUIPalette(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = id.rawValue
      paletteMenu.addItem(item)
      uiPaletteMenuItems[id] = item
    }
    paletteParent.submenu = paletteMenu
    submenu.addItem(paletteParent)

    submenu.addItem(NSMenuItem.separator())

    let rainbow = NSMenuItem(title: "Rainbow overlay", action: #selector(toggleUIRainbowOverlay), keyEquivalent: "")
    rainbow.target = self
    uiRainbowOverlayMenuItem = rainbow
    submenu.addItem(rainbow)

    parent.submenu = submenu
    menu.addItem(parent)
  }

  private func refreshRuntimeMenuState() {
    showCursorMenuItem?.state = RuntimePreferences.shared.captureShowCursor ? .on : .off
    let delay = RuntimePreferences.shared.captureDelaySeconds
    for (seconds, item) in screenshotDelayMenuItems {
      item.state = (seconds == delay) ? .on : .off
    }
    afterUploadCopyURLMenuItem?.state = RuntimePreferences.shared.afterUploadCopyURL ? .on : .off
    afterUploadCopyImageMenuItem?.state = RuntimePreferences.shared.afterUploadCopyImage ? .on : .off
    afterUploadOpenURLMenuItem?.state = RuntimePreferences.shared.afterUploadOpenURL ? .on : .off
    uiRainbowOverlayMenuItem?.state = RuntimePreferences.shared.uiRainbowMode ? .on : .off
    let selected = RuntimePreferences.shared.uiPaletteId
    for (id, item) in uiPaletteMenuItems {
      item.state = (id == selected) ? .on : .off
    }
  }

  private func ensureDestinationConfigured() -> Bool {
    let alert = NSAlert()
    alert.addButton(withTitle: "Open Preferences")
    alert.addButton(withTitle: "Cancel")

    guard ProfileStore.shared.hasConfiguredProfiles() else {
      alert.messageText = "No destination configured"
      alert.informativeText = "Set up a destination profile in Preferences before capturing or uploading."
      NSApp.activate(ignoringOtherApps: true)
      alert.ensureResizable()
      if alert.runModal() == .alertFirstButtonReturn {
        openPreferences()
      }
      return false
    }

    let profile = ProfileStore.shared.activeProfile()
    let endpoint = profile.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: endpoint), url.scheme != nil, url.host != nil else {
      alert.messageText = "No upload endpoint configured"
      alert.informativeText = "Set an upload endpoint for your active destination profile in Preferences, then try again."
      NSApp.activate(ignoringOtherApps: true)
      alert.ensureResizable()
      if alert.runModal() == .alertFirstButtonReturn {
        openPreferences()
      }
      return false
    }

    return true
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  @objc private func toggleShowCursor() {
    RuntimePreferences.shared.captureShowCursor.toggle()
    refreshRuntimeMenuState()
  }

  @objc private func selectScreenshotDelay(_ sender: NSMenuItem) {
    guard let seconds = sender.representedObject as? Int else { return }
    RuntimePreferences.shared.captureDelaySeconds = seconds
    refreshRuntimeMenuState()
  }

  @objc private func toggleAfterUploadCopyURL() {
    RuntimePreferences.shared.afterUploadCopyURL.toggle()
    refreshRuntimeMenuState()
  }

  @objc private func toggleAfterUploadCopyImage() {
    RuntimePreferences.shared.afterUploadCopyImage.toggle()
    refreshRuntimeMenuState()
  }

  @objc private func toggleAfterUploadOpenURL() {
    RuntimePreferences.shared.afterUploadOpenURL.toggle()
    refreshRuntimeMenuState()
  }

  @objc private func selectUIPalette(_ sender: NSMenuItem) {
    guard let raw = sender.representedObject as? String, let id = UIPaletteID(rawValue: raw) else { return }
    RuntimePreferences.shared.uiPaletteId = id
    refreshRuntimeMenuState()
  }

  @objc private func toggleUIRainbowOverlay() {
    RuntimePreferences.shared.uiRainbowMode.toggle()
    refreshRuntimeMenuState()
  }

  @objc private func openPreferences() {
    if prefs == nil {
      prefs = PreferencesWindowController()
    }
    prefs?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func openSettingsWindow() {
    openMainWindow()
    NotificationCenter.default.post(name: .mainHubShowSettings, object: nil)
  }

  @objc private func openMainWindow() {
    if mainWindow == nil {
      mainWindow = MainWindowController(actions: buildMainHubActions())
    }
    mainWindow?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func openColorPickerTool() {
    ToolsCoordinator.shared.openColorPicker()
  }

  @objc private func openQRCodeTool() {
    ToolsCoordinator.shared.openQRCodeTool()
  }

  @objc private func openHashCheckerTool() {
    ToolsCoordinator.shared.openHashChecker()
  }

  @objc private func openDirectoryIndexerTool() {
    ToolsCoordinator.shared.openDirectoryIndexer()
  }

  @objc private func pinClipboardImageTool() {
    ToolsCoordinator.shared.pinClipboardImage()
  }

  @objc private func pinImageFileTool() {
    ToolsCoordinator.shared.pinImageFile()
  }

  @objc private func openHistoryWorkspace() {
    openMainWindow()
    NotificationCenter.default.post(name: .mainHubShowHistory, object: nil)
  }

  @objc private func openWatchFolders() {
    openMainWindow()
    NotificationCenter.default.post(name: .mainHubShowWatchFolders, object: nil)
  }

  private func buildMainHubActions() -> MainHubActions {
    MainHubActions(
      captureRegionUpload: { [weak self] in self?.captureRegionUpload() },
      captureWindowUpload: { [weak self] in self?.captureWindowUpload() },
      captureFullscreenUpload: { [weak self] in self?.captureFullUpload() },
      captureTopTaskbarUpload: { [weak self] in self?.captureTopTaskbarUpload() },
      recordScreenUpload: { [weak self] in self?.recordScreenUpload() },
      captureRegionExpiringUpload: { [weak self] in self?.captureRegionExpiringUpload() },
      uploadClipboardImage: { [weak self] in self?.uploadClipboard() },
      uploadImageFile: { [weak self] in self?.uploadFile() },
      uploadExpiringFile: { [weak self] in self?.uploadAnyFile() },
      uploadFromURL: { [weak self] in self?.uploadFromURL() },
      uploadText: { [weak self] in self?.uploadText() },
      uploadFolder: { [weak self] in self?.uploadFolder() },
      shortenURL: { [weak self] in self?.shortenURL() },
      openWatchFolders: { [weak self] in self?.openWatchFolders() },
      openPreferences: { [weak self] in self?.openPreferences() },
      openScreenshotsFolder: { [weak self] in self?.openScreenshotsFolder() },
      chooseScreenshotsFolder: { [weak self] in self?.chooseScreenshotsFolder() },
      resetScreenshotsFolder: { [weak self] in self?.resetScreenshotsFolder() },
      openLatestInEditor: { [weak self] in self?.openLatestInEditor() },
      openHistorySection: { [weak self] in self?.openHistoryWorkspace() }
    )
  }

  @objc private func captureRegionUpload() {
    guard ensureDestinationConfigured() else { return }
    Task { await self.captureAndUpload(mode: .region) }
  }

  @objc private func captureRegionUploadFrozen() {
    guard ensureDestinationConfigured() else { return }
    Task { await self.captureAndUpload(mode: .region, freezeInteractiveState: true) }
  }

  @objc private func captureRegionExpiringUpload() {
    guard ensureDestinationConfigured() else { return }
    Task { await self.captureAndUploadExpiring(mode: .region) }
  }

  @objc private func captureWindowUpload() {
    guard ensureDestinationConfigured() else { return }
    Task { await self.captureAndUpload(mode: .window) }
  }

  @objc private func captureFullUpload() {
    guard ensureDestinationConfigured() else { return }
    Task { await self.captureAndUpload(mode: .full) }
  }

  @objc private func captureTopTaskbarUpload() {
    guard ensureDestinationConfigured() else { return }
    Task { await self.captureAndUpload(mode: .taskbar) }
  }

  @objc private func recordScreenUpload() {
    guard ensureDestinationConfigured() else { return }
    Task { await self.recordScreenAndUpload(maxDurationSeconds: 30) }
  }

  private func captureModeToken(mode: Screenshotter.Mode) -> String {
    switch mode {
    case .region:
      return "region"
    case .window:
      return "window"
    case .full:
      return "fullscreen"
    case .taskbar:
      return "top-taskbar"
    }
  }

  private func frontmostCaptureAppName() -> String? {
    let appName = NSWorkspace.shared.frontmostApplication?.localizedName?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let appName, !appName.isEmpty else { return nil }
    let lowered = appName.lowercased()
    if lowered.contains("craftycannon") {
      return nil
    }
    return appName
  }

  private func screenshotContext(mode: Screenshotter.Mode) -> String {
    let area = captureModeToken(mode: mode)
    if let appName = frontmostCaptureAppName() {
      return "\(area)-\(appName)"
    }
    return area
  }

  private func localMirrorPrefix(mode: Screenshotter.Mode) -> String {
    if let appName = frontmostCaptureAppName(),
       UploadService.normalizedLocalMirrorPrefix(appName) != nil {
      return appName
    }
    return captureModeToken(mode: mode)
  }

  private func recordingOutputURL() throws -> URL {
    let folder = try AppSupport.resolvedScreenshotsDir()
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    let timestamp = dateFormatter.string(from: Date())
    let randomSuffix = String(UUID().uuidString.prefix(6)).lowercased()
    return folder.appendingPathComponent("recording-\(timestamp)-\(randomSuffix)").appendingPathExtension("mov")
  }

  private func presentBlockingAlert(
    title: String,
    message: String,
    primaryButton: String = "OK",
    secondaryButton: String? = nil,
    onPrimary: (() -> Void)? = nil
  ) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: primaryButton)
    if let secondaryButton {
      alert.addButton(withTitle: secondaryButton)
    }

    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    NSApp.activate(ignoringOtherApps: true)

    let w = alert.window
    w.ensureResizable()
    w.level = .floating
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    w.center()
    w.makeKeyAndOrderFront(nil)

    let resp = alert.runModal()
    NSApp.discardEvents(matching: [.leftMouseUp, .leftMouseDown], before: nil)
    if resp == .alertFirstButtonReturn {
      onPrimary?()
    }
  }

  private func openScreenRecordingPrivacyPane() {
    let candidateURLs = [
      "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
      "x-apple.systempreferences:com.apple.preference.security?Privacy"
    ]
    for value in candidateURLs {
      if let url = URL(string: value), NSWorkspace.shared.open(url) {
        return
      }
    }
  }

  private func captureAndUpload(mode: Screenshotter.Mode, freezeInteractiveState: Bool = false) async {
    do {
      let context = screenshotContext(mode: mode)
      let mirrorPrefix = localMirrorPrefix(mode: mode)
      let fileUrl = try Screenshotter.shared.capture(
        mode: mode,
        options: RuntimePreferences.shared.captureOptions,
        freezeInteractiveState: freezeInteractiveState
      )
      UploadService.shared.enqueueImageUpload(
        fileUrl: fileUrl,
        managedCopy: RuntimePreferences.shared.afterCaptureSaveLocalCopy,
        uploadContext: context,
        localMirrorPrefix: mirrorPrefix,
        sourceKind: .capture
      )
    } catch ScreenshotError.cancelled {
      // silent
    } catch ScreenshotError.screenRecordingPermissionDenied {
      await MainActor.run {
        presentBlockingAlert(
          title: "Screen Recording Permission Required",
          message: "Enable Screen Recording for CraftyCannon in System Settings > Privacy & Security > Screen Recording, then quit and reopen the app.",
          primaryButton: "Open System Settings",
          secondaryButton: "OK",
          onPrimary: { [weak self] in self?.openScreenRecordingPrivacyPane() }
        )
      }
    } catch ScreenshotError.captureFailed(let exitCode) {
      let msg: String
      switch exitCode {
      case -2:
        msg = "Capture did not produce a file. If Screen Recording is already enabled, quit and reopen CraftyCannon. macOS can require a restart after permission changes."
      case -1:
        msg = "Failed to start screencapture."
      case -3:
        msg = "Top taskbar capture is unavailable on this display configuration."
      default:
        msg = "Capture failed (screencapture exit \(exitCode))."
      }
      await MainActor.run {
        presentBlockingAlert(title: "Capture Failed", message: msg)
      }
    } catch {
      await MainActor.run {
        presentBlockingAlert(title: "Capture Failed", message: "Capture failed (\(error))")
      }
    }
  }

  private func captureAndUploadExpiring(mode: Screenshotter.Mode) async {
    do {
      let context = screenshotContext(mode: mode)
      let mirrorPrefix = localMirrorPrefix(mode: mode)
      let fileUrl = try Screenshotter.shared.capture(mode: mode, options: RuntimePreferences.shared.captureOptions)
      // NSAlert must run on the main thread; this task runs off-main.
      let seconds = await MainActor.run {
        ExpiryPrompt.promptSeconds(maxDays: 5, title: "Image expiry", message: "Set expiry time for this screenshot link (maximum 5 days).")
      }
      guard let seconds else {
        try? FileManager.default.removeItem(at: fileUrl)
        return
      }
      UploadService.shared.enqueueExpiringImageUpload(
        fileUrl: fileUrl,
        managedCopy: RuntimePreferences.shared.afterCaptureSaveLocalCopy,
        uploadContext: context,
        localMirrorPrefix: mirrorPrefix,
        expiresSeconds: seconds,
        sourceKind: .capture
      )
    } catch ScreenshotError.cancelled {
      // silent
    } catch ScreenshotError.screenRecordingPermissionDenied {
      await MainActor.run {
        presentBlockingAlert(
          title: "Screen Recording Permission Required",
          message: "Enable Screen Recording for CraftyCannon in System Settings > Privacy & Security > Screen Recording, then quit and reopen the app.",
          primaryButton: "Open System Settings",
          secondaryButton: "OK",
          onPrimary: { [weak self] in self?.openScreenRecordingPrivacyPane() }
        )
      }
    } catch ScreenshotError.captureFailed(let exitCode) {
      let msg: String
      switch exitCode {
      case -2:
        msg = "Capture did not produce a file. If Screen Recording is already enabled, quit and reopen CraftyCannon. macOS can require a restart after permission changes."
      case -1:
        msg = "Failed to start screencapture."
      case -3:
        msg = "Top taskbar capture is unavailable on this display configuration."
      default:
        msg = "Capture failed (screencapture exit \(exitCode))."
      }
      await MainActor.run {
        presentBlockingAlert(title: "Capture Failed", message: msg)
      }
    } catch {
      await MainActor.run {
        presentBlockingAlert(title: "Capture Failed", message: "Capture failed (\(error))")
      }
    }
  }

  private func recordScreenAndUpload(maxDurationSeconds: Int) async {
    do {
      let outputUrl = try recordingOutputURL()
      let recordedFile = try Screenshotter.shared.record(
        maxDurationSeconds: maxDurationSeconds,
        options: RuntimePreferences.shared.captureOptions,
        outputUrl: outputUrl
      )
      UploadService.shared.enqueueFileUpload(
        fileUrl: recordedFile,
        expiresSeconds: RuntimePreferences.shared.defaultFileExpirySeconds,
        sourceKind: .manualFile,
        destinationKind: .file,
        operationKind: .fileUpload
      )
    } catch ScreenshotError.cancelled {
      // silent
    } catch ScreenshotError.screenRecordingPermissionDenied {
      await MainActor.run {
        presentBlockingAlert(
          title: "Screen Recording Permission Required",
          message: "Enable Screen Recording for CraftyCannon in System Settings > Privacy & Security > Screen Recording, then quit and reopen the app.",
          primaryButton: "Open System Settings",
          secondaryButton: "OK",
          onPrimary: { [weak self] in self?.openScreenRecordingPrivacyPane() }
        )
      }
    } catch ScreenshotError.captureFailed(let exitCode) {
      let msg: String
      switch exitCode {
      case -2:
        msg = "Recording did not produce a file. If Screen Recording is already enabled, quit and reopen CraftyCannon."
      case -1:
        msg = "Failed to start screen recording."
      default:
        msg = "Screen recording failed (screencapture exit \(exitCode))."
      }
      await MainActor.run {
        presentBlockingAlert(title: "Recording Failed", message: msg)
      }
    } catch {
      await MainActor.run {
        presentBlockingAlert(title: "Recording Failed", message: "Recording failed (\(error))")
      }
    }
  }

  @objc private func uploadClipboard() {
    guard ensureDestinationConfigured() else { return }
    Task {
      do {
        let action = try ClipboardUploadDispatcher.shared.resolveAction(rules: RuntimePreferences.shared.clipboardRules)
        switch action {
        case .image(let fileURL):
          UploadService.shared.enqueueImageUpload(
            fileUrl: fileURL,
            managedCopy: true,
            uploadContext: "clipboard-image",
            sourceKind: .clipboardImage
          )
        case .file(let fileURL):
          UploadService.shared.enqueueFileUpload(
            fileUrl: fileURL,
            expiresSeconds: RuntimePreferences.shared.defaultFileExpirySeconds,
            sourceKind: .clipboardFileURL
          )
        case .folder(let folderURL):
          UploadService.shared.enqueueFolderIndexUpload(
            folderURL: folderURL,
            includeSubdirectories: true,
            sourceKind: .clipboardFolderURL
          )
        case .remoteURL(let url):
          UploadService.shared.enqueueRemoteURLUpload(urlString: url, sourceKind: .clipboardRemoteURL)
        case .text(let text):
          UploadService.shared.enqueueTextUpload(text: text, sourceKind: .clipboardText)
        case .shortenURL(let url):
          UploadService.shared.shortenURL(urlString: url)
        case .copyURLOnly(let url):
          UploadService.shared.copyRawTextToClipboard(url)
          Notifier.shared.notify(title: "Copied", body: url)
        }
      } catch ClipboardDispatchError.unsupportedClipboardContent {
        Notifier.shared.notify(title: "CraftyCannon", body: "Clipboard has no uploadable content")
      } catch {
        Notifier.shared.notify(title: "CraftyCannon", body: "Clipboard upload failed (\(error.localizedDescription))")
      }
    }
  }

  @objc private func uploadFile() {
    guard ensureDestinationConfigured() else { return }
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true

    var types: [UTType] = [.png, .jpeg, .gif]
    if let webp = UTType(filenameExtension: "webp") {
      types.append(webp)
    }
    panel.allowedContentTypes = types

    panel.begin { resp in
      if resp == .OK, let url = panel.url {
        UploadService.shared.enqueueImageUpload(
          fileUrl: url,
          managedCopy: false,
          uploadContext: "manual-file",
          sourceKind: .manualFile
        )
      }
    }
  }

  @objc private func uploadAnyFile() {
    guard ensureDestinationConfigured() else { return }
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true

    panel.begin { resp in
      if resp == .OK, let url = panel.url {
        DispatchQueue.main.async {
          NSApp.activate(ignoringOtherApps: true)
          guard let seconds = ExpiryPrompt.promptSeconds(
            maxDays: 5,
            title: "File expiry",
            message: "Set expiry time for this file link (maximum 5 days)."
          ) else { return }
          UploadService.shared.enqueueFileUpload(
            fileUrl: url,
            expiresSeconds: seconds,
            sourceKind: .manualFile
          )
        }
      }
    }
  }

  @objc private func uploadFromURL() {
    guard ensureDestinationConfigured() else { return }
    guard let url = promptForSingleLine(
      title: "Upload from URL",
      message: "Enter a public URL to download and upload.",
      placeholder: "https://example.com/image.png"
    ) else {
      return
    }
    UploadService.shared.enqueueRemoteURLUpload(urlString: url, sourceKind: .manualRemoteURL)
  }

  @objc private func uploadText() {
    guard ensureDestinationConfigured() else { return }
    guard let text = promptForText(
      title: "Upload Text",
      message: "Paste or type the text content to upload."
    ) else {
      return
    }
    UploadService.shared.enqueueTextUpload(text: text, sourceKind: .manualText)
  }

  @objc private func uploadFolder() {
    guard ensureDestinationConfigured() else { return }
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.prompt = "Upload"

    panel.begin { resp in
      guard resp == .OK, let folderURL = panel.url else { return }
      UploadService.shared.enqueueFolderUpload(
        folderURL: folderURL,
        includeSubdirectories: true,
        sourceKind: .manualFolderBatch
      )
    }
  }

  @objc private func shortenURL() {
    guard ensureDestinationConfigured() else { return }
    guard let input = promptForSingleLine(
      title: "Shorten URL",
      message: "Enter a URL to shorten.",
      placeholder: "https://example.com/very/long/path"
    ) else {
      return
    }
    UploadService.shared.shortenURL(urlString: input)
  }

  @objc private func openScreenshotsFolder() {
    guard let path = try? AppSupport.resolvedScreenshotsDir() else {
      Notifier.shared.notify(title: "CraftyCannon", body: "Could not open screenshots folder")
      return
    }
    NSWorkspace.shared.open(path)
  }

  private func chooseScreenshotsFolder() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.prompt = "Choose Folder"
    panel.message = "Select where screenshot copies should be written."
    panel.directoryURL = try? AppSupport.resolvedScreenshotsDir()

    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      RuntimePreferences.shared.captureScreenshotsFolderPath = url.path
    }
  }

  private func resetScreenshotsFolder() {
    RuntimePreferences.shared.captureScreenshotsFolderPath = ""
  }

  @objc private func openLatestInEditor() {
    guard let record = UploadHistoryStore.shared.snapshot().first(where: {
      ($0.kind ?? .image) != .file && !$0.localFilePath.isEmpty
    }) else {
      Notifier.shared.notify(title: "CraftyCannon", body: "No local image available to edit")
      return
    }

    EditorCoordinator.shared.openEditor(forRecordId: record.id)
  }

  private func runOnboardingIfNeeded() {
    NSApp.activate(ignoringOtherApps: true)

    // Existing installs with configured profiles skip setup.
    if ProfileStore.shared.hasConfiguredProfiles() {
      RuntimePreferences.shared.onboardingState = .completed
      return
    }

    guard RuntimePreferences.shared.onboardingState == .pending else {
      return
    }

    guard let result = OnboardingWindow.runInitialSetup() else {
      openPreferences()
      return
    }

    if let secondaryS3Profile = result.secondaryS3Profile {
      Settings.shared.upsertProfile(secondaryS3Profile)
      if !result.secondaryS3AccessKeyId.isEmpty {
        try? Settings.shared.setS3AccessKeyId(result.secondaryS3AccessKeyId, profileId: secondaryS3Profile.id)
      }
      if !result.secondaryS3SecretAccessKey.isEmpty {
        try? Settings.shared.setS3SecretAccessKey(result.secondaryS3SecretAccessKey, profileId: secondaryS3Profile.id)
      }
      if !result.secondaryS3SessionToken.isEmpty {
        try? Settings.shared.setS3SessionToken(result.secondaryS3SessionToken, profileId: secondaryS3Profile.id)
      }
    }

    Settings.shared.upsertProfile(result.profile)
    Settings.shared.setActiveProfileId(result.profile.id)
    if result.profile.backend == .s3Compatible {
      if !result.s3AccessKeyId.isEmpty {
        try? Settings.shared.setS3AccessKeyId(result.s3AccessKeyId, profileId: result.profile.id)
      }
      if !result.s3SecretAccessKey.isEmpty {
        try? Settings.shared.setS3SecretAccessKey(result.s3SecretAccessKey, profileId: result.profile.id)
      }
      if !result.s3SessionToken.isEmpty {
        try? Settings.shared.setS3SessionToken(result.s3SessionToken, profileId: result.profile.id)
      }
    } else if !result.apiSecret.isEmpty {
      try? Settings.shared.setApiKey(result.apiSecret, profileId: result.profile.id)
    }
    RuntimePreferences.shared.onboardingState = .completed
  }

  private func promptForSingleLine(title: String, message: String, placeholder: String) -> String? {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")

    let field = NSTextField(string: "")
    field.placeholderString = placeholder
    field.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
    alert.accessoryView = field

    alert.ensureResizable()
    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else { return nil }
    let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }

  private func promptForText(title: String, message: String) -> String? {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "Upload")
    alert.addButton(withTitle: "Cancel")

    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 180))
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder

    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 180))
    textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    scroll.documentView = textView
    alert.accessoryView = scroll

    alert.ensureResizable()
    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else { return nil }
    let value = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}

@main
struct CraftyCannonMain {
  static func main() {
    if OCRAdminCommands.runIfNeeded() {
      return
    }

    let app = NSApplication.shared

    // When the app is launched as the XCTest unit-test host, booting the full
    // menubar UI (status item, global hotkeys, first-run onboarding modal) blocks
    // the main run loop, so the test runner can never attach ("Test runner never
    // began executing tests after launching"). Start a bare run loop instead and
    // let XCTest drive execution.
    if isRunningUnitTests {
      app.setActivationPolicy(.accessory)
      app.run()
      return
    }

    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }

  private static var isRunningUnitTests: Bool {
    let env = ProcessInfo.processInfo.environment
    return env["XCTestConfigurationFilePath"] != nil
      || env["XCTestBundlePath"] != nil
      || NSClassFromString("XCTestCase") != nil
  }
}
