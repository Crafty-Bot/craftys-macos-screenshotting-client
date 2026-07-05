import Foundation

final class Settings {
  static let shared = Settings()
  private init() {}

  // Active profile shortcuts.
  var activeProfile: UploadProfile {
    ProfileStore.shared.activeProfile()
  }

  var activeProfileId: String? {
    ProfileStore.shared.activeProfileId()
  }

  func setActiveProfileId(_ id: String) {
    ProfileStore.shared.setActiveProfileId(id)
  }

  func profiles() -> [UploadProfile] {
    ProfileStore.shared.list()
  }

  func upsertProfile(_ p: UploadProfile) {
    ProfileStore.shared.upsert(p)
  }

  func removeProfile(id: String) {
    ProfileStore.shared.remove(profileId: id)
  }

  func getActiveApiKey() -> String? {
    ProfileStore.shared.getApiKey(profileId: activeProfile.id)
  }

  func setActiveApiKey(_ value: String) throws {
    try ProfileStore.shared.setApiKey(value, profileId: activeProfile.id)
  }

  func getApiKey(profileId: String) -> String? {
    ProfileStore.shared.getApiKey(profileId: profileId)
  }

  func setApiKey(_ value: String, profileId: String) throws {
    try ProfileStore.shared.setApiKey(value, profileId: profileId)
  }

  func clearApiKey(profileId: String) {
    ProfileStore.shared.clearApiKey(profileId: profileId)
  }

  func getS3AccessKeyId(profileId: String) -> String? {
    ProfileStore.shared.getS3AccessKeyId(profileId: profileId)
  }

  func setS3AccessKeyId(_ value: String, profileId: String) throws {
    try ProfileStore.shared.setS3AccessKeyId(value, profileId: profileId)
  }

  func getS3SecretAccessKey(profileId: String) -> String? {
    ProfileStore.shared.getS3SecretAccessKey(profileId: profileId)
  }

  func setS3SecretAccessKey(_ value: String, profileId: String) throws {
    try ProfileStore.shared.setS3SecretAccessKey(value, profileId: profileId)
  }

  func getS3SessionToken(profileId: String) -> String? {
    ProfileStore.shared.getS3SessionToken(profileId: profileId)
  }

  func setS3SessionToken(_ value: String, profileId: String) throws {
    try ProfileStore.shared.setS3SessionToken(value, profileId: profileId)
  }

  func clearS3Secrets(profileId: String) {
    ProfileStore.shared.clearS3Secrets(profileId: profileId)
  }
}
