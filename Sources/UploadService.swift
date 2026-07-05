import AppKit
import Foundation

private enum RemoteUploadError: Error {
  case invalidURL
  case unsupportedScheme
  case httpStatus(Int)
  case emptyResponse
  case responseTooLarge(Int)
}

private enum UploadRedactionError: Error {
  case cancelled
  case detectionFailed(Error)
  case renderingFailed(Error)
}

private enum UploadPreparationError: Error {
  case metadataStripFailed(Error)
  case formatConversionFailed(Error)
}

private enum UploadRedactionDecision {
  case redact
  case uploadOriginal
  case cancel
}

private struct PreparedImageUpload {
  let fileURL: URL
  let redacted: Bool
  let temporary: Bool
}

struct PasteTargetPolicy {
  static func shouldPasteURLInsteadOfImage(
    applicationName: String?,
    bundleIdentifier: String?,
    windowTitle: String? = nil
  ) -> Bool {
    let bundle = normalized(bundleIdentifier)
    let appName = normalized(applicationName)
    let title = normalized(windowTitle)

    if bundle.contains("discord") || appName.contains("discord") {
      return true
    }

    if isBrowser(bundleIdentifier: bundle, applicationName: appName),
       title.contains("discord") {
      return true
    }

    return false
  }

  static func shouldPasteURLInsteadOfImageForFrontmostApplication() -> Bool {
    guard let app = NSWorkspace.shared.frontmostApplication else { return false }
    return shouldPasteURLInsteadOfImage(
      applicationName: app.localizedName,
      bundleIdentifier: app.bundleIdentifier,
      windowTitle: frontmostWindowTitle(processIdentifier: app.processIdentifier)
    )
  }

  private static func frontmostWindowTitle(processIdentifier: pid_t) -> String? {
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] else {
      return nil
    }

    for window in windows {
      let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t
      guard ownerPID == processIdentifier else { continue }

      if let layer = window[kCGWindowLayer as String] as? Int, layer != 0 {
        continue
      }

      if let title = window[kCGWindowName as String] as? String,
         !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return title
      }
    }

    return nil
  }

  private static func isBrowser(bundleIdentifier: String, applicationName: String) -> Bool {
    let knownBrowserBundles: Set<String> = [
      "com.apple.safari",
      "com.google.chrome",
      "com.google.chrome.canary",
      "com.microsoft.edgemac",
      "company.thebrowser.browser",
      "com.brave.browser",
      "org.mozilla.firefox"
    ]

    if knownBrowserBundles.contains(bundleIdentifier) {
      return true
    }

    let knownBrowserNames = ["safari", "chrome", "edge", "arc", "brave", "firefox"]
    return knownBrowserNames.contains(applicationName)
  }

  private static func normalized(_ value: String?) -> String {
    value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
  }
}

final class UploadService {
  static let shared = UploadService()
  private init() {}

  private let maxRemoteResponseBytes = 150 * 1024 * 1024
  private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff", "heic", "heif"]

  private func webURL(_ raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parsed = URL(string: trimmed),
          let scheme = parsed.scheme?.lowercased(),
          ["http", "https"].contains(scheme) else {
      return nil
    }
    return parsed
  }

  private func userFacingError(_ error: Error) -> String {
    if let ue = error as? UploadError {
      switch ue {
      case .missingAuthToken:
        return "Missing Authorization token (open Preferences and set the token)"
      case .missingS3Credentials:
        return "Missing S3 credentials (set access key ID and secret access key in Preferences)"
      case .badEndpoint:
        return "Bad endpoint URL (check Preferences)"
      case .invalidResponse:
        return "Invalid server response"
      case .serverError(let msg):
        return msg
      }
    }

    if let se = error as? S3UploadError {
      switch se {
      case .missingConfiguration(let msg):
        return msg
      case .missingCredentials:
        return "Missing S3 credentials (set access key ID and secret access key in Preferences)"
      case .invalidEndpoint:
        return "Invalid S3 endpoint URL"
      case .fileNotFound:
        return "Local file not found"
      case .invalidResponse:
        return "Invalid S3 response"
      case .serverError(let msg):
        return msg
      }
    }

    if let se = error as? URLShortenerError {
      switch se {
      case .invalidURL:
        return "Invalid URL"
      case .invalidTemplate:
        return "Shortener template must contain {url}"
      case .serverError(let msg):
        return msg
      }
    }

    if let re = error as? RemoteUploadError {
      switch re {
      case .invalidURL:
        return "URL is invalid"
      case .unsupportedScheme:
        return "Only HTTP and HTTPS URLs are supported"
      case .httpStatus(let status):
        return "Remote server returned HTTP \(status)"
      case .emptyResponse:
        return "Remote URL returned no content"
      case .responseTooLarge(let size):
        return "Remote content too large (\(size) bytes)"
      }
    }

    if let re = error as? UploadRedactionError {
      switch re {
      case .cancelled:
        return "Upload cancelled"
      case .detectionFailed:
        return "Redaction check failed; upload was not sent"
      case .renderingFailed:
        return "Redaction rendering failed; upload was not sent"
      }
    }

    if let pe = error as? UploadPreparationError {
      switch pe {
      case .metadataStripFailed:
        return "Metadata stripping failed; upload was not sent"
      case .formatConversionFailed:
        return "Image format conversion failed; upload was not sent"
      }
    }

    let ns = error as NSError
    // Common case seen in this app: local file path doesn't exist (often iCloud placeholder or a race).
    if ns.domain == NSCocoaErrorDomain && ns.code == 4 {
      return "Local file not found. If it's in iCloud Drive, download it first, then retry."
    }

    return "\(error)"
  }

