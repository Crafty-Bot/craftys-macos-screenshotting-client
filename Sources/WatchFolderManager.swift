import Foundation

final class WatchFolderManager {
  static let shared = WatchFolderManager()

  private struct PendingObservation {
    var signature: String
    var firstSeenAt: Date
  }

  private let queue = DispatchQueue(label: "com.crafty599.craftycannon.watchfolders")
  private var timer: DispatchSourceTimer?
  private var knownSignatures: [String: String] = [:]
  private var knownSignatureOrder: [String] = []
  private var pending: [String: PendingObservation] = [:]
  // Rule id -> normalized folder path that has completed its baseline scan.
  // Files already present when watching starts are recorded here and never
  // uploaded; only files that appear or change afterwards are.
  private var primedRules: [String: String] = [:]

  private init() {}

  func applyCurrentPreferences() {
    queue.async {
      self.configureTimer()
    }
  }

  private func configureTimer() {
    let enabled = RuntimePreferences.shared.watchFoldersEnabled
    let activeRules = RuntimePreferences.shared.watchFolderRules.filter { $0.enabled }

    if enabled && !activeRules.isEmpty {
      if timer == nil {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: .seconds(2), leeway: .milliseconds(250))
        t.setEventHandler { [weak self] in
          self?.scan(rules: RuntimePreferences.shared.watchFolderRules.filter { $0.enabled })
        }
        t.resume()
        timer = t
      }
    } else {
      timer?.cancel()
      timer = nil
      pending.removeAll()
      // Re-baseline on the next enable so files added while watching was off
      // are not retroactively uploaded.
      primedRules.removeAll()
    }
  }

  private func scan(rules: [WatchFolderRule]) {
    let now = Date()

    for rule in rules {
      let baseURL = URL(fileURLWithPath: rule.path)
      var isDir: ObjCBool = false
      guard FileManager.default.fileExists(atPath: baseURL.path, isDirectory: &isDir), isDir.boolValue else {
        continue
      }

      let options: FileManager.DirectoryEnumerationOptions = rule.includeSubdirectories
        ? [.skipsHiddenFiles]
        : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]

      let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
      guard let enumerator = FileManager.default.enumerator(at: baseURL, includingPropertiesForKeys: keys, options: options) else {
        continue
      }

      let normalizedRulePath = normalizedWatchFolderPath(rule.path)
      let isPrimed = primedRules[rule.id] == normalizedRulePath

      for case let fileURL as URL in enumerator {
        guard matchesFilter(fileURL: fileURL, filter: rule.fileFilter),
              let values = try? fileURL.resourceValues(forKeys: Set(keys)),
              values.isRegularFile == true else {
          continue
        }

        let size = values.fileSize ?? 0
        let mod = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        let signature = "\(size):\(Int(mod))"
        let observationKey = "\(rule.id)|\(fileURL.path)"

        if !isPrimed {
          // Baseline scan: mark pre-existing files as known without uploading.
          recordKnownSignature(signature, for: observationKey)
          continue
        }

        if knownSignatures[observationKey] == signature {
          continue
        }

        if let existingPending = pending[observationKey], existingPending.signature == signature {
          if now.timeIntervalSince(existingPending.firstSeenAt) >= 1.5 {
            pending.removeValue(forKey: observationKey)
            recordKnownSignature(signature, for: observationKey)
            enqueueUpload(fileURL: fileURL, rule: rule)
          }
        } else {
          pending[observationKey] = PendingObservation(signature: signature, firstSeenAt: now)
        }
      }

      if !isPrimed {
        primedRules[rule.id] = normalizedRulePath
      }
    }

    pending = pending.filter { now.timeIntervalSince($0.value.firstSeenAt) < 120 }

    // Bound dedupe memory growth.
    if knownSignatures.count > 25_000 {
      pruneKnownSignatures(activeRules: rules)
    }
  }

  private func recordKnownSignature(_ signature: String, for observationKey: String) {
    if knownSignatures[observationKey] == nil {
      knownSignatureOrder.append(observationKey)
    }
    knownSignatures[observationKey] = signature
  }

  private func pruneKnownSignatures(activeRules rules: [WatchFolderRule]) {
    var activeRulePaths: [String: String] = [:]
    for rule in rules {
      activeRulePaths[rule.id] = normalizedWatchFolderPath(rule.path)
    }

    knownSignatures = knownSignatures.filter { entry in
      guard let (ruleId, filePath) = observationParts(from: entry.key),
            let rulePath = activeRulePaths[ruleId] else {
        return false
      }
      return isWatchFilePath(filePath, under: rulePath)
    }
    knownSignatureOrder.removeAll { knownSignatures[$0] == nil }

    guard knownSignatures.count > 25_000 else { return }

    let removeCount = min(knownSignatures.count / 2, knownSignatureOrder.count)
    for key in knownSignatureOrder.prefix(removeCount) {
      knownSignatures.removeValue(forKey: key)
    }
    knownSignatureOrder.removeFirst(removeCount)
  }

  private func observationParts(from observationKey: String) -> (String, String)? {
    guard let separator = observationKey.firstIndex(of: "|") else { return nil }
    let id = String(observationKey[..<separator])
    let pathStart = observationKey.index(after: separator)
    return (id, String(observationKey[pathStart...]))
  }

  private func normalizedWatchFolderPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
  }

  private func isWatchFilePath(_ filePath: String, under folderPath: String) -> Bool {
    let normalizedFilePath = URL(fileURLWithPath: filePath).standardizedFileURL.path
    let normalizedFolderPath = normalizedWatchFolderPath(folderPath)
    if normalizedFilePath == normalizedFolderPath {
      return true
    }
    let folderPrefix = normalizedFolderPath.hasSuffix("/") ? normalizedFolderPath : normalizedFolderPath + "/"
    return normalizedFilePath.hasPrefix(folderPrefix)
  }

  private func enqueueUpload(fileURL: URL, rule: WatchFolderRule) {
    let ext = fileURL.pathExtension.lowercased()
    let isImage = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic"].contains(ext)
    let defaultExpiry = RuntimePreferences.shared.defaultFileExpirySeconds

    switch rule.mode {
    case .imageOnly:
      guard isImage else { return }
      UploadService.shared.enqueueImageUpload(
        fileUrl: fileURL,
        managedCopy: false,
        uploadContext: "watch-folder",
        sourceKind: .watchFolder
      )
    case .fileOnly:
      UploadService.shared.enqueueFileUpload(
        fileUrl: fileURL,
        expiresSeconds: rule.expirySeconds ?? defaultExpiry,
        sourceKind: .watchFolder
      )
    case .auto:
      if isImage {
        UploadService.shared.enqueueImageUpload(
          fileUrl: fileURL,
          managedCopy: false,
          uploadContext: "watch-folder",
          sourceKind: .watchFolder
        )
      } else {
        UploadService.shared.enqueueFileUpload(
          fileUrl: fileURL,
          expiresSeconds: rule.expirySeconds ?? defaultExpiry,
          sourceKind: .watchFolder
        )
      }
    }
  }

  private func matchesFilter(fileURL: URL, filter: String) -> Bool {
    let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed == "*" || trimmed == "*.*" {
      return true
    }

    let ext = fileURL.pathExtension.lowercased()
    let parts = trimmed
      .components(separatedBy: CharacterSet(charactersIn: ",; "))
      .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "* .")).lowercased() }
      .filter { !$0.isEmpty }

    if parts.isEmpty {
      return true
    }

    return parts.contains(ext)
  }
}
