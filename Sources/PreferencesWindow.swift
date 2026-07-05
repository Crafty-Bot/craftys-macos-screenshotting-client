import AppKit
import Foundation
import UniformTypeIdentifiers

final class PreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  private let backendPopup = NSPopUpButton()

  private let nameField = NSTextField(string: "")
  private let endpointField = NSTextField(string: "")
  private let apiKeyField = NSSecureTextField(string: "")
  private let pasteApiKeyButton = NSButton()
  private let activeCheckbox = NSButton(checkboxWithTitle: "Make active", target: nil, action: nil)
  private let secondaryS3Label = NSTextField(labelWithString: "Secondary S3 copy")
  private let secondaryS3Popup = NSPopUpButton()

  private let s3AccessKeyIdField = NSTextField(string: "")
  private let s3SecretAccessKeyField = NSSecureTextField(string: "")
  private let s3SessionTokenField = NSSecureTextField(string: "")
  private let s3RegionField = NSTextField(string: "")
  private let s3BucketField = NSTextField(string: "")
  private let s3KeyPrefixField = NSTextField(string: "")
  private let s3PublicBaseURLField = NSTextField(string: "")
  private let s3DefaultGetExpiryField = NSTextField(string: "3600")
  private let s3ForcePathStyleCheckbox = NSButton(checkboxWithTitle: "Force path-style bucket URLs", target: nil, action: nil)
  private let s3UseSignedGetCheckbox = NSButton(checkboxWithTitle: "Use signed GET URL by default", target: nil, action: nil)

  private let addButton = NSButton()
  private let removeButton = NSButton()
  private let importButton = NSButton()
  private let exportButton = NSButton()
  private let exportSelectedButton = NSButton()
  private let probeButton = NSButton(title: "Validate", target: nil, action: nil)
  private let saveButton = NSButton(title: "Save", target: nil, action: nil)

  private let endpointLabel = NSTextField(labelWithString: "Upload endpoint")
  private let tokenLabel = NSTextField(labelWithString: "API key / token")
  private let s3AccessLabel = NSTextField(labelWithString: "Access key ID")
  private let s3SecretLabel = NSTextField(labelWithString: "Secret access key")
  private let s3SessionLabel = NSTextField(labelWithString: "Session token")
  private let s3RegionLabel = NSTextField(labelWithString: "Region")
  private let s3BucketLabel = NSTextField(labelWithString: "Bucket")
  private let s3PrefixLabel = NSTextField(labelWithString: "Key prefix")
  private let s3PublicBaseLabel = NSTextField(labelWithString: "Public base URL")
  private let s3DefaultExpiryLabel = NSTextField(labelWithString: "Default GET expiry (s)")

  private var apiViews: [NSView] = []
  private var s3Views: [NSView] = []
  private var secondaryS3Views: [NSView] = []

  private var profiles: [UploadProfile] = []
  private var selectedId: String? = nil

  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Add and edit endpoints"
    // Allow resizing larger while preventing the fixed-frame layout from collapsing.
    window.minSize = NSSize(width: 920, height: 620)
    super.init(window: window)
    window.center()

    let content = NSView(frame: window.contentView?.bounds ?? .zero)
    content.autoresizingMask = [.width, .height]
    window.contentView = content

    let sidebarWidth: CGFloat = 250
    let left = NSView(frame: NSRect(x: 0, y: 0, width: sidebarWidth, height: 620))
    left.autoresizingMask = [.height]

    let sidebarBg = NSVisualEffectView(frame: left.bounds)
    sidebarBg.autoresizingMask = [.width, .height]
    sidebarBg.material = .sidebar
    sidebarBg.blendingMode = .behindWindow
    left.addSubview(sidebarBg)

    scrollView.frame = NSRect(x: 0, y: 72, width: sidebarWidth, height: 548)
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.autoresizingMask = [.height]

    let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("profile"))
    col.title = "Profiles"
    tableView.addTableColumn(col)
    tableView.headerView = nil
    tableView.rowHeight = 34
    tableView.allowsMultipleSelection = true
    tableView.style = .sourceList
    tableView.dataSource = self
    tableView.delegate = self
    scrollView.documentView = tableView

    addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Profile")
    addButton.bezelStyle = .push
    addButton.controlSize = .small
    addButton.imagePosition = .imageOnly
    addButton.frame = NSRect(x: 10, y: 40, width: 30, height: 24)
    addButton.target = self
    addButton.action = #selector(addProfile)

    removeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove Profile")
    removeButton.bezelStyle = .push
    removeButton.controlSize = .small
    removeButton.imagePosition = .imageOnly
    removeButton.frame = NSRect(x: 44, y: 40, width: 30, height: 24)
    removeButton.target = self
    removeButton.action = #selector(removeProfile)

    importButton.title = "Import..."
    importButton.bezelStyle = .rounded
    importButton.controlSize = .small
    importButton.frame = NSRect(x: 84, y: 40, width: 70, height: 24)
    importButton.target = self
    importButton.action = #selector(importProfiles)

    exportButton.title = "Export all..."
    exportButton.bezelStyle = .rounded
    exportButton.controlSize = .small
    exportButton.frame = NSRect(x: 160, y: 40, width: 82, height: 24)
    exportButton.target = self
    exportButton.action = #selector(exportProfiles)

    exportSelectedButton.title = "Export selected..."
    exportSelectedButton.bezelStyle = .rounded
    exportSelectedButton.controlSize = .small
    exportSelectedButton.frame = NSRect(x: 236, y: 40, width: 120, height: 24)
    exportSelectedButton.target = self
    exportSelectedButton.action = #selector(exportSelectedProfiles)

    left.addSubview(scrollView)
    left.addSubview(addButton)
    left.addSubview(removeButton)
    left.addSubview(importButton)
    left.addSubview(exportButton)
    left.addSubview(exportSelectedButton)

    let rightX = sidebarWidth
    let rightWidth = 920 - sidebarWidth
    let right = NSView(frame: NSRect(x: rightX, y: 0, width: rightWidth, height: 620))
    right.autoresizingMask = [.width, .height]

    let labelWidth: CGFloat = 176
    let fieldX: CGFloat = labelWidth + 18
    let fieldWidth: CGFloat = rightWidth - fieldX - 30

    let rowTop: CGFloat = 566
    let rowStep: CGFloat = 38
    func rowY(_ idx: Int) -> CGFloat { rowTop - (CGFloat(idx) * rowStep) }

    let nameLabel = makeRightLabel("Name", x: 12, y: rowY(0), width: labelWidth)
    nameField.frame = NSRect(x: fieldX, y: rowY(0) - 2, width: fieldWidth, height: 24)
    nameField.placeholderString = "My Upload Profile"
    nameField.autoresizingMask = [.width]

    let backendLabel = makeRightLabel("Backend", x: 12, y: rowY(1), width: labelWidth)
    backendPopup.frame = NSRect(x: fieldX, y: rowY(1) - 4, width: 280, height: 26)
    backendPopup.addItems(withTitles: ["Zipline v4", "S3-compatible"])
    backendPopup.target = self
    backendPopup.action = #selector(backendChanged)

    endpointLabel.font = .systemFont(ofSize: 13)
    endpointLabel.alignment = .right
    endpointLabel.frame = NSRect(x: 12, y: rowY(2), width: labelWidth, height: 20)
    endpointField.frame = NSRect(x: fieldX, y: rowY(2) - 2, width: fieldWidth, height: 24)
    endpointField.placeholderString = "https://zipline.example.com"
    endpointField.autoresizingMask = [.width]

    tokenLabel.font = .systemFont(ofSize: 13)
    tokenLabel.alignment = .right
    tokenLabel.frame = NSRect(x: 12, y: rowY(3), width: labelWidth, height: 20)
    apiKeyField.frame = NSRect(x: fieldX, y: rowY(3) - 2, width: fieldWidth - 72, height: 24)
    apiKeyField.placeholderString = "(stored in Keychain)"
    apiKeyField.autoresizingMask = [.width]

    pasteApiKeyButton.title = "Paste"
    pasteApiKeyButton.bezelStyle = .push
    pasteApiKeyButton.controlSize = .small
    pasteApiKeyButton.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paste")
    pasteApiKeyButton.imagePosition = .imageLeading
    pasteApiKeyButton.frame = NSRect(x: fieldX + fieldWidth - 66, y: rowY(3) - 2, width: 66, height: 24)
    pasteApiKeyButton.target = self
    pasteApiKeyButton.action = #selector(pasteApiKeyFromClipboard)
    pasteApiKeyButton.autoresizingMask = [.minXMargin]

    secondaryS3Label.frame = NSRect(x: 12, y: rowY(4), width: labelWidth, height: 20)
    secondaryS3Label.alignment = .right
    secondaryS3Label.font = .systemFont(ofSize: 13)
    secondaryS3Popup.frame = NSRect(x: fieldX, y: rowY(4) - 4, width: min(360, fieldWidth), height: 26)

    // S3 fields reuse the (hidden) API key row so they don't collide with the footer buttons.
    s3AccessLabel.frame = NSRect(x: 12, y: rowY(3), width: labelWidth, height: 20)
    s3AccessLabel.alignment = .right
    s3AccessLabel.font = .systemFont(ofSize: 13)
    s3AccessKeyIdField.frame = NSRect(x: fieldX, y: rowY(3) - 2, width: fieldWidth, height: 24)
    s3AccessKeyIdField.placeholderString = "AKIA..."
    s3AccessKeyIdField.autoresizingMask = [.width]

    s3SecretLabel.frame = NSRect(x: 12, y: rowY(4), width: labelWidth, height: 20)
    s3SecretLabel.alignment = .right
    s3SecretLabel.font = .systemFont(ofSize: 13)
    s3SecretAccessKeyField.frame = NSRect(x: fieldX, y: rowY(4) - 2, width: fieldWidth, height: 24)
    s3SecretAccessKeyField.placeholderString = "(stored in Keychain)"
    s3SecretAccessKeyField.autoresizingMask = [.width]

    s3SessionLabel.frame = NSRect(x: 12, y: rowY(5), width: labelWidth, height: 20)
    s3SessionLabel.alignment = .right
    s3SessionLabel.font = .systemFont(ofSize: 13)
    s3SessionTokenField.frame = NSRect(x: fieldX, y: rowY(5) - 2, width: fieldWidth, height: 24)
    s3SessionTokenField.placeholderString = "Optional temporary session token"
    s3SessionTokenField.autoresizingMask = [.width]

    s3RegionLabel.frame = NSRect(x: 12, y: rowY(6), width: labelWidth, height: 20)
    s3RegionLabel.alignment = .right
    s3RegionLabel.font = .systemFont(ofSize: 13)
    s3RegionField.frame = NSRect(x: fieldX, y: rowY(6) - 2, width: fieldWidth, height: 24)
    s3RegionField.placeholderString = "us-east-1"
    s3RegionField.autoresizingMask = [.width]

    s3BucketLabel.frame = NSRect(x: 12, y: rowY(7), width: labelWidth, height: 20)
    s3BucketLabel.alignment = .right
    s3BucketLabel.font = .systemFont(ofSize: 13)
    s3BucketField.frame = NSRect(x: fieldX, y: rowY(7) - 2, width: fieldWidth, height: 24)
    s3BucketField.placeholderString = "my-bucket"
    s3BucketField.autoresizingMask = [.width]

    s3PrefixLabel.frame = NSRect(x: 12, y: rowY(8), width: labelWidth, height: 20)
    s3PrefixLabel.alignment = .right
    s3PrefixLabel.font = .systemFont(ofSize: 13)
    s3KeyPrefixField.frame = NSRect(x: fieldX, y: rowY(8) - 2, width: fieldWidth, height: 24)
    s3KeyPrefixField.placeholderString = "optional/prefix"
    s3KeyPrefixField.autoresizingMask = [.width]

    s3PublicBaseLabel.frame = NSRect(x: 12, y: rowY(9), width: labelWidth, height: 20)
    s3PublicBaseLabel.alignment = .right
    s3PublicBaseLabel.font = .systemFont(ofSize: 13)
    s3PublicBaseURLField.frame = NSRect(x: fieldX, y: rowY(9) - 2, width: fieldWidth, height: 24)
    s3PublicBaseURLField.placeholderString = "https://cdn.example.com"
    s3PublicBaseURLField.autoresizingMask = [.width]

    s3DefaultExpiryLabel.frame = NSRect(x: 12, y: rowY(10), width: labelWidth, height: 20)
    s3DefaultExpiryLabel.alignment = .right
    s3DefaultExpiryLabel.font = .systemFont(ofSize: 13)
    s3DefaultGetExpiryField.frame = NSRect(x: fieldX, y: rowY(10) - 2, width: 140, height: 24)
    s3DefaultGetExpiryField.placeholderString = "3600"

    s3ForcePathStyleCheckbox.frame = NSRect(x: fieldX, y: rowY(11), width: fieldWidth, height: 22)
    s3UseSignedGetCheckbox.frame = NSRect(x: fieldX, y: rowY(12), width: fieldWidth, height: 22)
    s3ForcePathStyleCheckbox.autoresizingMask = [.width]
    s3UseSignedGetCheckbox.autoresizingMask = [.width]

    let footerY: CGFloat = 64
    let helpLineHeight: CGFloat = 34
    let footerInsetX: CGFloat = 16
    let footerInsetY: CGFloat = 18
    let helpRightClearance: CGFloat = 210
    let helpWidth = max(160, rightWidth - (footerInsetX * 2) - helpRightClearance)
    let buttonY: CGFloat = 72
    let footerSep = NSBox(frame: NSRect(x: 12, y: footerY, width: rightWidth - 24, height: 1))
    footerSep.boxType = .separator
    footerSep.autoresizingMask = [.width, .minYMargin]

    let help = NSTextField(labelWithString: "Use Validate to verify your destination settings before saving.")
    help.frame = NSRect(x: footerInsetX, y: footerInsetY, width: helpWidth, height: helpLineHeight)
    help.maximumNumberOfLines = 2
    help.lineBreakMode = .byWordWrapping
    help.textColor = .secondaryLabelColor
    help.font = .systemFont(ofSize: 12)
    help.autoresizingMask = [.width, .minYMargin]

    probeButton.bezelStyle = .rounded
    probeButton.frame = NSRect(x: rightWidth - 200, y: buttonY, width: 90, height: 28)
    probeButton.target = self
    probeButton.action = #selector(validateProfile)
    probeButton.autoresizingMask = [.minXMargin, .minYMargin]

    saveButton.bezelStyle = .push
    saveButton.keyEquivalent = "\r"
    saveButton.frame = NSRect(x: rightWidth - 102, y: buttonY, width: 80, height: 28)
    saveButton.target = self
    saveButton.action = #selector(saveProfile)
    saveButton.autoresizingMask = [.minXMargin, .minYMargin]

    activeCheckbox.frame = NSRect(x: fieldX, y: buttonY + 3, width: 240, height: 22)
    activeCheckbox.autoresizingMask = [.maxXMargin, .minYMargin]

    help.cell?.wraps = true
    help.cell?.usesSingleLineMode = false

    right.addSubview(nameLabel)
    right.addSubview(nameField)
    right.addSubview(backendLabel)
    right.addSubview(backendPopup)
    right.addSubview(endpointLabel)
    right.addSubview(endpointField)
    right.addSubview(tokenLabel)
    right.addSubview(apiKeyField)
    right.addSubview(pasteApiKeyButton)
    right.addSubview(secondaryS3Label)
    right.addSubview(secondaryS3Popup)

    right.addSubview(s3AccessLabel)
    right.addSubview(s3AccessKeyIdField)
    right.addSubview(s3SecretLabel)
    right.addSubview(s3SecretAccessKeyField)
    right.addSubview(s3SessionLabel)
    right.addSubview(s3SessionTokenField)
    right.addSubview(s3RegionLabel)
    right.addSubview(s3RegionField)
    right.addSubview(s3BucketLabel)
    right.addSubview(s3BucketField)
    right.addSubview(s3PrefixLabel)
    right.addSubview(s3KeyPrefixField)
    right.addSubview(s3PublicBaseLabel)
    right.addSubview(s3PublicBaseURLField)
    right.addSubview(s3DefaultExpiryLabel)
    right.addSubview(s3DefaultGetExpiryField)
    right.addSubview(s3ForcePathStyleCheckbox)
    right.addSubview(s3UseSignedGetCheckbox)

    right.addSubview(activeCheckbox)
    right.addSubview(footerSep)
    right.addSubview(probeButton)
    right.addSubview(saveButton)
    right.addSubview(help)

    content.addSubview(left)
    content.addSubview(right)

    apiViews = [tokenLabel, apiKeyField, pasteApiKeyButton]
    secondaryS3Views = [secondaryS3Label, secondaryS3Popup]
    s3Views = [
      s3AccessLabel, s3AccessKeyIdField,
      s3SecretLabel, s3SecretAccessKeyField,
      s3SessionLabel, s3SessionTokenField,
      s3RegionLabel, s3RegionField,
      s3BucketLabel, s3BucketField,
      s3PrefixLabel, s3KeyPrefixField,
      s3PublicBaseLabel, s3PublicBaseURLField,
      s3DefaultExpiryLabel, s3DefaultGetExpiryField,
      s3ForcePathStyleCheckbox, s3UseSignedGetCheckbox,
    ]

    reloadProfiles()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func makeRightLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 13)
    label.alignment = .right
    label.frame = NSRect(x: x, y: y, width: width, height: 20)
    return label
  }

  private func setViews(_ views: [NSView], hidden: Bool) {
    for view in views {
      view.isHidden = hidden
    }
  }

  private func trim(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func defaultS3Config(for profile: UploadProfile) -> S3DestinationConfig {
    if let cfg = profile.s3Config {
      return cfg
    }
    return S3DestinationConfig(endpoint: profile.endpoint)
  }

  private func populateSecondaryS3Popup(selectedProfile: UploadProfile?) {
    secondaryS3Popup.removeAllItems()
    secondaryS3Popup.addItem(withTitle: "No secondary S3 copy")
    secondaryS3Popup.lastItem?.representedObject = ""

    let s3Profiles = profiles.filter { profile in
      profile.backend == .s3Compatible && profile.id != selectedProfile?.id
    }
    for profile in s3Profiles {
      secondaryS3Popup.addItem(withTitle: profile.name)
      secondaryS3Popup.lastItem?.representedObject = profile.id
    }

    let selectedMirrorId = selectedProfile?.secondaryS3ProfileId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !selectedMirrorId.isEmpty,
       let idx = secondaryS3Popup.itemArray.firstIndex(where: { ($0.representedObject as? String) == selectedMirrorId }) {
      secondaryS3Popup.selectItem(at: idx)
    } else {
      secondaryS3Popup.selectItem(at: 0)
    }
  }

  private func selectedSecondaryS3ProfileId() -> String? {
    guard let raw = secondaryS3Popup.selectedItem?.representedObject as? String else { return nil }
    let trimmed = trim(raw)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func draftProfileFromFields(profileId: String) -> UploadProfile {
    let backend = selectedBackend()
    var profile = UploadProfile(
      id: profileId,
      name: trim(nameField.stringValue),
      endpoint: trim(endpointField.stringValue),
      backend: backend
    )

    if backend == .s3Compatible {
      let cfg = S3DestinationConfig(
        endpoint: trim(endpointField.stringValue),
        region: trim(s3RegionField.stringValue).isEmpty ? "us-east-1" : trim(s3RegionField.stringValue),
        bucket: trim(s3BucketField.stringValue),
        keyPrefix: trim(s3KeyPrefixField.stringValue),
        forcePathStyle: s3ForcePathStyleCheckbox.state == .on,
        publicBaseURL: trim(s3PublicBaseURLField.stringValue),
        useSignedGetURL: s3UseSignedGetCheckbox.state == .on,
        defaultGetExpirySeconds: Int(trim(s3DefaultGetExpiryField.stringValue)) ?? 3600
      )
      profile.endpoint = cfg.endpoint
      profile.s3Config = cfg
      profile.secondaryS3ProfileId = nil
    } else {
      profile.s3Config = nil
      profile.secondaryS3ProfileId = backend == .ziplineV4 ? selectedSecondaryS3ProfileId() : nil
    }

    if profile.name.isEmpty {
      profile.name = "Profile"
    }
    return profile
  }

  private func reloadProfiles() {
    profiles = Settings.shared.profiles()
    tableView.reloadData()

    if selectedId == nil {
      selectedId = Settings.shared.activeProfileId ?? profiles.first?.id
    }

    if let selectedId, let idx = profiles.firstIndex(where: { $0.id == selectedId }) {
      tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
    }

    loadSelectedIntoFields()
  }

  private func loadSelectedIntoFields() {
    guard let selectedId, let p = profiles.first(where: { $0.id == selectedId }) else {
      nameField.stringValue = ""
      endpointField.stringValue = ""
      apiKeyField.stringValue = ""
      backendPopup.selectItem(at: 0)
      populateSecondaryS3Popup(selectedProfile: nil)
      updateBackendUI(.ziplineV4)
      activeCheckbox.state = .off
      saveButton.isEnabled = false
      probeButton.isEnabled = false
      removeButton.isEnabled = false
      exportButton.isEnabled = !profiles.isEmpty
      exportSelectedButton.isEnabled = false
      return
    }

    saveButton.isEnabled = true
    probeButton.isEnabled = true
    removeButton.isEnabled = profiles.count > 1
    exportButton.isEnabled = !profiles.isEmpty
    exportSelectedButton.isEnabled = !selectedProfileIds().isEmpty

    nameField.stringValue = p.name
    backendPopup.selectItem(at: popupIndex(for: p.backend))
    populateSecondaryS3Popup(selectedProfile: p)
    updateBackendUI(p.backend)
    activeCheckbox.state = (Settings.shared.activeProfileId == p.id) ? .on : .off

    switch p.backend {
    case .ziplineV4:
      endpointField.stringValue = p.endpoint
      apiKeyField.stringValue = Settings.shared.getApiKey(profileId: p.id) ?? ""

      s3AccessKeyIdField.stringValue = ""
      s3SecretAccessKeyField.stringValue = ""
      s3SessionTokenField.stringValue = ""
      s3RegionField.stringValue = "us-east-1"
      s3BucketField.stringValue = ""
      s3KeyPrefixField.stringValue = ""
      s3PublicBaseURLField.stringValue = ""
      s3ForcePathStyleCheckbox.state = .off
      s3UseSignedGetCheckbox.state = .off
      s3DefaultGetExpiryField.stringValue = "3600"
    case .s3Compatible:
      apiKeyField.stringValue = ""

      let cfg = defaultS3Config(for: p)
      endpointField.stringValue = cfg.endpoint
      s3AccessKeyIdField.stringValue = Settings.shared.getS3AccessKeyId(profileId: p.id) ?? ""
      s3SecretAccessKeyField.stringValue = Settings.shared.getS3SecretAccessKey(profileId: p.id) ?? ""
      s3SessionTokenField.stringValue = Settings.shared.getS3SessionToken(profileId: p.id) ?? ""
      s3RegionField.stringValue = cfg.region
      s3BucketField.stringValue = cfg.bucket
      s3KeyPrefixField.stringValue = cfg.keyPrefix
      s3PublicBaseURLField.stringValue = cfg.publicBaseURL
      s3ForcePathStyleCheckbox.state = cfg.forcePathStyle ? .on : .off
      s3UseSignedGetCheckbox.state = cfg.useSignedGetURL ? .on : .off
      s3DefaultGetExpiryField.stringValue = "\(cfg.defaultGetExpirySeconds)"
    }
  }

  private func popupIndex(for backend: UploadBackend) -> Int {
    switch backend {
    case .ziplineV4:
      return 0
    case .s3Compatible:
      return 1
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    profiles.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let p = profiles[row]
    let id = NSUserInterfaceItemIdentifier("profileCell")

    let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
    cell.identifier = id

    if cell.textField == nil {
      let tf = NSTextField(labelWithString: "")
      tf.frame = NSRect(x: 8, y: 7, width: tableView.bounds.width - 16, height: 20)
      tf.autoresizingMask = [.width]
      cell.addSubview(tf)
      cell.textField = tf
    }

    let isActive = Settings.shared.activeProfileId == p.id
    cell.textField?.font = isActive ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 13)
    cell.textField?.stringValue = p.name

    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let row = tableView.selectedRow
    if row >= 0 && row < profiles.count {
      selectedId = profiles[row].id
    } else {
      selectedId = nil
    }
    loadSelectedIntoFields()
  }

  private func selectedProfileIds() -> [String] {
    tableView.selectedRowIndexes.compactMap { row in
      guard row >= 0 && row < profiles.count else { return nil }
      return profiles[row].id
    }
  }

  private func sanitizeFileComponent(_ value: String) -> String {
    let trimmed = trim(value)
      .lowercased()
      .replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
      .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

    if trimmed.isEmpty { return "profile" }
    return String(trimmed.prefix(32))
  }

  private func exportDefaultName(profileIds: [String]?) -> String {
    let date = ISO8601DateFormatter().string(from: Date()).prefix(10)
    guard let profileIds, !profileIds.isEmpty else {
      return "craftycannon-profiles-\(date).json"
    }

    let names = profileIds.compactMap { id in
      profiles.first(where: { $0.id == id })?.name
    }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    guard !names.isEmpty else {
      return "craftycannon-selected-profiles-\(date).json"
    }

    let sanitized = names.map(sanitizeFileComponent(_:))
    if sanitized.count == 1 {
      return "craftycannon-\(sanitized[0]).json"
    }

    if sanitized.count == 2 {
      return "craftycannon-\(sanitized[0])-\(sanitized[1]).json"
    }

    if sanitized.count == 3 {
      return "craftycannon-\(sanitized[0])-\(sanitized[1])-\(sanitized[2]).json"
    }

    return "craftycannon-selected-\(sanitized[0])-\(sanitized[1])-\(sanitized[2])-plus-\(sanitized.count - 3).json"
  }

  @objc private func addProfile() {
    let p = UploadProfile(name: "New Profile", endpoint: "", backend: .ziplineV4)
    Settings.shared.upsertProfile(p)
    selectedId = p.id
    reloadProfiles()
  }

  @objc private func removeProfile() {
    guard let selectedId else { return }
    Settings.shared.removeProfile(id: selectedId)
    self.selectedId = Settings.shared.activeProfileId
    reloadProfiles()
  }

  @objc private func importProfiles() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [UTType.json]

    panel.beginSheetModal(for: window!) { [weak self] resp in
      guard resp == .OK, let self, let url = panel.url else { return }

      let replacePrompt = NSAlert()
      replacePrompt.messageText = "Import profiles"
      replacePrompt.informativeText = "Merge with existing profiles or replace them?"
      replacePrompt.addButton(withTitle: "Merge")
      replacePrompt.addButton(withTitle: "Replace")
      replacePrompt.addButton(withTitle: "Cancel")
      replacePrompt.ensureResizable()
      let mode = replacePrompt.runModal()
      if mode == .alertThirdButtonReturn { return }

      do {
        let count = try ProfileStore.shared.importProfiles(from: url, replaceExisting: mode == .alertSecondButtonReturn)
        self.selectedId = Settings.shared.activeProfileId
        self.reloadProfiles()
        let action = mode == .alertSecondButtonReturn ? "Replaced" : "Merged"
        let suffix = count == 1 ? "1 profile" : "\(count) profiles"
        Notifier.shared.notify(
          title: "CraftyCannon",
          body: "\(action) \(suffix) from \(url.lastPathComponent)"
        )
      } catch {
        self.showError("Import failed", "Could not import profile bundle (\(error.localizedDescription)).")
      }
    }
  }

  @objc private func exportProfiles() {
    exportProfilesInternal(profileIds: nil)
  }

  @objc private func exportSelectedProfiles() {
    let selectedIds = selectedProfileIds()
    guard !selectedIds.isEmpty else {
      showError("No profiles selected", "Select at least one profile before exporting.")
      return
    }

    exportProfilesInternal(profileIds: selectedIds)
  }

  private func exportProfilesInternal(profileIds: [String]?) {
    guard !profiles.isEmpty else {
      showError("No profiles", "Create at least one profile before exporting.")
      return
    }

    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.allowedContentTypes = [UTType.json]
    panel.nameFieldStringValue = exportDefaultName(profileIds: profileIds)

    panel.beginSheetModal(for: window!) { [weak self] resp in
      guard resp == .OK, let self, let url = panel.url else { return }
      do {
        try ProfileStore.shared.exportProfiles(to: url, profileIds: profileIds)
        let exportedCount = profileIds?.count ?? self.profiles.count
        let suffix = exportedCount == 1 ? "1 profile" : "\(exportedCount) profiles"
        Notifier.shared.notify(
          title: "CraftyCannon",
          body: "Exported \(suffix) to \(url.lastPathComponent)"
        )
      } catch {
        self.showError("Export failed", "Could not write profile bundle (\(error.localizedDescription)).")
      }
    }
  }

  @objc private func saveProfile() {
    guard let selectedId, var p = profiles.first(where: { $0.id == selectedId }) else { return }

    let trimmedName = trim(nameField.stringValue)
    p.name = trimmedName.isEmpty ? "Profile" : trimmedName
    p.backend = selectedBackend()

    switch p.backend {
    case .ziplineV4:
      p.endpoint = trim(endpointField.stringValue)
      p.s3Config = nil
      p.secondaryS3ProfileId = selectedSecondaryS3ProfileId()

      let apiKey = trim(apiKeyField.stringValue)
      Settings.shared.clearApiKey(profileId: p.id)
      if !apiKey.isEmpty {
        try? Settings.shared.setApiKey(apiKey, profileId: p.id)
      }
    case .s3Compatible:
      let region = trim(s3RegionField.stringValue).isEmpty ? "us-east-1" : trim(s3RegionField.stringValue)
      let cfg = S3DestinationConfig(
        endpoint: trim(endpointField.stringValue),
        region: region,
        bucket: trim(s3BucketField.stringValue),
        keyPrefix: trim(s3KeyPrefixField.stringValue),
        forcePathStyle: s3ForcePathStyleCheckbox.state == .on,
        publicBaseURL: trim(s3PublicBaseURLField.stringValue),
        useSignedGetURL: s3UseSignedGetCheckbox.state == .on,
        defaultGetExpirySeconds: Int(trim(s3DefaultGetExpiryField.stringValue)) ?? 3600
      )
      p.endpoint = cfg.endpoint
      p.s3Config = cfg
      p.secondaryS3ProfileId = nil

      let access = trim(s3AccessKeyIdField.stringValue)
      let secret = trim(s3SecretAccessKeyField.stringValue)
      let session = trim(s3SessionTokenField.stringValue)
      Settings.shared.clearS3Secrets(profileId: p.id)
      if !access.isEmpty {
        try? Settings.shared.setS3AccessKeyId(access, profileId: p.id)
      }
      if !secret.isEmpty {
        try? Settings.shared.setS3SecretAccessKey(secret, profileId: p.id)
      }
      if !session.isEmpty {
        try? Settings.shared.setS3SessionToken(session, profileId: p.id)
      }
    }

    Settings.shared.upsertProfile(p)

    if activeCheckbox.state == .on {
      Settings.shared.setActiveProfileId(p.id)
    }

    Notifier.shared.notify(title: "CraftyCannon", body: "Saved profile")
    reloadProfiles()
  }

  @objc private func pasteApiKeyFromClipboard() {
    if let raw = NSPasteboard.general.string(forType: .string) {
      apiKeyField.stringValue = trim(raw)
    }
  }

  @objc private func backendChanged() {
    let backend = selectedBackend()
    if let selectedId, let p = profiles.first(where: { $0.id == selectedId }) {
      populateSecondaryS3Popup(selectedProfile: p)
    }
    updateBackendUI(backend)
  }

  @objc private func validateProfile() {
    guard let selectedId else { return }

    let draft = draftProfileFromFields(profileId: selectedId)
    let access = trim(s3AccessKeyIdField.stringValue)
    let secret = trim(s3SecretAccessKeyField.stringValue)
    let session = trim(s3SessionTokenField.stringValue)
    let isS3 = draft.backend == .s3Compatible

    probeButton.isEnabled = false
    Task { @MainActor [weak self] in
      let result: Uploader.EndpointValidationResult
      if isS3 {
        result = await Uploader.shared.validateEndpoint(
          profile: draft,
          s3AccessKeyId: access,
          s3SecretAccessKey: secret,
          s3SessionToken: session
        )
      } else {
        result = await Uploader.shared.validateEndpoint(profile: draft)
      }

      guard let self else { return }
      self.probeButton.isEnabled = true
      if result.isValid {
        let ok = NSAlert()
        ok.messageText = "Validation succeeded"
        ok.informativeText = result.message
        ok.addButton(withTitle: "OK")
        ok.ensureResizable()
        ok.runModal()
      } else {
        self.showError("Validation failed", result.message)
      }
    }
  }

  private func selectedBackend() -> UploadBackend {
    switch backendPopup.indexOfSelectedItem {
    case 1:
      return .s3Compatible
    default:
      return .ziplineV4
    }
  }

  private func updateBackendUI(_ backend: UploadBackend) {
    switch backend {
    case .ziplineV4:
      endpointLabel.stringValue = "Endpoint"
      endpointField.placeholderString = "https://zipline.example.com"
      tokenLabel.stringValue = "Authorization token"
      apiKeyField.placeholderString = "(stored in Keychain)"
      setViews(apiViews, hidden: false)
      setViews(secondaryS3Views, hidden: false)
      setViews(s3Views, hidden: true)
    case .s3Compatible:
      endpointLabel.stringValue = "S3 endpoint"
      endpointField.placeholderString = "https://s3.amazonaws.com"
      setViews(apiViews, hidden: true)
      setViews(secondaryS3Views, hidden: true)
      setViews(s3Views, hidden: false)
    }
  }

  private func showError(_ title: String, _ details: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = details
    alert.addButton(withTitle: "OK")
    alert.ensureResizable()
    alert.runModal()
  }
}
