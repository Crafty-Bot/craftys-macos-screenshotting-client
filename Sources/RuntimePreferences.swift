import CoreGraphics
import Foundation

extension Notification.Name {
  static let runtimePreferencesDidChange = Notification.Name("runtimePreferencesDidChange")
  static let hotKeyPreferencesDidChange = Notification.Name("hotKeyPreferencesDidChange")
}

struct UploaderFilterRule: Codable, Identifiable, Equatable {
  var id: String
  var extensions: [String]
  var profileId: String

  init(id: String = UUID().uuidString, extensions: [String], profileId: String) {
    self.id = id
    self.extensions = Self.normalizedExtensions(extensions)
    self.profileId = profileId
  }

  func matches(fileExtension: String) -> Bool {
    let ext = fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    guard !ext.isEmpty else { return false }
    return extensions.contains(ext)
  }

  static func normalizedExtensions(_ raw: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for item in raw {
      let ext = item.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ."))
      if ext.isEmpty || seen.contains(ext) { continue }
      seen.insert(ext)
      result.append(ext)
    }
    return result
  }
}

struct CaptureRuntimeOptions {
  var includeCursor: Bool
  var delaySeconds: Int
  var fixedRegion: CGRect?
  var showOverlayInfo: Bool
  var snapSizes: [CGSize]

  init(
    includeCursor: Bool = false,
    delaySeconds: Int = 0,
    fixedRegion: CGRect? = nil,
    showOverlayInfo: Bool = true,
    snapSizes: [CGSize] = []
  ) {
    self.includeCursor = includeCursor
    self.delaySeconds = delaySeconds
    self.fixedRegion = fixedRegion
    self.showOverlayInfo = showOverlayInfo
    self.snapSizes = snapSizes
  }
}

struct AfterCaptureTaskOptions {
  var saveLocalCopy: Bool
  var copyURL: Bool
  var copyImageAndURL: Bool
  var openEditor: Bool
}

enum ImageUploadFormat: String, CaseIterable, Codable, Identifiable {
  case png
  case jpeg
  case gif
  case tiff

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .png: return "PNG"
    case .jpeg: return "JPEG"
    case .gif: return "GIF"
    case .tiff: return "TIFF"
    }
  }

  var filenameExtension: String {
    switch self {
    case .png: return "png"
    case .jpeg: return "jpg"
    case .gif: return "gif"
    case .tiff: return "tiff"
    }
  }
}

enum OnboardingState: String, Codable {
  case pending
  case completed
}

enum DestinationKind: String, CaseIterable, Codable {
  case image
  case file
  case text
  case shortener
}

struct DestinationRoutingConfig: Codable, Equatable {
  var imageProfileId: String?
  var fileProfileId: String?
  var textProfileId: String?
  var shortenerProfileId: String?

  init(
    imageProfileId: String? = nil,
    fileProfileId: String? = nil,
    textProfileId: String? = nil,
    shortenerProfileId: String? = nil
  ) {
    self.imageProfileId = imageProfileId
    self.fileProfileId = fileProfileId
    self.textProfileId = textProfileId
    self.shortenerProfileId = shortenerProfileId
  }

  func profileId(for kind: DestinationKind) -> String? {
    switch kind {
    case .image: return imageProfileId
    case .file: return fileProfileId
    case .text: return textProfileId
    case .shortener: return shortenerProfileId
    }
  }

  mutating func setProfileId(_ profileId: String?, for kind: DestinationKind) {
    switch kind {
    case .image: imageProfileId = profileId
    case .file: fileProfileId = profileId
    case .text: textProfileId = profileId
    case .shortener: shortenerProfileId = profileId
    }
  }
}

enum URLShortenerProvider: String, CaseIterable, Codable {
  case tinyURL
  case customGetTemplate
}

extension URLShortenerProvider {
  init(normalizedRawValue rawValue: String) {
    self = URLShortenerProvider(rawValue: rawValue) ?? .tinyURL
  }
}

struct URLShortenerConfig: Codable, Equatable {
  var provider: URLShortenerProvider
  var customGetTemplate: String

  init(provider: URLShortenerProvider = .tinyURL, customGetTemplate: String = "") {
    self.provider = provider
    self.customGetTemplate = customGetTemplate
  }

  private enum CodingKeys: String, CodingKey {
    case provider, customGetTemplate
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let rawProvider = try container.decodeIfPresent(String.self, forKey: .provider) ?? URLShortenerProvider.tinyURL.rawValue
    provider = URLShortenerProvider(normalizedRawValue: rawProvider)
    customGetTemplate = try container.decodeIfPresent(String.self, forKey: .customGetTemplate) ?? ""
  }
}

struct CloudflareAllowlistConfig: Codable, Equatable {
  var enabled: Bool
  var accountId: String
  var listId: String
  var deviceName: String
  var checkIntervalMinutes: Int

