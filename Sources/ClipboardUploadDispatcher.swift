import AppKit
import Foundation

enum ClipboardUploadAction {
  case image(URL)
  case file(URL)
  case folder(URL)
  case remoteURL(String)
  case text(String)
  case shortenURL(String)
  case copyURLOnly(String)
}

enum ClipboardDispatchError: Error {
  case unsupportedClipboardContent
}

final class ClipboardUploadDispatcher {
  static let shared = ClipboardUploadDispatcher()
  private init() {}

  func resolveAction(rules: ClipboardUploadRules) throws -> ClipboardUploadAction {
    let pb = NSPasteboard.general

    if let imageURL = try? ClipboardImageExporter.shared.exportPngToTemp() {
      return .image(imageURL)
    }

    if let fileURL = readFileURL(from: pb) {
      var isDir: ObjCBool = false
      if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
        if rules.autoIndexFolder {
          return .folder(fileURL)
        }
      } else {
        return .file(fileURL)
      }
    }

    if let rawText = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !rawText.isEmpty {
      if let url = normalizedWebURL(rawText) {
        if rules.shortenURL {
          return .shortenURL(url)
        }
        if rules.uploadURLContents {
          return .remoteURL(url)
        }
        if rules.shareURLAfterUpload {
          return .copyURLOnly(url)
        }
      }

      if rules.uploadTextContents {
        return .text(rawText)
      }
    }

    throw ClipboardDispatchError.unsupportedClipboardContent
  }

  private func readFileURL(from pasteboard: NSPasteboard) -> URL? {
    if let items = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
       let fileURL = items.first(where: { $0.isFileURL }) {
      return fileURL
    }

    if let fileURLString = pasteboard.string(forType: .fileURL),
       let url = URL(string: fileURLString),
       url.isFileURL {
      return url
    }

    return nil
  }

  private func normalizedWebURL(_ raw: String) -> String? {
    guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
      return nil
    }
    return raw
  }
}
