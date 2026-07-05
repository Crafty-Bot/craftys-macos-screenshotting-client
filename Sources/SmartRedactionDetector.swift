import CoreGraphics
import Foundation
import ImageIO
import Vision

enum RedactionDetectorType: String, CaseIterable, Codable, Equatable, Hashable {
  case textOCR
  case faces
  case barcodes
  case emailAddresses
  case phoneNumbers
  case creditCardNumbers
  case ipv4Addresses
  case ipv6Addresses
  case macAddresses
  case urlsDomains
  case apiKeys
  case awsAccessKeys
  case githubTokens
  case openAIKeys
  case bearerTokens
  case jwts
  case privateKeyBlocks
  case sessionCookies
  case passwordFields
  case environmentVariables
  case filePaths
  case usernamesHostnames

  var title: String {
    switch self {
    case .textOCR: return "Text OCR"
    case .faces: return "Faces"
    case .barcodes: return "QR codes / barcodes"
    case .emailAddresses: return "Email addresses"
    case .phoneNumbers: return "Phone numbers"
    case .creditCardNumbers: return "Credit card numbers"
    case .ipv4Addresses: return "IPv4 addresses"
    case .ipv6Addresses: return "IPv6 addresses"
    case .macAddresses: return "MAC addresses"
    case .urlsDomains: return "URLs / domains"
    case .apiKeys: return "API keys"
    case .awsAccessKeys: return "AWS access keys"
    case .githubTokens: return "GitHub tokens"
    case .openAIKeys: return "OpenAI-style API keys"
    case .bearerTokens: return "Bearer tokens"
    case .jwts: return "JWTs"
    case .privateKeyBlocks: return "Private key blocks"
    case .sessionCookies: return "Session cookies"
    case .passwordFields: return "Password fields"
    case .environmentVariables: return "Environment variables"
    case .filePaths: return "File paths"
    case .usernamesHostnames: return "Usernames / hostnames"
    }
  }

  var isTextBased: Bool {
    switch self {
    case .textOCR, .faces, .barcodes:
      return false
    default:
      return true
    }
  }
}

struct RedactionDetectorSettings: Codable, Equatable {
  var textOCR: Bool
  var faces: Bool
  var barcodes: Bool
  var emailAddresses: Bool
  var phoneNumbers: Bool
  var creditCardNumbers: Bool
  var ipv4Addresses: Bool
  var ipv6Addresses: Bool
  var macAddresses: Bool
  var urlsDomains: Bool
  var apiKeys: Bool
  var awsAccessKeys: Bool
  var githubTokens: Bool
  var openAIKeys: Bool
  var bearerTokens: Bool
  var jwts: Bool
  var privateKeyBlocks: Bool
  var sessionCookies: Bool
  var passwordFields: Bool
  var environmentVariables: Bool
  var filePaths: Bool
  var usernamesHostnames: Bool
  var minimumConfidence: Float
  var useFastTextRecognition: Bool
  var allowSensitiveTextPreviews: Bool

  init(
    textOCR: Bool = true,
    faces: Bool = true,
    barcodes: Bool = true,
    emailAddresses: Bool = true,
    phoneNumbers: Bool = true,
    creditCardNumbers: Bool = true,
    ipv4Addresses: Bool = true,
    ipv6Addresses: Bool = false,
    macAddresses: Bool = false,
    urlsDomains: Bool = true,
    apiKeys: Bool = true,
    awsAccessKeys: Bool = true,
    githubTokens: Bool = true,
    openAIKeys: Bool = true,
    bearerTokens: Bool = true,
    jwts: Bool = true,
    privateKeyBlocks: Bool = true,
    sessionCookies: Bool = true,
    passwordFields: Bool = true,
    environmentVariables: Bool = true,
    filePaths: Bool = false,
    usernamesHostnames: Bool = false,
    minimumConfidence: Float = 0.20,
    useFastTextRecognition: Bool = false,
    allowSensitiveTextPreviews: Bool = false
  ) {
    self.textOCR = textOCR
    self.faces = faces
    self.barcodes = barcodes
    self.emailAddresses = emailAddresses
    self.phoneNumbers = phoneNumbers
    self.creditCardNumbers = creditCardNumbers
    self.ipv4Addresses = ipv4Addresses
    self.ipv6Addresses = ipv6Addresses
    self.macAddresses = macAddresses
    self.urlsDomains = urlsDomains
    self.apiKeys = apiKeys
    self.awsAccessKeys = awsAccessKeys
    self.githubTokens = githubTokens
    self.openAIKeys = openAIKeys
    self.bearerTokens = bearerTokens
    self.jwts = jwts
    self.privateKeyBlocks = privateKeyBlocks
    self.sessionCookies = sessionCookies
    self.passwordFields = passwordFields
    self.environmentVariables = environmentVariables
    self.filePaths = filePaths
    self.usernamesHostnames = usernamesHostnames
    self.minimumConfidence = max(0, min(1, minimumConfidence))
    self.useFastTextRecognition = useFastTextRecognition
    self.allowSensitiveTextPreviews = allowSensitiveTextPreviews
  }

