import Foundation

enum UploadError: Error {
  case missingAuthToken
  case missingS3Credentials
  case badEndpoint
  case serverError(String)
  case invalidResponse
}

final class Uploader {
  static let shared = Uploader()
  private init() {}

  struct EndpointValidationResult {
    let isValid: Bool
    let message: String
  }

  struct ExpiringImageUploadResult: Decodable {
    let url: String
    let expiresAt: String
    let maxExpiresSeconds: Int?
  }

  struct DirectUploadFileResult {
    let url: String
    let key: String?
    let expiresAt: Date?
  }

  private func endpointURL(from raw: String, overridePath: String, stripSuffixes: [String]) throws -> URL {
    guard let u = URL(string: raw) else { throw UploadError.badEndpoint }
    guard let scheme = u.scheme?.lowercased(), scheme == "https", u.host != nil else {
      throw UploadError.badEndpoint
    }

    guard var c = URLComponents(url: u, resolvingAgainstBaseURL: false) else {
      throw UploadError.badEndpoint
    }

    c.query = nil
    c.fragment = nil

    var basePath = c.path
    if basePath == "/" { basePath = "" }
    if basePath.count > 1 && basePath.hasSuffix("/") {
      basePath = String(basePath.dropLast())
    }

    for s in stripSuffixes {
      let suffix = s.hasPrefix("/") ? s : "/" + s
      if basePath == suffix {
        basePath = ""
      } else if basePath.hasSuffix(suffix) {
        basePath = String(basePath.dropLast(suffix.count))
        if basePath == "/" { basePath = "" }
        if basePath.count > 1 && basePath.hasSuffix("/") {
          basePath = String(basePath.dropLast())
        }
      }
    }

    c.path = basePath.isEmpty ? overridePath : basePath + overridePath

    guard let out = c.url else { throw UploadError.badEndpoint }
    return out
  }

  private func requiredZiplineToken(for profile: UploadProfile) throws -> String {
    let token = Settings.shared.getApiKey(profileId: profile.id)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !token.isEmpty { return token }
    throw UploadError.missingAuthToken
  }

  private func iso8601UTC(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
  }

