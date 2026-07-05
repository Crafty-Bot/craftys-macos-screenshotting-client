import Darwin
import Foundation
import Network

extension Notification.Name {
  static let cloudflareAllowlistStatusDidChange = Notification.Name("cloudflareAllowlistStatusDidChange")
}

enum CloudflareAllowlistError: LocalizedError {
  case missingConfiguration(String)
  case invalidPublicIP(String)
  case invalidResponse
  case listNotFound(String)
  case apiError(String)
  case bulkOperationFailed(String)

  var errorDescription: String? {
    switch self {
    case .missingConfiguration(let message):
      return message
    case .invalidPublicIP(let value):
      return "Public IP lookup returned an invalid address: \(value)"
    case .invalidResponse:
      return "Cloudflare returned an unexpected response."
    case .listNotFound(let value):
      return "Could not find a Cloudflare IP list named or identified by '\(value)'."
    case .apiError(let message):
      return message
    case .bulkOperationFailed(let message):
      return message
    }
  }
}

struct CloudflareAllowlistUpdateResult {
  var ipAddress: String
  var operationId: String?
  var message: String
}

enum CloudflareCredentialStore {
  private static let service = "com.crafty599.craftycannon"
  private static let apiTokenAccount = "cloudflare_api_token"

  static func getApiToken() -> String? {
    do {
      return try Keychain.getString(service: service, account: apiTokenAccount)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      return nil
    }
  }

  static func setApiToken(_ value: String) throws {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      clearApiToken()
    } else {
      try Keychain.setString(trimmed, service: service, account: apiTokenAccount)
    }
  }

  static func clearApiToken() {
    Keychain.deleteString(service: service, account: apiTokenAccount)
  }
}

final class CloudflareAllowlistManager: @unchecked Sendable {
  static let shared = CloudflareAllowlistManager()

  private struct CloudflareError: Decodable {
    var code: Int?
    var message: String
  }

  private struct CloudflareEnvelope<Result: Decodable>: Decodable {
    var success: Bool
    var result: Result?
    var errors: [CloudflareError]?
    var resultInfo: ResultInfo?

    private enum CodingKeys: String, CodingKey {
      case success, result, errors
      case resultInfo = "result_info"
    }
  }

  private struct ResultInfo: Decodable {
    var cursors: Cursors?
  }

  private struct Cursors: Decodable {
    var after: String?
  }

  struct ListItem: Decodable, Equatable {
    var id: String?
    var ip: String?
    var comment: String?
  }

  private struct CloudflareList: Decodable {
    var id: String
    var name: String
    var kind: String
  }

  private struct OperationResponse: Decodable {
    var operationId: String

    private enum CodingKeys: String, CodingKey {
      case operationId = "operation_id"
    }
  }

  private struct BulkOperationStatus: Decodable {
    var id: String?
    var status: String
    var error: String?
  }

  private let apiBaseURL = "https://api.cloudflare.com/client/v4"
  private let publicIPURL = URL(string: "https://cloudflare.com/cdn-cgi/trace")!
  private let queue = DispatchQueue(label: "com.crafty599.craftycannon.cloudflareAllowlist")
  private let defaults = UserDefaults.standard
  private let deviceIdKey = "runtime.cloudflare.allowlist.deviceId.v1"

  private var timer: DispatchSourceTimer?
  private var pathMonitor: NWPathMonitor?
  private var pendingPathRefresh: DispatchWorkItem?
  private var lastPathSignature: String?
  private var updateInFlight = false