  static let defaultValue = RedactionDetectorSettings()

  func isEnabled(_ type: RedactionDetectorType) -> Bool {
    switch type {
    case .textOCR: return textOCR
    case .faces: return faces
    case .barcodes: return barcodes
    case .emailAddresses: return emailAddresses
    case .phoneNumbers: return phoneNumbers
    case .creditCardNumbers: return creditCardNumbers
    case .ipv4Addresses: return ipv4Addresses
    case .ipv6Addresses: return ipv6Addresses
    case .macAddresses: return macAddresses
    case .urlsDomains: return urlsDomains
    case .apiKeys: return apiKeys
    case .awsAccessKeys: return awsAccessKeys
    case .githubTokens: return githubTokens
    case .openAIKeys: return openAIKeys
    case .bearerTokens: return bearerTokens
    case .jwts: return jwts
    case .privateKeyBlocks: return privateKeyBlocks
    case .sessionCookies: return sessionCookies
    case .passwordFields: return passwordFields
    case .environmentVariables: return environmentVariables
    case .filePaths: return filePaths
    case .usernamesHostnames: return usernamesHostnames
    }
  }

  mutating func setEnabled(_ type: RedactionDetectorType, _ enabled: Bool) {
    switch type {
    case .textOCR: textOCR = enabled
    case .faces: faces = enabled
    case .barcodes: barcodes = enabled
    case .emailAddresses: emailAddresses = enabled
    case .phoneNumbers: phoneNumbers = enabled
    case .creditCardNumbers: creditCardNumbers = enabled
    case .ipv4Addresses: ipv4Addresses = enabled
    case .ipv6Addresses: ipv6Addresses = enabled
    case .macAddresses: macAddresses = enabled
    case .urlsDomains: urlsDomains = enabled
    case .apiKeys: apiKeys = enabled
    case .awsAccessKeys: awsAccessKeys = enabled
    case .githubTokens: githubTokens = enabled
    case .openAIKeys: openAIKeys = enabled
    case .bearerTokens: bearerTokens = enabled
    case .jwts: jwts = enabled
    case .privateKeyBlocks: privateKeyBlocks = enabled
    case .sessionCookies: sessionCookies = enabled
    case .passwordFields: passwordFields = enabled
    case .environmentVariables: environmentVariables = enabled
    case .filePaths: filePaths = enabled
    case .usernamesHostnames: usernamesHostnames = enabled
    }
  }

  var hasEnabledTextRule: Bool {
    RedactionDetectorType.allCases.contains { $0.isTextBased && isEnabled($0) }
  }
}

enum RedactionFindingKind: String, Codable, Equatable {
  case text
  case face
  case barcode
}

struct RedactionBoundingBox: Codable, Equatable {
  var normalizedVisionRect: CGRect

  init(normalizedVisionRect: CGRect) {
    self.normalizedVisionRect = Self.clampUnit(normalizedVisionRect.standardized)
  }

  init(topLeftNormalizedRect: CGRect) {
    let rect = topLeftNormalizedRect.standardized
    self.normalizedVisionRect = Self.clampUnit(
      CGRect(x: rect.minX, y: 1.0 - rect.maxY, width: rect.width, height: rect.height)
    )
  }

  var topLeftNormalizedRect: CGRect {
    let rect = normalizedVisionRect.standardized
    return Self.clampUnit(CGRect(x: rect.minX, y: 1.0 - rect.maxY, width: rect.width, height: rect.height))
  }

