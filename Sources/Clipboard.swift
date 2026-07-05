import AppKit
import Foundation

enum ClipboardError: Error {
  case noImage
  case encodeFailed
}

final class ClipboardImageExporter {
  static let shared = ClipboardImageExporter()
  private init() {}

  func exportPngToTemp() throws -> URL {
    let pb = NSPasteboard.general

    if let data = pb.data(forType: .png) {
      return try writeTemp(data: data, ext: "png")
    }

    if let tiff = pb.data(forType: .tiff), let img = NSImage(data: tiff) {
      guard let rep = NSBitmapImageRep(data: img.tiffRepresentation ?? Data()) else {
        throw ClipboardError.encodeFailed
      }
      guard let png = rep.representation(using: .png, properties: [:]) else {
        throw ClipboardError.encodeFailed
      }
      return try writeTemp(data: png, ext: "png")
    }

    throw ClipboardError.noImage
  }

  private func writeTemp(data: Data, ext: String) throws -> URL {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("CraftyCannon", isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let outUrl = tmpDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    try data.write(to: outUrl, options: [.atomic])
    return outUrl
  }
}
