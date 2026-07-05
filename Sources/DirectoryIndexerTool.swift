import AppKit
import Foundation
import SwiftUI

@MainActor
final class DirectoryIndexerToolViewModel: ObservableObject {
  @Published var folderURL: URL?
  @Published var includeSubdirectories: Bool = true

  @Published var isWorking = false
  @Published var outputFileURL: URL?
  @Published var outputText: String = ""
  @Published var errorText: String?

  private var jobToken: String = ""

  func chooseFolder() {
    let panel = NSOpenPanel()
    panel.title = "Choose Folder"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false

    panel.begin { resp in
      guard resp == .OK, let url = panel.url else { return }
      DispatchQueue.main.async {
        self.folderURL = url
      }
    }
  }

  func generate() {
    errorText = nil
    outputText = ""
    outputFileURL = nil

    guard let folderURL else { return }

    let token = UUID().uuidString
    jobToken = token
    isWorking = true

    let include = includeSubdirectories

    Task.detached(priority: .userInitiated) {
      do {
        let out = try FolderIndexer.shared.createIndexFile(for: folderURL, includeSubdirectories: include)
        let text = (try? String(contentsOf: out, encoding: .utf8)) ?? ""

        await MainActor.run {
          guard self.jobToken == token else { return }
          self.isWorking = false
          self.outputFileURL = out
          self.outputText = text
          self.errorText = nil
        }
      } catch {
        await MainActor.run {
          guard self.jobToken == token else { return }
          self.isWorking = false
          self.errorText = error.localizedDescription
        }
      }
    }
  }

  func copyText() {
    let trimmed = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    ClipboardHelper.copyString(trimmed)
    Notifier.shared.notify(title: "Copied", body: "Folder index text")
  }

  func revealFile() {
    guard let outputFileURL else { return }
    NSWorkspace.shared.activateFileViewerSelecting([outputFileURL])
  }
}

struct DirectoryIndexerToolView: View {
  @StateObject private var vm = DirectoryIndexerToolViewModel()

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Directory Indexer")
          .font(.headline)
        Text("Generate a text index of a folder (optionally including subdirectories).")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Divider()

      HStack(spacing: 8) {
        Button("Choose Folder...") { vm.chooseFolder() }
          .buttonStyle(.bordered)
        Toggle("Include subdirectories", isOn: $vm.includeSubdirectories)
          .toggleStyle(.checkbox)
        Spacer()
        if vm.isWorking {
          ProgressView()
            .controlSize(.small)
        }
      }

      if let url = vm.folderURL {
        Text(url.path)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      HStack(spacing: 8) {
        Button("Generate Index") { vm.generate() }
          .buttonStyle(.borderedProminent)
          .disabled(vm.folderURL == nil || vm.isWorking)
        Button("Copy Text") { vm.copyText() }
          .buttonStyle(.bordered)
          .disabled(vm.outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button("Reveal File") { vm.revealFile() }
          .buttonStyle(.bordered)
          .disabled(vm.outputFileURL == nil)
        Spacer()
      }

      if let err = vm.errorText {
        Text(err)
          .foregroundStyle(.red)
          .font(.system(size: 12))
      }

      TextEditor(text: $vm.outputText)
        .font(.system(size: 12, design: .monospaced))
        .frame(minHeight: 220)
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )

      Spacer()
        .frame(minHeight: 0)
    }
    .padding(16)
  }
}