  func imageRect(pixelWidth: CGFloat, pixelHeight: CGFloat, originTopLeft: Bool = true) -> CGRect {
    let rect = originTopLeft ? topLeftNormalizedRect : normalizedVisionRect
    return CGRect(
      x: rect.minX * pixelWidth,
      y: rect.minY * pixelHeight,
      width: rect.width * pixelWidth,
      height: rect.height * pixelHeight
    )
  }

  static func normalizedVisionRect(fromImageRect rect: CGRect, pixelWidth: CGFloat, pixelHeight: CGFloat, originTopLeft: Bool = true) -> CGRect {
    guard pixelWidth > 0, pixelHeight > 0 else { return .zero }
    let normalized = CGRect(
      x: rect.minX / pixelWidth,
      y: rect.minY / pixelHeight,
      width: rect.width / pixelWidth,
      height: rect.height / pixelHeight
    )
    if originTopLeft {
      return RedactionBoundingBox(topLeftNormalizedRect: normalized).normalizedVisionRect
    }
    return clampUnit(normalized)
  }

  private static func clampUnit(_ rect: CGRect) -> CGRect {
    let minX = max(0, min(1, rect.minX))
    let minY = max(0, min(1, rect.minY))
    let maxX = max(0, min(1, rect.maxX))
    let maxY = max(0, min(1, rect.maxY))
    return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
  }
}

struct RedactionFinding: Codable, Equatable, Identifiable {
  var id: String
  var kind: RedactionFindingKind
  var detectorType: RedactionDetectorType
  var confidence: Float
  var matchedTextPreview: String?
  var boundingBox: RedactionBoundingBox
  var metadata: [String: String]

  init(
    id: String = UUID().uuidString,
    kind: RedactionFindingKind,
    detectorType: RedactionDetectorType,
    confidence: Float,
    matchedTextPreview: String?,
    boundingBox: RedactionBoundingBox,
    metadata: [String: String] = [:]
  ) {
    self.id = id
    self.kind = kind
    self.detectorType = detectorType
    self.confidence = max(0, min(1, confidence))
    self.matchedTextPreview = matchedTextPreview
    self.boundingBox = boundingBox
    self.metadata = metadata
  }
}

struct RegexRedactionRule {
  var detectorType: RedactionDetectorType
  var pattern: String
  var options: NSRegularExpression.Options
  var validator: ((String) -> Bool)?

  private let regex: NSRegularExpression

  init(
    detectorType: RedactionDetectorType,
    pattern: String,
    options: NSRegularExpression.Options = [.caseInsensitive],
    validator: ((String) -> Bool)? = nil
  ) {
    self.detectorType = detectorType
    self.pattern = pattern
    self.options = options
    self.validator = validator
    self.regex = try! NSRegularExpression(pattern: pattern, options: options)
  }

  func matches(in text: String) -> [RegexRedactionMatch] {
    let nsText = text as NSString
    let fullRange = NSRange(location: 0, length: nsText.length)
    return regex.matches(in: text, options: [], range: fullRange).compactMap { match in
      let raw = nsText.substring(with: match.range)
      if let validator, !validator(raw) {
        return nil
      }
      return RegexRedactionMatch(detectorType: detectorType, range: match.range, text: raw)
    }
  }
}

struct RegexRedactionMatch: Equatable {
  var detectorType: RedactionDetectorType
  var range: NSRange
  var text: String
}

struct SmartRedactionPatternClassifier {
  private let rules: [RegexRedactionRule]

  init(rules: [RegexRedactionRule] = SmartRedactionPatternClassifier.defaultRules) {
    self.rules = rules
  }

  func matches(in text: String, settings: RedactionDetectorSettings = .defaultValue) -> [RegexRedactionMatch] {
    let enabledRules = rules.filter { settings.isEnabled($0.detectorType) }
    var found: [RegexRedactionMatch] = []
    for rule in enabledRules {
      found.append(contentsOf: rule.matches(in: text))
    }
    if found.isEmpty {
      let compacted = Self.ocrCompacted(text)
      if compacted != text {
        for rule in enabledRules {
          found.append(contentsOf: rule.matches(in: compacted))
        }
      }
    }
    return Self.nonOverlapping(found)
  }

  func containsSensitiveText(_ text: String, settings: RedactionDetectorSettings = .defaultValue) -> Bool {
    !matches(in: text, settings: settings).isEmpty
  }

