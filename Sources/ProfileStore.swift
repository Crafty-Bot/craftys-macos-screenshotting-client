import Foundation
import Security

private struct ProfileBundle: Codable {
  var version: Int
  var exportedAt: Date
  var activeProfileId: String?
  var profiles: [ProfileBundleEntry]
}

private struct ProfileBundleEntry: Codable {
  var id: String
  var name: String
  var endpoint: String
  var backend: UploadBackend
  var s3Config: S3DestinationConfig?
  var secondaryS3ProfileId: String?
  var apiKey: String?
  var s3AccessKeyId: String?
  var s3SecretAccessKey: String?
  var s3SessionToken: String?
}

final class ProfileStore {
  static let shared = ProfileStore()

  private let defaults = UserDefaults.standard
  private let profilesKey = "upload_profiles_v1"
  private let activeIdKey = "active_profile_id_v1"

  // Legacy keys (v0.1.0 single-profile)
  private let legacyEndpointKey = "upload_endpoint"
  private let legacyKeychainService = "com.crafty599.ferretsuploader"
  private let legacyApiKeyAccount = "upload_api_key"

  private let keychainService = "com.crafty599.craftycannon"
  private var keychainServicesForRead: [String] { [keychainService, legacyKeychainService] }

  private init() {
    migrateIfNeeded()
    restoreProfilesFromConfigBackupIfNeeded()
    persistProfilesConfigBackup(list())
    ensureActiveProfileSetIfNeeded()
  }

  func list() -> [UploadProfile] {
    guard let data = defaults.data(forKey: profilesKey) else {
      return loadProfilesConfigBackup()
    }
    guard let decoded = try? JSONDecoder().decode([UploadProfile].self, from: data) else {
      let backup = loadProfilesConfigBackup()
      if !backup.isEmpty {
        save(backup)
      }
      return backup
    }
    return decoded
  }

  func save(_ profiles: [UploadProfile]) {
    let data = (try? JSONEncoder().encode(profiles)) ?? Data()
    defaults.set(data, forKey: profilesKey)
    persistProfilesConfigBackup(profiles)
  }

  func activeProfileId() -> String? {
    defaults.string(forKey: activeIdKey)
  }

