import AppKit
import Foundation
import Vision

extension Notification.Name {
  static let ocrIndexDidChange = Notification.Name("ocrIndexDidChange")
}

enum OCRIndexPhase: String {
  case idle
  case indexing
  case paused
  case cancelled
  case completed
}

struct OCRIndexProgress: Equatable {
  var phase: OCRIndexPhase = .idle
  var total: Int = 0
  var completed: Int = 0
  var skipped: Int = 0
  var failed: Int = 0
  var currentFilename: String?
  var startedAt: Date?
  var updatedAt: Date?
  var message: String?

  var remaining: Int {
    max(0, total - completed - skipped - failed)
  }

  var estimatedRemainingSeconds: TimeInterval? {
    guard let startedAt, completed + skipped + failed > 0, remaining > 0 else { return nil }
    let elapsed = Date().timeIntervalSince(startedAt)
    let processed = Double(completed + skipped + failed)
    guard elapsed > 0, processed > 0 else { return nil }
    return elapsed / processed * Double(remaining)
  }
}

protocol OCRTextRecognizing {
  var engineName: String { get }
  var engineVersion: String { get }
  func recognizeText(in imageURL: URL) throws -> String
}

struct VisionOCRTextRecognizer: OCRTextRecognizing {
  let engineName = "Apple Vision"
  let engineVersion: String = {
    if #available(macOS 13.0, *) {
      return "VNRecognizeTextRequest.revision\(VNRecognizeTextRequestRevision3)"
    }
    return "VNRecognizeTextRequest"
  }()

  func recognizeText(in imageURL: URL) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if #available(macOS 13.0, *) {
      request.revision = VNRecognizeTextRequestRevision3
    }

    let handler = VNImageRequestHandler(url: imageURL, options: [:])
    try handler.perform([request])

    let lines = (request.results ?? [])
      .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return lines.joined(separator: "\n")
  }
}

enum OCRBatchMode {
  case indexExisting
  case rebuild
}

struct OCRBatchSummary: Equatable {
  var total: Int = 0
  var indexed: Int = 0
  var skipped: Int = 0
  var failed: Int = 0
  var missing: Int = 0
  var cancelled: Bool = false
}

enum OCRIndexError: Error {
  case missingFile
  case unsupportedRecord
}

final class OCRIndexManager {
  static let shared = OCRIndexManager()

  private let recognizer: OCRTextRecognizing
  private let store: OCRHistoryStoring
  private let workQueue: DispatchQueue
  // Batches run on their own queue so pausing a batch (which blocks the queue)
  // never starves per-upload index jobs on `workQueue`.
  private let batchQueue: DispatchQueue
  private let stateQueue = DispatchQueue(label: "com.crafty599.craftycannon.ocr.state")
  private let maxRetries = 2
  private var progressValue = OCRIndexProgress()
  private var cancelRequested = false
  private var paused = false
  private var activeBatch = false

  init(
    recognizer: OCRTextRecognizing = VisionOCRTextRecognizer(),
    store: OCRHistoryStoring = UploadHistoryStore.shared,
    queueLabel: String = "com.crafty599.craftycannon.ocr"
  ) {
    self.recognizer = recognizer
    self.store = store
    self.workQueue = DispatchQueue(label: queueLabel, qos: .utility)
    self.batchQueue = DispatchQueue(label: queueLabel + ".batch", qos: .utility)
  }

  var progress: OCRIndexProgress {
    stateQueue.sync { progressValue }
  }

  func enqueueRecord(_ recordId: String, sourcePath: String? = nil, force: Bool = false) {
    guard RuntimePreferences.shared.ocrIndexingEnabled else {
      store.updateRecordSync(id: recordId) { record in
        record.clearOCRMetadata(status: .disabled)
      }
      return
    }

    workQueue.async { [weak self] in
      guard let self else { return }
      _ = self.indexRecordNow(id: recordId, sourcePath: sourcePath, force: force)
    }
  }

  func indexExistingInBackground() {
    startBatchInBackground(.indexExisting)
  }

  func rebuildInBackground() {
    startBatchInBackground(.rebuild)
  }

