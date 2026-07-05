import AppKit
import Combine
import Foundation

extension Notification.Name {
  static let mainHubShowHistory = Notification.Name("mainHubShowHistory")
  static let mainHubShowWatchFolders = Notification.Name("mainHubShowWatchFolders")
  static let mainHubShowSettings = Notification.Name("mainHubShowSettings")
}

enum RailSection: String, CaseIterable, Identifiable {
  case capture
  case upload
  case workflows
  case tools
  case afterCapture
  case afterUpload
  case destinations
  case settings
  case history

  var id: String { rawValue }

  var title: String {
    switch self {
    case .capture: return "Capture"
    case .upload: return "Upload"
    case .workflows: return "Workflows"
    case .tools: return "Tools"
    case .afterCapture: return "After capture tasks"
    case .afterUpload: return "After upload tasks"
    case .destinations: return "Destinations"
    case .settings: return "Settings"
    case .history: return "History"
    }
  }

  var symbol: String {
    switch self {
    case .capture: return "camera"
    case .upload: return "arrow.up.doc"
    case .workflows: return "list.bullet.rectangle"
    case .tools: return "wrench.and.screwdriver"
    case .afterCapture: return "camera.filters"
    case .afterUpload: return "checkmark.circle"
    case .destinations: return "network"
    case .settings: return "gearshape"
    case .history: return "clock.arrow.circlepath"
    }
  }
}

enum ContextNodeID: String, Hashable, Identifiable {
  case captureModesGroup
  case captureRegion
  case captureWindow
  case captureFullscreen
  case captureExpiringRegion
  case captureTopTaskbar
  case captureScreenRecording
  case captureOptionsGroup
  case captureCursorDelay
  case captureRegionFixedSize

  case uploadQuickGroup
  case uploadClipboardImage
  case uploadImageFile
  case uploadExpiringFile
  case uploadFromURL
  case uploadText
  case uploadFolder
  case uploadSettingsGroup
  case uploadClipboardRules
  case uploadURLShortener
  case uploadWatchFolders
  case uploadFileNaming
  case uploadUploaderFilters

  case workflowsQuickGroup
  case workflowRegionToUrl
  case workflowClipboardToUrl

  case toolsGroups
  case toolsHotkeys
  case toolsProductivity
  case toolsEditor

  case afterCaptureGroup
  case afterCaptureBehavior

  case afterUploadGroup
  case afterUploadBehavior

  case destinationGroup
  case destinationsActiveProfile
  case destinationsEndpointBackend
  case destinationsBehavior

  case settingsGroup
  case settingsApplication
  case settingsTask
  case settingsCloudflareAllowlist
  case settingsAdvanced

  case historyGroup
  case historyUploads

  var id: String { rawValue }
}

struct ContextNode: Identifiable, Hashable {
  let id: ContextNodeID
  let title: String
  let symbol: String
  let children: [ContextNode]

  var childNodes: [ContextNode]? {
    children.isEmpty ? nil : children
  }

  init(id: ContextNodeID, title: String, symbol: String, children: [ContextNode] = []) {
    self.id = id
    self.title = title
    self.symbol = symbol
    self.children = children
  }
}

final class MainShellViewModel: ObservableObject {
  @Published var railSelection: RailSection = .capture {
    didSet { syncNodeSelectionForCurrentRail() }
  }
  @Published var nodeSelection: ContextNodeID?
  @Published var contextSearchText = "" {
    didSet { syncNodeSelectionForCurrentRail() }
  }

