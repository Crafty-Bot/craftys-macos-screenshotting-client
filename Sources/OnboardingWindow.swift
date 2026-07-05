import AppKit
import Foundation

struct OnboardingResult {
  var profile: UploadProfile
  var apiSecret: String
  var s3AccessKeyId: String
  var s3SecretAccessKey: String
  var s3SessionToken: String
  var secondaryS3Profile: UploadProfile?
  var secondaryS3AccessKeyId: String
  var secondaryS3SecretAccessKey: String
  var secondaryS3SessionToken: String
}

struct AWSCLIProfile: Equatable {
  var name: String
  var accessKeyId: String
  var secretAccessKey: String
  var sessionToken: String
  var region: String
  var endpoint: String
}

enum AWSCLIProfileLoader {
  static func loadProfiles(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AWSCLIProfile] {
    let awsDir = homeDirectory.appendingPathComponent(".aws", isDirectory: true)
    let credentialsText = (try? String(contentsOf: awsDir.appendingPathComponent("credentials"), encoding: .utf8)) ?? ""
    let configText = (try? String(contentsOf: awsDir.appendingPathComponent("config"), encoding: .utf8)) ?? ""
    return parse(credentialsText: credentialsText, configText: configText)
  }

  static func parse(credentialsText: String, configText: String) -> [AWSCLIProfile] {
    let credentials = parseINI(credentialsText)
    let config = parseINI(configText)

    var names = Set(credentials.keys)
    names.formUnion(config.keys)

    return names.sorted { lhs, rhs in
      if lhs == "default" { return true }
      if rhs == "default" { return false }
      return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }.compactMap { name in
      let credSection = credentials[name] ?? [:]
      let configSection = config[name] ?? [:]
      let access = trim(credSection["aws_access_key_id"] ?? configSection["aws_access_key_id"] ?? "")
      let secret = trim(credSection["aws_secret_access_key"] ?? configSection["aws_secret_access_key"] ?? "")
      guard !access.isEmpty, !secret.isEmpty else { return nil }

      let session = trim(credSection["aws_session_token"] ?? configSection["aws_session_token"] ?? "")
      let region = trim(credSection["region"] ?? configSection["region"] ?? "us-east-1")
      let endpoint = trim(configSection["endpoint_url"] ?? credSection["endpoint_url"] ?? "https://s3.amazonaws.com")
      return AWSCLIProfile(
        name: name,
        accessKeyId: access,
        secretAccessKey: secret,
        sessionToken: session,
        region: region.isEmpty ? "us-east-1" : region,
        endpoint: endpoint.isEmpty ? "https://s3.amazonaws.com" : endpoint
      )
    }
  }

  private static func parseINI(_ text: String) -> [String: [String: String]] {
    var result: [String: [String: String]] = [:]
    var currentSection = ""

    for rawLine in text.components(separatedBy: .newlines) {
      let line = trim(rawLine)
      if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
        continue
      }

      if line.hasPrefix("[") && line.hasSuffix("]") {
        currentSection = normalizedSectionName(String(line.dropFirst().dropLast()))
        if result[currentSection] == nil {
          result[currentSection] = [:]
        }
        continue
      }

      guard !currentSection.isEmpty else { continue }
      let separatorIndex = line.firstIndex(of: "=") ?? line.firstIndex(of: ":")
      guard let separatorIndex else { continue }

      let key = trim(String(line[..<separatorIndex])).lowercased()
      let value = trim(String(line[line.index(after: separatorIndex)...]))
      if !key.isEmpty {
        result[currentSection, default: [:]][key] = value
      }
    }