  private func prepareImageForUpload(fileUrl: URL) async throws -> PreparedImageUpload {
    let policy = RuntimePreferences.shared.uploadRedactionPolicy
    var preparedURL = fileUrl
    var redacted = false
    var temporary = false

    if policy != .off {
      let regions: [SmartRedactionRegion]
      do {
        regions = try await SmartRedactionDetector.shared.detectSensitiveRegions(in: fileUrl)
      } catch {
        throw UploadRedactionError.detectionFailed(error)
      }

      if !regions.isEmpty {
        var shouldRedact = false
        switch policy {
        case .off:
          break
        case .askBeforeUpload:
          let decision = await promptForRedactionBeforeUpload(regions: regions)
          switch decision {
          case .redact:
            shouldRedact = true
          case .uploadOriginal:
            break
          case .cancel:
            throw UploadRedactionError.cancelled
          }
        case .autoRedact:
          shouldRedact = true
        }

        if shouldRedact {
          do {
            let redactedURL = try SmartRedactionImageProcessor.redactedTemporaryPNG(
              from: fileUrl,
              regions: regions,
              mode: RuntimePreferences.shared.smartRedactionRenderMode
            )
            Notifier.shared.notify(title: "CraftyCannon", body: "Redacted \(regions.count) sensitive region(s) before upload")
            preparedURL = redactedURL
            redacted = true
            temporary = true
          } catch {
            throw UploadRedactionError.renderingFailed(error)
          }
        }
      }
    }

    if RuntimePreferences.shared.stripImageMetadataBeforeUpload {
      do {
        if let strippedURL = try ImageUploadMetadataStripper.strippedTemporaryCopy(from: preparedURL) {
          if temporary, strippedURL.path != preparedURL.path {
            removeTemporaryFileIfSafe(preparedURL)
          }
          preparedURL = strippedURL
          temporary = true
        }
      } catch {
        throw UploadPreparationError.metadataStripFailed(error)
      }
    }

    do {
      if let convertedURL = try ImageUploadTranscoder.convertedTemporaryCopy(
        from: preparedURL,
        to: RuntimePreferences.shared.imageUploadFormat
      ) {
        if temporary, convertedURL.path != preparedURL.path {
          removeTemporaryFileIfSafe(preparedURL)
        }
        preparedURL = convertedURL
        temporary = true
      }
    } catch {
      throw UploadPreparationError.formatConversionFailed(error)
    }

    return PreparedImageUpload(fileURL: preparedURL, redacted: redacted, temporary: temporary)
  }

