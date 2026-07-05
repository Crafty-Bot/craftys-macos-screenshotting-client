import AppKit
import Foundation
import SwiftUI

final class PinnedImageWindowController: NSWindowController, NSWindowDelegate {
  let id = UUID().uuidString
  private let onClose: (String) -> Void

  init(image: NSImage, title: String = "Pinned", onClose: @escaping (String) -> Void) {
    self.onClose = onClose

    // Size: prefer a reasonable default while keeping large images manageable.
    let maxW: CGFloat = 640
    let maxH: CGFloat = 420
    let imgSize = image.size
    let w = max(240, min(maxW, imgSize.width))
    let h = max(180, min(maxH, imgSize.height))

    let window = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: w, height: h),
      styleMask: [.borderless, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = title
    window.hasShadow = true
    window.isOpaque = false
    window.backgroundColor = .clear
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isMovableByWindowBackground = true
    window.minSize = NSSize(width: 220, height: 160)
    window.center()

    let root = PinnedImageView(
      image: image,
      onCopy: { ClipboardHelper.copyImage(image) },
      onClose: { window.close() }
    )
    let hosting = NSHostingController(rootView: root)
    window.contentViewController = hosting

    super.init(window: window)
    window.delegate = self
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func windowWillClose(_ notification: Notification) {
    onClose(id)
  }
}

private struct PinnedImageView: View {
  let image: NSImage
  let onCopy: () -> Void
  let onClose: () -> Void

  @State private var hovered = false

  var body: some View {
    ZStack(alignment: .topTrailing) {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.black.opacity(0.18), lineWidth: 1)
        )

      Image(nsImage: image)
        .resizable()
        .scaledToFit()
        .padding(10)

      HStack(spacing: 6) {
        Button("Copy") { onCopy() }
          .buttonStyle(.bordered)
          .controlSize(.small)
        Button("Close") { onClose() }
          .buttonStyle(.bordered)
          .controlSize(.small)
      }
      .padding(10)
      .opacity(hovered ? 1.0 : 0.0)
      .animation(.easeInOut(duration: 0.15), value: hovered)
    }
    .padding(8)
    .background(Color.clear)
    .onHover { hovered = $0 }
  }
}
