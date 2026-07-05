import Foundation

enum URLShortenerError: Error {
  case invalidURL
  case invalidTemplate
  case serverError(String)
}

final class URLShortenerService {
  static let shared = URLShortenerService()
  private init() {}

  private static let strictQueryValueAllowed: CharacterSet = {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return allowed
  }()

  func shorten(urlString: String) async throws -> String {
    guard let parsed = URL(string: urlString), let scheme = parsed.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
      throw URLShortenerError.invalidURL
    }

    let config = RuntimePreferences.shared.shortenerConfig
    switch config.provider {
    case .tinyURL:
      return try await shortenWithTinyURL(urlString)
    case .customGetTemplate:
      return try await shortenWithCustomTemplate(urlString, template: config.customGetTemplate)
    }
  }

  private func shortenWithTinyURL(_ urlString: String) async throws -> String {
    var components = URLComponents(string: "https://tinyurl.com/api-create.php")
    components?.queryItems = [URLQueryItem(name: "url", value: urlString)]
    guard let endpoint = components?.url else {
      throw URLShortenerError.invalidURL
    }

    var req = URLRequest(url: endpoint)
    req.httpMethod = "GET"
    req.timeoutInterval = 10

    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else {
      throw URLShortenerError.serverError("Invalid HTTP response")
    }

    guard (200...299).contains(http.statusCode), let text = String(data: data, encoding: .utf8) else {
      throw URLShortenerError.serverError("TinyURL request failed (HTTP \(http.statusCode))")
    }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let out = URL(string: trimmed), ["http", "https"].contains(out.scheme?.lowercased() ?? "") else {
      throw URLShortenerError.serverError("TinyURL response did not contain a URL")
    }

    return trimmed
  }

  private func shortenWithCustomTemplate(_ urlString: String, template: String) async throws -> String {
    let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.contains("{url}") else {
      throw URLShortenerError.invalidTemplate
    }

    // Encode strictly (RFC 3986 unreserved only): .urlQueryAllowed leaves &, =
    // and ? intact, which would splice the target URL's query parameters into
    // the shortener request itself.
    let encoded = urlString.addingPercentEncoding(withAllowedCharacters: Self.strictQueryValueAllowed) ?? urlString
    let endpointString = trimmed.replacingOccurrences(of: "{url}", with: encoded)
    guard let endpoint = URL(string: endpointString) else {
      throw URLShortenerError.invalidTemplate
    }

    var req = URLRequest(url: endpoint)
    req.httpMethod = "GET"
    req.timeoutInterval = 10

    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else {
      throw URLShortenerError.serverError("Invalid HTTP response")
    }

    guard (200...299).contains(http.statusCode) else {
      throw URLShortenerError.serverError("Custom shortener failed (HTTP \(http.statusCode))")
    }

    if let json = try? JSONSerialization.jsonObject(with: data, options: []), let dict = json as? [String: Any] {
      if let url = dict["url"] as? String ?? dict["shortUrl"] as? String, !url.isEmpty {
        return url
      }
    }

    if let text = String(data: data, encoding: .utf8) {
      let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if let parsed = URL(string: trimmedText), ["http", "https"].contains(parsed.scheme?.lowercased() ?? "") {
        return trimmedText
      }
    }

    throw URLShortenerError.serverError("Custom shortener response did not include a URL")
  }

}
