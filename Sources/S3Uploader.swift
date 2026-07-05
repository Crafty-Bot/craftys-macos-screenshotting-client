import CryptoKit
import Foundation

enum S3UploadError: Error {
  case missingConfiguration(String)
  case missingCredentials
  case invalidEndpoint
  case fileNotFound
  case invalidResponse
  case serverError(String)
}

struct S3UploadResult {
  var key: String
  var url: String
  var expiresAt: Date?
}

final class S3Uploader {
  static let shared = S3Uploader()
  private init() {}

  private struct Credentials {
    var accessKeyId: String
    var secretAccessKey: String
    var sessionToken: String?
  }

  private struct EndpointInfo {
    var scheme: String
    var host: String
    var port: Int?
    var basePath: String
  }

  func uploadFile(
    fileUrl: URL,
    profile: UploadProfile,
    remoteFilename: String?,
    uploadContext: String?,
    expiresSeconds: Int? = nil
  ) async throws -> S3UploadResult {
    guard FileManager.default.fileExists(atPath: fileUrl.path) else {
      throw S3UploadError.fileNotFound
    }

    let cfg = try requiredConfig(for: profile)
    let creds = try requiredCredentials(for: profile)
    let endpoint = try parseEndpoint(cfg.endpoint)

    let filename = effectiveFilename(fileUrl: fileUrl, remoteFilename: remoteFilename)
    let key = makeObjectKey(
      date: Date(),
      filename: filename,
      keyPrefix: cfg.keyPrefix,
      uploadContext: uploadContext
    )
    let contentType = mimeType(for: fileUrl.pathExtension)

    var putReq = try signedRequest(
      method: "PUT",
      key: key,
      queryItems: [],
      payloadHash: try sha256Hex(fileUrl: fileUrl),
      contentType: contentType,
      endpoint: endpoint,
      cfg: cfg,
      creds: creds
    )
    putReq.httpMethod = "PUT"

    let (_, putResp) = try await URLSession.shared.upload(for: putReq, fromFile: fileUrl)
    guard let putHTTP = putResp as? HTTPURLResponse else {
      throw S3UploadError.invalidResponse
    }
    guard (200...299).contains(putHTTP.statusCode) else {
      throw S3UploadError.serverError("S3 PUT failed (HTTP \(putHTTP.statusCode))")
    }

    if let expiresSeconds, expiresSeconds > 0 {
      let signed = try signedGetURL(key: key, expiresSeconds: expiresSeconds, cfg: cfg, creds: creds, endpoint: endpoint)
      return S3UploadResult(key: key, url: signed.url.absoluteString, expiresAt: signed.expiresAt)
    }

    if let publicURL = publicURL(forKey: key, cfg: cfg, endpoint: endpoint) {
      return S3UploadResult(key: key, url: publicURL.absoluteString, expiresAt: nil)
    }

    if cfg.useSignedGetURL {
      let secs = max(60, min(7 * 24 * 60 * 60, cfg.defaultGetExpirySeconds))
      let signed = try signedGetURL(key: key, expiresSeconds: secs, cfg: cfg, creds: creds, endpoint: endpoint)
      return S3UploadResult(key: key, url: signed.url.absoluteString, expiresAt: signed.expiresAt)
    }

    let fallback = try objectURL(key: key, endpoint: endpoint, cfg: cfg)
    return S3UploadResult(key: key, url: fallback.absoluteString, expiresAt: nil)
  }