    return result
  }

  private static func normalizedSectionName(_ raw: String) -> String {
    let trimmed = trim(raw)
    if trimmed.hasPrefix("profile ") {
      return trim(String(trimmed.dropFirst("profile ".count)))
    }
    return trimmed
  }

  private static func trim(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private struct SecondaryS3OnboardingResult {
  var profile: UploadProfile
  var accessKeyId: String
  var secretAccessKey: String
  var sessionToken: String
}

enum OnboardingWindow {
  private static func activateForModalUI() {
    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    NSApp.activate(ignoringOtherApps: true)
  }

  private static func discardClickThroughEvents() {
    // When chaining modal NSAlert.runModal() calls, the mouse-up from the first
    // click can be delivered to the next alert, instantly "clicking" Continue.
    NSApp.discardEvents(matching: [.leftMouseUp, .leftMouseDown], before: nil)
  }

  private static func prepareAlertWindow(_ alert: NSAlert) {
    let w = alert.window
    w.level = .floating
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    // These "Add profile"/onboarding prompts are implemented as NSAlerts with an accessory view.
    // Make them resizable so long values don't force overlapping/clipped layouts.
    w.styleMask.insert(.resizable)
    w.minSize = w.frame.size
    w.center()
    w.makeKeyAndOrderFront(nil)
  }

  private enum Preset {
    case zipline
    case s3
    case custom

    var title: String {
      switch self {
    case .zipline: return "Zipline v4"
    case .s3: return "S3-compatible"
    case .custom: return "Custom"
      }
    }

    var defaultBackend: UploadBackend {
      switch self {
    case .zipline: return .ziplineV4
    case .s3: return .s3Compatible
    case .custom: return .ziplineV4
      }
    }

    var defaultEndpoint: String {
      switch self {
    case .zipline: return "https://zipline.example.com"
    case .s3: return "https://s3.amazonaws.com"
    case .custom: return ""
      }
    }
  }

  static func runInitialSetup() -> OnboardingResult? {
    guard let preset = choosePreset() else { return nil }

    var backend = preset.defaultBackend
    var endpoint = preset.defaultEndpoint
    var profileName = "Primary"
    var apiSecret = ""
    var s3Region = "us-east-1"
    var s3Bucket = ""
    var s3AccessKeyId = ""
    var s3SecretAccessKey = ""
    var s3SessionToken = ""

    while true {
      guard let details = promptDetails(
        preset: preset,
        profileName: profileName,
        backend: backend,
        endpoint: endpoint,
        apiSecret: apiSecret,
        s3Region: s3Region,
        s3Bucket: s3Bucket,
        s3AccessKeyId: s3AccessKeyId,
        s3SecretAccessKey: s3SecretAccessKey,
        s3SessionToken: s3SessionToken
      ) else {
        return nil
      }

      profileName = details.profileName
      backend = details.backend
      endpoint = details.endpoint
      apiSecret = details.apiSecret
      s3Region = details.s3Region
      s3Bucket = details.s3Bucket
      s3AccessKeyId = details.s3AccessKeyId
      s3SecretAccessKey = details.s3SecretAccessKey
      s3SessionToken = details.s3SessionToken

      var profile = makeProfile(
        profileName: profileName,
        backend: backend,
        endpoint: endpoint,
        s3Region: s3Region,
        s3Bucket: s3Bucket
      )
      let validation: Uploader.EndpointValidationResult
      if backend == .s3Compatible {
        validation = validateS3OnboardingInputs(
          profile: profile,
          accessKeyId: s3AccessKeyId,
          secretAccessKey: s3SecretAccessKey
        )
      } else {
        validation = runValidationWithProgress(for: profile)
      }
      if validation.isValid {
        let secondaryS3 = (backend == .ziplineV4) ? promptSecondaryS3MirrorIfAvailable(primaryProfileName: profile.name) : nil
        if let secondaryS3 {
          profile.secondaryS3ProfileId = secondaryS3.profile.id
        }
        return OnboardingResult(
          profile: profile,
          apiSecret: apiSecret,
          s3AccessKeyId: s3AccessKeyId,
          s3SecretAccessKey: s3SecretAccessKey,
          s3SessionToken: s3SessionToken,
          secondaryS3Profile: secondaryS3?.profile,
          secondaryS3AccessKeyId: secondaryS3?.accessKeyId ?? "",
          secondaryS3SecretAccessKey: secondaryS3?.secretAccessKey ?? "",
          secondaryS3SessionToken: secondaryS3?.sessionToken ?? ""
        )
      }

      let err = NSAlert()
      err.messageText = "Endpoint validation failed"
      err.informativeText = validation.message
      err.addButton(withTitle: "Retry")
      err.addButton(withTitle: "Cancel")
      activateForModalUI()
      prepareAlertWindow(err)
      if err.runModal() != .alertFirstButtonReturn {
        return nil
      }
      discardClickThroughEvents()
    }
  }

  private static func promptSecondaryS3MirrorIfAvailable(primaryProfileName: String) -> SecondaryS3OnboardingResult? {
    let awsProfiles = AWSCLIProfileLoader.loadProfiles()
    guard !awsProfiles.isEmpty else { return nil }

    let prompt = NSAlert()
    prompt.messageText = "Add secondary AWS S3 copy?"
    prompt.informativeText = "CraftyCannon found AWS CLI credentials on this Mac. You can keep Zipline as the primary upload destination and also mirror each upload to an S3 bucket."
    prompt.addButton(withTitle: "Use AWS S3")
    prompt.addButton(withTitle: "Skip")

    activateForModalUI()
    prepareAlertWindow(prompt)
    let response = prompt.runModal()
    discardClickThroughEvents()
    guard response == .alertFirstButtonReturn else { return nil }

    return promptSecondaryS3Details(awsProfiles: awsProfiles, primaryProfileName: primaryProfileName)
  }

  private static func promptSecondaryS3Details(
    awsProfiles: [AWSCLIProfile],
    primaryProfileName: String
  ) -> SecondaryS3OnboardingResult? {
    guard let firstProfile = awsProfiles.first else { return nil }

    let alert = NSAlert()
    alert.messageText = "Secondary AWS S3 destination"
    alert.informativeText = "Choose the AWS CLI profile and bucket to use for the secondary copy. Credentials stay local in Keychain."
    alert.addButton(withTitle: "Add S3 Mirror")
    alert.addButton(withTitle: "Cancel")

    let profilePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
    for profile in awsProfiles {
      profilePopup.addItem(withTitle: profile.name)
      profilePopup.lastItem?.representedObject = profile.name
    }

    let bucketField = NSTextField(string: "")
    let regionField = NSTextField(string: "")
    let prefixField = NSTextField(string: "craftycannon")
    let endpointField = NSTextField(string: "")

    bucketField.placeholderString = "my-s3-bucket"
    regionField.placeholderString = firstProfile.region
    prefixField.placeholderString = "optional/prefix"
    endpointField.placeholderString = "https://s3.amazonaws.com"

    let labels = ["AWS Profile", "Bucket", "Region", "Key Prefix", "S3 Endpoint"]
    let fields: [NSView] = [profilePopup, bucketField, regionField, prefixField, endpointField]

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.spacing = 8
    stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 4, right: 0)

    for (idx, labelText) in labels.enumerated() {
      let row = NSStackView()
      row.orientation = .horizontal
      row.alignment = .centerY
      row.spacing = 8

      let label = NSTextField(labelWithString: labelText)
      label.alignment = .right
      label.widthAnchor.constraint(equalToConstant: 86).isActive = true

      row.addArrangedSubview(label)
      row.addArrangedSubview(fields[idx])
      stack.addArrangedSubview(row)
    }

    alert.accessoryView = stack
    activateForModalUI()
    prepareAlertWindow(alert)
    let response = alert.runModal()
    discardClickThroughEvents()
    guard response == .alertFirstButtonReturn else { return nil }

    let selectedName = (profilePopup.selectedItem?.representedObject as? String) ?? firstProfile.name
    let awsProfile = awsProfiles.first(where: { $0.name == selectedName }) ?? firstProfile
    let bucket = bucketField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let rawRegion = regionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = prefixField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let rawEndpoint = endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let region = rawRegion.isEmpty ? awsProfile.region : rawRegion
    let endpoint = rawEndpoint.isEmpty ? awsProfile.endpoint : rawEndpoint

    if bucket.isEmpty || region.isEmpty || endpoint.isEmpty {
      let err = NSAlert()
      err.messageText = "Missing S3 mirror fields"
      err.informativeText = "Bucket, region, and endpoint are required to add the secondary S3 copy."
      err.addButton(withTitle: "OK")
      activateForModalUI()
      prepareAlertWindow(err)
      err.runModal()
      return promptSecondaryS3Details(awsProfiles: awsProfiles, primaryProfileName: primaryProfileName)
    }

    guard let endpointURL = URL(string: endpoint),
          let scheme = endpointURL.scheme?.lowercased(),
          ["https", "http"].contains(scheme),
          endpointURL.host != nil else {
      let err = NSAlert()
      err.messageText = "Invalid S3 endpoint"
      err.informativeText = "Enter a valid S3 endpoint URL, such as https://s3.amazonaws.com."
      err.addButton(withTitle: "OK")
      activateForModalUI()
      prepareAlertWindow(err)
      err.runModal()
      return promptSecondaryS3Details(awsProfiles: awsProfiles, primaryProfileName: primaryProfileName)
    }

    let config = S3DestinationConfig(
      endpoint: endpoint,
      region: region,
      bucket: bucket,
      keyPrefix: prefix,
      forcePathStyle: false,
      publicBaseURL: "",
      useSignedGetURL: false,
      defaultGetExpirySeconds: 3600
    )
    let profileName = "\(primaryProfileName) S3 Mirror"
    let profile = UploadProfile(
      name: profileName,
      endpoint: endpoint,
      backend: .s3Compatible,
      s3Config: config
    )

    return SecondaryS3OnboardingResult(
      profile: profile,
      accessKeyId: awsProfile.accessKeyId,
      secretAccessKey: awsProfile.secretAccessKey,
      sessionToken: awsProfile.sessionToken
    )
  }

  private static func choosePreset() -> Preset? {
    let prompt = NSAlert()
    prompt.messageText = "Welcome to CraftyCannon"
    prompt.informativeText = "Choose a destination setup to get started."
    prompt.addButton(withTitle: "Zipline v4")
    prompt.addButton(withTitle: "S3-compatible")
    prompt.addButton(withTitle: "Custom")
    prompt.addButton(withTitle: "Cancel")

    activateForModalUI()
    prepareAlertWindow(prompt)
    let response = prompt.runModal()
    discardClickThroughEvents()
    switch response {
    case .alertFirstButtonReturn:
      return .zipline
    case .alertSecondButtonReturn:
      return .s3
    case .alertThirdButtonReturn:
      return .custom
    default:
      return nil
    }
  }

  private static func promptDetails(
    preset: Preset,
    profileName: String,
    backend: UploadBackend,
    endpoint: String,
    apiSecret: String,
    s3Region: String,
    s3Bucket: String,
    s3AccessKeyId: String,
    s3SecretAccessKey: String,
    s3SessionToken: String
  ) -> (
    profileName: String,
    backend: UploadBackend,
    endpoint: String,
    apiSecret: String,
    s3Region: String,
    s3Bucket: String,
    s3AccessKeyId: String,
    s3SecretAccessKey: String,
    s3SessionToken: String
  )? {
    let alert = NSAlert()
    alert.messageText = "Initial setup: \(preset.title)"
    alert.informativeText = "Enter profile settings."
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Cancel")

    let nameField = NSTextField(string: profileName)
    let endpointField = NSTextField(string: endpoint)
    let secretField = NSSecureTextField(string: apiSecret)
    let s3RegionField = NSTextField(string: s3Region)
    let s3BucketField = NSTextField(string: s3Bucket)
    let s3AccessKeyField = NSTextField(string: s3AccessKeyId)
    let s3SecretField = NSSecureTextField(string: s3SecretAccessKey)
    let s3SessionField = NSSecureTextField(string: s3SessionToken)

    nameField.placeholderString = "Profile name"
    endpointField.placeholderString = preset.defaultEndpoint
    switch backend {
    case .ziplineV4:
      secretField.placeholderString = "Authorization token"
    case .s3Compatible:
      secretField.placeholderString = ""
    }
    s3RegionField.placeholderString = "us-east-1"
    s3BucketField.placeholderString = "my-bucket"
    s3AccessKeyField.placeholderString = "Access key ID"
    s3SecretField.placeholderString = "Secret access key"
    s3SessionField.placeholderString = "Optional session token"

    let backendPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26), pullsDown: false)
    backendPopup.addItems(withTitles: ["Zipline v4", "S3-compatible"])
    switch backend {
    case .ziplineV4:
      backendPopup.selectItem(at: 0)
    case .s3Compatible:
      backendPopup.selectItem(at: 1)
    }
    backendPopup.isEnabled = (preset == .custom)

    let labels = [
      "Profile",
      "Backend",
      "Endpoint",
      "API Secret",
      "S3 Region",
      "S3 Bucket",
      "S3 Access Key",
      "S3 Secret Key",
      "S3 Session Token",
    ]
    let fields: [NSView] = [
      nameField,
      backendPopup,
      endpointField,
      secretField,
      s3RegionField,
      s3BucketField,
      s3AccessKeyField,
      s3SecretField,
      s3SessionField,
    ]

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.spacing = 8
    stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 4, right: 0)

    for (idx, labelText) in labels.enumerated() {
      let row = NSStackView()
      row.orientation = .horizontal
      row.alignment = .centerY
      row.spacing = 8

      let label = NSTextField(labelWithString: labelText)
      label.alignment = .right
      label.frame = NSRect(x: 0, y: 0, width: 70, height: 20)
      label.widthAnchor.constraint(equalToConstant: 70).isActive = true

      row.addArrangedSubview(label)
      row.addArrangedSubview(fields[idx])
      stack.addArrangedSubview(row)
    }

    alert.accessoryView = stack

    activateForModalUI()
    prepareAlertWindow(alert)
    let response = alert.runModal()
    discardClickThroughEvents()
    if response != .alertFirstButtonReturn {
      return nil
    }

    let chosenBackend: UploadBackend
    if preset == .custom {
      switch backendPopup.indexOfSelectedItem {
      case 1:
        chosenBackend = .s3Compatible
      default:
        chosenBackend = .ziplineV4
      }
    } else {
      chosenBackend = preset.defaultBackend
    }

    let normalizedName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedEndpoint = endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedSecret = secretField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedS3Region = s3RegionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedS3Bucket = s3BucketField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedS3Access = s3AccessKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedS3Secret = s3SecretField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedS3Session = s3SessionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let effectiveEndpoint = normalizedEndpoint

    if normalizedName.isEmpty || effectiveEndpoint.isEmpty {
      let err = NSAlert()
      err.messageText = "Missing required fields"
      err.informativeText = "Profile name and endpoint are required."
      err.addButton(withTitle: "OK")
      activateForModalUI()
      prepareAlertWindow(err)
      err.runModal()
      return promptDetails(
        preset: preset,
        profileName: normalizedName.isEmpty ? profileName : normalizedName,
        backend: chosenBackend,
        endpoint: effectiveEndpoint,
        apiSecret: normalizedSecret,
        s3Region: normalizedS3Region,
        s3Bucket: normalizedS3Bucket,
        s3AccessKeyId: normalizedS3Access,
        s3SecretAccessKey: normalizedS3Secret,
        s3SessionToken: normalizedS3Session
      )
    }

    if chosenBackend == .s3Compatible &&
      (normalizedS3Region.isEmpty || normalizedS3Bucket.isEmpty || normalizedS3Access.isEmpty || normalizedS3Secret.isEmpty) {
      let err = NSAlert()
      err.messageText = "Missing S3 fields"
      err.informativeText = "S3 region, bucket, access key ID, and secret access key are required for S3-compatible backend."
      err.addButton(withTitle: "OK")
      activateForModalUI()
      prepareAlertWindow(err)
      err.runModal()
      return promptDetails(
        preset: preset,
        profileName: normalizedName,
        backend: chosenBackend,
        endpoint: effectiveEndpoint,
        apiSecret: normalizedSecret,
        s3Region: normalizedS3Region,
        s3Bucket: normalizedS3Bucket,
        s3AccessKeyId: normalizedS3Access,
        s3SecretAccessKey: normalizedS3Secret,
        s3SessionToken: normalizedS3Session
      )
    }

    return (
      profileName: normalizedName,
      backend: chosenBackend,
      endpoint: effectiveEndpoint,
      apiSecret: normalizedSecret,
      s3Region: normalizedS3Region,
      s3Bucket: normalizedS3Bucket,
      s3AccessKeyId: normalizedS3Access,
      s3SecretAccessKey: normalizedS3Secret,
      s3SessionToken: normalizedS3Session
    )
  }

  private static func makeProfile(
    profileName: String,
    backend: UploadBackend,
    endpoint: String,
    s3Region: String,
    s3Bucket: String
  ) -> UploadProfile {
    if backend == .s3Compatible {
      let config = S3DestinationConfig(
        endpoint: endpoint,
        region: s3Region,
        bucket: s3Bucket
      )
      return UploadProfile(name: profileName, endpoint: endpoint, backend: backend, s3Config: config)
    }
    return UploadProfile(name: profileName, endpoint: endpoint, backend: backend)
  }

  /// Runs the network endpoint probe on a background thread while spinning a
  /// small modal progress panel, so the main thread keeps servicing events
  /// instead of freezing for the duration of the probe.
  private static func runValidationWithProgress(for profile: UploadProfile) -> Uploader.EndpointValidationResult {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 84),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    panel.title = "Validating"
    panel.level = .floating

    let label = NSTextField(labelWithString: "Validating endpoint\u{2026}")
    label.frame = NSRect(x: 20, y: 48, width: 260, height: 20)
    let spinner = NSProgressIndicator(frame: NSRect(x: 20, y: 20, width: 260, height: 20))
    spinner.style = .bar
    spinner.isIndeterminate = true
    spinner.startAnimation(nil)
    panel.contentView?.addSubview(label)
    panel.contentView?.addSubview(spinner)
    panel.center()

    var result = Uploader.EndpointValidationResult(isValid: false, message: "Validation timed out.")
    DispatchQueue.global(qos: .userInitiated).async {
      let value = Uploader.shared.validateEndpointBlocking(profile: profile)
      DispatchQueue.main.async {
        result = value
        NSApp.stopModal()
      }
    }

    NSApp.runModal(for: panel)
    panel.orderOut(nil)
    discardClickThroughEvents()
    return result
  }

  private static func validateS3OnboardingInputs(
    profile: UploadProfile,
    accessKeyId: String,
    secretAccessKey: String
  ) -> Uploader.EndpointValidationResult {
    guard let cfg = profile.s3Config else {
      return Uploader.EndpointValidationResult(isValid: false, message: "Missing S3 configuration.")
    }
    guard let endpointURL = URL(string: cfg.endpoint),
          let scheme = endpointURL.scheme?.lowercased(),
          scheme == "https",
          endpointURL.host != nil else {
      return Uploader.EndpointValidationResult(isValid: false, message: "S3 endpoint must be a valid HTTPS URL.")
    }
    if accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return Uploader.EndpointValidationResult(
        isValid: false,
        message: "S3 access key ID and secret access key are required."
      )
    }
    return Uploader.EndpointValidationResult(
      isValid: true,
      message: "S3 settings look valid."
    )
  }
}
