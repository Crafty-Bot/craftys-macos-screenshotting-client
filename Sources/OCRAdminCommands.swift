import Foundation

enum OCRAdminCommands {
  static let supportedCommands: Set<String> = [
    "index-existing",
    "rebuild-index",
    "index-status",
    "clear-index",
  ]

  static func runIfNeeded(arguments: [String] = CommandLine.arguments) -> Bool {
    guard arguments.count >= 2 else { return false }
    let command = arguments[1]
    guard supportedCommands.contains(command) else { return false }

    switch command {
    case "index-existing":
      let summary = OCRIndexManager.shared.runBatchSync(mode: .indexExisting)
      printSummary("Index existing complete", summary)
    case "rebuild-index":
      let summary = OCRIndexManager.shared.runBatchSync(mode: .rebuild)
      printSummary("Rebuild complete", summary)
    case "index-status":
      printStatus()
    case "clear-index":
      OCRIndexManager.shared.clearIndex()
      print("OCR index cleared.")
    default:
      return false
    }
    return true
  }

  private static func printSummary(_ title: String, _ summary: OCRBatchSummary) {
    print(title)
    print("total: \(summary.total)")
    print("indexed: \(summary.indexed)")
    print("skipped: \(summary.skipped)")
    print("missing: \(summary.missing)")
    print("failed: \(summary.failed)")
    if summary.cancelled {
      print("cancelled: true")
    }
  }

  private static func printStatus() {
    let records = UploadHistoryStore.shared.snapshot().filter { $0.isImageRecord }
    var counts: [String: Int] = [:]
    for record in records {
      let key = record.ocrStatus?.rawValue ?? "notIndexed"
      counts[key, default: 0] += 1
    }

    print("OCR index status")
    print("imageRecords: \(records.count)")
    for key in ["indexed", "pending", "failed", "missingFile", "disabled", "skipped", "notIndexed"] {
      if let value = counts[key] {
        print("\(key): \(value)")
      }
    }
    print("enabled: \(RuntimePreferences.shared.ocrIndexingEnabled)")
  }
}
