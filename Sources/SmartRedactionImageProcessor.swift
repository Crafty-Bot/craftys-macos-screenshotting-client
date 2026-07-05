import AppKit
import CoreImage
import Foundation

enum SmartRedactionImageProcessorError: Error {
  case imageLoadFailed
  case imageRenderFailed
  case pngEncodingFailed
}

struct SmartRedactionImageProcessor {
  static let defaultPixelationStrength: CGFloat = 14

  static func redactedTemporaryPNG(
    from imageURL: URL,
    regions: [SmartRedactionRegion],
    mode: SmartRedactionRenderMode = .pixelate,
    strength: CGFloat = SmartRedactionImageProcessor.defaultPixelationStrength
  ) throws -> URL {
    guard let image = NSImage(contentsOf: imageURL) else {
      throw SmartRedactionImageProcessorError.imageLoadFailed
    }
    guard let redacted = redactedImage(image, regions: regions, mode: mode, strength: strength) else {
      throw SmartRedactionImageProcessorError.imageRenderFailed
    }

    let rep = try makeUprightBitmapRep(from: redacted)
    guard let png = rep.representation(using: .png, properties: [:]) else {
      throw SmartRedactionImageProcessorError.pngEncodingFailed
    }

    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("CraftyCannon", isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let output = tmpDir
      .appendingPathComponent("redacted-\(UUID().uuidString)")
      .appendingPathExtension("png")
    try png.write(to: output, options: [.atomic])
    return output
  }

  static func redactedImage(
    _ image: NSImage,
    regions: [SmartRedactionRegion],
    mode: SmartRedactionRenderMode,
    strength: CGFloat = SmartRedactionImageProcessor.defaultPixelationStrength
  ) -> NSImage? {
    switch mode {
    case .pixelate:
      return pixelatedImage(image, regions: regions, strength: strength)
    case .blackBox:
      return blackBoxedImage(image, regions: regions)
    }
  }

  static func pixelatedImage(
    _ image: NSImage,
    regions: [SmartRedactionRegion],
    strength: CGFloat = SmartRedactionImageProcessor.defaultPixelationStrength
  ) -> NSImage? {
    guard !regions.isEmpty else { return image }

    var output = image
    for region in regions {
      guard let filtered = filterRegion(image: output, normRect: region.rect, strength: strength) else {
        continue
      }
      output = filtered
    }
    return output
  }

  static func blackBoxedImage(
    _ image: NSImage,
    regions: [SmartRedactionRegion]
  ) -> NSImage? {
    guard !regions.isEmpty else { return image }

    var output = image
    for region in regions {
      guard let filled = fillRegion(image: output, normRect: region.rect, color: .black) else {
        continue
      }
      output = filled
    }
    return output
  }

  private static func fillRegion(image: NSImage, normRect: CGRect, color: NSColor) -> NSImage? {
    guard let rep = try? makeUprightBitmapRep(from: image), let cg = rep.cgImage else { return nil }
    let w = CGFloat(rep.pixelsWide)
    let h = CGFloat(rep.pixelsHigh)
    guard w > 0, h > 0 else { return nil }

    let clamped = normRect
      .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    guard clamped.width > 0, clamped.height > 0 else { return nil }

    let rx = clamped.origin.x * w
    let ry = clamped.origin.y * h
    let rw = clamped.size.width * w
    let rh = clamped.size.height * h

    guard let bitmapContext = makeTopLeftBitmapContext(width: Int(w), height: Int(h)) else { return nil }
    bitmapContext.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

    let drawRect = CGRect(x: rx, y: h - (ry + rh), width: rw, height: rh).integral
    bitmapContext.setFillColor(color.cgColor)
    bitmapContext.fill(drawRect)

    guard let outCG = bitmapContext.makeImage() else { return nil }
    return NSImage(cgImage: outCG, size: image.size)
  }

  private static func filterRegion(image: NSImage, normRect: CGRect, strength: CGFloat) -> NSImage? {
    guard let rep = try? makeUprightBitmapRep(from: image), let cg = rep.cgImage else { return nil }
    let w = CGFloat(rep.pixelsWide)
    let h = CGFloat(rep.pixelsHigh)
    guard w > 0, h > 0 else { return nil }

    let clamped = normRect
      .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    guard clamped.width > 0, clamped.height > 0 else { return nil }

    let rx = clamped.origin.x * w
    let ry = clamped.origin.y * h
    let rw = clamped.size.width * w
    let rh = clamped.size.height * h
    let regionCI = CGRect(x: rx, y: h - (ry + rh), width: rw, height: rh).integral

    let ci = CIImage(cgImage: cg)
    let cropped = ci.cropped(to: regionCI)
    let filter = CIFilter(name: "CIPixellate")
    filter?.setValue(cropped, forKey: kCIInputImageKey)
    filter?.setValue(max(2, strength), forKey: kCIInputScaleKey)
    let pixelated = (filter?.outputImage ?? cropped).cropped(to: regionCI)

    let context = CIContext(options: nil)
    guard let pixelatedCG = context.createCGImage(pixelated, from: regionCI) else { return nil }
    guard let bitmapContext = makeTopLeftBitmapContext(width: Int(w), height: Int(h)) else { return nil }
    bitmapContext.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

    // The bitmap context is y-up (origin bottom-left). normRect is top-left, so the patch
    // must be drawn at the flipped y the region was cropped from (regionCI), not raw `ry`.
    let drawRect = CGRect(x: rx, y: h - (ry + rh), width: rw, height: rh).integral
    bitmapContext.draw(pixelatedCG, in: drawRect)

    guard let outCG = bitmapContext.makeImage() else { return nil }
    return NSImage(cgImage: outCG, size: image.size)
  }
}
