import AppKit
import CryptoKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class HashCheckerToolViewModel: ObservableObject {
  @Published var fileURL: URL?
  @Published var textInput: String = ""
  @Published var expectedHash: String = ""

  @Published var isComputing = false
  @Published var md5Hex: String = ""
  @Published var sha1Hex: String = ""
  @Published var sha256Hex: String = ""
  @Published var errorText: String?

  private var jobToken: String = ""

  func chooseFile() {
    let panel = NSOpenPanel()
    panel.title = "Choose File"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [UTType.data]

    panel.begin { resp in
      guard resp == .OK, let url = panel.url else { return }
      DispatchQueue.main.async {
        self.fileURL = url
        self.recompute()
      }
    }
  }

  func clearFile() {
    fileURL = nil
    recompute()
  }

  func recompute() {
    errorText = nil
    md5Hex = ""
    sha1Hex = ""
    sha256Hex = ""

    let trimmedText = textInput
    let fileURL = self.fileURL

    let hasFile = (fileURL != nil)
    let hasText = !trimmedText.isEmpty
    guard hasFile || hasText else { return }

    let token = UUID().uuidString
    jobToken = token
    isComputing = true

    Task.detached(priority: .userInitiated) {
      do {
        let result: (md5: String, sha1: String, sha256: String)
        if let fileURL {
          result = try Self.hashFile(url: fileURL)
        } else {
          let data = Data(trimmedText.utf8)
          result = Self.hashData(data)
        }

        await MainActor.run {
          guard self.jobToken == token else { return }
          self.isComputing = false
          self.md5Hex = result.md5
          self.sha1Hex = result.sha1
          self.sha256Hex = result.sha256
        }
      } catch {
        await MainActor.run {
          guard self.jobToken == token else { return }
          self.isComputing = false
          self.errorText = error.localizedDescription
        }
      }
    }
  }

  func copy(_ s: String) {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    ClipboardHelper.copyString(trimmed)
    Notifier.shared.notify(title: "Copied", body: trimmed)
  }

  func expectedMatchesAny() -> String? {
    let exp = expectedHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !exp.isEmpty else { return nil }
    if exp == md5Hex.lowercased() { return "Matches MD5" }
    if exp == sha1Hex.lowercased() { return "Matches SHA-1" }
    if exp == sha256Hex.lowercased() { return "Matches SHA-256" }
    return "No match"
  }

  nonisolated private static func hashData(_ data: Data) -> (md5: String, sha1: String, sha256: String) {
    let md5 = Data(Insecure.MD5.hash(data: data)).map { String(format: "%02x", $0) }.joined()
    let sha1 = Data(Insecure.SHA1.hash(data: data)).map { String(format: "%02x", $0) }.joined()
    let sha256 = Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined()
    return (md5, sha1, sha256)
  }

  nonisolated private static func hashFile(url: URL) throws -> (md5: String, sha1: String, sha256: String) {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var md5 = Insecure.MD5()
    var sha1 = Insecure.SHA1()
    var sha256 = SHA256()

    while true {
      let chunk = try handle.read(upToCount: 1024 * 1024)
      guard let chunk, !chunk.isEmpty else { break }
      md5.update(data: chunk)
      sha1.update(data: chunk)
      sha256.update(data: chunk)
    }

    let md5Hex = Data(md5.finalize()).map { String(format: "%02x", $0) }.joined()
    let sha1Hex = Data(sha1.finalize()).map { String(format: "%02x", $0) }.joined()
    let sha256Hex = Data(sha256.finalize()).map { String(format: "%02x", $0) }.joined()
    return (md5Hex, sha1Hex, sha256Hex)
  }
}

struct HashCheckerToolView: View {
  @StateObject private var vm = HashCheckerToolViewModel()

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Hash Checker")
          .font(.headline)
        Text("Compute common hashes for a file or text input.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Divider()

      HStack(spacing: 8) {
        Button("Choose File...") { vm.chooseFile() }
          .buttonStyle(.bordered)
        Button("Clear File") { vm.clearFile() }
          .buttonStyle(.bordered)
          .disabled(vm.fileURL == nil)
        Spacer()
        if vm.isComputing {
          ProgressView()
            .controlSize(.small)
        }
      }

      if let url = vm.fileURL {
        Text(url.path)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Or hash this text")
          .font(.system(size: 12, weight: .semibold))
        TextEditor(text: $vm.textInput)
          .font(.system(size: 12, design: .monospaced))
          .frame(minHeight: 90)
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .stroke(Color.gray.opacity(0.25), lineWidth: 1)
          )
          .onChange(of: vm.textInput) { _ in
            if vm.fileURL == nil {
              vm.recompute()
            }
          }
      }

      Divider()

      VStack(alignment: .leading, spacing: 10) {
        hashRow("MD5", vm.md5Hex) { vm.copy(vm.md5Hex) }
        hashRow("SHA-1", vm.sha1Hex) { vm.copy(vm.sha1Hex) }
        hashRow("SHA-256", vm.sha256Hex) { vm.copy(vm.sha256Hex) }
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Expected hash (optional)")
          .font(.system(size: 12, weight: .semibold))
        TextField("Paste expected hash to compare", text: $vm.expectedHash)
          .textFieldStyle(.roundedBorder)

        if let match = vm.expectedMatchesAny() {
          Text(match)
            .font(.system(size: 12))
            .foregroundStyle(match == "No match" ? .red : .secondary)
        }
      }

      if let err = vm.errorText {
        Text(err)
          .foregroundStyle(.red)
          .font(.system(size: 12))
      }

      Spacer()
        .frame(minHeight: 0)
    }
    .padding(16)
    .onChange(of: vm.fileURL) { _ in vm.recompute() }
    .onAppear { vm.recompute() }
  }

  private func hashRow(_ label: String, _ value: String, onCopy: @escaping () -> Void) -> some View {
    HStack(spacing: 10) {
      Text(label)
        .font(.system(size: 12, weight: .semibold))
        .frame(width: 70, alignment: .leading)
      TextField("", text: .constant(value))
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 11, design: .monospaced))
        .disabled(true)
      Button("Copy") { onCopy() }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(value.isEmpty)
    }
  }
}