  func setActiveProfileId(_ id: String) {
    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      defaults.removeObject(forKey: activeIdKey)
    } else {
      defaults.set(trimmed, forKey: activeIdKey)
    }
  }

  func hasConfiguredProfiles() -> Bool {
    !list().isEmpty
  }

  func activeProfile() -> UploadProfile {
    let profiles = list()
    if let id = activeProfileId(), let p = profiles.first(where: { $0.id == id }) {
      return p
    }
    if let first = profiles.first {
      return first
    }

    // Intentionally neutral fallback for unconfigured installs.
    return UploadProfile(name: "Unconfigured", endpoint: "", backend: .ziplineV4)
  }

  func upsert(_ profile: UploadProfile) {
    var profiles = list()
    if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
      profiles[idx] = profile
    } else {
      profiles.append(profile)
    }
    save(profiles)

    if activeProfileId() == nil || activeProfileId()?.isEmpty == true {
      setActiveProfileId(profile.id)
      return
    }

    if let current = activeProfileId(), !profiles.contains(where: { $0.id == current }) {
      setActiveProfileId(profile.id)
    }
  }

  func remove(profileId: String) {
    var profiles = list()
    profiles.removeAll { $0.id == profileId }
    save(profiles)

    if activeProfileId() == profileId {
      setActiveProfileId(profiles.first?.id ?? "")
    }

    clearApiKey(profileId: profileId)
    clearS3Secrets(profileId: profileId)
  }

  private func readKeychainString(account: String) -> String? {
    for service in keychainServicesForRead {
      if let value = try? Keychain.getString(service: service, account: account), !value.isEmpty {
        return value
      }
    }
    return nil
  }

  private func deleteKeychainValue(service: String, account: String) {
    let delQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(delQuery as CFDictionary)
  }

  private func apiKeyAccount(profileId: String) -> String {
    "upload_api_key_\(profileId)"
  }

  private func s3AccessKeyIdAccount(profileId: String) -> String {
    "s3_access_key_id_\(profileId)"
  }

  private func s3SecretAccessKeyAccount(profileId: String) -> String {
    "s3_secret_access_key_\(profileId)"
  }

  private func s3SessionTokenAccount(profileId: String) -> String {
    "s3_session_token_\(profileId)"
  }

  func getApiKey(profileId: String) -> String? {
    let account = apiKeyAccount(profileId: profileId)
    return readKeychainString(account: account)
  }

  func setApiKey(_ value: String, profileId: String) throws {
    let account = apiKeyAccount(profileId: profileId)
    try Keychain.setString(value, service: keychainService, account: account)
  }

  func clearApiKey(profileId: String) {
    let account = apiKeyAccount(profileId: profileId)
    deleteKeychainValue(service: keychainService, account: account)
    deleteKeychainValue(service: legacyKeychainService, account: account)
  }

  func getS3AccessKeyId(profileId: String) -> String? {
    let account = s3AccessKeyIdAccount(profileId: profileId)
    return readKeychainString(account: account)
  }

  func setS3AccessKeyId(_ value: String, profileId: String) throws {
    let account = s3AccessKeyIdAccount(profileId: profileId)
    try Keychain.setString(value, service: keychainService, account: account)
  }

  func getS3SecretAccessKey(profileId: String) -> String? {
    let account = s3SecretAccessKeyAccount(profileId: profileId)
    return readKeychainString(account: account)
  }

  func setS3SecretAccessKey(_ value: String, profileId: String) throws {
    let account = s3SecretAccessKeyAccount(profileId: profileId)
    try Keychain.setString(value, service: keychainService, account: account)
  }

  func getS3SessionToken(profileId: String) -> String? {
    let account = s3SessionTokenAccount(profileId: profileId)
    return readKeychainString(account: account)
  }

  func setS3SessionToken(_ value: String, profileId: String) throws {
    let account = s3SessionTokenAccount(profileId: profileId)
    try Keychain.setString(value, service: keychainService, account: account)
  }

  func clearS3Secrets(profileId: String) {
    let accounts = [
      s3AccessKeyIdAccount(profileId: profileId),
      s3SecretAccessKeyAccount(profileId: profileId),
      s3SessionTokenAccount(profileId: profileId),
    ]
    for account in accounts {
      deleteKeychainValue(service: keychainService, account: account)
      deleteKeychainValue(service: legacyKeychainService, account: account)
    }
  }

  func exportProfiles(to url: URL, profileIds: [String]? = nil) throws {
    let profiles = list()
    let profileSet = profileIds.flatMap(Set.init) ?? Set(profiles.map(\.id))
    let filteredProfiles = profiles.filter { profileSet.contains($0.id) }
    if filteredProfiles.isEmpty {
      throw NSError(domain: "ProfileStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "No profiles selected for export."])
    }

    let entries = filteredProfiles.map { profile in
      ProfileBundleEntry(
        id: profile.id,
        name: profile.name,
        endpoint: profile.endpoint,
        backend: profile.backend,
        s3Config: profile.s3Config,
        secondaryS3ProfileId: profile.secondaryS3ProfileId,
        apiKey: nil,
        s3AccessKeyId: nil,
        s3SecretAccessKey: nil,
        s3SessionToken: nil
      )
    }

    let bundle = ProfileBundle(
      version: 1,
      exportedAt: Date(),
      activeProfileId: activeProfileId(),
      profiles: entries
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(bundle)
    try data.write(to: url, options: [.atomic])
  }

  func importProfiles(from url: URL, replaceExisting: Bool) throws -> Int {
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let bundle = try decoder.decode(ProfileBundle.self, from: data)
    var importedCount = 0

    if replaceExisting {
      clearAllProfilesAndSecrets()
    }

    for entry in bundle.profiles {
      let profile = UploadProfile(
        id: entry.id,
        name: entry.name,
        endpoint: entry.endpoint,
        backend: entry.backend,
        s3Config: entry.s3Config,
        secondaryS3ProfileId: entry.secondaryS3ProfileId
      )
      upsert(profile)
      if let apiKey = entry.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty {
        try? setApiKey(apiKey, profileId: profile.id)
      }
      if let access = entry.s3AccessKeyId?.trimmingCharacters(in: .whitespacesAndNewlines), !access.isEmpty {
        try? setS3AccessKeyId(access, profileId: profile.id)
      }
      if let secret = entry.s3SecretAccessKey?.trimmingCharacters(in: .whitespacesAndNewlines), !secret.isEmpty {
        try? setS3SecretAccessKey(secret, profileId: profile.id)
      }
      if let session = entry.s3SessionToken?.trimmingCharacters(in: .whitespacesAndNewlines), !session.isEmpty {
        try? setS3SessionToken(session, profileId: profile.id)
      }
      importedCount += 1
    }

    if let active = bundle.activeProfileId,
       list().contains(where: { $0.id == active }) {
      setActiveProfileId(active)
    } else {
      ensureActiveProfileSetIfNeeded()
    }

    return importedCount
  }

  private func clearAllProfilesAndSecrets() {
    let existing = list()
    for profile in existing {
      clearApiKey(profileId: profile.id)
      clearS3Secrets(profileId: profile.id)
    }

    save([])
    defaults.removeObject(forKey: activeIdKey)
  }

  private func ensureActiveProfileSetIfNeeded() {
    let profiles = list()
    if profiles.isEmpty {
      defaults.removeObject(forKey: activeIdKey)
      return
    }

    if let current = activeProfileId(), profiles.contains(where: { $0.id == current }) {
      return
    }

    setActiveProfileId(profiles[0].id)
  }

  private func migrateIfNeeded() {
    if defaults.data(forKey: profilesKey) != nil {
      return
    }

    if let legacyEndpoint = defaults.string(forKey: legacyEndpointKey), let _ = URL(string: legacyEndpoint) {
      let profile = UploadProfile(name: "Migrated", endpoint: legacyEndpoint)
      save([profile])
      setActiveProfileId(profile.id)

      if let legacyKey = (try? Keychain.getString(service: legacyKeychainService, account: legacyApiKeyAccount)) ?? nil {
        try? setApiKey(legacyKey, profileId: profile.id)
      }
    }
  }

  private func profileConfigPath() -> URL? {
    return try? AppSupport.profilesConfigPath()
  }

  private func loadProfilesConfigBackup() -> [UploadProfile] {
    guard let url = profileConfigPath(),
          let data = try? Data(contentsOf: url),
          let profiles = try? JSONDecoder().decode([UploadProfile].self, from: data) else {
      return []
    }
    return profiles
  }

  private func persistProfilesConfigBackup(_ profiles: [UploadProfile]) {
    guard let url = profileConfigPath() else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(profiles) else { return }
    try? data.write(to: url, options: [.atomic])
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  private func restoreProfilesFromConfigBackupIfNeeded() {
    guard defaults.object(forKey: profilesKey) == nil else { return }
    let restored = loadProfilesConfigBackup()
    guard !restored.isEmpty else { return }
    save(restored)
  }
}
