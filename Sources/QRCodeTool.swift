import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class QRCodeToolViewModel: ObservableObject {
  @Published var inputText: String = ""
  @Published var qrImage: NSImage?
  @Published var decodedText: String = ""
  @Published var errorText: String?

  func regenerate() {
    let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      qrImage = nil
      return
    }

    let data = Data(trimmed.utf8)
    let filter = CIFilter.qrCodeGenerator()
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let out = filter.outputImage else {
      qrImage = nil
      return
    }

    let scale: CGFloat = 12
    let scaled = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let rep = NSCIImageRep(ciImage: scaled)
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    qrImage = image
  }

  func copyQRCodeImage() {
    guard let qrImage else { return }
    ClipboardHelper.copyImage(qrImage)
    Notifier.shared.notify(title: "Copied", body: "QR code image")
  }

  func saveQRCodePNG() {
    guard let qrImage else { return }
    let panel = NSSavePanel()
    panel.title = "Save QR Code"
    panel.nameFieldStringValue = "qrcode.png"
    panel.allowedContentTypes = [UTType.png]
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false

    panel.begin { resp in
      guard resp == .OK, let url = panel.url else { return }
      do {
        guard let data = Self.pngData(from: qrImage) else {
          throw NSError(domain: "QRCodeTool", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
        }
        try data.write(to: url, options: [.atomic])
        Notifier.shared.notify(title: "Saved", body: url.lastPathComponent)
      } catch {
        Notifier.shared.notify(title: "Save failed", body: error.localizedDescription)
      }
    }
  }

  func decodeFromClipboardImage() {
    errorText = nil
    decodedText = ""

    let pb = NSPasteboard.general
    let ci: CIImage?
    if let png = pb.data(forType: .png) {
      ci = CIImage(data: png)
    } else if let tiff = pb.data(forType: .tiff) {
      ci = CIImage(data: tiff)
    } else {
      ci = nil
    }

    guard let ci else {
      errorText = "Clipboard has no image"
      return
    }
    decode(ciImage: ci)
  }

  func decodeFromImageFile() {
    errorText = nil
    decodedText = ""

    let panel = NSOpenPanel()
    panel.title = "Choose Image"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [UTType.image]

    panel.begin { resp in
      guard resp == .OK, let url = panel.url else { return }
      let ci = CIImage(contentsOf: url)
      guard let ci else {
        DispatchQueue.main.async {
          self.errorText = "Failed to load image"
        }
        return
      }
      DispatchQueue.main.async {
        self.decode(ciImage: ci)
      }
    }
  }

  func copyDecodedText() {
    let trimmed = decodedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    ClipboardHelper.copyString(trimmed)
    Notifier.shared.notify(title: "Copied", body: "Decoded text")
  }

  private func decode(ciImage: CIImage) {
    let opts: [String: Any] = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
    let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: opts)
    let features = (detector?.features(in: ciImage) as? [CIQRCodeFeature]) ?? []
    let messages = features.compactMap { $0.messageString }.filter { !$0.isEmpty }

    if messages.isEmpty {
      errorText = "No QR code found"
      decodedText = ""
      return
    }

    decodedText = messages.joined(separator: "\n")
    errorText = nil
  }

  private static func pngData(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
      return nil
    }
    return rep.representation(using: .png, properties: [:])
  }
}

struct QRCodeToolView: View {
  @StateObject private var vm = QRCodeToolViewModel()

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text("QR Code")
          .font(.headline)
        Text("Generate and decode QR codes from text or images.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Divider()

      VStack(alignment: .leading, spacing: 8) {
        Text("Generate")
          .font(.system(size: 12, weight: .semibold))
        TextField("Text or URL", text: $vm.inputText)
          .textFieldStyle(.roundedBorder)
          .onChange(of: vm.inputText) { _ in vm.regenerate() }

        HStack(alignment: .top, spacing: 12) {
          ZStack {
            RoundedRectangle(cornerRadius: 8)
              .fill(Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: 8)
              .stroke(Color.gray.opacity(0.25), lineWidth: 1)

            if let img = vm.qrImage {
              Image(nsImage: img)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(8)
            } else {
              Text("Enter text to generate")
                .foregroundStyle(.secondary)
            }
          }
          .frame(width: 220, height: 220)

          VStack(alignment: .leading, spacing: 8) {
            Button("Copy QR Image") { vm.copyQRCodeImage() }
              .buttonStyle(.bordered)
              .disabled(vm.qrImage == nil)
            Button("Save PNG...") { vm.saveQRCodePNG() }
              .buttonStyle(.bordered)
              .disabled(vm.qrImage == nil)
            Spacer()
          }
        }
      }

      Divider()

      VStack(alignment: .leading, spacing: 8) {
        Text("Decode")
          .font(.system(size: 12, weight: .semibold))

        HStack(spacing: 8) {
          Button("Decode Clipboard Image") { vm.decodeFromClipboardImage() }
            .buttonStyle(.bordered)
          Button("Decode Image File...") { vm.decodeFromImageFile() }
            .buttonStyle(.bordered)
          Button("Copy Decoded") { vm.copyDecodedText() }
            .buttonStyle(.bordered)
            .disabled(vm.decodedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          Spacer()
        }

        if let err = vm.errorText {
          Text(err)
            .foregroundStyle(.red)
            .font(.system(size: 12))
        }

        TextEditor(text: $vm.decodedText)
          .font(.system(size: 12, design: .monospaced))
          .frame(minHeight: 110)
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .stroke(Color.gray.opacity(0.25), lineWidth: 1)
          )
      }

      Spacer()
        .frame(minHeight: 0)
    }
    .padding(16)
    .onAppear { vm.regenerate() }
  }
}