  // These mirror ShareX-style controls; some are persisted as runtime preferences.
  @Published var includeCursorOnCapture = true {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.captureShowCursor = includeCursorOnCapture
    }
  }
  @Published var captureDelaySeconds = 0 {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.captureDelaySeconds = captureDelaySeconds
    }
  }
  @Published var captureFixedRegionEnabled = false {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.captureFixedRegionEnabled = captureFixedRegionEnabled
    }
  }
  @Published var captureFixedRegionX = 0 {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.captureFixedRegionX = captureFixedRegionX
    }
  }
  @Published var captureFixedRegionY = 0 {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.captureFixedRegionY = captureFixedRegionY
    }
  }
  @Published var captureFixedRegionWidth = 1280 {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.captureFixedRegionWidth = captureFixedRegionWidth
    }
  }
  @Published var captureFixedRegionHeight = 720 {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.captureFixedRegionHeight = captureFixedRegionHeight
    }
  }
  @Published var captureShowInfoOverlay = true {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.captureShowInfoOverlay = captureShowInfoOverlay
    }
  }
  @Published var captureSnapSizesText = "" {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.captureSnapSizes = Self.parseSnapSizes(captureSnapSizesText)
    }
  }
  @Published var afterCaptureSaveLocalCopy = true {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.afterCaptureSaveLocalCopy = afterCaptureSaveLocalCopy
    }
  }
  @Published var afterCaptureCopyURL = true {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.afterCaptureCopyURL = afterCaptureCopyURL
    }
  }
  @Published var afterCaptureCopyImageAndURL = false {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.afterCaptureCopyImageAndURL = afterCaptureCopyImageAndURL
    }
  }
  @Published var afterCaptureOpenEditor = false {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.afterCaptureOpenEditor = afterCaptureOpenEditor
    }
  }
  @Published private(set) var screenshotsFolderPathDisplay = ""
  @Published private(set) var screenshotsFolderIsCustom = false
  @Published var afterUploadOpenURL = false {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.afterUploadOpenURL = afterUploadOpenURL
    }
  }
  @Published var afterUploadCopyImage = false {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.afterUploadCopyImage = afterUploadCopyImage
    }
  }
  @Published var afterUploadCopyURL = true {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.afterUploadCopyURL = afterUploadCopyURL
    }
  }
  @Published var hotkeyCaptureRegionUpload = HotKeyBindings.defaultValue.captureRegionUpload {
    didSet {
      guard !runtimeSyncInProgress else { return }
      persistHotKeyBindings()
    }
  }
  @Published var hotkeyCaptureRegionUploadExpiring = HotKeyBindings.defaultValue.captureRegionUploadExpiring {
    didSet {
      guard !runtimeSyncInProgress else { return }
      persistHotKeyBindings()
    }
  }
  @Published var hotkeyCaptureRegionUploadFrozen = HotKeyBindings.defaultValue.captureRegionUploadFrozen {
    didSet {
      guard !runtimeSyncInProgress else { return }
      persistHotKeyBindings()
    }
  }
  @Published var hotkeyUploadClipboard = HotKeyBindings.defaultValue.uploadClipboard {
    didSet {
      guard !runtimeSyncInProgress else { return }
      persistHotKeyBindings()
    }
  }
  @Published var afterUploadShowNotification = true
  @Published var uploadShareURLAfterClipboard = false {
    didSet {
      guard !runtimeSyncInProgress else { return }
      var rules = RuntimePreferences.shared.clipboardRules
      rules.shareURLAfterUpload = uploadShareURLAfterClipboard
      RuntimePreferences.shared.clipboardRules = rules
    }
  }
  @Published var uploadShortenURL = false {
    didSet {
      guard !runtimeSyncInProgress else { return }
      var rules = RuntimePreferences.shared.clipboardRules
      rules.shortenURL = uploadShortenURL
      RuntimePreferences.shared.clipboardRules = rules
    }
  }
  @Published var uploadClipboardURLContents = true {
    didSet {
      guard !runtimeSyncInProgress else { return }
      var rules = RuntimePreferences.shared.clipboardRules
      rules.uploadURLContents = uploadClipboardURLContents
      RuntimePreferences.shared.clipboardRules = rules
    }
  }
  @Published var uploadClipboardAutoIndexFolder = false {
    didSet {
      guard !runtimeSyncInProgress else { return }
      var rules = RuntimePreferences.shared.clipboardRules
      rules.autoIndexFolder = uploadClipboardAutoIndexFolder
      RuntimePreferences.shared.clipboardRules = rules
    }
  }
  @Published var uploadClipboardTextContents = false {
    didSet {
      guard !runtimeSyncInProgress else { return }
      var rules = RuntimePreferences.shared.clipboardRules
      rules.uploadTextContents = uploadClipboardTextContents
      RuntimePreferences.shared.clipboardRules = rules
    }
  }
  @Published var fileUploadUseNamePattern = false {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.fileUploadUseNamePattern = fileUploadUseNamePattern
    }
  }
  @Published var fileUploadUseRandom16Name = false {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.fileUploadUseRandom16Name = fileUploadUseRandom16Name
    }
  }
  @Published var fileNamePattern = "{date}-{rand}" {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.fileNamePattern = fileNamePattern
    }
  }
  @Published var fileNameAutoIncrement = 1 {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.fileNameAutoIncrement = max(1, fileNameAutoIncrement)
      if fileNameAutoIncrement < 1 {
        fileNameAutoIncrement = 1
      }
    }
  }
  @Published var fileUploadReplaceProblematicCharacters = true {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.fileUploadReplaceProblematicCharacters = fileUploadReplaceProblematicCharacters
    }
  }
  @Published var stripImageMetadataBeforeUpload = false {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.stripImageMetadataBeforeUpload = stripImageMetadataBeforeUpload
    }
  }
  @Published var imageUploadFormat: ImageUploadFormat = .png {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.imageUploadFormat = imageUploadFormat
    }
  }
  @Published var urlRegexReplaceEnabled = false {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.urlRegexReplaceEnabled = urlRegexReplaceEnabled
    }
  }
  @Published var urlRegexPattern = "" {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.urlRegexPattern = urlRegexPattern
    }
  }
  @Published var urlRegexReplacement = "" {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.urlRegexReplacement = urlRegexReplacement
    }
  }
  @Published private(set) var uploaderFilters: [UploaderFilterRule] = []
  @Published var selectedUploaderFilterId: String?
  @Published var uploaderFilterExtensionsInput = ""
  @Published var uploaderFilterProfileId = ""

  @Published var defaultFileNamePattern = "{date}-{rand}" {
    didSet {
      guard !runtimeSyncInProgress else { return }
      fileNamePattern = defaultFileNamePattern
      fileUploadUseNamePattern = true
    }
  }
  @Published var selectedUploadBehavior = "Use active destination"
  @Published var routingImageProfileId = ""
  @Published var routingFileProfileId = ""
  @Published var routingTextProfileId = ""
  @Published var routingShortenerProfileId = ""
  @Published var shortenerProviderRawValue: String = URLShortenerProvider.tinyURL.rawValue
  @Published var shortenerCustomTemplate = ""
  @Published var watchFoldersEnabled = false {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.watchFoldersEnabled = watchFoldersEnabled
    }
  }
  @Published private(set) var watchFolderRules: [WatchFolderRule] = []
  @Published var selectedWatchFolderRuleId: String?
  @Published var watchFolderPathInput = ""
  @Published var watchFolderFilterInput = "*"
  @Published var watchFolderIncludeSubdirectories = true
  @Published var watchFolderModeRawValue = WatchFolderMode.auto.rawValue
  @Published var watchFolderExpirySeconds: Int = 0
  @Published var appShowMainWindowOnLaunch = true
  @Published var uiPaletteId: UIPaletteID = .classic {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.uiPaletteId = uiPaletteId
    }
  }
  @Published var uiCustomPalette: UIPaletteData = UIPaletteCatalog.defaultCustomSeed() {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.uiCustomPalette = uiCustomPalette
    }
  }
  @Published var uiRainbowMode = false {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.uiRainbowMode = uiRainbowMode
    }
  }
  @Published var taskOverrideEnabled = true
  @Published var advancedDebugLogging = false
  @Published var advancedRetryCount = 2
  @Published var cloudflareAllowlistEnabled = false {
    didSet {
      guard !runtimeSyncInProgress else { return }
      persistCloudflareAllowlistConfig()
    }
  }
  @Published var cloudflareAccountId = "" {
    didSet {
      guard !runtimeSyncInProgress else { return }
      persistCloudflareAllowlistConfig()
    }
  }
  @Published var cloudflareListId = "" {
    didSet {
      guard !runtimeSyncInProgress else { return }
      persistCloudflareAllowlistConfig()
    }
  }
  @Published var cloudflareDeviceName = CloudflareAllowlistConfig.defaultDeviceName() {
    didSet {
      guard !runtimeSyncInProgress else { return }
      persistCloudflareAllowlistConfig()
    }
  }
  @Published var cloudflareCheckIntervalMinutes = 15 {
    didSet {
      guard !runtimeSyncInProgress else { return }
      let normalized = CloudflareAllowlistConfig.normalizedInterval(cloudflareCheckIntervalMinutes)
      if cloudflareCheckIntervalMinutes != normalized {
        cloudflareCheckIntervalMinutes = normalized
        return
      }
      persistCloudflareAllowlistConfig()
    }
  }
  @Published var cloudflareApiToken = ""
  @Published private(set) var cloudflareTokenStored = false
  @Published private(set) var cloudflareAllowlistStatus = CloudflareAllowlistManager.shared.statusLine
  @Published private(set) var cloudflareAllowlistUpdateInProgress = false
  @Published var ocrIndexingEnabled = true {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.ocrIndexingEnabled = ocrIndexingEnabled
    }
  }
  @Published var redactionDetectorSettings = RedactionDetectorSettings.defaultValue {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.redactionDetectorSettings = redactionDetectorSettings
    }
  }
  @Published var uploadRedactionPolicy = UploadRedactionPolicy.askBeforeUpload {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.uploadRedactionPolicy = uploadRedactionPolicy
    }
  }
  @Published var smartRedactionRenderMode = SmartRedactionRenderMode.pixelate {
    didSet {
      guard !runtimeSyncInProgress else { return }
      RuntimePreferences.shared.smartRedactionRenderMode = smartRedactionRenderMode
    }
  }
  @Published private(set) var ocrProgress = OCRIndexProgress()

  @Published private(set) var profiles: [UploadProfile] = []
  @Published private(set) var activeProfile: UploadProfile?

  private let actions: MainHubActions
  private var observers: [NSObjectProtocol] = []
  private var runtimeSyncInProgress = false

  init(actions: MainHubActions) {
    self.actions = actions
    refreshProfileInfo()
    pullRuntimePreferences()
    syncNodeSelectionForCurrentRail()

    let center = NotificationCenter.default
    observers.append(
      center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
        self?.refreshProfileInfo()
      }
    )
    observers.append(
      center.addObserver(forName: .mainHubShowHistory, object: nil, queue: .main) { [weak self] _ in
        self?.showHistory()
      }
    )
    observers.append(
      center.addObserver(forName: .mainHubShowWatchFolders, object: nil, queue: .main) { [weak self] _ in
        self?.showWatchFolders()
      }
    )
    observers.append(
      center.addObserver(forName: .mainHubShowSettings, object: nil, queue: .main) { [weak self] _ in
        self?.showSettings()
      }
    )
    observers.append(
      center.addObserver(forName: .runtimePreferencesDidChange, object: nil, queue: .main) { [weak self] _ in
        self?.pullRuntimePreferences()
      }
    )
    observers.append(
      center.addObserver(forName: .ocrIndexDidChange, object: nil, queue: .main) { [weak self] _ in
        self?.ocrProgress = OCRIndexManager.shared.progress
        NotificationCenter.default.post(name: .uploadHistoryDidChange, object: nil)
      }
    )
    observers.append(
      center.addObserver(forName: .cloudflareAllowlistStatusDidChange, object: nil, queue: .main) { [weak self] _ in
        self?.cloudflareAllowlistStatus = CloudflareAllowlistManager.shared.statusLine
      }
    )
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  var currentTree: [ContextNode] {
    filteredContextTree
  }

  var filteredContextTree: [ContextNode] {
    guard let nodes = Self.contextTree[railSelection] else { return [] }
    let normalizedSearch = contextSearchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    return Self.filteredContextTree(
      nodes,
      for: normalizedSearch,
      matchesSection: railSelection.title.lowercased().contains(normalizedSearch)
    )
  }

  var currentNodeTitle: String {
    guard let selected = nodeSelection else { return railSelection.title }
    return Self.findTitle(for: selected, in: currentTree) ?? railSelection.title
  }

  var activeProfileName: String {
    activeProfile?.name ?? "No active profile"
  }

  var activeEndpoint: String {
    activeProfile?.endpoint ?? "-"
  }

  var activeBackendText: String {
    guard let backend = activeProfile?.backend else { return "-" }
    switch backend {
    case .ziplineV4: return "Zipline v4"
    case .s3Compatible: return "S3-compatible"
    }
  }

  func refreshProfileInfo() {
    profiles = Settings.shared.profiles()
    activeProfile = Settings.shared.activeProfile
    if profiles.isEmpty {
      uploaderFilterProfileId = ""
      routingImageProfileId = ""
      routingFileProfileId = ""
      routingTextProfileId = ""
      routingShortenerProfileId = ""
      return
    }
    if !profiles.contains(where: { $0.id == uploaderFilterProfileId }) {
      uploaderFilterProfileId = activeProfile?.id ?? profiles.first?.id ?? ""
    }
    if !profiles.contains(where: { $0.id == routingImageProfileId }) {
      routingImageProfileId = activeProfile?.id ?? profiles.first?.id ?? ""
    }
    if !profiles.contains(where: { $0.id == routingFileProfileId }) {
      routingFileProfileId = activeProfile?.id ?? profiles.first?.id ?? ""
    }
    if !profiles.contains(where: { $0.id == routingTextProfileId }) {
      routingTextProfileId = activeProfile?.id ?? profiles.first?.id ?? ""
    }
    if !profiles.contains(where: { $0.id == routingShortenerProfileId }) {
      routingShortenerProfileId = activeProfile?.id ?? profiles.first?.id ?? ""
    }
  }

  private func pullRuntimePreferences() {
    runtimeSyncInProgress = true
    uiPaletteId = RuntimePreferences.shared.uiPaletteId
    uiCustomPalette = RuntimePreferences.shared.uiCustomPalette
    uiRainbowMode = RuntimePreferences.shared.uiRainbowMode
    ocrIndexingEnabled = RuntimePreferences.shared.ocrIndexingEnabled
    redactionDetectorSettings = RuntimePreferences.shared.redactionDetectorSettings
    uploadRedactionPolicy = RuntimePreferences.shared.uploadRedactionPolicy
    smartRedactionRenderMode = RuntimePreferences.shared.smartRedactionRenderMode
    includeCursorOnCapture = RuntimePreferences.shared.captureShowCursor
    captureDelaySeconds = RuntimePreferences.shared.captureDelaySeconds
    captureFixedRegionEnabled = RuntimePreferences.shared.captureFixedRegionEnabled
    captureFixedRegionX = RuntimePreferences.shared.captureFixedRegionX
    captureFixedRegionY = RuntimePreferences.shared.captureFixedRegionY
    captureFixedRegionWidth = RuntimePreferences.shared.captureFixedRegionWidth
    captureFixedRegionHeight = RuntimePreferences.shared.captureFixedRegionHeight
    captureShowInfoOverlay = RuntimePreferences.shared.captureShowInfoOverlay
    captureSnapSizesText = Self.formatSnapSizes(RuntimePreferences.shared.captureSnapSizes)
    afterCaptureSaveLocalCopy = RuntimePreferences.shared.afterCaptureSaveLocalCopy
    afterCaptureCopyURL = RuntimePreferences.shared.afterCaptureCopyURL
    afterCaptureCopyImageAndURL = RuntimePreferences.shared.afterCaptureCopyImageAndURL
    afterCaptureOpenEditor = RuntimePreferences.shared.afterCaptureOpenEditor
    let configuredScreenshotsPath = RuntimePreferences.shared.captureScreenshotsFolderPath
    screenshotsFolderIsCustom = !configuredScreenshotsPath.isEmpty
    if let folderURL = try? AppSupport.resolvedScreenshotsDir() {
      screenshotsFolderPathDisplay = folderURL.path
    } else {
      screenshotsFolderPathDisplay = configuredScreenshotsPath
    }
    afterUploadCopyURL = RuntimePreferences.shared.afterUploadCopyURL
    afterUploadCopyImage = RuntimePreferences.shared.afterUploadCopyImage
    afterUploadOpenURL = RuntimePreferences.shared.afterUploadOpenURL
    let hotKeyBindings = RuntimePreferences.shared.hotKeyBindings
    hotkeyCaptureRegionUpload = hotKeyBindings.captureRegionUpload
    hotkeyCaptureRegionUploadExpiring = hotKeyBindings.captureRegionUploadExpiring
    hotkeyCaptureRegionUploadFrozen = hotKeyBindings.captureRegionUploadFrozen
    hotkeyUploadClipboard = hotKeyBindings.uploadClipboard
    let clipboardRules = RuntimePreferences.shared.clipboardRules
    uploadShareURLAfterClipboard = clipboardRules.shareURLAfterUpload
    uploadShortenURL = clipboardRules.shortenURL
    uploadClipboardURLContents = clipboardRules.uploadURLContents
    uploadClipboardAutoIndexFolder = clipboardRules.autoIndexFolder
    uploadClipboardTextContents = clipboardRules.uploadTextContents
    fileUploadUseNamePattern = RuntimePreferences.shared.fileUploadUseNamePattern
    fileUploadUseRandom16Name = RuntimePreferences.shared.fileUploadUseRandom16Name
    fileNamePattern = RuntimePreferences.shared.fileNamePattern
    fileNameAutoIncrement = RuntimePreferences.shared.fileNameAutoIncrement
    fileUploadReplaceProblematicCharacters = RuntimePreferences.shared.fileUploadReplaceProblematicCharacters
    stripImageMetadataBeforeUpload = RuntimePreferences.shared.stripImageMetadataBeforeUpload
    imageUploadFormat = RuntimePreferences.shared.imageUploadFormat
    urlRegexReplaceEnabled = RuntimePreferences.shared.urlRegexReplaceEnabled
    urlRegexPattern = RuntimePreferences.shared.urlRegexPattern
    urlRegexReplacement = RuntimePreferences.shared.urlRegexReplacement
    let routing = RuntimePreferences.shared.destinationRouting
    routingImageProfileId = routing.imageProfileId ?? activeProfile?.id ?? profiles.first?.id ?? ""
    routingFileProfileId = routing.fileProfileId ?? activeProfile?.id ?? profiles.first?.id ?? ""
    routingTextProfileId = routing.textProfileId ?? activeProfile?.id ?? profiles.first?.id ?? ""
    routingShortenerProfileId = routing.shortenerProfileId ?? activeProfile?.id ?? profiles.first?.id ?? ""
    let shortener = RuntimePreferences.shared.shortenerConfig
    shortenerProviderRawValue = shortener.provider.rawValue
    shortenerCustomTemplate = shortener.customGetTemplate
    let cloudflare = RuntimePreferences.shared.cloudflareAllowlistConfig
    cloudflareAllowlistEnabled = cloudflare.enabled
    cloudflareAccountId = cloudflare.accountId
    cloudflareListId = cloudflare.listId
    cloudflareDeviceName = cloudflare.deviceName
    cloudflareCheckIntervalMinutes = cloudflare.checkIntervalMinutes
    cloudflareTokenStored = !(CloudflareCredentialStore.getApiToken() ?? "").isEmpty
    if cloudflareTokenStored && cloudflareApiToken.isEmpty {
      cloudflareApiToken = ""
    }
    cloudflareAllowlistStatus = CloudflareAllowlistManager.shared.statusLine
    watchFoldersEnabled = RuntimePreferences.shared.watchFoldersEnabled
    watchFolderRules = RuntimePreferences.shared.watchFolderRules
    uploaderFilters = RuntimePreferences.shared.uploaderFilters

    if let selectedUploaderFilterId,
       let selected = uploaderFilters.first(where: { $0.id == selectedUploaderFilterId }) {
      uploaderFilterExtensionsInput = selected.extensions.joined(separator: ", ")
      uploaderFilterProfileId = selected.profileId
    } else if let first = uploaderFilters.first {
      selectedUploaderFilterId = first.id
      uploaderFilterExtensionsInput = first.extensions.joined(separator: ", ")
      uploaderFilterProfileId = first.profileId
    } else if uploaderFilterProfileId.isEmpty {
      uploaderFilterProfileId = activeProfile?.id ?? profiles.first?.id ?? ""
    }

    defaultFileNamePattern = fileNamePattern
    if selectedWatchFolderRuleId == nil, let first = watchFolderRules.first {
      selectWatchFolderRule(first.id)
    }
    runtimeSyncInProgress = false
  }

  func redactionDetectorEnabled(_ type: RedactionDetectorType) -> Bool {
    redactionDetectorSettings.isEnabled(type)
  }

  func setRedactionDetector(_ type: RedactionDetectorType, enabled: Bool) {
    var updated = redactionDetectorSettings
    updated.setEnabled(type, enabled)
    redactionDetectorSettings = updated
  }

  func resetRedactionDetectorDefaults() {
    redactionDetectorSettings = .defaultValue
  }

  private func persistHotKeyBindings() {
    let normalized = HotKeyBindings(
      captureRegionUpload: hotkeyCaptureRegionUpload.normalized,
      captureRegionUploadExpiring: hotkeyCaptureRegionUploadExpiring.normalized,
      captureRegionUploadFrozen: hotkeyCaptureRegionUploadFrozen.normalized,
      uploadClipboard: hotkeyUploadClipboard.normalized
    )
    runtimeSyncInProgress = true
    hotkeyCaptureRegionUpload = normalized.captureRegionUpload
    hotkeyCaptureRegionUploadExpiring = normalized.captureRegionUploadExpiring
    hotkeyCaptureRegionUploadFrozen = normalized.captureRegionUploadFrozen
    hotkeyUploadClipboard = normalized.uploadClipboard
    runtimeSyncInProgress = false
    RuntimePreferences.shared.hotKeyBindings = normalized
  }

  var effectivePalette: UIPalette {
    UIPaletteCatalog.effectivePalette(selected: uiPaletteId, custom: uiCustomPalette)
  }

  func syncNodeSelectionForCurrentRail() {
    if let nodeSelection, Self.contains(nodeSelection, in: filteredContextTree) {
      return
    }
    nodeSelection = Self.firstLeaf(in: filteredContextTree)
  }

  func showHistory() {
    railSelection = .history
    nodeSelection = .historyUploads
  }

  func showWatchFolders() {
    railSelection = .upload
    nodeSelection = .uploadWatchFolders
  }

  func showSettings() {
    railSelection = .settings
    nodeSelection = .settingsApplication
  }

  func runCaptureRegion() { actions.captureRegionUpload() }
  func runCaptureWindow() { actions.captureWindowUpload() }
  func runCaptureFullscreen() { actions.captureFullscreenUpload() }
  func runCaptureTopTaskbar() { actions.captureTopTaskbarUpload() }
  func runCaptureScreenRecording() { actions.recordScreenUpload() }
  func runCaptureRegionExpiring() { actions.captureRegionExpiringUpload() }

  func runUploadClipboard() { actions.uploadClipboardImage() }
  func runUploadImageFile() { actions.uploadImageFile() }
  func runUploadExpiringFile() { actions.uploadExpiringFile() }
  func runUploadFromURL() { actions.uploadFromURL() }
  func runUploadText() { actions.uploadText() }
  func runUploadFolder() { actions.uploadFolder() }
  func runShortenURL() { actions.shortenURL() }
  func openWatchFolders() { actions.openWatchFolders() }

  func openPreferences() {
    refreshProfileInfo()
    actions.openPreferences()
  }

  func openScreenshotsFolder() { actions.openScreenshotsFolder() }
  func chooseScreenshotsFolder() { actions.chooseScreenshotsFolder() }
  func resetScreenshotsFolder() { actions.resetScreenshotsFolder() }
  func openLatestEditor() { actions.openLatestInEditor() }

  func openHistoryWorkspace() {
    actions.openHistorySection()
    showHistory()
  }

  func indexExistingOCR() {
    OCRIndexManager.shared.indexExistingInBackground()
  }

  func rebuildOCRIndex() {
    OCRIndexManager.shared.rebuildInBackground()
  }

  func clearOCRIndex() {
    OCRIndexManager.shared.clearIndex()
  }

  func pauseOCRIndexing() {
    OCRIndexManager.shared.pause()
  }

  func resumeOCRIndexing() {
    OCRIndexManager.shared.resume()
  }

  func cancelOCRIndexing() {
    OCRIndexManager.shared.cancel()
  }

  func saveCloudflareApiToken() {
    do {
      try CloudflareCredentialStore.setApiToken(cloudflareApiToken)
      cloudflareApiToken = ""
      cloudflareTokenStored = !(CloudflareCredentialStore.getApiToken() ?? "").isEmpty
      cloudflareAllowlistStatus = cloudflareTokenStored ? "Cloudflare API token saved in Keychain." : "Cloudflare API token cleared."
      CloudflareAllowlistManager.shared.applyCurrentPreferences()
    } catch {
      cloudflareAllowlistStatus = "Could not save Cloudflare token: \(error.localizedDescription)"
    }
  }

  func clearCloudflareApiToken() {
    CloudflareCredentialStore.clearApiToken()
    cloudflareApiToken = ""
    cloudflareTokenStored = false
    cloudflareAllowlistStatus = "Cloudflare API token cleared."
    CloudflareAllowlistManager.shared.applyCurrentPreferences()
  }

  func runCloudflareAllowlistUpdate() {
    cloudflareAllowlistUpdateInProgress = true
    cloudflareAllowlistStatus = "Cloudflare allowlist update running..."
    Task { @MainActor in
      let result = await CloudflareAllowlistManager.shared.updateNow()
      switch result {
      case .success(let update):
        cloudflareAllowlistStatus = update.message
      case .failure(let error):
        cloudflareAllowlistStatus = "Cloudflare allowlist update failed: \(error.localizedDescription)"
      }
      cloudflareAllowlistUpdateInProgress = false
    }
  }

  var ocrProgressLine: String {
    let p = ocrProgress
    let base: String
    switch p.phase {
    case .idle:
      base = "Idle"
    case .indexing:
      base = "Indexing \(p.completed + p.skipped + p.failed)/\(p.total)"
    case .paused:
      base = "Paused \(p.completed + p.skipped + p.failed)/\(p.total)"
    case .cancelled:
      base = "Cancelled"
    case .completed:
      base = "Complete"
    }

    var parts = [base, "indexed \(p.completed)", "skipped \(p.skipped)", "failed \(p.failed)"]
    if let eta = p.estimatedRemainingSeconds {
      parts.append("about \(shortDuration(eta)) left")
    }
    if let current = p.currentFilename {
      parts.append(current)
    } else if let message = p.message, !message.isEmpty {
      parts.append(message)
    }
    return parts.joined(separator: "  •  ")
  }

  var fileNamingPreview: String {
    let sampleName = "example.\(imageUploadFormat.filenameExtension)"
    let sampleBase = RuntimePreferences.shared.generateUploadFilenameBase(originalFilename: sampleName)
    return "\(sampleBase).\(imageUploadFormat.filenameExtension)"
  }

  func uploaderFilterProfileName(_ profileId: String) -> String {
    profiles.first(where: { $0.id == profileId })?.name ?? "Unknown destination"
  }

  func selectUploaderFilter(_ filterId: String?) {
    selectedUploaderFilterId = filterId
    guard let filterId,
          let rule = uploaderFilters.first(where: { $0.id == filterId }) else {
      uploaderFilterExtensionsInput = ""
      if uploaderFilterProfileId.isEmpty {
        uploaderFilterProfileId = activeProfile?.id ?? profiles.first?.id ?? ""
      }
      return
    }
    uploaderFilterExtensionsInput = rule.extensions.joined(separator: ", ")
    uploaderFilterProfileId = rule.profileId
  }

  func addUploaderFilter() {
    let extensions = Self.parseExtensionsInput(uploaderFilterExtensionsInput)
    guard !extensions.isEmpty else { return }
    let profileId = resolvedUploaderFilterProfileId()
    let newRule = UploaderFilterRule(extensions: extensions, profileId: profileId)
    uploaderFilters.append(newRule)
    RuntimePreferences.shared.uploaderFilters = uploaderFilters
    selectUploaderFilter(newRule.id)
  }

  func updateSelectedUploaderFilter() {
    guard let selectedUploaderFilterId,
          let index = uploaderFilters.firstIndex(where: { $0.id == selectedUploaderFilterId }) else {
      addUploaderFilter()
      return
    }
    let extensions = Self.parseExtensionsInput(uploaderFilterExtensionsInput)
    guard !extensions.isEmpty else { return }
    uploaderFilters[index] = UploaderFilterRule(
      id: selectedUploaderFilterId,
      extensions: extensions,
      profileId: resolvedUploaderFilterProfileId()
    )
    RuntimePreferences.shared.uploaderFilters = uploaderFilters
    selectUploaderFilter(selectedUploaderFilterId)
  }

  func removeSelectedUploaderFilter() {
    guard let selectedUploaderFilterId else { return }
    uploaderFilters.removeAll(where: { $0.id == selectedUploaderFilterId })
    RuntimePreferences.shared.uploaderFilters = uploaderFilters
    if let first = uploaderFilters.first {
      selectUploaderFilter(first.id)
    } else {
      selectUploaderFilter(nil)
    }
  }

  func setRoutingProfile(_ profileId: String, for kind: DestinationKind) {
    switch kind {
    case .image:
      routingImageProfileId = profileId
    case .file:
      routingFileProfileId = profileId
    case .text:
      routingTextProfileId = profileId
    case .shortener:
      routingShortenerProfileId = profileId
    }
    persistDestinationRouting()
  }

  func updateShortenerProvider(_ raw: String) {
    shortenerProviderRawValue = raw
    persistShortenerConfig()
  }

  func updateShortenerTemplate(_ value: String) {
    shortenerCustomTemplate = value
    persistShortenerConfig()
  }

  func selectWatchFolderRule(_ ruleId: String?) {
    selectedWatchFolderRuleId = ruleId
    guard let ruleId, let rule = watchFolderRules.first(where: { $0.id == ruleId }) else {
      watchFolderPathInput = ""
      watchFolderFilterInput = "*"
      watchFolderIncludeSubdirectories = true
      watchFolderModeRawValue = WatchFolderMode.auto.rawValue
      watchFolderExpirySeconds = 0
      return
    }
    watchFolderPathInput = rule.path
    watchFolderFilterInput = rule.fileFilter
    watchFolderIncludeSubdirectories = rule.includeSubdirectories
    watchFolderModeRawValue = rule.mode.rawValue
    watchFolderExpirySeconds = rule.expirySeconds ?? 0
  }

  func addWatchFolderRule() {
    let path = watchFolderPathInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else { return }
    let mode = WatchFolderMode(rawValue: watchFolderModeRawValue) ?? .auto
    let expiry = watchFolderExpirySeconds > 0 ? watchFolderExpirySeconds : nil

    let rule = WatchFolderRule(
      path: path,
      includeSubdirectories: watchFolderIncludeSubdirectories,
      fileFilter: watchFolderFilterInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "*" : watchFolderFilterInput,
      mode: mode,
      expirySeconds: expiry,
      enabled: true
    )

    watchFolderRules.append(rule)
    RuntimePreferences.shared.watchFolderRules = watchFolderRules
    selectWatchFolderRule(rule.id)
    WatchFolderManager.shared.applyCurrentPreferences()
  }

  func updateSelectedWatchFolderRule() {
    guard let selectedWatchFolderRuleId,
          let idx = watchFolderRules.firstIndex(where: { $0.id == selectedWatchFolderRuleId }) else {
      addWatchFolderRule()
      return
    }

    let path = watchFolderPathInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else { return }
    let mode = WatchFolderMode(rawValue: watchFolderModeRawValue) ?? .auto
    let expiry = watchFolderExpirySeconds > 0 ? watchFolderExpirySeconds : nil

    watchFolderRules[idx] = WatchFolderRule(
      id: selectedWatchFolderRuleId,
      path: path,
      includeSubdirectories: watchFolderIncludeSubdirectories,
      fileFilter: watchFolderFilterInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "*" : watchFolderFilterInput,
      mode: mode,
      expirySeconds: expiry,
      enabled: watchFolderRules[idx].enabled
    )
    RuntimePreferences.shared.watchFolderRules = watchFolderRules
    selectWatchFolderRule(selectedWatchFolderRuleId)
    WatchFolderManager.shared.applyCurrentPreferences()
  }

  func removeSelectedWatchFolderRule() {
    guard let selectedWatchFolderRuleId else { return }
    watchFolderRules.removeAll(where: { $0.id == selectedWatchFolderRuleId })
    RuntimePreferences.shared.watchFolderRules = watchFolderRules
    if let first = watchFolderRules.first {
      selectWatchFolderRule(first.id)
    } else {
      selectWatchFolderRule(nil)
    }
    WatchFolderManager.shared.applyCurrentPreferences()
  }

  func toggleWatchFolderRuleEnabled(_ ruleId: String, enabled: Bool) {
    guard let idx = watchFolderRules.firstIndex(where: { $0.id == ruleId }) else { return }
    watchFolderRules[idx].enabled = enabled
    RuntimePreferences.shared.watchFolderRules = watchFolderRules
    WatchFolderManager.shared.applyCurrentPreferences()
  }

  func setWatchFoldersEnabled(_ enabled: Bool) {
    watchFoldersEnabled = enabled
    RuntimePreferences.shared.watchFoldersEnabled = enabled
    WatchFolderManager.shared.applyCurrentPreferences()
  }

  private func persistDestinationRouting() {
    guard !runtimeSyncInProgress else { return }
    var routing = RuntimePreferences.shared.destinationRouting
    routing.imageProfileId = resolvedProfileIdOrNil(routingImageProfileId)
    routing.fileProfileId = resolvedProfileIdOrNil(routingFileProfileId)
    routing.textProfileId = resolvedProfileIdOrNil(routingTextProfileId)
    routing.shortenerProfileId = resolvedProfileIdOrNil(routingShortenerProfileId)
    RuntimePreferences.shared.destinationRouting = routing
  }

  private func persistShortenerConfig() {
    guard !runtimeSyncInProgress else { return }
    let provider = URLShortenerProvider(rawValue: shortenerProviderRawValue) ?? .tinyURL
    let template = shortenerCustomTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
    RuntimePreferences.shared.shortenerConfig = URLShortenerConfig(provider: provider, customGetTemplate: template)
  }

  private func persistCloudflareAllowlistConfig() {
    guard !runtimeSyncInProgress else { return }
    RuntimePreferences.shared.cloudflareAllowlistConfig = CloudflareAllowlistConfig(
      enabled: cloudflareAllowlistEnabled,
      accountId: cloudflareAccountId,
      listId: cloudflareListId,
      deviceName: cloudflareDeviceName,
      checkIntervalMinutes: cloudflareCheckIntervalMinutes
    )
    CloudflareAllowlistManager.shared.applyCurrentPreferences()
  }

  private static func firstLeaf(in nodes: [ContextNode]) -> ContextNodeID? {
    for node in nodes {
      if node.children.isEmpty {
        return node.id
      }
      if let child = firstLeaf(in: node.children) {
        return child
      }
    }
    return nil
  }

  private static func contains(_ id: ContextNodeID, in nodes: [ContextNode]) -> Bool {
    for node in nodes {
      if node.id == id { return true }
      if contains(id, in: node.children) { return true }
    }
    return false
  }

  private static func filteredContextTree(_ nodes: [ContextNode], for query: String, matchesSection: Bool) -> [ContextNode] {
    let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.isEmpty || matchesSection {
      return nodes
    }
    return nodes.compactMap { node in
      let visibleChildren = filteredContextTree(node.children, for: normalized, matchesSection: false)
      if node.title.lowercased().contains(normalized) {
        return node
      }
      if !visibleChildren.isEmpty {
        return ContextNode(id: node.id, title: node.title, symbol: node.symbol, children: visibleChildren)
      }
      return nil
    }
  }

  private static func findTitle(for id: ContextNodeID, in nodes: [ContextNode]) -> String? {
    for node in nodes {
      if node.id == id { return node.title }
      if let title = findTitle(for: id, in: node.children) {
        return title
      }
    }
    return nil
  }

  private func resolvedUploaderFilterProfileId() -> String {
    if profiles.contains(where: { $0.id == uploaderFilterProfileId }) {
      return uploaderFilterProfileId
    }
    return activeProfile?.id ?? profiles.first?.id ?? ""
  }

  private func resolvedProfileIdOrNil(_ id: String) -> String? {
    guard !id.isEmpty else { return nil }
    return profiles.contains(where: { $0.id == id }) ? id : nil
  }

  private func shortDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
  }

  private static func parseExtensionsInput(_ raw: String) -> [String] {
    let separators = CharacterSet(charactersIn: ",; \n\t")
    let parts = raw.components(separatedBy: separators)
    return UploaderFilterRule.normalizedExtensions(parts)
  }

  private static func parseSnapSizes(_ raw: String) -> [CGSize] {
    let separators = CharacterSet(charactersIn: ",;\n")
    let parts = raw.components(separatedBy: separators)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    var values: [CGSize] = []
    var seen = Set<String>()

    for part in parts {
      let pieces = part.lowercased().split(separator: "x", maxSplits: 1).map(String.init)
      guard pieces.count == 2,
            let width = Int(pieces[0].trimmingCharacters(in: .whitespaces)),
            let height = Int(pieces[1].trimmingCharacters(in: .whitespaces)),
            width > 0,
            height > 0 else {
        continue
      }
      let key = "\(width)x\(height)"
      if seen.contains(key) { continue }
      seen.insert(key)
      values.append(CGSize(width: width, height: height))
    }

    return values
  }

  private static func formatSnapSizes(_ values: [CGSize]) -> String {
    values
      .map { "\(Int($0.width))x\(Int($0.height))" }
      .joined(separator: ", ")
  }

  private static let contextTree: [RailSection: [ContextNode]] = [
    .capture: [
      ContextNode(
        id: .captureModesGroup,
        title: "Capture modes",
        symbol: "camera.aperture",
        children: [
          ContextNode(id: .captureRegion, title: "Region", symbol: "selection.pin.in.out"),
          ContextNode(id: .captureWindow, title: "Window", symbol: "macwindow"),
          ContextNode(id: .captureFullscreen, title: "Fullscreen", symbol: "rectangle.inset.filled"),
          ContextNode(id: .captureTopTaskbar, title: "Top taskbar", symbol: "rectangle"),
          ContextNode(id: .captureScreenRecording, title: "Screen recording (30s max)", symbol: "record.circle"),
          ContextNode(id: .captureExpiringRegion, title: "Expiring region upload", symbol: "timer")
        ]
      ),
      ContextNode(
        id: .captureOptionsGroup,
        title: "Capture options",
        symbol: "slider.horizontal.3",
        children: [
          ContextNode(id: .captureCursorDelay, title: "Cursor and delay", symbol: "cursorarrow.click"),
          ContextNode(id: .captureRegionFixedSize, title: "Region fixed size", symbol: "viewfinder")
        ]
      )
    ],
    .upload: [
      ContextNode(
        id: .uploadQuickGroup,
        title: "Manual uploads",
        symbol: "arrow.up.doc",
        children: [
          ContextNode(id: .uploadClipboardImage, title: "Clipboard image", symbol: "clipboard"),
          ContextNode(id: .uploadImageFile, title: "Image file", symbol: "photo"),
          ContextNode(id: .uploadExpiringFile, title: "Expiring file link", symbol: "clock.badge.exclamationmark"),
          ContextNode(id: .uploadFromURL, title: "Upload from URL", symbol: "link"),
          ContextNode(id: .uploadText, title: "Upload text", symbol: "text.alignleft"),
          ContextNode(id: .uploadFolder, title: "Upload folder", symbol: "folder.badge.plus")
        ]
      ),
      ContextNode(
        id: .uploadSettingsGroup,
        title: "Upload settings",
        symbol: "slider.horizontal.3",
        children: [
          ContextNode(id: .uploadClipboardRules, title: "Clipboard rules", symbol: "list.bullet.clipboard"),
          ContextNode(id: .uploadURLShortener, title: "URL shortener", symbol: "link.badge.plus"),
          ContextNode(id: .uploadWatchFolders, title: "Watch folders", symbol: "folder.badge.gear"),
          ContextNode(id: .uploadFileNaming, title: "File naming and URL regex", symbol: "character.textbox"),
          ContextNode(id: .uploadUploaderFilters, title: "Uploader filters", symbol: "line.3.horizontal.decrease.circle")
        ]
      )
    ],
    .workflows: [
      ContextNode(
        id: .workflowsQuickGroup,
        title: "Quick workflows",
        symbol: "list.bullet.rectangle.portrait",
        children: [
          ContextNode(id: .workflowRegionToUrl, title: "Region -> Upload -> Copy URL", symbol: "arrow.triangle.swap"),
          ContextNode(id: .workflowClipboardToUrl, title: "Clipboard -> Upload -> Copy URL", symbol: "arrow.triangle.branch")
        ]
      )
    ],
    .tools: [
      ContextNode(
        id: .toolsGroups,
        title: "Productivity tools",
        symbol: "hammer",
        children: [
          ContextNode(id: .toolsHotkeys, title: "Hotkeys", symbol: "keyboard"),
          ContextNode(id: .toolsProductivity, title: "Folders and history", symbol: "folder"),
          ContextNode(id: .toolsEditor, title: "Image editor entry", symbol: "pencil.tip")
        ]
      )
    ],
    .afterCapture: [
      ContextNode(
        id: .afterCaptureGroup,
        title: "After capture behaviors",
        symbol: "camera.filters",
        children: [
          ContextNode(id: .afterCaptureBehavior, title: "Default behavior set", symbol: "checkmark.square")
        ]
      )
    ],
    .afterUpload: [
      ContextNode(
        id: .afterUploadGroup,
        title: "After upload behaviors",
        symbol: "checkmark.seal",
        children: [
          ContextNode(id: .afterUploadBehavior, title: "Default behavior set", symbol: "checkmark.square")
        ]
      )
    ],
    .destinations: [
      ContextNode(
        id: .destinationGroup,
        title: "Add and edit endpoints",
        symbol: "network",
        children: [
          ContextNode(id: .destinationsActiveProfile, title: "Active profile", symbol: "person.crop.square"),
          ContextNode(id: .destinationsEndpointBackend, title: "Endpoint and backend", symbol: "server.rack"),
          ContextNode(id: .destinationsBehavior, title: "Upload behavior", symbol: "slider.horizontal.3")
        ]
      )
    ],
    .settings: [
      ContextNode(
        id: .settingsGroup,
        title: "Main settings",
        symbol: "gearshape",
        children: [
          ContextNode(id: .settingsApplication, title: "Application-like", symbol: "app"),
          ContextNode(id: .settingsTask, title: "Task-like", symbol: "gearshape.2"),
          ContextNode(id: .settingsCloudflareAllowlist, title: "Cloudflare allowlist", symbol: "checkmark.shield"),
          ContextNode(id: .settingsAdvanced, title: "Advanced", symbol: "wrench.and.screwdriver")
        ]
      )
    ],
    .history: [
      ContextNode(
        id: .historyGroup,
        title: "Upload history",
        symbol: "clock.arrow.circlepath",
        children: [
          ContextNode(id: .historyUploads, title: "Uploads table and preview", symbol: "tablecells")
        ]
      )
    ]
  ]
}