  init(
    enabled: Bool = false,
    accountId: String = "",
    listId: String = "",
    deviceName: String = CloudflareAllowlistConfig.defaultDeviceName(),
    checkIntervalMinutes: Int = 15
  ) {
    self.enabled = enabled
    self.accountId = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.listId = listId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.deviceName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    self.checkIntervalMinutes = Self.normalizedInterval(checkIntervalMinutes)
  }

  var normalized: CloudflareAllowlistConfig {
    CloudflareAllowlistConfig(
      enabled: enabled,
      accountId: accountId,
      listId: listId,
      deviceName: deviceName.isEmpty ? Self.defaultDeviceName() : deviceName,
      checkIntervalMinutes: checkIntervalMinutes
    )
  }

  static func normalizedInterval(_ minutes: Int) -> Int {
    max(5, min(24 * 60, minutes))
  }

  static func defaultDeviceName() -> String {
    let hostName = Host.current().localizedName ?? Host.current().name ?? "This Mac"
    let trimmed = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "This Mac" : trimmed
  }
}

struct ClipboardUploadRules: Codable, Equatable {
  var uploadURLContents: Bool
  var shortenURL: Bool
  var shareURLAfterUpload: Bool
  var autoIndexFolder: Bool
  var uploadTextContents: Bool

  init(
    uploadURLContents: Bool = true,
    shortenURL: Bool = false,
    shareURLAfterUpload: Bool = false,
    autoIndexFolder: Bool = false,
    uploadTextContents: Bool = false
  ) {
    self.uploadURLContents = uploadURLContents
    self.shortenURL = shortenURL
    self.shareURLAfterUpload = shareURLAfterUpload
    self.autoIndexFolder = autoIndexFolder
    self.uploadTextContents = uploadTextContents
  }
}

struct HotKeyShortcut: Codable, Equatable {
  static let allowedKeys: [String] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").map(String.init)
  private static let allowedKeySet = Set(allowedKeys)

  var key: String
  var command: Bool
  var shift: Bool
  var option: Bool
  var control: Bool

  init(key: String, command: Bool = true, shift: Bool = false, option: Bool = false, control: Bool = false) {
    self.key = Self.normalizeKey(key)
    self.command = command
    self.shift = shift
    self.option = option
    self.control = control
  }

  var normalized: HotKeyShortcut {
    var updated = self
    updated.key = Self.normalizeKey(updated.key)
    if !updated.command && !updated.shift && !updated.option && !updated.control {
      updated.command = true
    }
    return updated
  }

  var displayText: String {
    var parts: [String] = []
    if command { parts.append("Cmd") }
    if shift { parts.append("Shift") }
    if option { parts.append("Opt") }
    if control { parts.append("Ctrl") }
    parts.append(Self.normalizeKey(key))
    return parts.joined(separator: "+")
  }

  static func normalizeKey(_ raw: String) -> String {
    let candidate = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().prefix(1))
    guard allowedKeySet.contains(candidate) else { return "G" }
    return candidate
  }
}

struct HotKeyBindings: Codable, Equatable {
  var captureRegionUpload: HotKeyShortcut
  var captureRegionUploadExpiring: HotKeyShortcut
  var captureRegionUploadFrozen: HotKeyShortcut
  var uploadClipboard: HotKeyShortcut

  static let defaultValue = HotKeyBindings(
    captureRegionUpload: HotKeyShortcut(key: "G", command: true),
    captureRegionUploadExpiring: HotKeyShortcut(key: "G", command: true, shift: true),
    captureRegionUploadFrozen: HotKeyShortcut(key: "P", command: true, shift: true),
    uploadClipboard: HotKeyShortcut(key: "7", command: true, shift: true)
  )

  init(
    captureRegionUpload: HotKeyShortcut,
    captureRegionUploadExpiring: HotKeyShortcut,
    captureRegionUploadFrozen: HotKeyShortcut,
    uploadClipboard: HotKeyShortcut
  ) {
    self.captureRegionUpload = captureRegionUpload
    self.captureRegionUploadExpiring = captureRegionUploadExpiring
    self.captureRegionUploadFrozen = captureRegionUploadFrozen
    self.uploadClipboard = uploadClipboard
  }

  private enum CodingKeys: String, CodingKey {
    case captureRegionUpload, captureRegionUploadExpiring, captureRegionUploadFrozen, uploadClipboard
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = HotKeyBindings.defaultValue
    captureRegionUpload = try c.decodeIfPresent(HotKeyShortcut.self, forKey: .captureRegionUpload)
      ?? defaults.captureRegionUpload
    captureRegionUploadExpiring = try c.decodeIfPresent(HotKeyShortcut.self, forKey: .captureRegionUploadExpiring)
      ?? defaults.captureRegionUploadExpiring
    // Older installs stored bindings without this key; fall back to the default
    // instead of resetting all bindings.
    captureRegionUploadFrozen = try c.decodeIfPresent(HotKeyShortcut.self, forKey: .captureRegionUploadFrozen)
      ?? defaults.captureRegionUploadFrozen
    uploadClipboard = try c.decodeIfPresent(HotKeyShortcut.self, forKey: .uploadClipboard)
      ?? defaults.uploadClipboard
  }