  private func parseISO8601(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }

    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: value)
  }

  private func parseZiplineUploadResponse(_ data: Data) throws -> (url: String, deletesAt: Date?) {
    guard
      let obj = try? JSONSerialization.jsonObject(with: data, options: []),
      let dict = obj as? [String: Any]
    else {
      throw UploadError.invalidResponse
    }

    var deletesAt: Date? = nil
    if let value = dict["deletesAt"] as? String ?? dict["deletes_at"] as? String {
      deletesAt = parseISO8601(value)
    }

    if let files = dict["files"] as? [[String: Any]], let first = files.first {
      if deletesAt == nil, let value = first["deletesAt"] as? String ?? first["deletes_at"] as? String {
        deletesAt = parseISO8601(value)
      }
      if let url = first["url"] as? String, !url.isEmpty {
        return (url, deletesAt)
      }
      if let url = first["link"] as? String, !url.isEmpty {
        return (url, deletesAt)
      }
    }

    if let url = dict["url"] as? String, !url.isEmpty {
      return (url, deletesAt)
    }

    throw UploadError.invalidResponse
  }

  func uploadImage(
    fileUrl: URL,
    uploadContext: String? = nil,
    profile: UploadProfile? = nil,
    remoteFilename: String? = nil
  ) async throws -> String {
    let targetProfile = profile ?? Settings.shared.activeProfile
    switch targetProfile.backend {
    case .ziplineV4:
      let (url, _) = try await uploadZipline(
        fileUrl: fileUrl,
        deletesAt: nil,
        profile: targetProfile,
        remoteFilename: remoteFilename
      )
      return url
    case .s3Compatible:
      let result = try await S3Uploader.shared.uploadFile(
        fileUrl: fileUrl,
        profile: targetProfile,
        remoteFilename: remoteFilename,
        uploadContext: uploadContext
      )
      return result.url
    }
  }

  func uploadImageWithExpiry(
    fileUrl: URL,
    uploadContext: String? = nil,
    expiresSeconds: Int,
    profile: UploadProfile? = nil,
    remoteFilename: String? = nil
  ) async throws -> ExpiringImageUploadResult {
    let targetProfile = profile ?? Settings.shared.activeProfile
    switch targetProfile.backend {
    case .ziplineV4:
      let desired = Date().addingTimeInterval(TimeInterval(expiresSeconds))
      let (url, deletesAt) = try await uploadZipline(
        fileUrl: fileUrl,
        deletesAt: desired,
        profile: targetProfile,
        remoteFilename: remoteFilename
      )
      return ExpiringImageUploadResult(
        url: url,
        expiresAt: iso8601UTC(deletesAt ?? desired),
        maxExpiresSeconds: nil
      )
    case .s3Compatible:
      let result = try await S3Uploader.shared.uploadFile(
        fileUrl: fileUrl,
        profile: targetProfile,
        remoteFilename: remoteFilename,
        uploadContext: uploadContext,
        expiresSeconds: expiresSeconds
      )
      return ExpiringImageUploadResult(
        url: result.url,
        expiresAt: iso8601UTC(result.expiresAt ?? Date().addingTimeInterval(TimeInterval(expiresSeconds))),
        maxExpiresSeconds: nil
      )
    }
  }

  func uploadFileDirect(
    fileUrl: URL,
    expiresSeconds: Int,
    profile: UploadProfile? = nil,
    remoteFilename: String? = nil
  ) async throws -> DirectUploadFileResult {
    let targetProfile = profile ?? Settings.shared.activeProfile
    switch targetProfile.backend {
    case .s3Compatible:
      let result = try await S3Uploader.shared.uploadFile(
        fileUrl: fileUrl,
        profile: targetProfile,
        remoteFilename: remoteFilename,
        uploadContext: "file",
        expiresSeconds: expiresSeconds
      )
      return DirectUploadFileResult(
        url: result.url,
        key: result.key,
        expiresAt: result.expiresAt
      )
    case .ziplineV4:
      let desired = Date().addingTimeInterval(TimeInterval(expiresSeconds))
      let (url, deletesAt) = try await uploadZipline(
        fileUrl: fileUrl,
        deletesAt: desired,
        profile: targetProfile,
        remoteFilename: remoteFilename
      )
      return DirectUploadFileResult(
        url: url,
        key: nil,
        expiresAt: deletesAt ?? desired
      )
    }
  }

  func uploadZipline(
    fileUrl: URL,
    deletesAt: Date?,
    profile: UploadProfile? = nil,
    remoteFilename: String? = nil
  ) async throws -> (url: String, deletesAt: Date?) {
    let targetProfile = profile ?? Settings.shared.activeProfile
    guard targetProfile.backend == .ziplineV4 else {
      throw UploadError.badEndpoint
    }

    let token = try requiredZiplineToken(for: targetProfile)
    let endpoint = try endpointURL(
      from: targetProfile.endpoint,
      overridePath: "/api/upload",
      stripSuffixes: ["/api/upload"]
    )

    let boundary = "Boundary-\(UUID().uuidString)"
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("CraftyCannon", isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let bodyUrl = tmpDir.appendingPathComponent("multipart-\(UUID().uuidString)")

    let filename = effectiveUploadFilename(fileUrl: fileUrl, overrideFilename: remoteFilename)
    let preamble = "--\(boundary)\r\n" +
      "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n" +
      "Content-Type: application/octet-stream\r\n\r\n"
    let epilogue = "\r\n--\(boundary)--\r\n"

    FileManager.default.createFile(atPath: bodyUrl.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: bodyUrl) }
    let fh = try FileHandle(forWritingTo: bodyUrl)
    defer { try? fh.close() }
    try fh.write(contentsOf: Data(preamble.utf8))

    let inFh = try FileHandle(forReadingFrom: fileUrl)
    defer { try? inFh.close() }
    while true {
      let chunk = try inFh.read(upToCount: 1024 * 1024)
      if let chunk, !chunk.isEmpty {
        try fh.write(contentsOf: chunk)
      } else {
        break
      }
    }

    try fh.write(contentsOf: Data(epilogue.utf8))
    try fh.close()

    var req = URLRequest(url: endpoint)
    req.httpMethod = "POST"
    req.setValue(token, forHTTPHeaderField: "Authorization")
    req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    Self.applyZiplineFilenameHeaders(to: &req, filename: filename)
    if let deletesAt {
      req.setValue("date=\(iso8601UTC(deletesAt))", forHTTPHeaderField: "x-zipline-deletes-at")
    }

    let (data, resp) = try await URLSession.shared.upload(for: req, fromFile: bodyUrl)

    guard let http = resp as? HTTPURLResponse else {
      throw UploadError.invalidResponse
    }

    if http.statusCode < 200 || http.statusCode > 299 {
      let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
      throw UploadError.serverError(msg)
    }

    return try parseZiplineUploadResponse(data)
  }

  private func effectiveUploadFilename(fileUrl: URL, overrideFilename: String?) -> String {
    let cleanedOverride = (overrideFilename ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let raw = cleanedOverride.isEmpty ? fileUrl.lastPathComponent : cleanedOverride
    return Self.multipartSafeFilename(raw)
  }

  /// The filename is emitted inside a double-quoted Content-Disposition value.
  /// Strip characters that would terminate the quoted string or inject header
  /// lines into the multipart body.
  static func multipartSafeFilename(_ raw: String) -> String {
    let cleaned = raw
      .components(separatedBy: CharacterSet(charactersIn: "\"\\\r\n"))
      .joined(separator: "_")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let meaningful = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return meaningful.isEmpty ? "file.bin" : cleaned
  }

  static func applyZiplineFilenameHeaders(to request: inout URLRequest, filename: String) {
    let cleaned = multipartSafeFilename(filename)
    let ext = (cleaned as NSString).pathExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    let base = (cleaned as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)

    request.setValue(base.isEmpty ? cleaned : base, forHTTPHeaderField: "x-zipline-filename")
    if !ext.isEmpty {
      request.setValue(ext, forHTTPHeaderField: "x-zipline-file-extension")
    }
  }

  func validateEndpoint(
    profile: UploadProfile,
    s3AccessKeyId: String? = nil,
    s3SecretAccessKey: String? = nil,
    s3SessionToken: String? = nil
  ) async -> EndpointValidationResult {
    if profile.backend == .s3Compatible {
      return await S3Uploader.shared.probe(
        profile: profile,
        accessKeyIdOverride: s3AccessKeyId,
        secretAccessKeyOverride: s3SecretAccessKey,
        sessionTokenOverride: s3SessionToken
      )
    }

    let pingURL: URL
    do {
      pingURL = try endpointURL(
        from: profile.endpoint,
        overridePath: "/api/upload",
        stripSuffixes: ["/api/upload"]
      )
    } catch {
      return EndpointValidationResult(isValid: false, message: "Endpoint is not a valid URL.")
    }

    var req = URLRequest(url: pingURL)
    req.timeoutInterval = 8
    req.httpMethod = "HEAD"

    do {
      let (data, response) = try await URLSession.shared.data(for: req)
      guard let http = response as? HTTPURLResponse else {
        return EndpointValidationResult(isValid: false, message: "Endpoint did not return an HTTP response.")
      }
      return Self.endpointValidationResult(
        backend: profile.backend,
        statusCode: http.statusCode,
        body: String(data: data, encoding: .utf8)
      )
    } catch {
      return EndpointValidationResult(
        isValid: false,
        message: "Could not reach endpoint (\(error.localizedDescription))."
      )
    }
  }

  /// Blocking variant for callers that cannot await. Must not be called on the
  /// main thread — it parks the calling thread on a semaphore for up to 12s.
  func validateEndpointBlocking(
    profile: UploadProfile,
    s3AccessKeyId: String? = nil,
    s3SecretAccessKey: String? = nil,
    s3SessionToken: String? = nil
  ) -> EndpointValidationResult {
    let semaphore = DispatchSemaphore(value: 0)
    var validation = EndpointValidationResult(isValid: false, message: "Validation timed out.")
    Task {
      validation = await validateEndpoint(
        profile: profile,
        s3AccessKeyId: s3AccessKeyId,
        s3SecretAccessKey: s3SecretAccessKey,
        s3SessionToken: s3SessionToken
      )
      semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 12)
    return validation
  }

  static func endpointValidationResult(
    backend: UploadBackend,
    statusCode: Int,
    body: String?
  ) -> EndpointValidationResult {
    switch backend {
    case .ziplineV4:
      if (200...299).contains(statusCode) ||
        statusCode == 401 ||
        statusCode == 403 ||
        statusCode == 404 ||
        statusCode == 405 {
        if statusCode == 404 {
          return EndpointValidationResult(isValid: true, message: "Zipline endpoint responded (HTTP 404). Assuming reachable.")
        }
        return EndpointValidationResult(isValid: true, message: "Zipline endpoint is reachable.")
      }
      return EndpointValidationResult(
        isValid: false,
        message: "Zipline probe returned HTTP \(statusCode)."
      )
    case .s3Compatible:
      return EndpointValidationResult(isValid: false, message: "S3 validation must use S3 backend probe.")
    }
  }
}
