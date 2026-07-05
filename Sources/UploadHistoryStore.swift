import Foundation

extension Notification.Name {
  static let uploadHistoryDidChange = Notification.Name("uploadHistoryDidChange")
}

protocol OCRHistoryStoring: AnyObject {
  func snapshot() -> [UploadRecord]
  func record(id: String) -> UploadRecord?
  func addRecordSync(_ record: UploadRecord)
  func updateRecordSync(id: String, _ mutate: (inout UploadRecord) -> Void)
  func mutateRecordsSync(_ mutate: (inout [UploadRecord]) -> Void)
}

final class UploadHistoryStore {
  static let shared = UploadHistoryStore()

  private(set) var records: [UploadRecord] = []
  private let queue = DispatchQueue(label: "com.crafty599.craftycannon.history")

  private init() {
    load()
  }

  func load() {
    queue.sync {
      do {
        let path = try AppSupport.historyPath()
        let data = try Data(contentsOf: path)
        records = try JSONDecoder().decode([UploadRecord].self, from: data)
      } catch {
        records = []
      }
    }
  }

  private func persistLocked() {
    do {
      let path = try AppSupport.historyPath()
      let data = try JSONEncoder().encode(records)
      try data.write(to: path, options: [.atomic])
      // History includes OCR text of uploaded screenshots; keep it owner-only.
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    } catch {
      // ignore
    }
  }

  private func notifyChanged() {
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .uploadHistoryDidChange, object: nil)
    }
  }

  func addRecord(_ record: UploadRecord) {
    queue.async {
      self.records.insert(record, at: 0)
      self.persistLocked()
      self.notifyChanged()
    }
  }

  func addRecordSync(_ record: UploadRecord) {
    queue.sync {
      self.records.insert(record, at: 0)
      self.persistLocked()
    }
    notifyChanged()
  }

  func updateRecord(id: String, _ mutate: @escaping (inout UploadRecord) -> Void) {
    queue.async {
      guard let idx = self.records.firstIndex(where: { $0.id == id }) else { return }
      var r = self.records[idx]
      mutate(&r)
      self.records[idx] = r
      self.persistLocked()
      self.notifyChanged()
    }
  }

  func updateRecordSync(id: String, _ mutate: (inout UploadRecord) -> Void) {
    var didChange = false
    queue.sync {
      guard let idx = self.records.firstIndex(where: { $0.id == id }) else { return }
      var r = self.records[idx]
      mutate(&r)
      self.records[idx] = r
      self.persistLocked()
      didChange = true
    }
    if didChange {
      notifyChanged()
    }
  }

  func mutateRecordsSync(_ mutate: (inout [UploadRecord]) -> Void) {
    queue.sync {
      mutate(&self.records)
      self.persistLocked()
    }
    notifyChanged()
  }

  func record(id: String) -> UploadRecord? {
    queue.sync {
      records.first(where: { $0.id == id })
    }
  }

  func snapshot() -> [UploadRecord] {
    queue.sync { records }
  }

  func removeRecord(id: String) {
    queue.async {
      self.records.removeAll { $0.id == id }
      self.persistLocked()
      self.notifyChanged()
    }
  }
}

extension UploadHistoryStore: OCRHistoryStoring {}