  var normalized: HotKeyBindings {
    HotKeyBindings(
      captureRegionUpload: captureRegionUpload.normalized,
      captureRegionUploadExpiring: captureRegionUploadExpiring.normalized,
      captureRegionUploadFrozen: captureRegionUploadFrozen.normalized,
      uploadClipboard: uploadClipboard.normalized
    )
  }
}

enum WatchFolderMode: String, CaseIterable, Codable {
  case auto
  case imageOnly
  case fileOnly
}

struct WatchFolderRule: Codable, Identifiable, Equatable {
  var id: String
  var path: String
  var includeSubdirectories: Bool
  var fileFilter: String
  var mode: WatchFolderMode
  var expirySeconds: Int?
  var enabled: Bool

  init(
    id: String = UUID().uuidString,
    path: String,
    includeSubdirectories: Bool = true,
    fileFilter: String = "*",
    mode: WatchFolderMode = .auto,
    expirySeconds: Int? = nil,
    enabled: Bool = true
  ) {
    self.id = id
    self.path = path
    self.includeSubdirectories = includeSubdirectories
    self.fileFilter = fileFilter
    self.mode = mode
    self.expirySeconds = expirySeconds
    self.enabled = enabled
  }
}

final class RuntimePreferences {
  static let shared = RuntimePreferences()
  private init() {
    migrateCaptureClipboardWorkflowDefaultsIfNeeded()
  }

  private let defaults = UserDefaults.standard

  private let captureShowCursorKey = "runtime.capture.showCursor.v1"
  private let captureDelaySecondsKey = "runtime.capture.delaySeconds.v1"
  private let captureFixedRegionEnabledKey = "runtime.capture.fixedRegionEnabled.v1"
  private let captureFixedRegionXKey = "runtime.capture.fixedRegion.x.v1"
  private let captureFixedRegionYKey = "runtime.capture.fixedRegion.y.v1"
  private let captureFixedRegionWidthKey = "runtime.capture.fixedRegion.width.v1"
  private let captureFixedRegionHeightKey = "runtime.capture.fixedRegion.height.v1"
  private let captureShowInfoOverlayKey = "runtime.capture.showInfoOverlay.v1"
  private let captureSnapSizesKey = "runtime.capture.snapSizes.v1"
  private let captureScreenshotsFolderPathKey = "runtime.capture.screenshotsFolderPath.v1"

  private let afterCaptureSaveLocalCopyKey = "runtime.afterCapture.saveLocalCopy.v1"
  private let afterCaptureCopyURLKey = "runtime.afterCapture.copyURL.v1"
  private let afterCaptureCopyImageAndURLKey = "runtime.afterCapture.copyImageAndURL.v1"
  private let afterCaptureOpenEditorKey = "runtime.afterCapture.openEditor.v1"

  private let afterUploadCopyURLKey = "runtime.afterUpload.copyURL.v1"
  private let afterUploadCopyImageKey = "runtime.afterUpload.copyImage.v1"
  private let afterUploadOpenURLKey = "runtime.afterUpload.openURL.v1"
  private let captureClipboardWorkflowVersionKey = "runtime.captureClipboardWorkflowVersion.v1"

  private let fileUploadUseNamePatternKey = "runtime.upload.fileName.usePattern.v1"
  private let fileUploadUseRandom16NameKey = "runtime.upload.fileName.useRandom16.v1"
  private let fileNamePatternKey = "runtime.upload.fileName.pattern.v1"
  private let fileNameAutoIncrementKey = "runtime.upload.fileName.autoIncrement.v1"
  private let fileUploadReplaceProblematicCharactersKey = "runtime.upload.fileName.replaceProblematic.v1"
  private let stripImageMetadataBeforeUploadKey = "runtime.upload.stripImageMetadataBeforeUpload.v1"
  private let imageUploadFormatKey = "runtime.upload.imageFormat.v1"
  private let urlRegexReplaceEnabledKey = "runtime.upload.urlRegex.enabled.v1"
  private let urlRegexPatternKey = "runtime.upload.urlRegex.pattern.v1"
  private let urlRegexReplacementKey = "runtime.upload.urlRegex.replacement.v1"

  private let uploaderFiltersKey = "runtime.upload.filters.v1"
  private let destinationRoutingKey = "runtime.destination.routing.v1"
  private let shortenerConfigKey = "runtime.shortener.config.v1"
  private let cloudflareAllowlistConfigKey = "runtime.cloudflare.allowlist.config.v1"
  private let clipboardRulesKey = "runtime.clipboard.rules.v1"
  private let watchFoldersKey = "runtime.watchFolders.rules.v1"
  private let watchFoldersEnabledKey = "runtime.watchFolders.enabled.v1"
  private let defaultFileExpirySecondsKey = "runtime.upload.defaultFileExpirySeconds.v1"
  private let onboardingStateKey = "runtime.onboarding.state.v1"
  private let uiRainbowModeKey = "runtime.ui.rainbowMode.v1"
  private let uiPaletteIdKey = "runtime.ui.paletteId.v1"
  private let uiCustomPaletteKey = "runtime.ui.customPalette.v1"
  private let hotKeyBindingsKey = "runtime.hotkeys.bindings.v1"
  private let ocrIndexingEnabledKey = "runtime.ocr.indexingEnabled.v1"
  private let redactionDetectorSettingsKey = "runtime.redaction.detectorSettings.v1"
  private let uploadRedactionPolicyKey = "runtime.redaction.uploadPolicy.v1"
  private let smartRedactionRenderModeKey = "runtime.redaction.renderMode.v1"

