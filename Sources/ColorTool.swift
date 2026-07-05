import AppKit
import Foundation
import SwiftUI

@MainActor
final class ColorToolViewModel: ObservableObject {
  @Published var color: NSColor = .systemRed
  @Published var lastPickSource: String = "Palette"

  func pickFromScreen() {
    let sampler = NSColorSampler()
    sampler.show { [weak self] picked in
      guard let picked else { return }
      DispatchQueue.main.async {
        self?.color = picked
        self?.lastPickSource = "Screen"
      }
    }
  }

  func copy(_ s: String) {
    ClipboardHelper.copyString(s)
    Notifier.shared.notify(title: "Copied", body: s)
  }
}

struct ColorToolView: View {
  @StateObject private var vm = ColorToolViewModel()

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Color")
            .font(.headline)
          HStack(spacing: 10) {
            NSColorWellView(color: $vm.color)
              .frame(width: 52, height: 28)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .fill(Color(nsColor: vm.color))
              .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                  .stroke(Color.black.opacity(0.18), lineWidth: 1)
              )
              .frame(width: 56, height: 28)

            Button("Pick From Screen") { vm.pickFromScreen() }
              .buttonStyle(.bordered)

            Spacer()
          }
        }
      }

      Divider()

      valueRow(label: "HEX (RGB)", value: vm.color.hexRGB()) {
        vm.copy(vm.color.hexRGB())
      }

      valueRow(label: "HEX (RGBA)", value: vm.color.hexRGBA()) {
        vm.copy(vm.color.hexRGBA())
      }

      valueRow(label: "RGBA", value: vm.color.rgbaString()) {
        vm.copy(vm.color.rgbaString())
      }

      Spacer()
        .frame(minHeight: 0)

      Text("Source: \(vm.lastPickSource)")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding(16)
  }

  private func valueRow(label: String, value: String, onCopy: @escaping () -> Void) -> some View {
    HStack(spacing: 10) {
      Text(label)
        .font(.system(size: 12, weight: .semibold))
        .frame(width: 92, alignment: .leading)
      TextField("", text: .constant(value))
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 12, design: .monospaced))
        .disabled(true)
      Button("Copy") { onCopy() }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
  }
}