  func probe(
    profile: UploadProfile,
    accessKeyIdOverride: String? = nil,
    secretAccessKeyOverride: String? = nil,
    sessionTokenOverride: String? = nil
  ) async -> Uploader.EndpointValidationResult {
    do {
      let cfg = try requiredConfig(for: profile)
      let creds = try requiredCredentials(
        for: profile,
        accessKeyIdOverride: accessKeyIdOverride,
        secretAccessKeyOverride: secretAccessKeyOverride,
        sessionTokenOverride: sessionTokenOverride
      )
      let endpoint = try parseEndpoint(cfg.endpoint)
      let key = makeObjectKey(
        date: Date(),
        filename: "craftycannon-probe.txt",
        keyPrefix: cfg.keyPrefix,
        uploadContext: "probe"
      )

      let body = Data("probe".utf8)
      let payloadHash = sha256Hex(data: body)
      var putReq = try signedRequest(
        method: "PUT",
        key: key,
        queryItems: [],
        payloadHash: payloadHash,
        contentType: "text/plain; charset=utf-8",
        endpoint: endpoint,
        cfg: cfg,
        creds: creds
      )
      putReq.httpMethod = "PUT"
      putReq.httpBody = body

      let (_, putResp) = try await URLSession.shared.data(for: putReq)
      guard let putHTTP = putResp as? HTTPURLResponse else {
        return Uploader.EndpointValidationResult(isValid: false, message: "S3 probe returned a non-HTTP response.")
      }

      if !(200...299).contains(putHTTP.statusCode) {
        return Uploader.EndpointValidationResult(
          isValid: false,
          message: "S3 probe upload failed (HTTP \(putHTTP.statusCode)). Check credentials, bucket policy, region, and endpoint."
        )
      }

      // Best-effort cleanup.
      if let deleteReq = try? signedRequest(
        method: "DELETE",
        key: key,
        queryItems: [],
        payloadHash: "UNSIGNED-PAYLOAD",
        contentType: nil,
        endpoint: endpoint,
        cfg: cfg,
        creds: creds
      ) {
        _ = try? await URLSession.shared.data(for: deleteReq)
      }

      return Uploader.EndpointValidationResult(isValid: true, message: "S3 endpoint and credentials validated.")
    } catch S3UploadError.missingConfiguration(let msg) {
      return Uploader.EndpointValidationResult(isValid: false, message: msg)
    } catch S3UploadError.missingCredentials {
      return Uploader.EndpointValidationResult(
        isValid: false,
        message: "Missing S3 credentials. Set access key ID and secret access key in profile settings."
      )
    } catch {
      return Uploader.EndpointValidationResult(isValid: false, message: "S3 probe failed (\(error.localizedDescription)).")
    }
  }