  var onboardingState: OnboardingState {
    get {
      guard let raw = defaults.string(forKey: onboardingStateKey), let parsed = OnboardingState(rawValue: raw) else {
        return .pending
      }
      return parsed
    }
    set {
      let oldValue = onboardingState
      defaults.set(newValue.rawValue, forKey: onboardingStateKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var uiRainbowMode: Bool {
    get { defaults.bool(forKey: uiRainbowModeKey) }
    set {
      let oldValue = uiRainbowMode
      defaults.set(newValue, forKey: uiRainbowModeKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var ocrIndexingEnabled: Bool {
    get { defaults.object(forKey: ocrIndexingEnabledKey) as? Bool ?? true }
    set {
      let oldValue = ocrIndexingEnabled
      defaults.set(newValue, forKey: ocrIndexingEnabledKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var redactionDetectorSettings: RedactionDetectorSettings {
    get {
      guard let data = defaults.data(forKey: redactionDetectorSettingsKey),
            let decoded = try? JSONDecoder().decode(RedactionDetectorSettings.self, from: data) else {
        return .defaultValue
      }
      return decoded
    }
    set {
      let normalized = RedactionDetectorSettings(
        textOCR: newValue.textOCR,
        faces: newValue.faces,
        barcodes: newValue.barcodes,
        emailAddresses: newValue.emailAddresses,
        phoneNumbers: newValue.phoneNumbers,
        creditCardNumbers: newValue.creditCardNumbers,
        ipv4Addresses: newValue.ipv4Addresses,
        ipv6Addresses: newValue.ipv6Addresses,
        macAddresses: newValue.macAddresses,
        urlsDomains: newValue.urlsDomains,
        apiKeys: newValue.apiKeys,
        awsAccessKeys: newValue.awsAccessKeys,
        githubTokens: newValue.githubTokens,
        openAIKeys: newValue.openAIKeys,
        bearerTokens: newValue.bearerTokens,
        jwts: newValue.jwts,
        privateKeyBlocks: newValue.privateKeyBlocks,
        sessionCookies: newValue.sessionCookies,
        passwordFields: newValue.passwordFields,
        environmentVariables: newValue.environmentVariables,
        filePaths: newValue.filePaths,
        usernamesHostnames: newValue.usernamesHostnames,
        minimumConfidence: newValue.minimumConfidence,
        useFastTextRecognition: newValue.useFastTextRecognition,
        allowSensitiveTextPreviews: newValue.allowSensitiveTextPreviews
      )
      let oldValue = redactionDetectorSettings
      let data = (try? JSONEncoder().encode(normalized)) ?? Data()
      defaults.set(data, forKey: redactionDetectorSettingsKey)
      if oldValue != normalized { notifyChanged() }
    }
  }

  var uploadRedactionPolicy: UploadRedactionPolicy {
    get {
      guard let raw = defaults.string(forKey: uploadRedactionPolicyKey),
            let parsed = UploadRedactionPolicy(rawValue: raw) else {
        return .askBeforeUpload
      }
      return parsed
    }
    set {
      let oldValue = uploadRedactionPolicy
      defaults.set(newValue.rawValue, forKey: uploadRedactionPolicyKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var smartRedactionRenderMode: SmartRedactionRenderMode {
    get {
      guard let raw = defaults.string(forKey: smartRedactionRenderModeKey),
            let parsed = SmartRedactionRenderMode(rawValue: raw) else {
        return .pixelate
      }
      return parsed
    }
    set {
      let oldValue = smartRedactionRenderMode
      defaults.set(newValue.rawValue, forKey: smartRedactionRenderModeKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var uiPaletteId: UIPaletteID {
    get {
      guard let raw = defaults.string(forKey: uiPaletteIdKey), let parsed = UIPaletteID(rawValue: raw) else {
        return .classic
      }
      return parsed
    }
    set {
      let oldValue = uiPaletteId
      defaults.set(newValue.rawValue, forKey: uiPaletteIdKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var uiCustomPalette: UIPaletteData {
    get {
      guard let data = defaults.data(forKey: uiCustomPaletteKey) else {
        return UIPaletteCatalog.defaultCustomSeed()
      }
      if let decoded = try? JSONDecoder().decode(UIPaletteData.self, from: data) {
        return decoded
      }
      return UIPaletteCatalog.defaultCustomSeed()
    }
    set {
      let oldValue = uiCustomPalette
      guard let encoded = try? JSONEncoder().encode(newValue) else { return }
      defaults.set(encoded, forKey: uiCustomPaletteKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var captureShowCursor: Bool {
    get { defaults.object(forKey: captureShowCursorKey) as? Bool ?? false }
    set {
      let oldValue = captureShowCursor
      defaults.set(newValue, forKey: captureShowCursorKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var captureDelaySeconds: Int {
    get {
      let value = defaults.object(forKey: captureDelaySecondsKey) as? Int ?? 0
      return max(0, min(5, value))
    }
    set {
      let normalized = max(0, min(5, newValue))
      let oldValue = captureDelaySeconds
      defaults.set(normalized, forKey: captureDelaySecondsKey)
      if oldValue != normalized { notifyChanged() }
    }
  }

  var captureFixedRegionEnabled: Bool {
    get { defaults.object(forKey: captureFixedRegionEnabledKey) as? Bool ?? false }
    set {
      let oldValue = captureFixedRegionEnabled
      defaults.set(newValue, forKey: captureFixedRegionEnabledKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var captureFixedRegionX: Int {
    get { defaults.object(forKey: captureFixedRegionXKey) as? Int ?? 0 }
    set {
      // Negative values are valid: displays left of the main display.
      let oldValue = captureFixedRegionX
      defaults.set(newValue, forKey: captureFixedRegionXKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var captureFixedRegionY: Int {
    get { defaults.object(forKey: captureFixedRegionYKey) as? Int ?? 0 }
    set {
      // Negative values are valid: displays above the main display.
      let oldValue = captureFixedRegionY
      defaults.set(newValue, forKey: captureFixedRegionYKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var captureFixedRegionWidth: Int {
    get { defaults.object(forKey: captureFixedRegionWidthKey) as? Int ?? 1280 }
    set {
      let normalized = max(1, newValue)
      let oldValue = captureFixedRegionWidth
      defaults.set(normalized, forKey: captureFixedRegionWidthKey)
      if oldValue != normalized { notifyChanged() }
    }
  }

  var captureFixedRegionHeight: Int {
    get { defaults.object(forKey: captureFixedRegionHeightKey) as? Int ?? 720 }
    set {
      let normalized = max(1, newValue)
      let oldValue = captureFixedRegionHeight
      defaults.set(normalized, forKey: captureFixedRegionHeightKey)
      if oldValue != normalized { notifyChanged() }
    }
  }

  var captureShowInfoOverlay: Bool {
    get { defaults.object(forKey: captureShowInfoOverlayKey) as? Bool ?? true }
    set {
      let oldValue = captureShowInfoOverlay
      defaults.set(newValue, forKey: captureShowInfoOverlayKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var captureSnapSizes: [CGSize] {
    get {
      let raw = defaults.stringArray(forKey: captureSnapSizesKey) ?? []
      return raw.compactMap(Self.parseSizeString)
    }
    set {
      let oldValue = captureSnapSizes
      let encoded = newValue.map { "\(Int($0.width))x\(Int($0.height))" }
      defaults.set(encoded, forKey: captureSnapSizesKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var captureScreenshotsFolderPath: String {
    get { defaults.string(forKey: captureScreenshotsFolderPathKey) ?? "" }
    set {
      let oldValue = captureScreenshotsFolderPath
      let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
      if normalized.isEmpty {
        defaults.removeObject(forKey: captureScreenshotsFolderPathKey)
      } else {
        defaults.set((normalized as NSString).expandingTildeInPath, forKey: captureScreenshotsFolderPathKey)
      }
      if oldValue != captureScreenshotsFolderPath { notifyChanged() }
    }
  }

  var afterCaptureSaveLocalCopy: Bool {
    get { defaults.object(forKey: afterCaptureSaveLocalCopyKey) as? Bool ?? true }
    set {
      let oldValue = afterCaptureSaveLocalCopy
      defaults.set(newValue, forKey: afterCaptureSaveLocalCopyKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var afterCaptureCopyURL: Bool {
    get { defaults.object(forKey: afterCaptureCopyURLKey) as? Bool ?? true }
    set {
      let oldValue = afterCaptureCopyURL
      defaults.set(newValue, forKey: afterCaptureCopyURLKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var afterCaptureCopyImageAndURL: Bool {
    get { defaults.object(forKey: afterCaptureCopyImageAndURLKey) as? Bool ?? false }
    set {
      let oldValue = afterCaptureCopyImageAndURL
      defaults.set(newValue, forKey: afterCaptureCopyImageAndURLKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  private func migrateCaptureClipboardWorkflowDefaultsIfNeeded() {
    guard defaults.integer(forKey: captureClipboardWorkflowVersionKey) < 1 else { return }

    if defaults.object(forKey: afterCaptureCopyImageAndURLKey) == nil
      || defaults.object(forKey: afterCaptureCopyImageAndURLKey) as? Bool == true {
      defaults.set(false, forKey: afterCaptureCopyImageAndURLKey)
    }

    defaults.set(1, forKey: captureClipboardWorkflowVersionKey)
  }

  var afterCaptureOpenEditor: Bool {
    get { defaults.object(forKey: afterCaptureOpenEditorKey) as? Bool ?? false }
    set {
      let oldValue = afterCaptureOpenEditor
      defaults.set(newValue, forKey: afterCaptureOpenEditorKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var afterCaptureTasks: AfterCaptureTaskOptions {
    AfterCaptureTaskOptions(
      saveLocalCopy: afterCaptureSaveLocalCopy,
      copyURL: afterCaptureCopyURL,
      copyImageAndURL: afterCaptureCopyImageAndURL,
      openEditor: afterCaptureOpenEditor
    )
  }

  var afterUploadCopyURL: Bool {
    get { defaults.object(forKey: afterUploadCopyURLKey) as? Bool ?? true }
    set {
      let oldValue = afterUploadCopyURL
      defaults.set(newValue, forKey: afterUploadCopyURLKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var afterUploadCopyImage: Bool {
    get { defaults.object(forKey: afterUploadCopyImageKey) as? Bool ?? false }
    set {
      let oldValue = afterUploadCopyImage
      defaults.set(newValue, forKey: afterUploadCopyImageKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var afterUploadOpenURL: Bool {
    get { defaults.object(forKey: afterUploadOpenURLKey) as? Bool ?? false }
    set {
      let oldValue = afterUploadOpenURL
      defaults.set(newValue, forKey: afterUploadOpenURLKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var fileUploadUseNamePattern: Bool {
    get { defaults.object(forKey: fileUploadUseNamePatternKey) as? Bool ?? false }
    set {
      let oldValue = fileUploadUseNamePattern
      defaults.set(newValue, forKey: fileUploadUseNamePatternKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var fileUploadUseRandom16Name: Bool {
    get { defaults.object(forKey: fileUploadUseRandom16NameKey) as? Bool ?? false }
    set {
      let oldValue = fileUploadUseRandom16Name
      defaults.set(newValue, forKey: fileUploadUseRandom16NameKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var fileNamePattern: String {
    get { defaults.string(forKey: fileNamePatternKey) ?? "{date}-{rand}" }
    set {
      let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
      let value = normalized.isEmpty ? "{date}-{rand}" : normalized
      let oldValue = fileNamePattern
      defaults.set(value, forKey: fileNamePatternKey)
      if oldValue != value { notifyChanged() }
    }
  }

  var fileNameAutoIncrement: Int {
    get { max(1, defaults.object(forKey: fileNameAutoIncrementKey) as? Int ?? 1) }
    set {
      let normalized = max(1, newValue)
      let oldValue = fileNameAutoIncrement
      defaults.set(normalized, forKey: fileNameAutoIncrementKey)
      if oldValue != normalized { notifyChanged() }
    }
  }

  var fileUploadReplaceProblematicCharacters: Bool {
    get { defaults.object(forKey: fileUploadReplaceProblematicCharactersKey) as? Bool ?? true }
    set {
      let oldValue = fileUploadReplaceProblematicCharacters
      defaults.set(newValue, forKey: fileUploadReplaceProblematicCharactersKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var stripImageMetadataBeforeUpload: Bool {
    get { defaults.object(forKey: stripImageMetadataBeforeUploadKey) as? Bool ?? false }
    set {
      let oldValue = stripImageMetadataBeforeUpload
      defaults.set(newValue, forKey: stripImageMetadataBeforeUploadKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var imageUploadFormat: ImageUploadFormat {
    get {
      guard let raw = defaults.string(forKey: imageUploadFormatKey),
            let parsed = ImageUploadFormat(rawValue: raw) else {
        return .png
      }
      return parsed
    }
    set {
      let oldValue = imageUploadFormat
      defaults.set(newValue.rawValue, forKey: imageUploadFormatKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var urlRegexReplaceEnabled: Bool {
    get { defaults.object(forKey: urlRegexReplaceEnabledKey) as? Bool ?? false }
    set {
      let oldValue = urlRegexReplaceEnabled
      defaults.set(newValue, forKey: urlRegexReplaceEnabledKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var urlRegexPattern: String {
    get { defaults.string(forKey: urlRegexPatternKey) ?? "" }
    set {
      let oldValue = urlRegexPattern
      defaults.set(newValue, forKey: urlRegexPatternKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var urlRegexReplacement: String {
    get { defaults.string(forKey: urlRegexReplacementKey) ?? "" }
    set {
      let oldValue = urlRegexReplacement
      defaults.set(newValue, forKey: urlRegexReplacementKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var uploaderFilters: [UploaderFilterRule] {
    get {
      guard let data = defaults.data(forKey: uploaderFiltersKey) else { return [] }
      return (try? JSONDecoder().decode([UploaderFilterRule].self, from: data)) ?? []
    }
    set {
      let normalized = newValue.map { rule in
        UploaderFilterRule(id: rule.id, extensions: rule.extensions, profileId: rule.profileId)
      }.filter { !$0.extensions.isEmpty && !$0.profileId.isEmpty }
      let oldValue = uploaderFilters
      let data = (try? JSONEncoder().encode(normalized)) ?? Data()
      defaults.set(data, forKey: uploaderFiltersKey)
      if oldValue != normalized { notifyChanged() }
    }
  }

  var destinationRouting: DestinationRoutingConfig {
    get {
      guard let data = defaults.data(forKey: destinationRoutingKey),
            let decoded = try? JSONDecoder().decode(DestinationRoutingConfig.self, from: data) else {
        return DestinationRoutingConfig()
      }
      return decoded
    }
    set {
      let oldValue = destinationRouting
      let data = (try? JSONEncoder().encode(newValue)) ?? Data()
      defaults.set(data, forKey: destinationRoutingKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var shortenerConfig: URLShortenerConfig {
    get {
      guard let data = defaults.data(forKey: shortenerConfigKey),
            let decoded = try? JSONDecoder().decode(URLShortenerConfig.self, from: data) else {
        return URLShortenerConfig()
      }
      return decoded
    }
    set {
      let oldValue = shortenerConfig
      let data = (try? JSONEncoder().encode(newValue)) ?? Data()
      defaults.set(data, forKey: shortenerConfigKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var cloudflareAllowlistConfig: CloudflareAllowlistConfig {
    get {
      guard let data = defaults.data(forKey: cloudflareAllowlistConfigKey),
            let decoded = try? JSONDecoder().decode(CloudflareAllowlistConfig.self, from: data) else {
        return CloudflareAllowlistConfig()
      }
      return decoded.normalized
    }
    set {
      let normalized = newValue.normalized
      let oldValue = cloudflareAllowlistConfig
      let data = (try? JSONEncoder().encode(normalized)) ?? Data()
      defaults.set(data, forKey: cloudflareAllowlistConfigKey)
      if oldValue != normalized { notifyChanged() }
    }
  }

  var clipboardRules: ClipboardUploadRules {
    get {
      guard let data = defaults.data(forKey: clipboardRulesKey),
            let decoded = try? JSONDecoder().decode(ClipboardUploadRules.self, from: data) else {
        return ClipboardUploadRules()
      }
      return decoded
    }
    set {
      let oldValue = clipboardRules
      let data = (try? JSONEncoder().encode(newValue)) ?? Data()
      defaults.set(data, forKey: clipboardRulesKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var watchFolderRules: [WatchFolderRule] {
    get {
      guard let data = defaults.data(forKey: watchFoldersKey),
            let decoded = try? JSONDecoder().decode([WatchFolderRule].self, from: data) else {
        return []
      }
      return decoded
    }
    set {
      let oldValue = watchFolderRules
      let normalized = newValue.filter { !$0.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      let data = (try? JSONEncoder().encode(normalized)) ?? Data()
      defaults.set(data, forKey: watchFoldersKey)
      if oldValue != normalized { notifyChanged() }
    }
  }

  var watchFoldersEnabled: Bool {
    get { defaults.object(forKey: watchFoldersEnabledKey) as? Bool ?? false }
    set {
      let oldValue = watchFoldersEnabled
      defaults.set(newValue, forKey: watchFoldersEnabledKey)
      if oldValue != newValue { notifyChanged() }
    }
  }

  var hotKeyBindings: HotKeyBindings {
    get {
      guard let data = defaults.data(forKey: hotKeyBindingsKey),
            let decoded = try? JSONDecoder().decode(HotKeyBindings.self, from: data) else {
        return .defaultValue
      }
      return decoded.normalized
    }
    set {
      let normalized = newValue.normalized
      let oldValue = hotKeyBindings
      let data = (try? JSONEncoder().encode(normalized)) ?? Data()
      defaults.set(data, forKey: hotKeyBindingsKey)
      if oldValue != normalized {
        notifyChanged()
        NotificationCenter.default.post(name: .hotKeyPreferencesDidChange, object: nil)
      }
    }
  }

  var defaultFileExpirySeconds: Int {
    get {
      let value = defaults.object(forKey: defaultFileExpirySecondsKey) as? Int ?? 86_400
      return max(60, min(432_000, value))
    }
    set {
      let normalized = max(60, min(432_000, newValue))
      let oldValue = defaultFileExpirySeconds
      defaults.set(normalized, forKey: defaultFileExpirySecondsKey)
      if oldValue != normalized { notifyChanged() }
    }
  }

  var captureOptions: CaptureRuntimeOptions {
    let fixedRegion: CGRect?
    if captureFixedRegionEnabled && captureFixedRegionWidth > 0 && captureFixedRegionHeight > 0 {
      fixedRegion = CGRect(
        x: captureFixedRegionX,
        y: captureFixedRegionY,
        width: captureFixedRegionWidth,
        height: captureFixedRegionHeight
      )
    } else {
      fixedRegion = nil
    }

    return CaptureRuntimeOptions(
      includeCursor: captureShowCursor,
      delaySeconds: captureDelaySeconds,
      fixedRegion: fixedRegion,
      showOverlayInfo: captureShowInfoOverlay,
      snapSizes: captureSnapSizes
    )
  }

  func routedProfile(fileUrl: URL?, destinationKind: DestinationKind) -> UploadProfile {
    let profiles = Settings.shared.profiles()

    // ShareX-like uploader filters have highest priority for extension-specific matching.
    if let fileUrl {
      let ext = fileUrl.pathExtension.lowercased()
      for rule in uploaderFilters {
        guard rule.matches(fileExtension: ext) else { continue }
        if let profile = profiles.first(where: { $0.id == rule.profileId }) {
          return profile
        }
      }
    }

    if let routeProfileId = destinationRouting.profileId(for: destinationKind),
       let routed = profiles.first(where: { $0.id == routeProfileId }) {
      return routed
    }

    return Settings.shared.activeProfile
  }

  func profileForUpload(fileUrl: URL) -> UploadProfile {
    routedProfile(fileUrl: fileUrl, destinationKind: .image)
  }

  func shortenerProfile() -> UploadProfile {
    routedProfile(fileUrl: nil, destinationKind: .shortener)
  }

  func secondaryS3Profile(for primaryProfile: UploadProfile) -> UploadProfile? {
    guard primaryProfile.backend == .ziplineV4,
          let id = primaryProfile.secondaryS3ProfileId?.trimmingCharacters(in: .whitespacesAndNewlines),
          !id.isEmpty else {
      return nil
    }
    return Settings.shared.profiles().first { $0.id == id && $0.backend == .s3Compatible }
  }

  func generateUploadFilenameBase(originalFilename: String) -> String {
    if fileUploadUseRandom16Name {
      return Self.randomToken(length: 16)
    }

    let sourceBase = URL(fileURLWithPath: originalFilename).deletingPathExtension().lastPathComponent
    var pattern = fileNamePattern
    let now = Date()

    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")

    dateFormatter.dateFormat = "yyyy-MM-dd"
    pattern = pattern.replacingOccurrences(of: "{date}", with: dateFormatter.string(from: now))

    dateFormatter.dateFormat = "HH-mm-ss"
    pattern = pattern.replacingOccurrences(of: "{time}", with: dateFormatter.string(from: now))

    dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    pattern = pattern.replacingOccurrences(of: "{datetime}", with: dateFormatter.string(from: now))

    pattern = pattern.replacingOccurrences(of: "{rand}", with: Self.randomToken(length: 6))
    pattern = pattern.replacingOccurrences(of: "{name}", with: sourceBase)

    if pattern.contains("{inc}") {
      pattern = pattern.replacingOccurrences(of: "{inc}", with: "\(nextAutoIncrementValue())")
    }

    return Self.sanitizeFilenameComponent(
      pattern,
      aggressive: fileUploadReplaceProblematicCharacters
    )
  }

  func transformUploadedURL(_ rawURL: String) -> String {
    guard urlRegexReplaceEnabled else { return rawURL }
    let pattern = urlRegexPattern
    guard !pattern.isEmpty else { return rawURL }
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return rawURL }
    let range = NSRange(rawURL.startIndex..<rawURL.endIndex, in: rawURL)
    return regex.stringByReplacingMatches(in: rawURL, options: [], range: range, withTemplate: urlRegexReplacement)
  }

  private func nextAutoIncrementValue() -> Int {
    let value = max(1, defaults.object(forKey: fileNameAutoIncrementKey) as? Int ?? 1)
    defaults.set(value + 1, forKey: fileNameAutoIncrementKey)
    return value
  }

  private static func sanitizeFilenameComponent(_ raw: String, aggressive: Bool) -> String {
    let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
    let parts = raw.components(separatedBy: invalid)
    var sanitized = parts.joined(separator: "-")
    sanitized = sanitized.replacingOccurrences(of: "\n", with: "-")
    sanitized = sanitized.replacingOccurrences(of: "\r", with: "-")

    if aggressive {
      sanitized = sanitized.replacingOccurrences(of: " ", with: "-")
      sanitized = sanitized.replacingOccurrences(of: "\t", with: "-")
      while sanitized.contains("--") {
        sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
      }
    }

    let trimmed = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-_. "))
    return trimmed.isEmpty ? "upload" : trimmed
  }

  private static func randomToken(length: Int) -> String {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    var token = ""
    token.reserveCapacity(length)
    for _ in 0..<length {
      token.append(alphabet[Int.random(in: 0..<alphabet.count)])
    }
    return token
  }

  private static func parseSizeString(_ raw: String) -> CGSize? {
    let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = lower.split(separator: "x", maxSplits: 1).map(String.init)
    guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 else {
      return nil
    }
    return CGSize(width: w, height: h)
  }

  private func notifyChanged() {
    NotificationCenter.default.post(name: .runtimePreferencesDidChange, object: nil)
  }
}
