import AppKit
import Foundation

enum AppSupport {
  static let appName = "CraftyCannon"

  static func baseDir() throws -> URL {
    let fm = FileManager.default
    let dir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent(appName, isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  static func imagesDir() throws -> URL {
    let dir = try baseDir().appendingPathComponent("Images", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  static func documentsImagesDir() throws -> URL {
    let fm = FileManager.default
    let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let dir = docs.appendingPathComponent("images", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  static func screenshotsDir(preferredPath: String?) throws -> URL {
    let normalized = (preferredPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.isEmpty {
      return try documentsImagesDir()
    }

    let resolvedPath = (normalized as NSString).expandingTildeInPath
    let dir = URL(fileURLWithPath: resolvedPath, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.standardizedFileURL
  }

  static func resolvedScreenshotsDir() throws -> URL {
    do {
      return try screenshotsDir(preferredPath: RuntimePreferences.shared.captureScreenshotsFolderPath)
    } catch {
      return try documentsImagesDir()
    }
  }

  static func historyPath() throws -> URL {
    try baseDir().appendingPathComponent("history.json")
  }

  static func profilesConfigPath() throws -> URL {
    try baseDir().appendingPathComponent("destinations.json")
  }
}

enum BrandAssets {
  private static let logoName = "FerretCannon"
  private static let logoExtension = "png"
  private static let iconBundleName = "AppIcon"
  private static let iconBundleExtension = "icns"

  static func logoImage(size: NSSize? = nil) -> NSImage? {
    if let url = Bundle.main.url(forResource: logoName, withExtension: logoExtension),
       let image = NSImage(contentsOf: url) {
      guard let size else {
        return image
      }
      return image.resized(to: size)
    }

    if let url = Bundle.main.url(forResource: iconBundleName, withExtension: iconBundleExtension),
       let image = NSImage(contentsOf: url) {
      guard let size else {
        return image
      }
      return image.resized(to: size)
    }

    if let appIcon = NSApp.applicationIconImage {
      return size.map { appIcon.resized(to: $0) } ?? appIcon
    }
    return nil
  }

  static func statusBarLogo() -> NSImage? {
    if let logoImage = logoImage(size: NSSize(width: 18, height: 18)) {
      return logoImage
    }
    if let appIcon = NSApp.applicationIconImage {
      return appIcon.resized(to: NSSize(width: 18, height: 18))
    }
    return nil
  }
}

extension NSImage {
  func resized(to targetSize: NSSize) -> NSImage {
    let resizedImage = NSImage(size: targetSize)
    resizedImage.lockFocus()
    draw(
      in: NSRect(origin: .zero, size: targetSize),
      from: NSRect(origin: .zero, size: size),
      operation: .copy,
      fraction: 1.0
    )
    resizedImage.unlockFocus()
    return resizedImage
  }
}

extension NSWindow {
  /// Ensure the window can be resized. Optionally clamp the minimum size to
  /// the current size, since many views in this app are laid out with fixed
  /// frames and can overlap if the window is allowed to shrink too far.
  func ensureResizable(clampMinSizeToCurrent: Bool = false) {
    styleMask.insert(.resizable)

    guard clampMinSizeToCurrent else { return }

    // Only set a minimum if none is already configured. Avoid ever increasing
    // minSize on focus changes, which would prevent users from shrinking later.
    if minSize == .zero {
      minSize = frame.size
    }
  }
}

extension NSAlert {
  /// NSAlert is backed by an NSWindow/NSPanel. Make it resizable so long text
  /// and accessory views can be expanded instead of overlapping/clipping.
  func ensureResizable(clampMinSizeToCurrent: Bool = false) {
    window.ensureResizable(clampMinSizeToCurrent: clampMinSizeToCurrent)
  }
}