  private func requiredConfig(for profile: UploadProfile) throws -> S3DestinationConfig {
    guard profile.backend == .s3Compatible else {
      throw S3UploadError.missingConfiguration("Profile backend is not S3-compatible.")
    }
    guard let cfg = profile.s3Config else {
      throw S3UploadError.missingConfiguration("Missing S3 configuration in profile.")
    }
    if cfg.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw S3UploadError.missingConfiguration("S3 endpoint is required.")
    }
    if cfg.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw S3UploadError.missingConfiguration("S3 region is required.")
    }
    if cfg.bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw S3UploadError.missingConfiguration("S3 bucket is required.")
    }
    return cfg
  }

  private func requiredCredentials(
    for profile: UploadProfile,
    accessKeyIdOverride: String? = nil,
    secretAccessKeyOverride: String? = nil,
    sessionTokenOverride: String? = nil
  ) throws -> Credentials {
    let accessKeyId = (accessKeyIdOverride ?? Settings.shared.getS3AccessKeyId(profileId: profile.id))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let secretAccessKey = (secretAccessKeyOverride ?? Settings.shared.getS3SecretAccessKey(profileId: profile.id))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let sessionToken = (sessionTokenOverride ?? Settings.shared.getS3SessionToken(profileId: profile.id))?
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if accessKeyId.isEmpty || secretAccessKey.isEmpty {
      throw S3UploadError.missingCredentials
    }
    return Credentials(
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      sessionToken: sessionToken?.isEmpty == true ? nil : sessionToken
    )
  }

  private func parseEndpoint(_ raw: String) throws -> EndpointInfo {
    guard let url = URL(string: raw) else { throw S3UploadError.invalidEndpoint }
    guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
      throw S3UploadError.invalidEndpoint
    }
    guard let host = url.host, !host.isEmpty else { throw S3UploadError.invalidEndpoint }

    var basePath = url.path
    if basePath == "/" { basePath = "" }
    if basePath.count > 1 && basePath.hasSuffix("/") {
      basePath.removeLast()
    }

    return EndpointInfo(
      scheme: scheme,
      host: host,
      port: url.port,
      basePath: basePath
    )
  }

  private func effectiveFilename(fileUrl: URL, remoteFilename: String?) -> String {
    let trimmed = (remoteFilename ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      return safeFilename(trimmed)
    }
    return safeFilename(fileUrl.lastPathComponent)
  }

  private func safeFilename(_ raw: String) -> String {
    let base = raw.split(separator: "/").last?.split(separator: "\\").last.map(String.init) ?? raw
    let cleaned = base.replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
    let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return trimmed.isEmpty ? "file.bin" : String(trimmed.prefix(180))
  }

  private func sanitizeContext(_ raw: String?) -> String {
    let cleaned = (raw ?? "")
      .lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
      .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return String(cleaned.prefix(64))
  }

  private func makeObjectKey(date: Date, filename: String, keyPrefix: String, uploadContext: String?) -> String {
    let d = dateFolder(date)
    let random = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let context = sanitizeContext(uploadContext)
    let name = context.isEmpty ? "\(random)-\(filename)" : "\(context)-\(random)-\(filename)"

    let trimmedPrefix = keyPrefix
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

    if trimmedPrefix.isEmpty {
      return "\(d)/\(name)"
    }
    return "\(trimmedPrefix)/\(d)/\(name)"
  }

  private func dateFolder(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
  }

  private func mimeType(for extRaw: String) -> String {
    switch extRaw.lowercased() {
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "webp": return "image/webp"
    case "bmp": return "image/bmp"
    case "tif", "tiff": return "image/tiff"
    case "heic": return "image/heic"
    case "heif": return "image/heif"
    case "txt": return "text/plain; charset=utf-8"
    case "json": return "application/json"
    case "pdf": return "application/pdf"
    case "zip": return "application/zip"
    default: return "application/octet-stream"
    }
  }

  private func sha256Hex(fileUrl: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: fileUrl)
    defer { try? handle.close() }

    var hasher = SHA256()
    while true {
      let chunk = try handle.read(upToCount: 1024 * 1024)
      guard let chunk, !chunk.isEmpty else { break }
      hasher.update(data: chunk)
    }
    return Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()
  }

  private func sha256Hex(data: Data) -> String {
    Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined()
  }

  private func signedRequest(
    method: String,
    key: String,
    queryItems: [URLQueryItem],
    payloadHash: String,
    contentType: String?,
    endpoint: EndpointInfo,
    cfg: S3DestinationConfig,
    creds: Credentials
  ) throws -> URLRequest {
    let region = cfg.region.trimmingCharacters(in: .whitespacesAndNewlines)
    let amzDate = timestamp()
    let dateStamp = String(amzDate.prefix(8))
    let service = "s3"

    let objectURL = try objectURL(key: key, endpoint: endpoint, cfg: cfg, queryItems: queryItems)
    guard let components = URLComponents(url: objectURL, resolvingAgainstBaseURL: false) else {
      throw S3UploadError.invalidEndpoint
    }
    let canonicalURI = canonicalPath(components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath)

    var headers: [(String, String)] = []
    headers.append(("host", hostHeader(endpoint: endpoint, cfg: cfg)))
    headers.append(("x-amz-content-sha256", payloadHash))
    headers.append(("x-amz-date", amzDate))
    if let token = creds.sessionToken, !token.isEmpty {
      headers.append(("x-amz-security-token", token))
    }
    if let contentType, !contentType.isEmpty {
      headers.append(("content-type", contentType))
    }

    let sortedHeaders = headers
      .map { (k: $0.0.lowercased(), v: $0.1.trimmingCharacters(in: .whitespacesAndNewlines)) }
      .sorted { $0.k < $1.k }

    let canonicalHeaders = sortedHeaders.map { "\($0.k):\($0.v)\n" }.joined()
    let signedHeaders = sortedHeaders.map(\.k).joined(separator: ";")
    let canonicalQuery = canonicalQueryString(queryItems)

    let canonicalRequest = [
      method,
      canonicalURI,
      canonicalQuery,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].joined(separator: "\n")

    let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
    let stringToSign = [
      "AWS4-HMAC-SHA256",
      amzDate,
      credentialScope,
      sha256Hex(data: Data(canonicalRequest.utf8)),
    ].joined(separator: "\n")

    let signingKey = signingKey(secretKey: creds.secretAccessKey, date: dateStamp, region: region, service: service)
    let signature = hmacHex(key: signingKey, data: Data(stringToSign.utf8))

    let authorization = "AWS4-HMAC-SHA256 Credential=\(creds.accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

    var req = URLRequest(url: objectURL)
    req.setValue(authorization, forHTTPHeaderField: "Authorization")
    req.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
    req.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
    if let contentType, !contentType.isEmpty {
      req.setValue(contentType, forHTTPHeaderField: "Content-Type")
    }
    if let token = creds.sessionToken, !token.isEmpty {
      req.setValue(token, forHTTPHeaderField: "x-amz-security-token")
    }
    return req
  }

  private func signedGetURL(
    key: String,
    expiresSeconds: Int,
    cfg: S3DestinationConfig,
    creds: Credentials,
    endpoint: EndpointInfo
  ) throws -> (url: URL, expiresAt: Date) {
    let region = cfg.region.trimmingCharacters(in: .whitespacesAndNewlines)
    let amzDate = timestamp()
    let dateStamp = String(amzDate.prefix(8))
    let service = "s3"
    let expires = max(60, min(7 * 24 * 60 * 60, expiresSeconds))
    let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"

    var query: [URLQueryItem] = [
      URLQueryItem(name: "X-Amz-Algorithm", value: "AWS4-HMAC-SHA256"),
      URLQueryItem(name: "X-Amz-Credential", value: "\(creds.accessKeyId)/\(credentialScope)"),
      URLQueryItem(name: "X-Amz-Date", value: amzDate),
      URLQueryItem(name: "X-Amz-Expires", value: String(expires)),
      URLQueryItem(name: "X-Amz-SignedHeaders", value: "host"),
    ]
    if let token = creds.sessionToken, !token.isEmpty {
      query.append(URLQueryItem(name: "X-Amz-Security-Token", value: token))
    }

    let objectURL = try objectURL(key: key, endpoint: endpoint, cfg: cfg, queryItems: query)
    guard var components = URLComponents(url: objectURL, resolvingAgainstBaseURL: false) else {
      throw S3UploadError.invalidEndpoint
    }

    let canonicalURI = canonicalPath(components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath)
    let canonicalQuery = canonicalQueryString(query)
    let canonicalHeaders = "host:\(hostHeader(endpoint: endpoint, cfg: cfg))\n"
    let canonicalRequest = [
      "GET",
      canonicalURI,
      canonicalQuery,
      canonicalHeaders,
      "host",
      "UNSIGNED-PAYLOAD",
    ].joined(separator: "\n")

    let stringToSign = [
      "AWS4-HMAC-SHA256",
      amzDate,
      credentialScope,
      sha256Hex(data: Data(canonicalRequest.utf8)),
    ].joined(separator: "\n")

    let signingKey = signingKey(secretKey: creds.secretAccessKey, date: dateStamp, region: region, service: service)
    let signature = hmacHex(key: signingKey, data: Data(stringToSign.utf8))

    query.append(URLQueryItem(name: "X-Amz-Signature", value: signature))
    components.percentEncodedQuery = canonicalQueryString(query)
    guard let signedURL = components.url else { throw S3UploadError.invalidEndpoint }

    let expiresAt = Date().addingTimeInterval(TimeInterval(expires))
    return (signedURL, expiresAt)
  }

  private func publicURL(forKey key: String, cfg: S3DestinationConfig, endpoint: EndpointInfo) -> URL? {
    let trimmed = cfg.publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, var comps = URLComponents(string: trimmed) else { return nil }
    comps.query = nil
    comps.fragment = nil
    let escapedKey = key.split(separator: "/").map { part in
      part.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(part)
    }.joined(separator: "/")
    var path = comps.path
    if !path.hasSuffix("/") { path += "/" }
    comps.path = path + escapedKey
    return comps.url
  }

  private func objectURL(
    key: String,
    endpoint: EndpointInfo,
    cfg: S3DestinationConfig,
    queryItems: [URLQueryItem] = []
  ) throws -> URL {
    var comps = URLComponents()
    comps.scheme = endpoint.scheme
    comps.port = endpoint.port

    let escapedKey = key.split(separator: "/").map { part in
      part.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(part)
    }.joined(separator: "/")

    let bucket = cfg.bucket.trimmingCharacters(in: .whitespacesAndNewlines)
    if cfg.forcePathStyle {
      comps.host = endpoint.host
      let prefix = endpoint.basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      if prefix.isEmpty {
        comps.path = "/\(bucket)/\(escapedKey)"
      } else {
        comps.path = "/\(prefix)/\(bucket)/\(escapedKey)"
      }
    } else {
      comps.host = "\(bucket).\(endpoint.host)"
      let prefix = endpoint.basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      comps.path = prefix.isEmpty ? "/\(escapedKey)" : "/\(prefix)/\(escapedKey)"
    }

    if !queryItems.isEmpty {
      comps.queryItems = queryItems
    }
    guard let out = comps.url else { throw S3UploadError.invalidEndpoint }
    return out
  }

  private func hostHeader(endpoint: EndpointInfo, cfg: S3DestinationConfig) -> String {
    // Trim to match objectURL, which builds the request host from the trimmed
    // bucket — a mismatch here would produce an unverifiable signature.
    let bucket = cfg.bucket.trimmingCharacters(in: .whitespacesAndNewlines)
    let host: String = cfg.forcePathStyle ? endpoint.host : "\(bucket).\(endpoint.host)"
    if let port = endpoint.port {
      return "\(host):\(port)"
    }
    return host
  }

  private func canonicalPath(_ path: String) -> String {
    if path.isEmpty { return "/" }
    return path
  }

  private func canonicalQueryString(_ queryItems: [URLQueryItem]) -> String {
    let pairs: [(String, String)] = queryItems.map { item in
      (awsPercentEncode(item.name), awsPercentEncode(item.value ?? ""))
    }
    return pairs
      .sorted { lhs, rhs in
        if lhs.0 == rhs.0 { return lhs.1 < rhs.1 }
        return lhs.0 < rhs.0
      }
      .map { "\($0.0)=\($0.1)" }
      .joined(separator: "&")
  }

  private func awsPercentEncode(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }

  private func timestamp(_ date: Date = Date()) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    return f.string(from: date)
  }

  private func signingKey(secretKey: String, date: String, region: String, service: String) -> SymmetricKey {
    let kSecret = Data(("AWS4" + secretKey).utf8)
    let kDate = hmac(key: kSecret, data: Data(date.utf8))
    let kRegion = hmac(key: kDate, data: Data(region.utf8))
    let kService = hmac(key: kRegion, data: Data(service.utf8))
    let kSigning = hmac(key: kService, data: Data("aws4_request".utf8))
    return SymmetricKey(data: kSigning)
  }

  private func hmac(key: Data, data: Data) -> Data {
    let key = SymmetricKey(data: key)
    let sig = HMAC<SHA256>.authenticationCode(for: data, using: key)
    return Data(sig)
  }

  private func hmacHex(key: SymmetricKey, data: Data) -> String {
    let sig = HMAC<SHA256>.authenticationCode(for: data, using: key)
    return Data(sig).map { String(format: "%02x", $0) }.joined()
  }
}
