import AppKit
import Foundation
import SwiftUI

enum ClipboardHelper {
  static func copyString(_ s: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(s, forType: .string)
  }

  static func copyImage(_ image: NSImage) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects([image])
  }
}

final class HostingToolWindowController: NSWindowController {
  init(
    title: String,
    subtitle: String? = nil,
    size: NSSize,
    minSize: NSSize? = nil,
    rootView: AnyView
  ) {
    let hosting = NSHostingController(rootView: rootView)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = title
    if let subtitle, !subtitle.isEmpty {
      window.subtitle = subtitle
    }
    window.center()
    window.minSize = minSize ?? NSSize(width: 420, height: 300)
    window.isReleasedWhenClosed = false
    window.contentViewController = hosting

    super.init(window: window)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct NSColorWellView: NSViewRepresentable {
  @Binding var color: NSColor

  func makeCoordinator() -> Coordinator {
    Coordinator(color: $color)
  }

  func makeNSView(context: Context) -> NSColorWell {
    let well = NSColorWell(frame: .zero)
    well.color = color
    well.target = context.coordinator
    well.action = #selector(Coordinator.onColorChange(_:))
    return well
  }

  func updateNSView(_ nsView: NSColorWell, context: Context) {
    if nsView.color != color {
      nsView.color = color
    }
  }

  final class Coordinator: NSObject {
    private var color: Binding<NSColor>

    init(color: Binding<NSColor>) {
      self.color = color
    }

    @objc func onColorChange(_ sender: NSColorWell) {
      color.wrappedValue = sender.color
    }
  }
}

extension NSColor {
  fileprivate func rgbaComponentsSRGB() -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
    guard let c = usingColorSpace(.sRGB) else { return nil }
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    c.getRed(&r, green: &g, blue: &b, alpha: &a)
    return (r, g, b, a)
  }

  fileprivate func toHexByte(_ v: CGFloat) -> Int {
    let clamped = max(0, min(1, v))
    return Int((clamped * 255.0).rounded())
  }

  func hexRGB() -> String {
    guard let c = rgbaComponentsSRGB() else { return "#000000" }
    let r = toHexByte(c.r)
    let g = toHexByte(c.g)
    let b = toHexByte(c.b)
    return String(format: "#%02X%02X%02X", r, g, b)
  }

  func hexRGBA() -> String {
    guard let c = rgbaComponentsSRGB() else { return "#000000FF" }
    let r = toHexByte(c.r)
    let g = toHexByte(c.g)
    let b = toHexByte(c.b)
    let a = toHexByte(c.a)
    return String(format: "#%02X%02X%02X%02X", r, g, b, a)
  }

  func rgbaString() -> String {
    guard let c = rgbaComponentsSRGB() else { return "rgba(0, 0, 0, 1)" }
    let r = toHexByte(c.r)
    let g = toHexByte(c.g)
    let b = toHexByte(c.b)
    let a = Double(max(0, min(1, c.a)))
    return String(format: "rgba(%d, %d, %d, %.3f)", r, g, b, a)
  }
}
