import AppKit
import Foundation
import SwiftUI

struct MainHubActions {
  let captureRegionUpload: () -> Void
  let captureWindowUpload: () -> Void
  let captureFullscreenUpload: () -> Void
  let captureTopTaskbarUpload: () -> Void
  let recordScreenUpload: () -> Void
  let captureRegionExpiringUpload: () -> Void
  let uploadClipboardImage: () -> Void
  let uploadImageFile: () -> Void
  let uploadExpiringFile: () -> Void
  let uploadFromURL: () -> Void
  let uploadText: () -> Void
  let uploadFolder: () -> Void
  let shortenURL: () -> Void
  let openWatchFolders: () -> Void
  let openPreferences: () -> Void
  let openScreenshotsFolder: () -> Void
  let chooseScreenshotsFolder: () -> Void
  let resetScreenshotsFolder: () -> Void
  let openLatestInEditor: () -> Void
  let openHistorySection: () -> Void
}

final class MainWindowController: NSWindowController {
  private let hostingController: NSHostingController<ShareXMainShellView>

  init(actions: MainHubActions) {
    self.hostingController = NSHostingController(rootView: ShareXMainShellView(actions: actions))

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1160, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "CraftyCannon"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.minSize = NSSize(width: 900, height: 560)
    window.center()
    window.contentViewController = hostingController
    if let windowIcon = BrandAssets.logoImage(size: NSSize(width: 20, height: 20)) {
      window.standardWindowButton(.documentIconButton)?.image = windowIcon
    }

    super.init(window: window)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