  @MainActor
  private func promptForRedactionBeforeUpload(regions: [SmartRedactionRegion]) -> UploadRedactionDecision {
    let alert = NSAlert()
    alert.messageText = "Sensitive content detected"
    alert.informativeText = redactionPromptSummary(regions: regions)
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Redact & Upload")
    alert.addButton(withTitle: "Upload Original")
    alert.addButton(withTitle: "Cancel")

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      return .redact
    case .alertSecondButtonReturn:
      return .uploadOriginal
    default:
      return .cancel
    }
  }

  private func redactionPromptSummary(regions: [SmartRedactionRegion]) -> String {
    let grouped = Dictionary(grouping: regions, by: { $0.category })
      .map { type, matches in "\(type.title): \(matches.count)" }
      .sorted()
      .joined(separator: "\n")
    let countLabel = regions.count == 1 ? "1 region" : "\(regions.count) regions"
    return "CraftyCannon found \(countLabel) that may need redaction before upload.\n\n\(grouped)"
  }

  func enqueueImageUpload(
    fileUrl: URL,
    managedCopy: Bool,
    uploadContext: String? = nil,
    localMirrorPrefix: String? = nil,
    sourceKind: UploadSourceKind = .manualFile,
    batchId: String? = nil,
    cleanupSourceFile: URL? = nil
  ) {
    Task {
      let prepared: PreparedImageUpload
      do {
        prepared = try await prepareImageForUpload(fileUrl: fileUrl)
      } catch {
        if let cleanupSourceFile {
          removeTemporaryFileIfSafe(cleanupSourceFile)
        }
        removeTemporaryFileIfSafe(fileUrl)
        Notifier.shared.notify(title: "Upload cancelled", body: userFacingError(error))
        return
      }

      let keepLocalPath = shouldKeepLocalPathForImage(sourceKind: sourceKind, managedCopy: managedCopy)
      let forceManagedPreparedCopy = prepared.temporary && keepLocalPath
      let stored: URL = ((managedCopy || forceManagedPreparedCopy) ? (try? storeLocalCopy(fileUrl: prepared.fileURL)) : nil) ?? prepared.fileURL

      if prepared.temporary, stored.path != prepared.fileURL.path {
        removeTemporaryFileIfSafe(prepared.fileURL)
      }
      if prepared.temporary, prepared.fileURL.path != fileUrl.path {
        removeTemporaryFileIfSafe(fileUrl)
      }
      if prepared.redacted, fileUrl.path != stored.path {
        removeTemporaryFileIfSafe(fileUrl)
      }
      if let cleanupSourceFile, cleanupSourceFile.path != stored.path {
        removeTemporaryFileIfSafe(cleanupSourceFile)
      }
      let localPathForRecord = keepLocalPath ? stored.path : ""
      let isManaged = (managedCopy || forceManagedPreparedCopy) && stored.path != fileUrl.path && keepLocalPath
      let config = makeUploadConfiguration(fileUrl: stored, destinationKind: .image)

      // Keep image history parity with ShareX while respecting capture task overrides.
      if keepLocalPath && shouldMirrorImageLocally(sourceKind: sourceKind) {
        _ = try? mirrorToScreenshotsFolder(fileUrl: stored, preferredPrefix: localMirrorPrefix)
      }

      let record = imageRecord(
        profileId: config.profile.id,
        localFilePath: localPathForRecord,
        status: .uploading,
        kind: .image,
        managedLocalCopy: isManaged,
        sourceKind: sourceKind,
        batchId: batchId,
        operationKind: sourceKind == .watchFolder ? .watchFolder : .imageUpload
      )
      UploadHistoryStore.shared.addRecordSync(record)
      OCRIndexManager.shared.enqueueRecord(record.id, sourcePath: stored.path)

      do {
        let rawURL = try await Uploader.shared.uploadImage(
          fileUrl: stored,
          uploadContext: uploadContext,
          profile: config.profile,
          remoteFilename: config.remoteFilename
        )
        let url = finalizeUploadedURL(rawURL)

        UploadHistoryStore.shared.updateRecord(id: record.id) { r in
          r.status = .uploaded
          r.url = url
          r.error = nil
        }

        applyPostUploadTasks(
          recordId: record.id,
          url: url,
          imageFileUrl: stored,
          sourceKind: sourceKind
        )

        await uploadSecondaryS3CopyIfNeeded(
          recordId: record.id,
          fileUrl: stored,
          primaryProfile: config.profile,
          remoteFilename: config.remoteFilename,
          uploadContext: uploadContext
        )

        if !keepLocalPath {
          scheduleTemporaryFileCleanupAfterOCR(stored)
        }
        Notifier.shared.notify(title: "Uploaded", body: url)
      } catch {
        UploadHistoryStore.shared.updateRecord(id: record.id) { r in
          r.status = .failed
          r.error = String(describing: error)
        }
        if !keepLocalPath {
          scheduleTemporaryFileCleanupAfterOCR(stored)
        }
        Notifier.shared.notify(title: "Upload failed", body: userFacingError(error))
      }
    }
  }

  func enqueueExpiringImageUpload(
    fileUrl: URL,
    managedCopy: Bool,
    uploadContext: String? = nil,
    localMirrorPrefix: String? = nil,
    expiresSeconds: Int,
    sourceKind: UploadSourceKind = .manualFile,
    batchId: String? = nil
  ) {
    Task {
      let prepared: PreparedImageUpload
      do {
        prepared = try await prepareImageForUpload(fileUrl: fileUrl)
      } catch {
        removeTemporaryFileIfSafe(fileUrl)
        Notifier.shared.notify(title: "Upload cancelled", body: userFacingError(error))
        return
      }

      let keepLocalPath = shouldKeepLocalPathForImage(sourceKind: sourceKind, managedCopy: managedCopy)
      let forceManagedPreparedCopy = prepared.temporary && keepLocalPath
      let stored: URL = ((managedCopy || forceManagedPreparedCopy) ? (try? storeLocalCopy(fileUrl: prepared.fileURL)) : nil) ?? prepared.fileURL

      if prepared.temporary, stored.path != prepared.fileURL.path {
        removeTemporaryFileIfSafe(prepared.fileURL)
      }
      if prepared.temporary, prepared.fileURL.path != fileUrl.path {
        removeTemporaryFileIfSafe(fileUrl)
      }
      if prepared.redacted, fileUrl.path != stored.path {
        removeTemporaryFileIfSafe(fileUrl)
      }

      let localPathForRecord = keepLocalPath ? stored.path : ""
      let isManaged = (managedCopy || forceManagedPreparedCopy) && stored.path != fileUrl.path && keepLocalPath
      let config = makeUploadConfiguration(fileUrl: stored, destinationKind: .image)

      if keepLocalPath && shouldMirrorImageLocally(sourceKind: sourceKind) {
        _ = try? mirrorToScreenshotsFolder(fileUrl: stored, preferredPrefix: localMirrorPrefix)
      }

      let record = imageRecord(
        profileId: config.profile.id,
        localFilePath: localPathForRecord,
        status: .uploading,
        kind: .image,
        managedLocalCopy: isManaged,
        sourceKind: sourceKind,
        batchId: batchId,
        operationKind: sourceKind == .watchFolder ? .watchFolder : .imageUpload
      )
      UploadHistoryStore.shared.addRecordSync(record)
      OCRIndexManager.shared.enqueueRecord(record.id, sourcePath: stored.path)

      do {
        let result = try await Uploader.shared.uploadImageWithExpiry(
          fileUrl: stored,
          uploadContext: uploadContext,
          expiresSeconds: expiresSeconds,
          profile: config.profile,
          remoteFilename: config.remoteFilename
        )
        let url = finalizeUploadedURL(result.url)
        let exp = parseISO8601(result.expiresAt)

        UploadHistoryStore.shared.updateRecord(id: record.id) { r in
          r.status = .uploaded
          r.url = url
          r.expiresAt = exp
          r.error = nil
        }

        applyPostUploadTasks(
          recordId: record.id,
          url: url,
          imageFileUrl: stored,
          sourceKind: sourceKind
        )
        await uploadSecondaryS3CopyIfNeeded(
          recordId: record.id,
          fileUrl: stored,
          primaryProfile: config.profile,
          remoteFilename: config.remoteFilename,
          uploadContext: uploadContext,
          expiresSeconds: expiresSeconds
        )
        if !keepLocalPath {
          scheduleTemporaryFileCleanupAfterOCR(stored)
        }
        Notifier.shared.notify(title: "Uploaded", body: url)
      } catch {
        UploadHistoryStore.shared.updateRecord(id: record.id) { r in
          r.status = .failed
          r.error = String(describing: error)
        }
        if !keepLocalPath {
          scheduleTemporaryFileCleanupAfterOCR(stored)
        }
        Notifier.shared.notify(title: "Upload failed", body: userFacingError(error))
      }
    }
  }

  func enqueueFileUpload(
    fileUrl: URL,
    expiresSeconds: Int,
    sourceKind: UploadSourceKind = .manualFile,
    batchId: String? = nil,
    destinationKind: DestinationKind = .file,
    operationKind: UploadOperationKind = .fileUpload,
    temporarySourceFile: Bool = false
  ) {
    Task {
      defer {
        if temporarySourceFile {
          removeTemporaryFileIfSafe(fileUrl)
        }
      }

      let config = makeUploadConfiguration(fileUrl: fileUrl, destinationKind: destinationKind)

      let record = UploadRecord(
        profileId: config.profile.id,
        localFilePath: temporarySourceFile ? "" : fileUrl.path,
        status: .uploading,
        kind: .file,
        managedLocalCopy: false,
        sourceKind: sourceKind,
        batchId: batchId,
        operationKind: sourceKind == .watchFolder ? .watchFolder : operationKind
      )
      UploadHistoryStore.shared.addRecord(record)

      do {
        let result = try await Uploader.shared.uploadFileDirect(
          fileUrl: fileUrl,
          expiresSeconds: expiresSeconds,
          profile: config.profile,
          remoteFilename: config.remoteFilename
        )

        let url = finalizeUploadedURL(result.url)
        UploadHistoryStore.shared.updateRecord(id: record.id) { r in
          r.status = .uploaded
          r.url = url
          r.remotePath = result.key
          r.expiresAt = result.expiresAt
          r.error = nil
        }

        applyPostUploadTasks(recordId: record.id, url: url, imageFileUrl: nil, sourceKind: sourceKind)
        await uploadSecondaryS3CopyIfNeeded(
          recordId: record.id,
          fileUrl: fileUrl,
          primaryProfile: config.profile,
          remoteFilename: config.remoteFilename,
          uploadContext: "file",
          expiresSeconds: expiresSeconds
        )
        Notifier.shared.notify(title: "Uploaded", body: url)
      } catch {
        UploadHistoryStore.shared.updateRecord(id: record.id) { r in
          r.status = .failed
          r.error = String(describing: error)
        }
        Notifier.shared.notify(title: "Upload failed", body: userFacingError(error))
      }
    }
  }

  func enqueueRemoteURLUpload(urlString: String, sourceKind: UploadSourceKind = .manualRemoteURL) {
    Task {
      do {
        let downloaded = try await downloadRemoteToTemp(urlString: urlString)
        if isImageFile(url: downloaded.fileURL, mimeType: downloaded.mimeType) {
          enqueueImageUpload(
            fileUrl: downloaded.fileURL,
            managedCopy: true,
            uploadContext: "remote-url",
            sourceKind: sourceKind,
            cleanupSourceFile: downloaded.fileURL
          )
        } else {
          enqueueFileUpload(
            fileUrl: downloaded.fileURL,
            expiresSeconds: RuntimePreferences.shared.defaultFileExpirySeconds,
            sourceKind: sourceKind,
            destinationKind: .file,
            operationKind: .fileUpload,
            temporarySourceFile: true
          )
        }
      } catch {
        Notifier.shared.notify(title: "Upload failed", body: userFacingError(error))
      }
    }
  }

  func enqueueTextUpload(text: String, sourceKind: UploadSourceKind = .manualText) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      Notifier.shared.notify(title: "CraftyCannon", body: "Text is empty")
      return
    }

    Task {
      do {
        let tempFile = try tempTextFile(contents: trimmed)
        enqueueFileUpload(
          fileUrl: tempFile,
          expiresSeconds: RuntimePreferences.shared.defaultFileExpirySeconds,
          sourceKind: sourceKind,
          destinationKind: .text,
          operationKind: .textUpload,
          temporarySourceFile: true
        )
      } catch {
        Notifier.shared.notify(title: "Upload failed", body: userFacingError(error))
      }
    }
  }

  func enqueueFolderUpload(
    folderURL: URL,
    includeSubdirectories: Bool,
    sourceKind: UploadSourceKind = .manualFolderBatch
  ) {
    Task {
      let files = collectFolderFiles(folderURL: folderURL, includeSubdirectories: includeSubdirectories)
      guard !files.isEmpty else {
        Notifier.shared.notify(title: "CraftyCannon", body: "Folder contains no files")
        return
      }

      let batchId = UUID().uuidString
      for file in files {
        if isImageFile(url: file, mimeType: nil) {
          enqueueImageUpload(
            fileUrl: file,
            managedCopy: false,
            uploadContext: "folder-batch",
            sourceKind: sourceKind,
            batchId: batchId
          )
        } else {
          enqueueFileUpload(
            fileUrl: file,
            expiresSeconds: RuntimePreferences.shared.defaultFileExpirySeconds,
            sourceKind: sourceKind,
            batchId: batchId,
            destinationKind: .file,
            operationKind: .folderBatch
          )
        }
      }

      Notifier.shared.notify(title: "Folder upload", body: "Queued \(files.count) file(s).")
    }
  }

  func enqueueFolderIndexUpload(
    folderURL: URL,
    includeSubdirectories: Bool,
    sourceKind: UploadSourceKind = .clipboardFolderURL
  ) {
    Task {
      do {
        let indexFile = try FolderIndexer.shared.createIndexFile(for: folderURL, includeSubdirectories: includeSubdirectories)
        enqueueFileUpload(
          fileUrl: indexFile,
          expiresSeconds: RuntimePreferences.shared.defaultFileExpirySeconds,
          sourceKind: sourceKind,
          destinationKind: .text,
          operationKind: .folderBatch
        )
      } catch {
        Notifier.shared.notify(title: "Folder index failed", body: userFacingError(error))
      }
    }
  }

  func shortenURL(urlString: String, sourceRecordId: String? = nil) {
    Task {
      let shortenerProfile = RuntimePreferences.shared.shortenerProfile()
      let newRecord: UploadRecord?
      if sourceRecordId == nil {
        let created = UploadRecord(
          profileId: shortenerProfile.id,
          localFilePath: "",
          status: .uploading,
          url: urlString,
          sourceKind: .manualRemoteURL,
          operationKind: .urlShorten
        )
        UploadHistoryStore.shared.addRecord(created)
        newRecord = created
      } else {
        newRecord = nil
      }

      do {
        let shortened = try await URLShortenerService.shared.shorten(urlString: urlString)

        if let sourceRecordId {
          UploadHistoryStore.shared.updateRecord(id: sourceRecordId) { r in
            r.shortenedURL = shortened
          }
        }

        if let newRecord {
          UploadHistoryStore.shared.updateRecord(id: newRecord.id) { r in
            r.status = .uploaded
            r.shortenedURL = shortened
            r.error = nil
          }
        }

        copyToClipboard(shortened)
        Notifier.shared.notify(title: "Shortened URL", body: shortened)
      } catch {
        if let newRecord {
          UploadHistoryStore.shared.updateRecord(id: newRecord.id) { r in
            r.status = .failed
            r.error = String(describing: error)
          }
        }
        Notifier.shared.notify(title: "Shorten failed", body: userFacingError(error))
      }
    }
  }

  func shortenURLForRecord(_ recordId: String) {
    guard let record = UploadHistoryStore.shared.record(id: recordId), let url = record.url, !url.isEmpty else {
      return
    }
    shortenURL(urlString: url, sourceRecordId: recordId)
  }

  func copyRawTextToClipboard(_ value: String) {
    copyToClipboard(value)
  }

  func reupload(recordId: String) {
    guard let record = UploadHistoryStore.shared.record(id: recordId) else { return }
    guard !record.localFilePath.isEmpty else {
      Notifier.shared.notify(title: "CraftyCannon", body: "No local file available to re-upload")
      return
    }
    let url = URL(fileURLWithPath: record.localFilePath)

    UploadHistoryStore.shared.updateRecord(id: recordId) { r in
      r.status = .uploading
      r.error = nil
      r.sourceKind = .reupload
    }

    Task {
      do {
        if record.kind == .file {
          // NSAlert must run on the main thread; this task runs off-main.
          let promptedSeconds = await MainActor.run { ExpiryPrompt.promptSeconds(maxDays: 5) }
          guard let seconds = promptedSeconds else {
            UploadHistoryStore.shared.updateRecord(id: recordId) { r in
              r.status = .failed
              r.error = "cancelled"
            }
            return
          }
          let config = makeUploadConfiguration(fileUrl: url, destinationKind: .file)
          let result = try await Uploader.shared.uploadFileDirect(
            fileUrl: url,
            expiresSeconds: seconds,
            profile: config.profile,
            remoteFilename: config.remoteFilename
          )
          let uploadedURL = finalizeUploadedURL(result.url)
          UploadHistoryStore.shared.updateRecord(id: recordId) { r in
            r.profileId = config.profile.id
            r.status = .uploaded
            r.url = uploadedURL
            r.remotePath = result.key
            r.expiresAt = result.expiresAt
            r.error = nil
            r.operationKind = .fileUpload
          }
          applyPostUploadTasks(recordId: recordId, url: uploadedURL, imageFileUrl: nil, sourceKind: .reupload)
          await uploadSecondaryS3CopyIfNeeded(
            recordId: recordId,
            fileUrl: url,
            primaryProfile: config.profile,
            remoteFilename: config.remoteFilename,
            uploadContext: "file",
            expiresSeconds: seconds
          )
          Notifier.shared.notify(title: "Uploaded", body: uploadedURL)
          return
        }

        let prepared = try await prepareImageForUpload(fileUrl: url)
        let uploadURL: URL
        if prepared.temporary {
          uploadURL = (try? storeLocalCopy(fileUrl: prepared.fileURL)) ?? prepared.fileURL
          if uploadURL.path != prepared.fileURL.path {
            removeTemporaryFileIfSafe(prepared.fileURL)
          }
          if prepared.fileURL.path != url.path {
            removeTemporaryFileIfSafe(url)
          }
        } else {
          uploadURL = prepared.fileURL
        }
        _ = try? mirrorToScreenshotsFolder(fileUrl: uploadURL, preferredPrefix: nil)
        let config = makeUploadConfiguration(fileUrl: uploadURL, destinationKind: .image)
        let uploadedRawURL = try await Uploader.shared.uploadImage(
          fileUrl: uploadURL,
          profile: config.profile,
          remoteFilename: config.remoteFilename
        )
        let uploadedURL = finalizeUploadedURL(uploadedRawURL)
        UploadHistoryStore.shared.updateRecord(id: recordId) { r in
          r.profileId = config.profile.id
          r.status = .uploaded
          r.url = uploadedURL
          r.error = nil
          r.operationKind = .imageUpload
        }
        applyPostUploadTasks(recordId: recordId, url: uploadedURL, imageFileUrl: uploadURL, sourceKind: .reupload)
        await uploadSecondaryS3CopyIfNeeded(
          recordId: recordId,
          fileUrl: uploadURL,
          primaryProfile: config.profile,
          remoteFilename: config.remoteFilename,
          uploadContext: nil
        )
        Notifier.shared.notify(title: "Uploaded", body: uploadedURL)
      } catch {
        UploadHistoryStore.shared.updateRecord(id: recordId) { r in
          r.status = .failed
          r.error = String(describing: error)
        }
        Notifier.shared.notify(title: "Upload failed", body: userFacingError(error))
      }
    }
  }

  func copyUrlForRecord(_ recordId: String) {
    guard let record = UploadHistoryStore.shared.record(id: recordId) else { return }
    if let shortened = record.shortenedURL, !shortened.isEmpty {
      copyToClipboard(shortened)
      Notifier.shared.notify(title: "Copied", body: shortened)
      return
    }
    guard let url = record.url else { return }
    copyToClipboard(url)
    Notifier.shared.notify(title: "Copied", body: url)
  }

  func openUrlForRecord(_ recordId: String) {
    guard let record = UploadHistoryStore.shared.record(id: recordId) else { return }
    let openValue = record.shortenedURL ?? record.url
    guard let openValue, let url = webURL(openValue) else { return }
    NSWorkspace.shared.open(url)
  }

  func showInFinder(_ recordId: String) {
    guard let record = UploadHistoryStore.shared.record(id: recordId), !record.localFilePath.isEmpty else { return }
    let url = URL(fileURLWithPath: record.localFilePath)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  func deleteLocalCopy(_ recordId: String) {
    guard let record = UploadHistoryStore.shared.record(id: recordId) else { return }
    if record.managedLocalCopy != true {
      Notifier.shared.notify(title: "CraftyCannon", body: "Not an app-managed local copy")
      return
    }
    let url = URL(fileURLWithPath: record.localFilePath)
    try? FileManager.default.removeItem(at: url)
    UploadHistoryStore.shared.updateRecord(id: recordId) { r in
      r.localFilePath = ""
      r.managedLocalCopy = false
    }
  }

  private func copyToClipboard(_ s: String) {
    _ = copyStringToClipboard(s)
  }

  private func copyStringToClipboard(_ s: String) -> Bool {
    let pb = NSPasteboard.general
    pb.clearContents()
    return pb.setString(s, forType: .string)
  }

  private func removeTemporaryFileIfSafe(_ url: URL) {
    let tempRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path == tempRoot || path.hasPrefix(tempRoot + "/") else { return }
    try? FileManager.default.removeItem(at: url)
  }

  /// Deletes a temporary upload file only after any already-enqueued OCR job
  /// has had a chance to read it, so indexing and cleanup don't race.
  private func scheduleTemporaryFileCleanupAfterOCR(_ url: URL) {
    OCRIndexManager.shared.performAfterPendingRecordWork {
      self.removeTemporaryFileIfSafe(url)
    }
  }

  private func parseISO8601(_ s: String) -> Date? {
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }
    let f2 = ISO8601DateFormatter()
    f2.formatOptions = [.withInternetDateTime]
    return f2.date(from: s)
  }

  private func makeUploadConfiguration(fileUrl: URL, destinationKind: DestinationKind) -> (profile: UploadProfile, remoteFilename: String?) {
    let profile = RuntimePreferences.shared.routedProfile(fileUrl: fileUrl, destinationKind: destinationKind)
    let remoteFilename = generatedRemoteFilename(fileUrl: fileUrl)
    return (profile, remoteFilename)
  }

  private func imageRecord(
    profileId: String,
    localFilePath: String,
    status: UploadStatus,
    kind: UploadKind,
    managedLocalCopy: Bool,
    sourceKind: UploadSourceKind,
    batchId: String?,
    operationKind: UploadOperationKind
  ) -> UploadRecord {
    UploadRecord(
      profileId: profileId,
      localFilePath: localFilePath,
      status: status,
      kind: kind,
      managedLocalCopy: managedLocalCopy,
      sourceKind: sourceKind,
      batchId: batchId,
      operationKind: operationKind,
      ocrStatus: RuntimePreferences.shared.ocrIndexingEnabled ? .pending : .disabled
    )
  }

  private func generatedRemoteFilename(fileUrl: URL) -> String? {
    let preferences = RuntimePreferences.shared
    guard preferences.fileUploadUseRandom16Name || preferences.fileUploadUseNamePattern else { return nil }
    let base = preferences.generateUploadFilenameBase(originalFilename: fileUrl.lastPathComponent)
    let ext = fileUrl.pathExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
    if ext.isEmpty {
      return base
    }
    return "\(base).\(ext)"
  }

  private func finalizeUploadedURL(_ rawURL: String) -> String {
    RuntimePreferences.shared.transformUploadedURL(rawURL)
  }

  private func applyPostUploadTasks(recordId: String, url: String, imageFileUrl: URL?, sourceKind: UploadSourceKind) {
    if sourceKind == .capture {
      applyAfterCaptureTasks(recordId: recordId, url: url, imageFileUrl: imageFileUrl)
    } else {
      applyAfterUploadTasks(url: url, imageFileUrl: imageFileUrl)
    }
  }

  private func applyAfterUploadTasks(url: String, imageFileUrl: URL?) {
    let copyImage = RuntimePreferences.shared.afterUploadCopyImage
    let copyURL = RuntimePreferences.shared.afterUploadCopyURL

    if copyImage || copyURL {
      DispatchQueue.main.async {
        if copyImage {
          if PasteTargetPolicy.shouldPasteURLInsteadOfImageForFrontmostApplication() {
            self.copyToClipboard(url)
            return
          }

          if let imageFileUrl {
            if !self.copyImageToClipboard(imageFileUrl) {
              self.copyToClipboard(url)
            }
          } else {
            self.copyToClipboard(url)
          }
          return
        }

        if copyURL {
          self.copyToClipboard(url)
        }
      }
    }

    if RuntimePreferences.shared.afterUploadOpenURL, let openURL = webURL(url) {
      DispatchQueue.main.async {
        NSWorkspace.shared.open(openURL)
      }
    }
  }

  private func uploadSecondaryS3CopyIfNeeded(
    recordId: String,
    fileUrl: URL,
    primaryProfile: UploadProfile,
    remoteFilename: String?,
    uploadContext: String?,
    expiresSeconds: Int? = nil
  ) async {
    guard let secondaryProfile = RuntimePreferences.shared.secondaryS3Profile(for: primaryProfile) else {
      return
    }

    UploadHistoryStore.shared.updateRecord(id: recordId) { r in
      r.secondaryUploadStatus = .pending
      r.secondaryProfileId = secondaryProfile.id
      r.secondaryURL = nil
      r.secondaryRemotePath = nil
      r.secondaryCompletedAt = nil
      r.secondaryError = nil
    }

    do {
      let result = try await S3Uploader.shared.uploadFile(
        fileUrl: fileUrl,
        profile: secondaryProfile,
        remoteFilename: remoteFilename,
        uploadContext: uploadContext,
        expiresSeconds: expiresSeconds
      )
      let url = finalizeUploadedURL(result.url)
      UploadHistoryStore.shared.updateRecord(id: recordId) { r in
        r.secondaryUploadStatus = .uploaded
        r.secondaryProfileId = secondaryProfile.id
        r.secondaryURL = url
        r.secondaryRemotePath = result.key
        r.secondaryCompletedAt = Date()
        r.secondaryError = nil
      }
    } catch {
      let message = userFacingError(error)
      UploadHistoryStore.shared.updateRecord(id: recordId) { r in
        r.secondaryUploadStatus = .failed
        r.secondaryProfileId = secondaryProfile.id
        r.secondaryCompletedAt = Date()
        r.secondaryError = message
      }
      Notifier.shared.notify(title: "S3 mirror failed", body: message)
    }
  }

  private func applyAfterCaptureTasks(recordId: String, url: String, imageFileUrl: URL?) {
    let tasks = RuntimePreferences.shared.afterCaptureTasks
    DispatchQueue.main.async {
      if tasks.copyImageAndURL, let imageFileUrl {
        if PasteTargetPolicy.shouldPasteURLInsteadOfImageForFrontmostApplication() {
          self.copyToClipboard(url)
        } else if !self.copyImageToClipboard(imageFileUrl), tasks.copyURL {
          self.copyToClipboard(url)
        }
      } else if tasks.copyURL {
        self.copyToClipboard(url)
      }

      if tasks.openEditor {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
          EditorCoordinator.shared.openEditor(forRecordId: recordId)
        }
      }
    }
  }

  private func shouldMirrorImageLocally(sourceKind: UploadSourceKind) -> Bool {
    if sourceKind == .capture {
      return RuntimePreferences.shared.afterCaptureSaveLocalCopy
    }
    return true
  }

  private func shouldKeepLocalPathForImage(sourceKind: UploadSourceKind, managedCopy: Bool) -> Bool {
    if sourceKind == .capture {
      return RuntimePreferences.shared.afterCaptureSaveLocalCopy || managedCopy
    }
    return true
  }

  private func isImageFile(url: URL, mimeType: String?) -> Bool {
    let ext = url.pathExtension.lowercased()
    if imageExtensions.contains(ext) {
      return true
    }
    if let mimeType, mimeType.lowercased().hasPrefix("image/") {
      return true
    }
    return false
  }

  private func mimeExtension(_ mimeType: String?) -> String {
    guard let mimeType else { return "bin" }
    switch mimeType.lowercased() {
    case "image/png": return "png"
    case "image/jpeg": return "jpg"
    case "image/gif": return "gif"
    case "image/webp": return "webp"
    case "image/bmp": return "bmp"
    case "text/plain": return "txt"
    case "application/json": return "json"
    case "text/html": return "html"
    default: return "bin"
    }
  }

  private func safeFilenameComponent(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty { value = "remote-file" }
    value = value.replacingOccurrences(of: "/", with: "-")
    value = value.replacingOccurrences(of: "\\", with: "-")
    return value
  }

  private func downloadRemoteToTemp(urlString: String) async throws -> (fileURL: URL, mimeType: String?) {
    guard let url = URL(string: urlString) else { throw RemoteUploadError.invalidURL }
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
      throw RemoteUploadError.unsupportedScheme
    }

    var req = URLRequest(url: url)
    req.timeoutInterval = 20
    req.httpMethod = "GET"

    let (downloadedURL, response) = try await URLSession.shared.download(for: req)
    defer {
      if FileManager.default.fileExists(atPath: downloadedURL.path) {
        try? FileManager.default.removeItem(at: downloadedURL)
      }
    }

    guard let http = response as? HTTPURLResponse else {
      throw UploadError.invalidResponse
    }
    guard (200...299).contains(http.statusCode) else {
      throw RemoteUploadError.httpStatus(http.statusCode)
    }

    if let lenHeader = http.value(forHTTPHeaderField: "Content-Length"),
       let expected = Int64(lenHeader.trimmingCharacters(in: .whitespacesAndNewlines)),
       expected > Int64(maxRemoteResponseBytes) {
      throw RemoteUploadError.responseTooLarge(Int(expected))
    }

    let fileAttrs = try FileManager.default.attributesOfItem(atPath: downloadedURL.path)
    let fileSize = fileAttrs[.size] as? NSNumber
    guard let rawSize = fileSize else {
      throw UploadError.invalidResponse
    }
    let size = Int64(truncatingIfNeeded: rawSize.int64Value)
    if size > Int64(maxRemoteResponseBytes) {
      throw RemoteUploadError.responseTooLarge(Int(size))
    }
    if size == 0 {
      throw RemoteUploadError.emptyResponse
    }

    let mimeType = http.value(forHTTPHeaderField: "Content-Type")?.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines)
    var baseName = safeFilenameComponent(response.suggestedFilename ?? url.lastPathComponent)
    var ext = URL(fileURLWithPath: baseName).pathExtension.lowercased()
    if ext.isEmpty {
      ext = mimeExtension(mimeType)
      baseName = URL(fileURLWithPath: baseName).deletingPathExtension().lastPathComponent
    } else {
      baseName = URL(fileURLWithPath: baseName).deletingPathExtension().lastPathComponent
    }

    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("CraftyCannon", isDirectory: true)
      .appendingPathComponent("RemoteDownloads", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

    let fileURL = tempRoot.appendingPathComponent("\(baseName)-\(UUID().uuidString).\(ext)")
    try FileManager.default.moveItem(at: downloadedURL, to: fileURL)
    return (fileURL, mimeType)
  }

  private func tempTextFile(contents: String) throws -> URL {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("CraftyCannon", isDirectory: true)
      .appendingPathComponent("TextUploads", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let fileURL = tempRoot.appendingPathComponent("text-\(UUID().uuidString).txt")
    try Data(contents.utf8).write(to: fileURL, options: [.atomic])
    return fileURL
  }

  private func collectFolderFiles(folderURL: URL, includeSubdirectories: Bool) -> [URL] {
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
      return []
    }

    let options: FileManager.DirectoryEnumerationOptions = includeSubdirectories
      ? [.skipsHiddenFiles]
      : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
    let keys: [URLResourceKey] = [.isRegularFileKey]
    guard let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: keys, options: options) else {
      return []
    }

    var files: [URL] = []
    for case let fileURL as URL in enumerator {
      guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
            values.isRegularFile == true else {
        continue
      }
      files.append(fileURL)
    }

    return files.sorted { $0.path < $1.path }
  }

  private func copyImageToClipboard(_ imageFileUrl: URL) -> Bool {
    writeImageToClipboard(imageFileUrl: imageFileUrl)
  }

  private func writeImageToClipboard(imageFileUrl: URL) -> Bool {
    let representations = imagePasteboardRepresentations(from: imageFileUrl)
    guard !representations.isEmpty else { return false }

    let pb = NSPasteboard.general
    pb.clearContents()

    let imageItem = NSPasteboardItem()
    var wroteImage = false
    for representation in representations {
      if imageItem.setData(representation.data, forType: representation.type) {
        wroteImage = true
      }
    }
    guard wroteImage else { return false }

    return pb.writeObjects([imageItem])
  }

  private func imagePasteboardRepresentations(from imageFileUrl: URL) -> [(type: NSPasteboard.PasteboardType, data: Data)] {
    var output: [(type: NSPasteboard.PasteboardType, data: Data)] = []
    let ext = imageFileUrl.pathExtension.lowercased()
    if let raw = try? Data(contentsOf: imageFileUrl),
       let rawType = pasteboardType(forImageExtension: ext) {
      output.append((type: rawType, data: raw))
    }

    if let image = NSImage(contentsOf: imageFileUrl),
       let tiff = image.tiffRepresentation {
      if !output.contains(where: { $0.type == .tiff }) {
        output.append((type: .tiff, data: tiff))
      }

      if !output.contains(where: { $0.type == .png }),
         let bitmap = NSBitmapImageRep(data: tiff),
         let png = bitmap.representation(using: .png, properties: [:]) {
        output.append((type: .png, data: png))
      }
    }

    var deduped: [(type: NSPasteboard.PasteboardType, data: Data)] = []
    for entry in output where !entry.data.isEmpty {
      if !deduped.contains(where: { $0.type == entry.type }) {
        deduped.append(entry)
      }
    }
    return deduped
  }

  private func pasteboardType(forImageExtension ext: String) -> NSPasteboard.PasteboardType? {
    switch ext {
    case "png":
      return .png
    case "jpg", "jpeg":
      return NSPasteboard.PasteboardType("public.jpeg")
    case "gif":
      return NSPasteboard.PasteboardType("com.compuserve.gif")
    case "webp":
      return NSPasteboard.PasteboardType("org.webmproject.webp")
    case "bmp":
      return NSPasteboard.PasteboardType("com.microsoft.bmp")
    case "heic":
      return NSPasteboard.PasteboardType("public.heic")
    case "heif":
      return NSPasteboard.PasteboardType("public.heif")
    case "tif", "tiff":
      return .tiff
    default:
      return nil
    }
  }

  private func storeLocalCopy(fileUrl: URL) throws -> URL {
    let fm = FileManager.default
    let imagesDir = try AppSupport.imagesDir()

    let dateFolder = localYYYYMMDD()
    let dayDir = imagesDir.appendingPathComponent(dateFolder, isDirectory: true)
    try fm.createDirectory(at: dayDir, withIntermediateDirectories: true)

    let ext = fileUrl.pathExtension.isEmpty ? "png" : fileUrl.pathExtension.lowercased()
    var dest: URL
    repeat {
      let name = UUID().uuidString.replacingOccurrences(of: "-", with: "")
      dest = dayDir.appendingPathComponent("\(name).\(ext)")
    } while fm.fileExists(atPath: dest.path)

    try fm.copyItem(at: fileUrl, to: dest)
    return dest
  }

  static func normalizedLocalMirrorPrefix(_ value: String?) -> String? {
    let cleaned = (value ?? "")
      .lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
      .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    guard !cleaned.isEmpty else { return nil }
    return cleaned
  }

  static func buildLocalMirrorFilename(
    fileUrl: URL,
    preferredPrefix: String?,
    fallbackPrefix: String = "capture",
    randomToken: String? = nil
  ) -> String {
    let ext = fileUrl.pathExtension.isEmpty ? "png" : fileUrl.pathExtension.lowercased()
    let rawToken = randomToken ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let normalizedToken = rawToken
      .lowercased()
      .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    let tokenBase = normalizedToken.isEmpty
      ? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
      : normalizedToken
    let token = String(tokenBase.prefix(8))

    guard preferredPrefix != nil else {
      return "\(token).\(ext)"
    }

    let prefix = normalizedLocalMirrorPrefix(preferredPrefix)
      ?? normalizedLocalMirrorPrefix(fallbackPrefix)
      ?? "capture"
    return "\(prefix)-\(token).\(ext)"
  }

  private func mirrorToScreenshotsFolder(fileUrl: URL, preferredPrefix: String?) throws -> URL {
    let fm = FileManager.default
    let imagesDir = try AppSupport.resolvedScreenshotsDir()

    let dateFolder = localYYYYMMDD()
    let dayDir = imagesDir.appendingPathComponent(dateFolder, isDirectory: true)
    try fm.createDirectory(at: dayDir, withIntermediateDirectories: true)

    var dest: URL
    repeat {
      let filename = Self.buildLocalMirrorFilename(fileUrl: fileUrl, preferredPrefix: preferredPrefix)
      dest = dayDir.appendingPathComponent(filename)
    } while fm.fileExists(atPath: dest.path)

    try fm.copyItem(at: fileUrl, to: dest)
    return dest
  }

  private func localYYYYMMDD(d: Date = Date()) -> String {
    let cal = Calendar.current
    let y = cal.component(.year, from: d)
    let m = String(cal.component(.month, from: d)).pad2()
    let day = String(cal.component(.day, from: d)).pad2()
    return "\(y)-\(m)-\(day)"
  }
}

private extension String {
  func pad2() -> String { self.count == 1 ? "0" + self : self }
}