  private(set) var statusLine = "Cloudflare allowlist has not run yet." {
    didSet {
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: .cloudflareAllowlistStatusDidChange, object: nil)
      }
    }
  }

  private init() {}

  func applyCurrentPreferences() {
    queue.async {
      self.configureTimer()
    }
  }

  func updateNow() async -> Result<CloudflareAllowlistUpdateResult, Error> {
    await withCheckedContinuation { continuation in
      queue.async {
        if self.updateInFlight {
          continuation.resume(returning: .failure(CloudflareAllowlistError.apiError("Cloudflare allowlist update is already running.")))
          return
        }

        self.updateInFlight = true
        Task {
          defer {
            self.queue.async {
              self.updateInFlight = false
            }
          }

          do {
            let result = try await self.performUpdate()
            self.setStatus(result.message)
            continuation.resume(returning: .success(result))
          } catch {
            self.setStatus("Cloudflare allowlist update failed: \(error.localizedDescription)")
            continuation.resume(returning: .failure(error))
          }
        }
      }
    }
  }

  static func publicIP(fromCloudflareTrace text: String) -> String? {
    for line in text.split(whereSeparator: \.isNewline) {
      guard line.hasPrefix("ip=") else { continue }
      let value = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty ? nil : value
    }
    return nil
  }

  static func isValidIPAddress(_ value: String) -> Bool {
    var ipv4 = in_addr()
    if value.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
      return true
    }

    var ipv6 = in6_addr()
    return value.withCString { inet_pton(AF_INET6, $0, &ipv6) } == 1
  }

  static func managedItems(
    currentItems: [ListItem],
    currentIP: String,
    deviceMarker: String,
    deviceName: String,
    updatedAt: Date = Date()
  ) -> [[String: String]] {
    let preserved = currentItems.compactMap { item -> [String: String]? in
      guard let ip = item.ip, isValidIPAddress(ip) else { return nil }
      if item.comment?.hasPrefix(deviceMarker) == true {
        return nil
      }
      if ip == currentIP {
        return ["ip": ip, "comment": item.comment ?? ""]
      }
      return ["ip": ip, "comment": item.comment ?? ""]
    }

    if preserved.contains(where: { $0["ip"] == currentIP }) {
      return preserved
    }

    let formatter = ISO8601DateFormatter()
    let comment = "\(deviceMarker) \(deviceName) updated \(formatter.string(from: updatedAt))"
    return preserved + [["ip": currentIP, "comment": comment]]
  }

  private func configureTimer() {
    timer?.cancel()
    timer = nil
    stopNetworkMonitor()

    let config = RuntimePreferences.shared.cloudflareAllowlistConfig
    guard config.enabled else {
      setStatus("Cloudflare allowlist is disabled.")
      return
    }

    guard configurationIsRunnable(config) else {
      setStatus("Cloudflare allowlist needs an account ID, list name or ID, and API token.")
      return
    }

    let interval = DispatchTimeInterval.seconds(config.checkIntervalMinutes * 60)
    let newTimer = DispatchSource.makeTimerSource(queue: queue)
    newTimer.schedule(deadline: .now() + 2, repeating: interval, leeway: .seconds(30))
    newTimer.setEventHandler { [weak self] in
      Task {
        _ = await self?.updateNow()
      }
    }
    newTimer.resume()
    timer = newTimer
    startNetworkMonitor()
    setStatus("Cloudflare allowlist will refresh every \(config.checkIntervalMinutes) minutes and after network changes.")
  }

  static func networkPathSignature(status: String, interfaces: [String]) -> String {
    "\(status)|\(interfaces.sorted().joined(separator: ","))"
  }

  static func shouldRefreshAfterPathChange(previousSignature: String?, newSignature: String, isSatisfied: Bool) -> Bool {
    guard isSatisfied else { return false }
    guard let previousSignature else { return false }
    return previousSignature != newSignature
  }

  private func startNetworkMonitor() {
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] path in
      self?.handlePathUpdate(path)
    }
    monitor.start(queue: queue)
    pathMonitor = monitor
  }

  private func stopNetworkMonitor() {
    pathMonitor?.cancel()
    pathMonitor = nil
    pendingPathRefresh?.cancel()
    pendingPathRefresh = nil
    lastPathSignature = nil
  }

  private func handlePathUpdate(_ path: NWPath) {
    let signature = Self.networkPathSignature(
      status: String(describing: path.status),
      interfaces: path.availableInterfaces.map(\.name)
    )
    let shouldRefresh = Self.shouldRefreshAfterPathChange(
      previousSignature: lastPathSignature,
      newSignature: signature,
      isSatisfied: path.status == .satisfied
    )
    lastPathSignature = signature
    guard shouldRefresh else { return }

    pendingPathRefresh?.cancel()
    let work = DispatchWorkItem { [weak self] in
      Task {
        _ = await self?.updateNow()
      }
    }
    pendingPathRefresh = work
    queue.asyncAfter(deadline: .now() + 3, execute: work)
  }

  private func configurationIsRunnable(_ config: CloudflareAllowlistConfig) -> Bool {
    !config.accountId.isEmpty && !config.listId.isEmpty && !(CloudflareCredentialStore.getApiToken() ?? "").isEmpty
  }

  private func performUpdate() async throws -> CloudflareAllowlistUpdateResult {
    let config = RuntimePreferences.shared.cloudflareAllowlistConfig
    guard !config.accountId.isEmpty else {
      throw CloudflareAllowlistError.missingConfiguration("Missing Cloudflare account ID.")
    }
    guard !config.listId.isEmpty else {
      throw CloudflareAllowlistError.missingConfiguration("Missing Cloudflare list name or ID.")
    }
    guard let apiToken = CloudflareCredentialStore.getApiToken(), !apiToken.isEmpty else {
      throw CloudflareAllowlistError.missingConfiguration("Missing Cloudflare API token.")
    }

    let resolvedListId = try await resolveListId(accountId: config.accountId, listNameOrId: config.listId, apiToken: apiToken)
    let ipAddress = try await fetchPublicIP()
    let currentItems = try await fetchListItems(accountId: config.accountId, listId: resolvedListId, apiToken: apiToken)
    let body = Self.managedItems(
      currentItems: currentItems,
      currentIP: ipAddress,
      deviceMarker: deviceMarker(),
      deviceName: config.deviceName
    )
    let operationId = try await replaceListItems(accountId: config.accountId, listId: resolvedListId, apiToken: apiToken, items: body)
    try await waitForBulkOperationIfNeeded(accountId: config.accountId, apiToken: apiToken, operationId: operationId)

    let message = "Cloudflare allowlist updated for \(ipAddress)."
    return CloudflareAllowlistUpdateResult(ipAddress: ipAddress, operationId: operationId, message: message)
  }

  private func resolveListId(accountId: String, listNameOrId: String, apiToken: String) async throws -> String {
    let trimmed = listNameOrId.trimmingCharacters(in: .whitespacesAndNewlines)
    if Self.looksLikeCloudflareId(trimmed) {
      return trimmed
    }

    let lists = try await fetchLists(accountId: accountId, apiToken: apiToken)
    if let exactIPList = lists.first(where: { $0.kind.lowercased() == "ip" && $0.name == trimmed }) {
      return exactIPList.id
    }
    if let caseInsensitiveIPList = lists.first(where: { $0.kind.lowercased() == "ip" && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
      return caseInsensitiveIPList.id
    }
    throw CloudflareAllowlistError.listNotFound(trimmed)
  }

  static func looksLikeCloudflareId(_ value: String) -> Bool {
    guard value.count == 32 else { return false }
    return value.allSatisfy { char in
      char.isNumber || ("a"..."f").contains(char) || ("A"..."F").contains(char)
    }
  }

  private func fetchPublicIP() async throws -> String {
    var request = URLRequest(url: publicIPURL)
    request.timeoutInterval = 10
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
          let text = String(data: data, encoding: .utf8),
          let ip = Self.publicIP(fromCloudflareTrace: text) else {
      throw CloudflareAllowlistError.invalidResponse
    }
    guard Self.isValidIPAddress(ip) else {
      throw CloudflareAllowlistError.invalidPublicIP(ip)
    }
    return ip
  }

  private func fetchListItems(accountId: String, listId: String, apiToken: String) async throws -> [ListItem] {
    var allItems: [ListItem] = []
    var cursor: String?

    repeat {
      var query = [URLQueryItem(name: "per_page", value: "500")]
      if let cursor, !cursor.isEmpty {
        query.append(URLQueryItem(name: "cursor", value: cursor))
      }
      let envelope: CloudflareEnvelope<[ListItem]> = try await cloudflareRequest(
        method: "GET",
        path: "/accounts/\(accountId)/rules/lists/\(listId)/items",
        apiToken: apiToken,
        queryItems: query
      )
      allItems.append(contentsOf: envelope.result ?? [])
      cursor = envelope.resultInfo?.cursors?.after
    } while cursor?.isEmpty == false

    return allItems
  }

  private func fetchLists(accountId: String, apiToken: String) async throws -> [CloudflareList] {
    let envelope: CloudflareEnvelope<[CloudflareList]> = try await cloudflareRequest(
      method: "GET",
      path: "/accounts/\(accountId)/rules/lists",
      apiToken: apiToken
    )
    return envelope.result ?? []
  }

  private func replaceListItems(accountId: String, listId: String, apiToken: String, items: [[String: String]]) async throws -> String? {
    let envelope: CloudflareEnvelope<OperationResponse> = try await cloudflareRequest(
      method: "PUT",
      path: "/accounts/\(accountId)/rules/lists/\(listId)/items",
      apiToken: apiToken,
      body: items
    )
    return envelope.result?.operationId
  }

  private func waitForBulkOperationIfNeeded(accountId: String, apiToken: String, operationId: String?) async throws {
    guard let operationId, !operationId.isEmpty else { return }

    for _ in 0..<12 {
      try await Task.sleep(nanoseconds: 1_000_000_000)
      let envelope: CloudflareEnvelope<BulkOperationStatus> = try await cloudflareRequest(
        method: "GET",
        path: "/accounts/\(accountId)/rules/lists/bulk_operations/\(operationId)",
        apiToken: apiToken
      )
      guard let status = envelope.result?.status else { continue }
      switch status {
      case "completed":
        return
      case "failed":
        throw CloudflareAllowlistError.bulkOperationFailed(envelope.result?.error ?? "Cloudflare list update failed.")
      default:
        continue
      }
    }

    throw CloudflareAllowlistError.bulkOperationFailed(
      "Timed out waiting for the Cloudflare list update to complete."
    )
  }

  private func cloudflareRequest<Result: Decodable>(
    method: String,
    path: String,
    apiToken: String,
    queryItems: [URLQueryItem] = [],
    body: Any? = nil
  ) async throws -> CloudflareEnvelope<Result> {
    var components = URLComponents(string: apiBaseURL)!
    components.path = "/client/v4\(path)"
    components.queryItems = queryItems.isEmpty ? nil : queryItems
    guard let url = components.url else {
      throw CloudflareAllowlistError.invalidResponse
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 20
    request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw CloudflareAllowlistError.invalidResponse
    }

    let envelope = try JSONDecoder().decode(CloudflareEnvelope<Result>.self, from: data)
    guard (200...299).contains(http.statusCode), envelope.success else {
      throw CloudflareAllowlistError.apiError(Self.errorMessage(from: envelope.errors, fallbackStatus: http.statusCode))
    }
    return envelope
  }

  private static func errorMessage(from errors: [CloudflareError]?, fallbackStatus: Int) -> String {
    let messages = errors?.map { error -> String in
      if let code = error.code {
        return "\(code): \(error.message)"
      }
      return error.message
    }.filter { !$0.isEmpty } ?? []

    if messages.isEmpty {
      return "Cloudflare API request failed (HTTP \(fallbackStatus))."
    }
    return messages.joined(separator: " ")
  }

  private func deviceMarker() -> String {
    "craftycannon-device:\(deviceId())"
  }

  private func deviceId() -> String {
    if let existing = defaults.string(forKey: deviceIdKey), !existing.isEmpty {
      return existing
    }
    let value = UUID().uuidString
    defaults.set(value, forKey: deviceIdKey)
    return value
  }

  private func setStatus(_ value: String) {
    statusLine = value
  }
}
