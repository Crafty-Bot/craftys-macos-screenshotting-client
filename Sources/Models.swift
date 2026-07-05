import Foundation

enum UploadBackend: String, Codable {
  case ziplineV4
  case s3Compatible

  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    let raw = try c.decode(String.self)
    switch raw {
    case "ziplineV4":
      self = .ziplineV4
    case "s3Compatible":
      self = .s3Compatible
    default:
      self = .ziplineV4
    }
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    try c.encode(rawValue)
  }
}

struct S3DestinationConfig: Codable, Equatable {
  var endpoint: String
  var region: String
  var bucket: String
  var keyPrefix: String
  var forcePathStyle: Bool
  var publicBaseURL: String
  var useSignedGetURL: Bool
  var defaultGetExpirySeconds: Int

  init(
    endpoint: String = "",
    region: String = "us-east-1",
    bucket: String = "",
    keyPrefix: String = "",
    forcePathStyle: Bool = false,
    publicBaseURL: String = "",
    useSignedGetURL: Bool = false,
    defaultGetExpirySeconds: Int = 3600
  ) {
    self.endpoint = endpoint
    self.region = region
    self.bucket = bucket
    self.keyPrefix = keyPrefix
    self.forcePathStyle = forcePathStyle
    self.publicBaseURL = publicBaseURL
    self.useSignedGetURL = useSignedGetURL
    self.defaultGetExpirySeconds = max(60, min(7 * 24 * 60 * 60, defaultGetExpirySeconds))
  }
}

struct UploadProfile: Codable, Equatable {
  var id: String
  var name: String
  var endpoint: String
  var backend: UploadBackend
  var s3Config: S3DestinationConfig?
  var secondaryS3ProfileId: String?

  init(
    id: String = UUID().uuidString,
    name: String,
    endpoint: String,
    backend: UploadBackend = .ziplineV4,
    s3Config: S3DestinationConfig? = nil,
    secondaryS3ProfileId: String? = nil
  ) {
    self.id = id
    self.name = name
    self.endpoint = endpoint
    self.backend = backend
    self.s3Config = s3Config
    self.secondaryS3ProfileId = secondaryS3ProfileId
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, endpoint, backend, s3Config, secondaryS3ProfileId
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
    backend = try c.decodeIfPresent(UploadBackend.self, forKey: .backend) ?? .ziplineV4
    s3Config = try c.decodeIfPresent(S3DestinationConfig.self, forKey: .s3Config)
    secondaryS3ProfileId = try c.decodeIfPresent(String.self, forKey: .secondaryS3ProfileId)
  }
}

enum UploadStatus: String, Codable {
  case pending
  case uploading
  case uploaded
  case failed
}

enum UploadKind: String, Codable {
  case image
  case file
}

enum UploadSourceKind: String, Codable {
  case capture
  case clipboardImage
  case clipboardFileURL
  case clipboardFolderURL
  case clipboardRemoteURL
  case clipboardText
  case manualFile
  case manualFolderBatch
  case manualRemoteURL
  case manualText
  case watchFolder
  case reupload
}

enum UploadOperationKind: String, Codable {
  case imageUpload
  case fileUpload
  case textUpload
  case urlShorten
  case folderBatch
  case watchFolder
}

enum SecondaryUploadStatus: String, Codable {
  case pending
  case uploaded
  case failed
  case skipped
}

enum OCRIndexStatus: String, Codable {
  case disabled
  case pending
  case indexed
  case failed
  case missingFile
  case skipped
}

enum UploadRedactionPolicy: String, Codable, CaseIterable {
  case off
  case askBeforeUpload
  case autoRedact

  var displayName: String {
    switch self {
    case .off: return "Off"
    case .askBeforeUpload: return "Ask before upload"
    case .autoRedact: return "Auto-redact"
    }
  }
}

enum SmartRedactionRenderMode: String, Codable, CaseIterable, Identifiable {
  case pixelate
  case blackBox

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .pixelate: return "Pixelate"
    case .blackBox: return "Black box"
    }
  }
}

struct UploadRecord: Codable, Equatable {
  var id: String
  var createdAt: Date
  var profileId: String
  var localFilePath: String
  var status: UploadStatus
  var url: String?
  var error: String?
  // Optional fields for newer records (kept optional for backward compatibility).
  var kind: UploadKind?
  var remotePath: String?
  var expiresAt: Date?
  var managedLocalCopy: Bool?
  var sourceKind: UploadSourceKind?
  var batchId: String?
  var shortenedURL: String?
  var operationKind: UploadOperationKind?
  var secondaryUploadStatus: SecondaryUploadStatus?
  var secondaryProfileId: String?
  var secondaryURL: String?
  var secondaryRemotePath: String?
  var secondaryCompletedAt: Date?
  var secondaryError: String?
  var ocrStatus: OCRIndexStatus?
  var ocrText: String?
  var ocrEngine: String?
  var ocrEngineVersion: String?
  var ocrIndexedAt: Date?
  var ocrFileSize: Int64?
  var ocrFileModifiedAt: Date?
  var ocrError: String?
  var ocrRetryCount: Int?

