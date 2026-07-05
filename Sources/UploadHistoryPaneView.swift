import AppKit
import SwiftUI

private enum UploadHistoryLayout {
  static let rowSpacing = 6.0
  static let headerHeight = 32.0
  static let statusWidth = 122.0
  static let progressWidth = 82.0
  static let speedWidth = 80.0
  static let elapsedWidth = 80.0
  static let remainingWidth = 90.0
}

struct UploadHistoryPaneView: View {
  @ObservedObject var vm: UploadHistoryViewModel

  var body: some View {
    HSplitView {
      leftTablePane
        .frame(minWidth: 460, idealWidth: 680, maxWidth: .infinity)

      rightPreviewPane
        .frame(minWidth: 380, idealWidth: 520, maxWidth: .infinity)
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var leftTablePane: some View {
    VStack(spacing: 0) {
      VStack(spacing: UploadHistoryLayout.rowSpacing) {
        HStack(spacing: 8) {
          TextField("Filter by filename, URL, profile, status, or OCR text", text: $vm.historySearchText)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .help("Filter upload history rows, including locally indexed OCR text")
          if !vm.historySearchText.isEmpty {
            Button("Clear", action: { vm.historySearchText = "" })
              .buttonStyle(.plain)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)

        Picker("Filter", selection: $vm.historyStatusFilter) {
          ForEach(UploadHistoryStatusFilter.allCases) { filter in
            Text(filter.title).tag(filter)
          }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 8)

        Divider()
      }

      // ShareX-like dense table headers including placeholder telemetry columns.
      HistoryRowColumns(
        filename: "Filename",
        status: "Status",
        progress: "Progress",
        speed: "Speed",
        elapsed: "Elapsed",
        remaining: "Remaining",
        url: "URL",
        isHeader: true
      )
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(Color(nsColor: .controlBackgroundColor))
      .frame(height: UploadHistoryLayout.headerHeight)

      Divider()

      if vm.filteredRecords.isEmpty {
        VStack(spacing: 6) {
          Spacer()
          Text(vm.records.isEmpty ? "No uploads yet" : "No results")
            .font(.headline)
          Text(vm.records.isEmpty ? "History will populate after uploads complete." : "Try clearing the status or text filter.")
            .foregroundStyle(.secondary)
          Spacer()
        }
      } else {
        List(selection: $vm.selectedId) {
          ForEach(vm.filteredRecords) { record in
            HistoryRowColumns(
              filename: vm.filename(for: record),
              status: vm.statusColumn(for: record),
              progress: vm.progressColumn(for: record),
              speed: vm.speedColumn(for: record),
              elapsed: vm.elapsedColumn(for: record),
              remaining: vm.remainingColumn(for: record),
              url: vm.urlColumn(for: record),
              isHeader: false
            )
            .tag(record.id)
          }
        }
        .listStyle(.plain)
      }
    }
  }

  private var rightPreviewPane: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let record = vm.selectedRecord {
        HStack(alignment: .center) {
          Text(vm.filename(for: record))
            .font(.headline)
            .lineLimit(1)

          Spacer()

          Text(vm.statusText(record.status).uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(nsColor: vm.statusColor(record.status)))
            .clipShape(Capsule())
        }

        Divider()

        ZStack {
          RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: .controlBackgroundColor))
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.gray.opacity(0.30), lineWidth: 1)
          if let image = vm.previewImage(for: record) {
            Image(nsImage: image)
              .resizable()
              .scaledToFit()
              .padding(8)
          } else {
            Text("No preview available")
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        Text(vm.infoLine(for: record))
          .font(.system(size: 12))
          .foregroundStyle(.secondary)

        Text(vm.ocrStatusLine(for: record))
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)

        if let ocrMatch = vm.ocrMatchLine(for: record) {
          Text(ocrMatch)
            .font(.system(size: 11))
            .foregroundStyle(Color(nsColor: .controlAccentColor))
            .lineLimit(3)
            .textSelection(.enabled)
        }

        Text(vm.urlLine(for: record))
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(record.error == nil ? Color.secondary : Color.red)
          .lineLimit(2)
          .textSelection(.enabled)

        Divider()

        HStack(spacing: 8) {
          Button("Copy") { vm.copySelectedURL() }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!vm.canCopyURL)

          Button("Open") { vm.openSelectedURL() }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!vm.canOpenURL)

          Button("Shorten") { vm.shortenSelectedURL() }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!vm.canShortenURL)

          Button("Finder") { vm.showSelectedInFinder() }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!vm.canShowInFinder)

          Button("Reupload") { vm.reuploadSelected() }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!vm.canReupload)

          Button("Edit") { vm.editSelected() }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!vm.canEdit)

          Button("Delete") { vm.deleteSelectedManagedCopy() }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!vm.canDeleteManagedCopy)
        }
      } else {
        Spacer()
        Text(vm.records.isEmpty ? "No uploads yet" : "No results")
          .font(.title3.weight(.semibold))
        Text(vm.records.isEmpty
          ? "History will populate after uploads complete."
          : "Try changing filters or opening a new upload.")
          .foregroundStyle(.secondary)
        Spacer()
      }
    }
    .padding(12)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

private struct HistoryRowColumns: View {
  let filename: String
  let status: String
  let progress: String
  let speed: String
  let elapsed: String
  let remaining: String
  let url: String
  let isHeader: Bool

  var body: some View {
    HStack(spacing: 8) {
      Text(filename)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(status)
        .frame(width: UploadHistoryLayout.statusWidth, alignment: .leading)
        .monospacedDigit()
      Text(progress)
        .frame(width: UploadHistoryLayout.progressWidth, alignment: .leading)
        .monospacedDigit()
      Text(speed)
        .frame(width: UploadHistoryLayout.speedWidth, alignment: .leading)
        .monospacedDigit()
      Text(elapsed)
        .frame(width: UploadHistoryLayout.elapsedWidth, alignment: .leading)
        .monospacedDigit()
      Text(remaining)
        .frame(width: UploadHistoryLayout.remainingWidth, alignment: .leading)
        .monospacedDigit()
      Text(url)
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.system(size: 11, design: .monospaced))
    }
    .font(isHeader ? .system(size: 11, weight: .semibold) : .system(size: 11))
    .lineLimit(1)
  }
}