  static let defaultRules: [RegexRedactionRule] = [
    RegexRedactionRule(detectorType: .privateKeyBlocks, pattern: #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
    RegexRedactionRule(detectorType: .bearerTokens, pattern: #"\bBearer\s+[A-Za-z0-9._~+/=-]{20,}\b"#),
    RegexRedactionRule(detectorType: .jwts, pattern: #"\beyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#),
    RegexRedactionRule(detectorType: .awsAccessKeys, pattern: #"\bAKIA[0-9A-Z]{16}\b"#),
    RegexRedactionRule(detectorType: .githubTokens, pattern: #"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{30,255}\b"#),
    RegexRedactionRule(detectorType: .openAIKeys, pattern: #"\bsk-[A-Za-z0-9_-]{20,}\b"#),
    RegexRedactionRule(detectorType: .apiKeys, pattern: #"(?i)\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|secret[_-]?key)\b\s*[:=]\s*["']?[A-Za-z0-9._~+/=-]{12,}["']?"#),
    RegexRedactionRule(detectorType: .sessionCookies, pattern: #"(?i)\b(?:Set-Cookie:\s*)?(?:sessionid|session_id|sid|connect\.sid|JSESSIONID|PHPSESSID|csrftoken|xsrf-token|auth_token)\s*=\s*[^;\s]{8,}"#),
    RegexRedactionRule(detectorType: .passwordFields, pattern: #"(?i)\b(?:password|passwd|pwd|secret|token|api[_-]?key|auth|credential)\b\s*[:=]\s*["']?[^"'\s]{4,}["']?"#),
    RegexRedactionRule(detectorType: .environmentVariables, pattern: #"\b[A-Z][A-Z0-9_]{2,}\s*=\s*["']?[^"'\s]{4,}["']?"#, options: []),
    RegexRedactionRule(detectorType: .emailAddresses, pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#),
    RegexRedactionRule(detectorType: .urlsDomains, pattern: #"\b(?:(?:https?://|www\.)[^\s<>"']+|(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+(?:com|net|org|io|dev|app|cloud|co|us|edu|gov|local)\b[^\s<>"']*)"#),
    RegexRedactionRule(detectorType: .ipv4Addresses, pattern: #"\b(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}\b"#, options: []),
    RegexRedactionRule(detectorType: .ipv6Addresses, pattern: #"\b(?:(?:[A-F0-9]{1,4}:){7}[A-F0-9]{1,4}|(?:[A-F0-9]{1,4}:){1,7}:|:(?::[A-F0-9]{1,4}){1,7}|(?:[A-F0-9]{1,4}:){1,6}:[A-F0-9]{1,4})\b"#),
    RegexRedactionRule(detectorType: .macAddresses, pattern: #"\b(?:[A-F0-9]{2}[:-]){5}[A-F0-9]{2}\b"#),
    RegexRedactionRule(detectorType: .phoneNumbers, pattern: #"(?<!\w)(?:\+?1[\s.-]?)?(?:\(?\d{3}\)?[\s.-]?)\d{3}[\s.-]?\d{4}(?!\w)"#, options: []),
    RegexRedactionRule(detectorType: .creditCardNumbers, pattern: #"\b(?:\d[ -]?){13,19}\b"#, options: [], validator: SmartRedactionPatternClassifier.isLikelyCreditCard),
    RegexRedactionRule(detectorType: .filePaths, pattern: #"(?:(?:/[A-Za-z0-9._ -]+){2,}|(?:[A-Z]:\\(?:[^\\/:*?"<>|\r\n]+\\?){2,}|~/(?:[^\s:]+/?){1,}))"#, options: [.caseInsensitive]),
    RegexRedactionRule(detectorType: .usernamesHostnames, pattern: #"(?i)\b(?:user(?:name)?|host(?:name)?|login)\s*[:=]\s*[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?"#),
  ]

  static func isLikelyCreditCard(_ value: String) -> Bool {
    let digits = value.compactMap { $0.wholeNumberValue }
    guard (13...19).contains(digits.count) else { return false }

    var sum = 0
    var doubleDigit = false
    for digit in digits.reversed() {
      var value = digit
      if doubleDigit {
        value *= 2
        if value > 9 { value -= 9 }
      }
      sum += value
      doubleDigit.toggle()
    }
    return sum % 10 == 0
  }

  private static func ocrCompacted(_ text: String) -> String {
    text
      .replacingOccurrences(of: #"\s*([@._:/?&=#%+-])\s*"#, with: "$1", options: .regularExpression)
      .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func nonOverlapping(_ matches: [RegexRedactionMatch]) -> [RegexRedactionMatch] {
    let sorted = matches.sorted {
      if $0.range.location != $1.range.location {
        return $0.range.location < $1.range.location
      }
      return detectorPriority($0.detectorType) < detectorPriority($1.detectorType)
    }

    var accepted: [RegexRedactionMatch] = []
    for match in sorted {
      let overlaps = accepted.contains { NSIntersectionRange($0.range, match.range).length > 0 }
      if !overlaps {
        accepted.append(match)
      }
    }
    return accepted.sorted { $0.range.location < $1.range.location }
  }

  private static func detectorPriority(_ type: RedactionDetectorType) -> Int {
    switch type {
    case .privateKeyBlocks: return 0
    case .bearerTokens: return 1
    case .jwts: return 2
    case .awsAccessKeys, .githubTokens, .openAIKeys: return 3
    case .apiKeys, .sessionCookies, .passwordFields, .environmentVariables: return 4
    default: return 10
    }
  }
}

protocol SmartRedactionVisionRecognizing {
  func recognizeFindings(in image: CGImage, settings: RedactionDetectorSettings, classifier: SmartRedactionPatternClassifier) throws -> [RedactionFinding]
}

struct VisionSmartRedactionRecognizer: SmartRedactionVisionRecognizing {
  func recognizeFindings(
    in image: CGImage,
    settings: RedactionDetectorSettings,
    classifier: SmartRedactionPatternClassifier
  ) throws -> [RedactionFinding] {
    var findings: [RedactionFinding] = []

    if settings.textOCR && settings.hasEnabledTextRule {
      findings.append(contentsOf: try textFindings(in: image, settings: settings, classifier: classifier))
    }
    if settings.faces {
      findings.append(contentsOf: try faceFindings(in: image, settings: settings))
    }
    if settings.barcodes {
      findings.append(contentsOf: try barcodeFindings(in: image, settings: settings))
    }

    return findings
  }

  private func textFindings(
    in image: CGImage,
    settings: RedactionDetectorSettings,
    classifier: SmartRedactionPatternClassifier
  ) throws -> [RedactionFinding] {
    let recognitionImage = Self.textRecognitionImage(from: image)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = settings.useFastTextRecognition ? .fast : .accurate
    request.usesLanguageCorrection = false
    request.customWords = ["sk-", "AKIA", "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "Bearer", "Set-Cookie", "api_key"]
    if #available(macOS 13.0, *) {
      request.revision = VNRecognizeTextRequestRevision3
    }

    try VNImageRequestHandler(cgImage: recognitionImage, options: [:]).perform([request])

    var findings: [RedactionFinding] = []
    for observation in request.results ?? [] {
      guard observation.confidence >= settings.minimumConfidence,
            let candidate = observation.topCandidates(1).first else {
        continue
      }

      let matches = classifier.matches(in: candidate.string, settings: settings)
      guard !matches.isEmpty else { continue }

      let box = Self.textObservationBoundingBox(observation.boundingBox)
      for match in matches {
        findings.append(
          RedactionFinding(
            kind: .text,
            detectorType: match.detectorType,
            confidence: observation.confidence,
            matchedTextPreview: Self.preview(for: match.text, settings: settings),
            boundingBox: box,
            metadata: ["source": "Vision OCR"]
          )
        )
      }
    }
    return findings
  }

  private func faceFindings(in image: CGImage, settings: RedactionDetectorSettings) throws -> [RedactionFinding] {
    let request = VNDetectFaceRectanglesRequest()
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

    return (request.results ?? []).compactMap { face in
      guard face.confidence >= settings.minimumConfidence else { return nil }
      return RedactionFinding(
        kind: .face,
        detectorType: .faces,
        confidence: face.confidence,
        matchedTextPreview: nil,
        boundingBox: RedactionBoundingBox(normalizedVisionRect: face.boundingBox),
        metadata: ["source": "Vision face detection"]
      )
    }
  }

  private func barcodeFindings(in image: CGImage, settings: RedactionDetectorSettings) throws -> [RedactionFinding] {
    let request = VNDetectBarcodesRequest()
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

    return (request.results ?? []).compactMap { barcode in
      guard barcode.confidence >= settings.minimumConfidence else { return nil }
      var metadata = ["source": "Vision barcode detection", "symbology": barcode.symbology.rawValue]
      if let payload = barcode.payloadStringValue {
        metadata["payloadPreview"] = Self.preview(for: payload, settings: settings)
      }
      return RedactionFinding(
        kind: .barcode,
        detectorType: .barcodes,
        confidence: barcode.confidence,
        matchedTextPreview: barcode.payloadStringValue.map { Self.preview(for: $0, settings: settings) },
        boundingBox: RedactionBoundingBox(normalizedVisionRect: barcode.boundingBox),
        metadata: metadata
      )
    }
  }

  private static func preview(for value: String, settings: RedactionDetectorSettings) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    if settings.allowSensitiveTextPreviews {
      return trimmed
    }
    let prefix = String(trimmed.prefix(3))
    let suffix = String(trimmed.suffix(2))
    return trimmed.count <= 6 ? "[redacted]" : "\(prefix)...\(suffix)"
  }

  static func textObservationBoundingBox(_ observationRect: CGRect) -> RedactionBoundingBox {
    // Vision reports text observation bounding boxes in normalized, bottom-left-origin
    // coordinates (same as face and barcode observations). Wrap them as Vision rects so the
    // single bottom-left -> top-left conversion happens in `topLeftNormalizedRect`. Treating
    // them as already-top-left here double-flips the box and mirrors the redaction vertically.
    RedactionBoundingBox(normalizedVisionRect: observationRect)
  }

  private static func textRecognitionImage(from image: CGImage) -> CGImage {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return image }

    let minDimension = min(width, height)
    let maxDimension = max(width, height)
    guard minDimension < 700 || maxDimension < 1200 else { return image }

    let minScale = CGFloat(700) / CGFloat(max(1, minDimension))
    let maxScale = CGFloat(2400) / CGFloat(max(1, maxDimension))
    let scale = min(max(1, minScale), max(1, maxScale), 4)
    guard scale > 1.01 else { return image }

    let scaledWidth = max(1, Int((CGFloat(width) * scale).rounded()))
    let scaledHeight = max(1, Int((CGFloat(height) * scale).rounded()))
    guard let context = makeTopLeftBitmapContext(width: scaledWidth, height: scaledHeight) else {
      return image
    }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
    return context.makeImage() ?? image
  }
}

enum SmartRedactionDetectionError: Error {
  case imageLoadFailed
}

final class SmartRedactionDetector {
  static let shared = SmartRedactionDetector()

  private let recognizer: SmartRedactionVisionRecognizing
  private let classifier: SmartRedactionPatternClassifier

  init(
    recognizer: SmartRedactionVisionRecognizing = VisionSmartRedactionRecognizer(),
    classifier: SmartRedactionPatternClassifier = SmartRedactionPatternClassifier()
  ) {
    self.recognizer = recognizer
    self.classifier = classifier
  }

  func detectRedactions(
    in image: CGImage,
    settings: RedactionDetectorSettings = .defaultValue
  ) async throws -> [RedactionFinding] {
    try await Task.detached(priority: .userInitiated) { [self] in
      let raw = try recognizer.recognizeFindings(in: image, settings: settings, classifier: classifier)
      return Self.deduplicated(raw, settings: settings)
    }.value
  }

  func detectSensitiveRegions(in imageURL: URL) async throws -> [SmartRedactionRegion] {
    guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      // Fail closed: an unreadable image must not silently bypass the
      // redaction policy and upload unchecked.
      throw SmartRedactionDetectionError.imageLoadFailed
    }
    let findings = try await detectRedactions(in: image, settings: RuntimePreferences.shared.redactionDetectorSettings)
    let regions = findings.map {
      SmartRedactionRegion(
        rect: $0.boundingBox.topLeftNormalizedRect,
        category: $0.detectorType,
        matchedText: $0.matchedTextPreview
      )
    }
    return Self.paddedAndMerged(regions)
  }

  static func deduplicated(_ findings: [RedactionFinding], settings: RedactionDetectorSettings) -> [RedactionFinding] {
    let thresholded = findings
      .filter { $0.confidence >= settings.minimumConfidence }
      .sorted {
        if $0.kind != $1.kind { return kindPriority($0.kind) < kindPriority($1.kind) }
        if abs($0.confidence - $1.confidence) > 0.0001 { return $0.confidence > $1.confidence }
        return detectorPriority($0.detectorType) < detectorPriority($1.detectorType)
      }

    var accepted: [RedactionFinding] = []
    for finding in thresholded {
      let overlaps = accepted.contains {
        $0.kind == finding.kind && overlapRatio($0.boundingBox.normalizedVisionRect, finding.boundingBox.normalizedVisionRect) >= 0.85
      }
      if !overlaps {
        accepted.append(finding)
      }
    }
    return accepted
  }

  static func paddedAndMerged(
    _ regions: [SmartRedactionRegion],
    padding: CGFloat = 0.006,
    adjacency: CGFloat = 0.004
  ) -> [SmartRedactionRegion] {
    let padded = regions.map { region in
      SmartRedactionRegion(
        rect: clampUnit(region.rect.insetBy(dx: -padding, dy: -padding)),
        category: region.category,
        matchedText: region.matchedText
      )
    }
    .filter { !$0.rect.isNull && !$0.rect.isEmpty }
    .sorted {
      if abs($0.rect.minY - $1.rect.minY) > 0.0001 {
        return $0.rect.minY < $1.rect.minY
      }
      return $0.rect.minX < $1.rect.minX
    }

    var merged: [SmartRedactionRegion] = []
    for region in padded {
      if let idx = merged.firstIndex(where: { shouldMerge($0.rect, region.rect, adjacency: adjacency) }) {
        let current = merged[idx]
        merged[idx] = SmartRedactionRegion(
          rect: current.rect.union(region.rect),
          category: current.category == region.category ? current.category : .textOCR,
          matchedText: joinedMatchedText(current.matchedText, region.matchedText)
        )
      } else {
        merged.append(region)
      }
    }

    var changed = true
    while changed {
      changed = false
      outer: for i in merged.indices {
        for j in merged.indices where i != j {
          if shouldMerge(merged[i].rect, merged[j].rect, adjacency: adjacency) {
            let a = merged[i]
            let b = merged[j]
            merged[i] = SmartRedactionRegion(
              rect: a.rect.union(b.rect),
              category: a.category == b.category ? a.category : .textOCR,
              matchedText: joinedMatchedText(a.matchedText, b.matchedText)
            )
            merged.remove(at: j)
            changed = true
            break outer
          }
        }
      }
    }

    return merged
  }

  private static func kindPriority(_ kind: RedactionFindingKind) -> Int {
    switch kind {
    case .text: return 0
    case .barcode: return 1
    case .face: return 2
    }
  }

  private static func detectorPriority(_ type: RedactionDetectorType) -> Int {
    switch type {
    case .privateKeyBlocks: return 0
    case .bearerTokens, .jwts: return 1
    case .awsAccessKeys, .githubTokens, .openAIKeys: return 2
    case .apiKeys, .sessionCookies, .passwordFields, .environmentVariables: return 3
    default: return 10
    }
  }

  private static func overlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
    let intersection = a.intersection(b)
    guard !intersection.isNull && !intersection.isEmpty else { return 0 }
    let smaller = min(a.width * a.height, b.width * b.height)
    guard smaller > 0 else { return 0 }
    return (intersection.width * intersection.height) / smaller
  }

  private static func shouldMerge(_ a: CGRect, _ b: CGRect, adjacency: CGFloat) -> Bool {
    a.insetBy(dx: -adjacency, dy: -adjacency).intersects(b)
  }

  private static func joinedMatchedText(_ a: String?, _ b: String?) -> String? {
    let parts = [a, b].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    guard !parts.isEmpty else { return nil }
    var seen = Set<String>()
    let unique = parts.filter { seen.insert($0).inserted }
    return unique.joined(separator: " ")
  }

  private static func clampUnit(_ rect: CGRect) -> CGRect {
    let minX = max(0, min(1, rect.minX))
    let minY = max(0, min(1, rect.minY))
    let maxX = max(0, min(1, rect.maxX))
    let maxY = max(0, min(1, rect.maxY))
    return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
  }
}

struct SmartRedactionRegion: Equatable {
  var rect: CGRect
  var category: RedactionDetectorType
  var matchedText: String?
}
