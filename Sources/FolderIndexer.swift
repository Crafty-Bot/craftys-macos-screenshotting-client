import Foundation

final class FolderIndexer {
  static let shared = FolderIndexer()
  private init() {}

  func createIndexFile(for directoryURL: URL, includeSubdirectories: Bool) throws -> URL {
    let fm = FileManager.default
    let rootPath = directoryURL.path

    var lines: [String] = []
    lines.append("Folder index")
    lines.append("Root: \(directoryURL.path)")
    lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
    lines.append("")

    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
    let options: FileManager.DirectoryEnumerationOptions = includeSubdirectories ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]

    if let enumerator = fm.enumerator(at: directoryURL, includingPropertiesForKeys: keys, options: options) {
      for case let fileURL as URL in enumerator {
        guard let values = try? fileURL.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
          continue
        }

        let relative = fileURL.path.hasPrefix(rootPath)
          ? String(fileURL.path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
          : fileURL.lastPathComponent

        let size = values.fileSize ?? 0
        lines.append("- \(relative) (\(size) bytes)")
      }
    }

    if lines.count == 4 {
      lines.append("(no files found)")
    }

    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("CraftyCannon", isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

    let safeName = directoryURL.lastPathComponent.replacingOccurrences(of: " ", with: "-")
    let outURL = tmpDir.appendingPathComponent("\(safeName)-index-\(UUID().uuidString.prefix(8)).txt")
    try lines.joined(separator: "\n").write(to: outURL, atomically: true, encoding: .utf8)
    return outURL
  }
}