extension UploadRecord: Identifiable {}

enum UploadHistoryStatusFilter: String, CaseIterable, Identifiable {
  case all = "All"
  case uploaded = "Uploaded"
  case failed = "Failed"
  case uploading = "Uploading"
  case pending = "Pending"

  var id: String { rawValue }

  var title: String {
    rawValue
  }

  func matches(_ status: UploadStatus) -> Bool {
    switch self {
    case .all:
      return true
    case .uploaded:
      return status == .uploaded
    case .failed:
      return status == .failed
    case .uploading:
      return status == .uploading
    case .pending:
      return status == .pending
    }
  }
}

final class UploadHistoryViewModel: ObservableObject {
  @Published private(set) var records: [UploadRecord] = []
  @Published var selectedId: String?
  @Published var historySearchText = "" {
    didSet { clampSelectionToFilteredRecords() }
  }
  @Published var historyStatusFilter: UploadHistoryStatusFilter = .all {
    didSet { clampSelectionToFilteredRecords() }
  }

  private var observer: NSObjectProtocol?

  init() {
    observer = NotificationCenter.default.addObserver(
      forName: .uploadHistoryDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.reload()
    }
    reload()
  }

  deinit {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  var selectedRecord: UploadRecord? {
    guard let selectedId else { return nil }
    return filteredRecords.first(where: { $0.id == selectedId })
  }

  var filteredRecords: [UploadRecord] {
    let normalized = historySearchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    return records.filter { record in
      guard historyStatusFilter.matches(record.status) else { return false }
      if normalized.isEmpty {
        return true
      }
      return Self.record(
        record,
        matchesSearch: normalized,
        profileName: profileName(for: record),
        filename: filename(for: record),
        statusText: statusText(record.status)
      )
    }
    .sorted(by: Self.sortNewestFirst)
  }

  var canCopyURL: Bool { selectedRecord?.url != nil }
  var canOpenURL: Bool { selectedRecord?.url != nil }
  var canShortenURL: Bool { selectedRecord?.url != nil }
  var canShowInFinder: Bool { selectedRecord != nil }

  var canReupload: Bool {
    guard let record = selectedRecord else { return false }
    return !record.localFilePath.isEmpty
  }

  var canEdit: Bool {
    guard let record = selectedRecord else { return false }
    return (record.kind != .file) && !record.localFilePath.isEmpty
  }

  var canDeleteManagedCopy: Bool {
    guard let record = selectedRecord else { return false }
    return (record.managedLocalCopy == true) && !record.localFilePath.isEmpty
  }

  func reload() {
    records = Self.sortNewestFirstRecords(UploadHistoryStore.shared.snapshot())
    clampSelectionToFilteredRecords()
  }

  func statusText(_ status: UploadStatus) -> String {
    switch status {
    case .pending: return "Pending"
    case .uploading: return "Uploading"
    case .uploaded: return "Uploaded"
    case .failed: return "Failed"
    }
  }

  func statusColor(_ status: UploadStatus) -> NSColor {
    switch status {
    case .pending:
      return NSColor(calibratedWhite: 0.46, alpha: 1.0)
    case .uploading:
      return NSColor(calibratedRed: 0.15, green: 0.47, blue: 0.90, alpha: 1.0)
    case .uploaded:
      return NSColor(calibratedRed: 0.19, green: 0.62, blue: 0.31, alpha: 1.0)
    case .failed:
      return NSColor(calibratedRed: 0.78, green: 0.26, blue: 0.24, alpha: 1.0)
    }
  }

  func profileName(for record: UploadRecord) -> String {
    Settings.shared.profiles().first(where: { $0.id == record.profileId })?.name ?? "Upload"
  }

  func filename(for record: UploadRecord) -> String {
    if record.localFilePath.isEmpty { return "Upload" }
    return URL(fileURLWithPath: record.localFilePath).lastPathComponent
  }

  func statusColumn(for record: UploadRecord) -> String {
    let kindText = record.kind == .file ? "File" : "Image"
    let ocr = ocrShortStatus(for: record)
    let secondary = secondaryShortStatus(for: record)
    let suffixes = [ocr, secondary].filter { !$0.isEmpty }
    if suffixes.isEmpty {
      return "\(statusText(record.status)) • \(kindText)"
    }
    return "\(statusText(record.status)) • \(kindText) • \(suffixes.joined(separator: " • "))"
  }

  func progressColumn(for record: UploadRecord) -> String {
    switch record.status {
    case .uploaded: return "100%"
    case .uploading: return "..."
    case .pending: return "0%"
    case .failed: return "Err"
    }
  }

  func speedColumn(for record: UploadRecord) -> String {
    record.status == .uploading ? "..." : "-"
  }

  func elapsedColumn(for record: UploadRecord) -> String {
    if record.status == .uploading {
      return formatDuration(Date().timeIntervalSince(record.createdAt))
    }
    return "-"
  }

  func remainingColumn(for record: UploadRecord) -> String {
    record.status == .uploading ? "..." : "-"
  }

  func urlColumn(for record: UploadRecord) -> String {
    if let error = record.error, !error.isEmpty { return "Error" }
    if let shortened = record.shortenedURL, !shortened.isEmpty { return shortened }
    return record.url ?? "-"
  }

  func infoLine(for record: UploadRecord) -> String {
    let profile = profileName(for: record)
    let dateStr = record.createdAt.formatted(date: .abbreviated, time: .shortened)
    var line = "\(profile)  •  \(statusText(record.status))  •  \(dateStr)"
    if let exp = record.expiresAt {
      line += "  •  Expires: \(exp.formatted(date: .abbreviated, time: .shortened))"
    }
    if let secondaryLine = secondaryStatusLine(for: record) {
      line += "  •  \(secondaryLine)"
    }
    return line
  }

  private func secondaryStatusLine(for record: UploadRecord) -> String? {
    guard let status = record.secondaryUploadStatus else { return nil }
    switch status {
    case .pending:
      return "S3 mirror: pending"
    case .uploaded:
      if let date = record.secondaryCompletedAt {
        return "S3 mirror: uploaded \(date.formatted(date: .abbreviated, time: .shortened))"
      }
      return "S3 mirror: uploaded"
    case .failed:
      return "S3 mirror: failed\(record.secondaryError.map { "  •  \($0)" } ?? "")"
    case .skipped:
      return "S3 mirror: skipped"
    }
  }

  func ocrStatusLine(for record: UploadRecord) -> String {
    guard record.isImageRecord else { return "OCR: not an image upload" }
    guard let status = record.ocrStatus else { return "OCR: not indexed yet" }
    switch status {
    case .disabled:
      return "OCR: disabled"
    case .pending:
      return "OCR: pending"
    case .indexed:
      let count = record.ocrText?.split(whereSeparator: { $0.isWhitespace }).count ?? 0
      if let date = record.ocrIndexedAt {
        return "OCR: indexed \(count) word(s)  •  \(date.formatted(date: .abbreviated, time: .shortened))"
      }
      return "OCR: indexed \(count) word(s)"
    case .failed:
      return "OCR: failed\(record.ocrError.map { "  •  \($0)" } ?? "")"
    case .missingFile:
      return "OCR: local image missing"
    case .skipped:
      return "OCR: skipped"
    }
  }

  func ocrMatchLine(for record: UploadRecord) -> String? {
    let query = historySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty,
          let snippet = OCRIndexManager.snippet(for: record.ocrText, query: query) else {
      return nil
    }
    return "OCR match: \(snippet)"
  }

  func urlLine(for record: UploadRecord) -> String {
    if let error = record.error, !error.isEmpty { return error }
    if let shortened = record.shortenedURL, !shortened.isEmpty {
      return "\(record.url ?? "") -> \(shortened)"
    }
    var line = record.url ?? ""
    if let secondaryURL = record.secondaryURL, !secondaryURL.isEmpty {
      line += line.isEmpty ? "S3 mirror: \(secondaryURL)" : "\nS3 mirror: \(secondaryURL)"
    } else if let secondaryError = record.secondaryError, !secondaryError.isEmpty {
      line += line.isEmpty ? "S3 mirror failed: \(secondaryError)" : "\nS3 mirror failed: \(secondaryError)"
    }
    return line
  }

  private func ocrShortStatus(for record: UploadRecord) -> String {
    guard record.isImageRecord, let status = record.ocrStatus else { return "" }
    switch status {
    case .disabled: return "OCR off"
    case .pending: return "OCR pending"
    case .indexed: return "OCR"
    case .failed: return "OCR failed"
    case .missingFile: return "OCR missing"
    case .skipped: return "OCR skipped"
    }
  }

  private func secondaryShortStatus(for record: UploadRecord) -> String {
    guard let status = record.secondaryUploadStatus else { return "" }
    switch status {
    case .pending: return "S3 mirror pending"
    case .uploaded: return "S3 mirror"
    case .failed: return "S3 mirror failed"
    case .skipped: return "S3 mirror skipped"
    }
  }

  func previewImage(for record: UploadRecord) -> NSImage? {
    guard !record.localFilePath.isEmpty else { return nil }
    if let image = NSImage(contentsOfFile: record.localFilePath) {
      return image
    }
    return NSWorkspace.shared.icon(forFile: record.localFilePath)
  }

  func copySelectedURL() {
    guard let id = selectedRecord?.id else { return }
    UploadService.shared.copyUrlForRecord(id)
  }

  func openSelectedURL() {
    guard let id = selectedRecord?.id else { return }
    UploadService.shared.openUrlForRecord(id)
  }

  func shortenSelectedURL() {
    guard let id = selectedRecord?.id else { return }
    UploadService.shared.shortenURLForRecord(id)
  }

  func showSelectedInFinder() {
    guard let id = selectedRecord?.id else { return }
    UploadService.shared.showInFinder(id)
  }

  func reuploadSelected() {
    guard let id = selectedRecord?.id else { return }
    UploadService.shared.reupload(recordId: id)
  }

  func editSelected() {
    guard let id = selectedRecord?.id else { return }
    EditorCoordinator.shared.openEditor(forRecordId: id)
  }

  func deleteSelectedManagedCopy() {
    guard let id = selectedRecord?.id else { return }
    UploadService.shared.deleteLocalCopy(id)
  }

  private func formatDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
  }

  private func clampSelectionToFilteredRecords() {
    let visibleRecords = filteredRecords
    if let selectedId, visibleRecords.contains(where: { $0.id == selectedId }) {
      return
    }
    selectedId = visibleRecords.first?.id
  }

  private static func sortNewestFirst(_ lhs: UploadRecord, _ rhs: UploadRecord) -> Bool {
    if lhs.createdAt != rhs.createdAt {
      return lhs.createdAt > rhs.createdAt
    }
    return lhs.id > rhs.id
  }

  private static func sortNewestFirstRecords(_ records: [UploadRecord]) -> [UploadRecord] {
    records.sorted(by: sortNewestFirst)
  }

  static func record(
    _ record: UploadRecord,
    matchesSearch query: String,
    profileName: String,
    filename: String,
    statusText: String
  ) -> Bool {
    let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return true }
    let searchableText = [
      profileName,
      filename,
      statusText,
      record.url ?? "",
      record.shortenedURL ?? "",
      record.error ?? "",
      record.secondaryURL ?? "",
      record.secondaryError ?? "",
      record.ocrText ?? "",
    ]
    .joined(separator: " ")
    .lowercased()
    return searchableText.contains(normalized)
  }
}