  private func startBatchInBackground(_ mode: OCRBatchMode) {
    batchQueue.async { [weak self] in
      guard let self else { return }
      _ = self.runBatchSync(mode: mode)
    }
  }

  /// Runs `block` on the per-record indexing queue, behind any index jobs that
  /// were already enqueued (FIFO). Callers use this to defer deleting a
  /// temporary file until its pending OCR job has read it.
  func performAfterPendingRecordWork(_ block: @escaping () -> Void) {
    workQueue.async(execute: block)
  }

  func pause() {
    stateQueue.sync {
      paused = true
      progressValue.phase = .paused
      progressValue.updatedAt = Date()
    }
    notifyChanged()
  }

  func resume() {
    stateQueue.sync {
      paused = false
      if activeBatch {
        progressValue.phase = .indexing
      }
      progressValue.updatedAt = Date()
    }
    notifyChanged()
  }

  func cancel() {
    stateQueue.sync {
      cancelRequested = true
      progressValue.phase = .cancelled
      progressValue.updatedAt = Date()
    }
    notifyChanged()
  }

  func clearIndex() {
    store.mutateRecordsSync { records in
      for idx in records.indices where records[idx].isImageRecord {
        records[idx].clearOCRMetadata()
      }
    }
    setProgress(OCRIndexProgress(phase: .idle, message: "OCR index cleared"))
  }

  @discardableResult
  func runBatchSync(mode: OCRBatchMode) -> OCRBatchSummary {
    let enabled = RuntimePreferences.shared.ocrIndexingEnabled
    let candidates = store.snapshot().filter { $0.isImageRecord }
    if mode == .rebuild {
      store.mutateRecordsSync { records in
        for idx in records.indices where records[idx].isImageRecord {
          records[idx].clearOCRMetadata()
        }
      }
    }

    stateQueue.sync {
      activeBatch = true
      cancelRequested = false
      paused = false
      progressValue = OCRIndexProgress(
        phase: .indexing,
        total: candidates.count,
        completed: 0,
        skipped: 0,
        failed: 0,
        currentFilename: nil,
        startedAt: Date(),
        updatedAt: Date(),
        message: enabled ? nil : "OCR indexing is disabled"
      )
    }
    notifyChanged()

    var summary = OCRBatchSummary(total: candidates.count)
    guard enabled else {
      store.mutateRecordsSync { records in
        for idx in records.indices where records[idx].isImageRecord {
          records[idx].clearOCRMetadata(status: .disabled)
        }
      }
      summary.skipped = candidates.count
      finishBatch(message: "OCR indexing is disabled", summary: summary)
      return summary
    }

    for candidate in candidates {
      waitIfPaused()
      if isCancelRequested() {
        summary.cancelled = true
        break
      }

      updateCurrentFilename(candidate.localFilePath)
      let result = indexRecordNow(id: candidate.id, force: mode == .rebuild)
      switch result {
      case .indexed:
        summary.indexed += 1
      case .skipped:
        summary.skipped += 1
      case .missing:
        summary.missing += 1
      case .failed:
        summary.failed += 1
      }
      updateProgressCounts(summary)
    }

    finishBatch(
      message: summary.cancelled ? "OCR indexing cancelled" : "OCR indexing complete",
      summary: summary
    )
    return summary
  }

  enum RecordIndexResult: Equatable {
    case indexed
    case skipped
    case missing
    case failed
  }

  @discardableResult
  func indexRecordNow(id: String, sourcePath: String? = nil, force: Bool = false) -> RecordIndexResult {
    guard RuntimePreferences.shared.ocrIndexingEnabled else {
      store.updateRecordSync(id: id) { record in
        record.clearOCRMetadata(status: .disabled)
      }
      return .skipped
    }

    guard var record = store.record(id: id), record.isImageRecord else {
      return .skipped
    }

    let path = sourcePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? sourcePath!
      : record.localFilePath
    guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      markMissing(id: id, message: "No local image path available")
      return .missing
    }

    let url = URL(fileURLWithPath: path)
    guard let signature = Self.fileSignature(for: url) else {
      markMissing(id: id, message: "Image file is missing or unreadable")
      return .missing
    }

    if !force,
       record.ocrStatus == .indexed,
       record.ocrFileSize == signature.size,
       record.ocrFileModifiedAt == signature.modifiedAt,
       record.ocrText != nil {
      return .skipped
    }

