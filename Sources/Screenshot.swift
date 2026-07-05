import Foundation
import Darwin
import CoreGraphics
import AppKit

enum ScreenshotError: Error {
  case cancelled
  case screenRecordingPermissionDenied
  case captureFailed(exitCode: Int32)
}

final class Screenshotter {
  static let shared = Screenshotter()
  private init() {}

  enum Mode {
    case region
    case window
    case full
    case taskbar
  }

  func capture(
    mode: Mode,
    options: CaptureRuntimeOptions = CaptureRuntimeOptions(),
    freezeInteractiveState: Bool = false
  ) throws -> URL {
    if !hasUsableScreenCaptureAccess() {
      throw ScreenshotError.screenRecordingPermissionDenied
    }

    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("CraftyCannon", isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

    let outUrl = tmpDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")

    // /usr/sbin/screencapture:
    // -i: interactive
    // -s: selection
    // -w: window
    // -C: capture cursor
    // -T: delay
    // -x: no sound
    var args: [String] = ["-x"]
    if options.includeCursor {
      args.append("-C")
    }
    if options.delaySeconds > 0 {
      args += ["-T", String(options.delaySeconds)]
    }
    switch mode {
    case .region:
      if let fixedRegion = normalizedFixedRegion(options.fixedRegion) {
        // ShareX-like fixed region mode: capture without interactive selection.
        args += ["-R", "\(fixedRegion.x),\(fixedRegion.y),\(fixedRegion.width),\(fixedRegion.height)"]
      } else {
        if freezeInteractiveState {
          // Interactive toolbar mode pauses the scene so selection can target a frozen frame.
          args += ["-i", "-U", "-J", "selection"]
        } else {
          args += ["-i", "-s"]
        }
      }
    case .window:
      args += ["-i", "-w"]
    case .full:
      break
    case .taskbar:
      if let taskbarRect = taskbarCaptureRect() {
        args += ["-R", "\(taskbarRect.x),\(taskbarRect.y),\(taskbarRect.width),\(taskbarRect.height)"]
      } else {
        throw ScreenshotError.captureFailed(exitCode: -3)
      }
    }
    args.append(outUrl.path)
    return try runScreencapture(args: args, outputUrl: outUrl)
  }

  func record(
    maxDurationSeconds: Int = 30,
    options: CaptureRuntimeOptions = CaptureRuntimeOptions(),
    outputUrl: URL? = nil
  ) throws -> URL {
    if !hasUsableScreenCaptureAccess() {
      throw ScreenshotError.screenRecordingPermissionDenied
    }

    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("CraftyCannon", isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

    let outUrl = outputUrl ?? tmpDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
    try FileManager.default.createDirectory(at: outUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
    let cappedDuration = max(1, min(30, maxDurationSeconds))

    var args: [String] = [
      "-x",
      "-v",
      "-V", String(cappedDuration),
    ]
    if options.includeCursor {
      args.append("-k")
    }
    if options.delaySeconds > 0 {
      args += ["-T", String(options.delaySeconds)]
    }

    if let fixedRegion = normalizedFixedRegion(options.fixedRegion) {
      args += ["-R", "\(fixedRegion.x),\(fixedRegion.y),\(fixedRegion.width),\(fixedRegion.height)"]
    } else {
      // `-i` is not valid with `-v` (video mode). Start in video capture mode instead.
      args += ["-J", "video"]
    }

    args.append(outUrl.path)
    return try runScreencapture(args: args, outputUrl: outUrl)
  }

  private func runScreencapture(args: [String], outputUrl: URL) throws -> URL {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    proc.arguments = args
    let errPipe = Pipe()
    proc.standardError = errPipe

    do {
      try proc.run()
    } catch {
      throw ScreenshotError.captureFailed(exitCode: -1)
    }

    proc.waitUntilExit()

    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    let errStr = String(data: errData, encoding: .utf8) ?? ""

    // Exit code 0 = success, 1 = cancel (commonly)
    if proc.terminationStatus == 1 {
      // screencapture also uses exit code 1 for other failures; try to disambiguate.
      let lowered = errStr.lowercased()
      if isPermissionDeniedError(lowered) || !hasUsableScreenCaptureAccess() {
        throw ScreenshotError.screenRecordingPermissionDenied
      }
      throw ScreenshotError.cancelled
    }
    if proc.terminationStatus != 0 {
      throw ScreenshotError.captureFailed(exitCode: proc.terminationStatus)
    }

    // screencapture can sometimes return before the file is fully materialized.
    // Wait briefly for existence and non-zero size to avoid "file not found" races.
    let fm = FileManager.default
    let deadline = Date().addingTimeInterval(2.0)
    while Date() < deadline {
      if fm.fileExists(atPath: outputUrl.path),
         let attrs = try? fm.attributesOfItem(atPath: outputUrl.path),
         let size = attrs[.size] as? NSNumber,
         size.intValue > 0 {
        break
      }
      usleep(50_000)
    }
    if !fm.fileExists(atPath: outputUrl.path) {
      // If the file never appears, treat as a capture failure (often permission-related).
      throw ScreenshotError.captureFailed(exitCode: -2)
    }

    return outputUrl
  }

  private func hasUsableScreenCaptureAccess() -> Bool {
    // Ask for permission first, then wait briefly for the TCC database to finish updating.
    if CGPreflightScreenCaptureAccess() {
      return true
    }

    let requested = CGRequestScreenCaptureAccess()
    if !requested {
      return false
    }

    let deadline = Date().addingTimeInterval(1.0)
    while Date() < deadline {
      if CGPreflightScreenCaptureAccess() {
        return true
      }
      usleep(100_000)
    }
    return false
  }

  private func isPermissionDeniedError(_ errorText: String) -> Bool {
    return errorText.contains("permission")
      || errorText.contains("not authorized")
      || errorText.contains("not permitted")
      || errorText.contains("screen recording")
      || errorText.contains("operation is not permitted")
  }

  private func normalizedFixedRegion(_ value: CGRect?) -> (x: Int, y: Int, width: Int, height: Int)? {
    guard let value else { return nil }
    // Displays left of or above the main display have negative global
    // coordinates; screencapture -R accepts them, so don't clamp to 0.
    let x = Int(value.origin.x.rounded(.down))
    let y = Int(value.origin.y.rounded(.down))
    let width = max(1, Int(value.size.width.rounded(.toNearestOrAwayFromZero)))
    let height = max(1, Int(value.size.height.rounded(.toNearestOrAwayFromZero)))
    return (x, y, width, height)
  }

  private func taskbarCaptureRect() -> (x: Int, y: Int, width: Int, height: Int)? {
    // Prefer the macOS "main display" (menu bar display) instead of `NSScreen.main`, since this
    // app can run without a key window and `NSScreen.main` may be nil or misleading.
    let mainDisplayID = CGMainDisplayID()
    let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
    let main = NSScreen.screens.first(where: { s in
      guard let n = s.deviceDescription[screenNumberKey] as? NSNumber else { return false }
      return n.uint32Value == mainDisplayID
    }) ?? NSScreen.main

    guard let main else { return nil }

    // When the menu bar is visible, `visibleFrame.maxY` sits below the menu bar and we can derive
    // its height. If the menu bar is set to auto-hide, `visibleFrame` often equals `frame`,
    // so fall back to `NSStatusBar.system.thickness`.
    var menuBarHeight = Int((main.frame.maxY - main.visibleFrame.maxY).rounded(.toNearestOrAwayFromZero))
    var menuBarBottomY = main.visibleFrame.maxY
    if menuBarHeight <= 0 {
      menuBarHeight = Int(NSStatusBar.system.thickness.rounded(.toNearestOrAwayFromZero))
      menuBarBottomY = main.frame.maxY - CGFloat(menuBarHeight)
    }
    if menuBarHeight <= 0 { return nil }

    // Include some area below the menu bar so open dropdown menus are captured too.
    let dropdownExtraHeight = 600
    let yStart = max(main.frame.minY, menuBarBottomY - CGFloat(dropdownExtraHeight))
    let height = Int((main.frame.maxY - yStart).rounded(.toNearestOrAwayFromZero))
    if height <= 0 { return nil }

    return (
      x: Int(main.frame.minX.rounded(.down)),
      y: Int(yStart.rounded(.down)),
      width: Int(main.frame.width.rounded(.toNearestOrAwayFromZero)),
      height: height
    )
  }
}
