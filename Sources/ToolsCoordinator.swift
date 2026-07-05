import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class ToolsCoordinator {
  static let shared = ToolsCoordinator()
  private init() {}

  private var colorTool: NSWindowController?
  private var qrTool: NSWindowController?
  private var hashTool: NSWindowController?
  private var directoryIndexerTool: NSWindowController?
  private var pinned: [String: PinnedImageWindowController] = [:]

  func openColorPicker() {
    if colorTool == nil {
      colorTool = HostingToolWindowController(
        title: "Color Picker",
        subtitle: "Palette + screen sampler",
        size: NSSize(width: 520, height: 320),
        minSize: NSSize(width: 480, height: 300),
        rootView: AnyView(ColorToolView())
      )
    }
    show(colorTool)
  }

  func openQRCodeTool() {
    if qrTool == nil {
      qrTool = HostingToolWindowController(
        title: "QR Code",
        subtitle: "Generate + decode",
        size: NSSize(width: 720, height: 680),
        minSize: NSSize(width: 640, height: 560),
        rootView: AnyView(QRCodeToolView())
      )
    }
    show(qrTool)
  }

  func openHashChecker() {
    if hashTool == nil {
      hashTool = HostingToolWindowController(
        title: "Hash Checker",
        subtitle: "MD5 / SHA-1 / SHA-256",
        size: NSSize(width: 720, height: 620),
        minSize: NSSize(width: 640, height: 520),
        rootView: AnyView(HashCheckerToolView())
      )
    }
    show(hashTool)
  }

  func openDirectoryIndexer() {
    if directoryIndexerTool == nil {
      directoryIndexerTool = HostingToolWindowController(
        title: "Directory Indexer",
        subtitle: "Folder -> index text file",
        size: NSSize(width: 820, height: 720),
        minSize: NSSize(width: 720, height: 620),
        rootView: AnyView(DirectoryIndexerToolView())
      )
    }
    show(directoryIndexerTool)
  }

  func pinClipboardImage() {
    do {
      let url = try ClipboardImageExporter.shared.exportPngToTemp()
      guard let image = NSImage(contentsOf: url) else {
        Notifier.shared.notify(title: "Pin failed", body: "Failed to load clipboard image")
        return
      }
      pin(image: image)
    } catch {
      Notifier.shared.notify(title: "Pin failed", body: "Clipboard has no image")
    }
  }

  func pinImageFile() {
    let panel = NSOpenPanel()
    panel.title = "Choose Image"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [UTType.image]

    panel.begin { resp in
      guard resp == .OK, let url = panel.url else { return }
      guard let image = NSImage(contentsOf: url) else {
        Notifier.shared.notify(title: "Pin failed", body: "Failed to load image")
        return
      }
      DispatchQueue.main.async {
        self.pin(image: image, title: url.lastPathComponent)
      }
    }
  }

  private func pin(image: NSImage, title: String = "Pinned") {
    let wc = PinnedImageWindowController(image: image, title: title) { [weak self] id in
      self?.pinned.removeValue(forKey: id)
    }
    pinned[wc.id] = wc
    wc.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func show(_ wc: NSWindowController?) {
    wc?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
