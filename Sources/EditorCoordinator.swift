import AppKit
import Foundation

final class EditorCoordinator {
  static let shared = EditorCoordinator()
  private init() {}

  private var editor: EditorWindowController?

  func openEditor(forRecordId recordId: String) {
    guard let record = UploadHistoryStore.shared.record(id: recordId), !record.localFilePath.isEmpty else {
      Notifier.shared.notify(title: "CraftyCannon", body: "No local file to edit")
      return
    }

    let url = URL(fileURLWithPath: record.localFilePath)
    guard let image = NSImage(contentsOf: url) else {
      Notifier.shared.notify(title: "CraftyCannon", body: "Failed to load image")
      return
    }

    editor = EditorWindowController(image: image, suggestedFilenameExt: url.pathExtension.isEmpty ? "png" : url.pathExtension) { exportedUrl in
      // Save as a new upload entry (keeps original history item intact).
      UploadService.shared.enqueueImageUpload(fileUrl: exportedUrl, managedCopy: true)
    }

    editor?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