  init(id: String = UUID().uuidString,
       createdAt: Date = Date(),
       profileId: String,
       localFilePath: String,
       status: UploadStatus = .pending,
       url: String? = nil,
       error: String? = nil,
       kind: UploadKind? = nil,
       remotePath: String? = nil,
       expiresAt: Date? = nil,
       managedLocalCopy: Bool? = nil,
       sourceKind: UploadSourceKind? = nil,
       batchId: String? = nil,
       shortenedURL: String? = nil,
       operationKind: UploadOperationKind? = nil,
       secondaryUploadStatus: SecondaryUploadStatus? = nil,
       secondaryProfileId: String? = nil,
       secondaryURL: String? = nil,
       secondaryRemotePath: String? = nil,
       secondaryCompletedAt: Date? = nil,
       secondaryError: String? = nil,
       ocrStatus: OCRIndexStatus? = nil,
       ocrText: String? = nil,
       ocrEngine: String? = nil,
       ocrEngineVersion: String? = nil,
       ocrIndexedAt: Date? = nil,
       ocrFileSize: Int64? = nil,
       ocrFileModifiedAt: Date? = nil,
       ocrError: String? = nil,
       ocrRetryCount: Int? = nil) {
    self.id = id
    self.createdAt = createdAt
    self.profileId = profileId
    self.localFilePath = localFilePath
    self.status = status
    self.url = url
    self.error = error
    self.kind = kind
    self.remotePath = remotePath
    self.expiresAt = expiresAt
    self.managedLocalCopy = managedLocalCopy
    self.sourceKind = sourceKind
    self.batchId = batchId
    self.shortenedURL = shortenedURL
    self.operationKind = operationKind
    self.secondaryUploadStatus = secondaryUploadStatus
    self.secondaryProfileId = secondaryProfileId
    self.secondaryURL = secondaryURL
    self.secondaryRemotePath = secondaryRemotePath
    self.secondaryCompletedAt = secondaryCompletedAt
    self.secondaryError = secondaryError
    self.ocrStatus = ocrStatus
    self.ocrText = ocrText
    self.ocrEngine = ocrEngine
    self.ocrEngineVersion = ocrEngineVersion
    self.ocrIndexedAt = ocrIndexedAt
    self.ocrFileSize = ocrFileSize
    self.ocrFileModifiedAt = ocrFileModifiedAt
    self.ocrError = ocrError
    self.ocrRetryCount = ocrRetryCount
  }

  private enum CodingKeys: String, CodingKey {
    case id, createdAt, profileId, localFilePath, status, url, error
    case kind, remotePath, expiresAt, managedLocalCopy
    case sourceKind, batchId, shortenedURL, operationKind
    case secondaryUploadStatus, secondaryProfileId, secondaryURL, secondaryRemotePath
    case secondaryCompletedAt, secondaryError
    case ocrStatus, ocrText, ocrEngine, ocrEngineVersion, ocrIndexedAt
    case ocrFileSize, ocrFileModifiedAt, ocrError, ocrRetryCount
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
    createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    profileId = try c.decodeIfPresent(String.self, forKey: .profileId) ?? ""
    localFilePath = try c.decodeIfPresent(String.self, forKey: .localFilePath) ?? ""
    status = try c.decodeIfPresent(UploadStatus.self, forKey: .status) ?? .pending
    url = try c.decodeIfPresent(String.self, forKey: .url)
    error = try c.decodeIfPresent(String.self, forKey: .error)
    kind = try c.decodeIfPresent(UploadKind.self, forKey: .kind)
    remotePath = try c.decodeIfPresent(String.self, forKey: .remotePath)
    expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
    managedLocalCopy = try c.decodeIfPresent(Bool.self, forKey: .managedLocalCopy)
    sourceKind = try c.decodeIfPresent(UploadSourceKind.self, forKey: .sourceKind)
    batchId = try c.decodeIfPresent(String.self, forKey: .batchId)
    shortenedURL = try c.decodeIfPresent(String.self, forKey: .shortenedURL)
    operationKind = try c.decodeIfPresent(UploadOperationKind.self, forKey: .operationKind)
    secondaryUploadStatus = try c.decodeIfPresent(SecondaryUploadStatus.self, forKey: .secondaryUploadStatus)
    secondaryProfileId = try c.decodeIfPresent(String.self, forKey: .secondaryProfileId)
    secondaryURL = try c.decodeIfPresent(String.self, forKey: .secondaryURL)
    secondaryRemotePath = try c.decodeIfPresent(String.self, forKey: .secondaryRemotePath)
    secondaryCompletedAt = try c.decodeIfPresent(Date.self, forKey: .secondaryCompletedAt)
    secondaryError = try c.decodeIfPresent(String.self, forKey: .secondaryError)
    ocrStatus = try c.decodeIfPresent(OCRIndexStatus.self, forKey: .ocrStatus)
    ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText)
    ocrEngine = try c.decodeIfPresent(String.self, forKey: .ocrEngine)
    ocrEngineVersion = try c.decodeIfPresent(String.self, forKey: .ocrEngineVersion)
    ocrIndexedAt = try c.decodeIfPresent(Date.self, forKey: .ocrIndexedAt)
    ocrFileSize = try c.decodeIfPresent(Int64.self, forKey: .ocrFileSize)
    ocrFileModifiedAt = try c.decodeIfPresent(Date.self, forKey: .ocrFileModifiedAt)
    ocrError = try c.decodeIfPresent(String.self, forKey: .ocrError)
    ocrRetryCount = try c.decodeIfPresent(Int.self, forKey: .ocrRetryCount)
  }

  var isImageRecord: Bool {
    (kind ?? .image) == .image
  }

  mutating func clearOCRMetadata(status: OCRIndexStatus? = nil) {
    ocrStatus = status
    ocrText = nil
    ocrEngine = nil
    ocrEngineVersion = nil
    ocrIndexedAt = nil
    ocrFileSize = nil
    ocrFileModifiedAt = nil
    ocrError = nil
    ocrRetryCount = nil
  }
}