    store.updateRecordSync(id: id) { record in
      record.ocrStatus = .pending
      record.ocrError = nil
    }

    do {
      let text = try recognizer.recognizeText(in: url).trimmingCharacters(in: .whitespacesAndNewlines)
      store.updateRecordSync(id: id) { record in
        record.ocrStatus = .indexed
        record.ocrText = text
        record.ocrEngine = recognizer.engineName
        record.ocrEngineVersion = recognizer.engineVersion
        record.ocrIndexedAt = Date()
        record.ocrFileSize = signature.size
        record.ocrFileModifiedAt = signature.modifiedAt
        record.ocrError = nil
        record.ocrRetryCount = 0
      }
      return .indexed
    } catch {
      record = store.record(id: id) ?? record
      let retryCount = (record.ocrRetryCount ?? 0) + 1
      store.updateRecordSync(id: id) { record in
        record.ocrRetryCount = retryCount
        record.ocrFileSize = signature.size
        record.ocrFileModifiedAt = signature.modifiedAt
        record.ocrError = error.localizedDescription.isEmpty ? String(describing: error) : error.localizedDescription
        record.ocrStatus = retryCount <= maxRetries ? .pending : .failed
      }

      if retryCount <= maxRetries {
        Thread.sleep(forTimeInterval: 0.25)
        return indexRecordNow(id: id, sourcePath: sourcePath, force: force)
      }
      return .failed
    }
  }

  static func fileSignature(for url: URL) -> (size: Int64, modifiedAt: Date)? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let sizeNumber = attrs[.size] as? NSNumber else {
      return nil
    }
    let modifiedAt = attrs[.modificationDate] as? Date ?? Date.distantPast
    return (sizeNumber.int64Value, modifiedAt)
  }

  static func snippet(for text: String?, query: String, radius: Int = 48) -> String? {
    let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let text, !text.isEmpty, !cleanQuery.isEmpty else { return nil }
    guard let range = text.range(of: cleanQuery, options: [.caseInsensitive, .diacriticInsensitive]) else {
      return nil
    }

    let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
    let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
    var snippet = String(text[start..<end])
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if start > text.startIndex { snippet = "..." + snippet }
    if end < text.endIndex { snippet += "..." }
    return snippet.isEmpty ? nil : snippet
  }

  private func markMissing(id: String, message: String) {
    store.updateRecordSync(id: id) { record in
      record.ocrStatus = .missingFile
      record.ocrText = nil
      record.ocrError = message
      record.ocrIndexedAt = Date()
    }
  }

  private func waitIfPaused() {
    while true {
      let shouldPause = stateQueue.sync { paused && !cancelRequested }
      if !shouldPause { return }
      Thread.sleep(forTimeInterval: 0.2)
    }
  }

  private func isCancelRequested() -> Bool {
    stateQueue.sync { cancelRequested }
  }

  private func updateCurrentFilename(_ path: String) {
    stateQueue.sync {
      progressValue.currentFilename = path.isEmpty ? nil : URL(fileURLWithPath: path).lastPathComponent
      progressValue.updatedAt = Date()
    }
    notifyChanged()
  }

  private func updateProgressCounts(_ summary: OCRBatchSummary) {
    stateQueue.sync {
      progressValue.completed = summary.indexed
      progressValue.skipped = summary.skipped + summary.missing
      progressValue.failed = summary.failed
      progressValue.updatedAt = Date()
    }
    notifyChanged()
  }

  private func finishBatch(message: String, summary: OCRBatchSummary) {
    stateQueue.sync {
      activeBatch = false
      cancelRequested = false
      paused = false
      progressValue.phase = summary.cancelled ? .cancelled : .completed
      progressValue.currentFilename = nil
      progressValue.message = message
      progressValue.updatedAt = Date()
    }
    notifyChanged()
  }

  private func setProgress(_ progress: OCRIndexProgress) {
    stateQueue.sync {
      progressValue = progress
      progressValue.updatedAt = Date()
    }
    notifyChanged()
  }

  private func notifyChanged() {
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .ocrIndexDidChange, object: nil)
    }
  }
}
