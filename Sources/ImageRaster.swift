import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum ImageRasterError: Error {
  case missingPixelSize
  case createBitmapFailed
  case createContextFailed
}

enum ImageUploadMetadataStripError: Error {
  case unreadableImage
  case unsupportedImageType
  case missingDestinationType
  case createDestinationFailed
  case missingCGImage
  case finalizeFailed
}

enum ImageUploadTranscodeError: Error {
  case unreadableImage
  case missingDestinationType
  case unsupportedDestinationType
  case missingCGImage
  case createDestinationFailed
  case finalizeFailed
}

extension ImageUploadFormat {
  var typeIdentifier: String {
    switch self {
    case .png: return UTType.png.identifier
    case .jpeg: return UTType.jpeg.identifier
    case .gif: return UTType.gif.identifier
    case .tiff: return UTType.tiff.identifier
    }
  }

  fileprivate var lossyCompressionQuality: CGFloat? {
    switch self {
    case .jpeg: return 0.92
    case .png, .gif, .tiff: return nil
    }
  }

  fileprivate var needsOpaqueBackground: Bool {
    switch self {
    case .jpeg:
      return true
    case .png, .gif, .tiff:
      return false
    }
  }
}

enum ImageUploadTranscoder {
  static func convertedTemporaryCopy(from sourceURL: URL, to format: ImageUploadFormat) throws -> URL? {
    let sourceType = try sourceTypeIdentifier(for: sourceURL)
    if sourceType == format.typeIdentifier {
      return nil
    }

    guard let image = NSImage(contentsOf: sourceURL) else {
      throw ImageUploadTranscodeError.unreadableImage
    }

    let bitmap = try makeUprightBitmapRep(from: image)
    guard let cgImage = bitmap.cgImage else {
      throw ImageUploadTranscodeError.missingCGImage
    }

    let destinationTypes = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
    guard destinationTypes.contains(format.typeIdentifier) else {
      throw ImageUploadTranscodeError.unsupportedDestinationType
    }

    let outputURL = try temporaryOutputURL(for: sourceURL, format: format)
    guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, format.typeIdentifier as CFString, 1, nil) else {
      throw ImageUploadTranscodeError.createDestinationFailed
    }

    let encodedImage = format.needsOpaqueBackground ? opaqueCGImage(from: cgImage) ?? cgImage : cgImage
    CGImageDestinationAddImage(destination, encodedImage, destinationProperties(for: format) as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      try? FileManager.default.removeItem(at: outputURL)
      throw ImageUploadTranscodeError.finalizeFailed
    }
    return outputURL
  }

  private static func sourceTypeIdentifier(for sourceURL: URL) throws -> String {
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
      throw ImageUploadTranscodeError.unreadableImage
    }
    guard let typeIdentifier = CGImageSourceGetType(source) as String? else {
      throw ImageUploadTranscodeError.missingDestinationType
    }
    return typeIdentifier
  }

  private static func destinationProperties(for format: ImageUploadFormat) -> [CFString: Any] {
    var properties: [CFString: Any] = [:]
    if let quality = format.lossyCompressionQuality {
      properties[kCGImageDestinationLossyCompressionQuality] = quality
    }
    return properties
  }

  private static func temporaryOutputURL(for sourceURL: URL, format: ImageUploadFormat) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("CraftyCannon", isDirectory: true)
      .appendingPathComponent("ImageFormat", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let base = sourceURL.deletingPathExtension().lastPathComponent
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let safeBase = base.isEmpty ? "image" : base
    return root.appendingPathComponent("\(safeBase)-\(UUID().uuidString).\(format.filenameExtension)")
  }

  private static func opaqueCGImage(from source: CGImage) -> CGImage? {
    guard let context = CGContext(
      data: nil,
      width: source.width,
      height: source.height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
      return nil
    }

    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: source.width, height: source.height))
    context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
    return context.makeImage()
  }
}

enum ImageUploadMetadataStripper {
  private static let skippedTypeIdentifiers: Set<String> = [
    UTType.gif.identifier,
  ]

  static func strippedTemporaryCopy(from sourceURL: URL) throws -> URL? {
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
      throw ImageUploadMetadataStripError.unreadableImage
    }
    guard let typeIdentifier = CGImageSourceGetType(source) as String? else {
      throw ImageUploadMetadataStripError.missingDestinationType
    }
    if skippedTypeIdentifiers.contains(typeIdentifier) {
      return nil
    }
    let destinationTypes = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
    guard destinationTypes.contains(typeIdentifier) else {
      throw ImageUploadMetadataStripError.unsupportedImageType
    }
    guard let image = NSImage(contentsOf: sourceURL) else {
      throw ImageUploadMetadataStripError.unreadableImage
    }

    let bitmap = try makeUprightBitmapRep(from: image)
    guard let cgImage = bitmap.cgImage else {
      throw ImageUploadMetadataStripError.missingCGImage
    }

    let destinationURL = try temporaryOutputURL(for: sourceURL, typeIdentifier: typeIdentifier)
    if let bitmapFileType = bitmapFileType(for: typeIdentifier) {
      guard let data = bitmap.representation(using: bitmapFileType, properties: bitmapProperties(for: bitmapFileType)) else {
        throw ImageUploadMetadataStripError.finalizeFailed
      }
      try data.write(to: destinationURL, options: [.atomic])
      return destinationURL
    }

    guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, typeIdentifier as CFString, 1, nil) else {
      throw ImageUploadMetadataStripError.createDestinationFailed
    }

    CGImageDestinationAddImage(destination, cgImage, destinationProperties(for: typeIdentifier) as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      try? FileManager.default.removeItem(at: destinationURL)
      throw ImageUploadMetadataStripError.finalizeFailed
    }

    return destinationURL
  }

  private static func bitmapFileType(for typeIdentifier: String) -> NSBitmapImageRep.FileType? {
    switch typeIdentifier {
    case UTType.jpeg.identifier:
      return .jpeg
    case UTType.png.identifier:
      return .png
    case UTType.tiff.identifier:
      return .tiff
    case UTType.bmp.identifier:
      return .bmp
    default:
      return nil
    }
  }

  private static func bitmapProperties(for fileType: NSBitmapImageRep.FileType) -> [NSBitmapImageRep.PropertyKey: Any] {
    switch fileType {
    case .jpeg:
      return [.compressionFactor: 0.92]
    default:
      return [:]
    }
  }

  private static func destinationProperties(for typeIdentifier: String) -> [CFString: Any] {
    if typeIdentifier == UTType.jpeg.identifier {
      return [kCGImageDestinationLossyCompressionQuality: 0.92]
    }
    return [:]
  }

  private static func temporaryOutputURL(for sourceURL: URL, typeIdentifier: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("CraftyCannon", isDirectory: true)
      .appendingPathComponent("MetadataStripped", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let originalExtension = sourceURL.pathExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    let preferredExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "img"
    let ext = originalExtension.isEmpty ? preferredExtension : originalExtension
    let base = sourceURL.deletingPathExtension().lastPathComponent
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let safeBase = base.isEmpty ? "image" : base
    return root.appendingPathComponent("\(safeBase)-\(UUID().uuidString).\(ext.lowercased())")
  }
}

func makeTopLeftBitmapContext(width: Int, height: Int, colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()) -> CGContext? {
  guard width > 0, height > 0 else { return nil }

  // A Core Graphics bitmap context is y-up (origin bottom-left). `makeUprightBitmapRep`
  // already returns an upright CGImage, so blitting it here with no CTM flip round-trips
  // the pixels correctly. Callers that draw editor annotations (top-left normalized
  // coordinates) must flip y themselves, e.g. `(1 - ny) * h`. Do NOT flip the CTM here:
  // that would turn the already-upright base image upside down.
  return CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )
}

private func rasterizeWithAppKit(image: NSImage, width: Int, height: Int) -> NSBitmapImageRep? {
  guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else {
    return nil
  }

  rep.size = NSSize(width: CGFloat(width), height: CGFloat(height))

  guard let g = NSGraphicsContext(bitmapImageRep: rep) else {
    return nil
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = g
  NSGraphicsContext.current?.imageInterpolation = .high

  NSColor.clear.setFill()
  NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()

  image.draw(
    in: NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
    from: .zero,
    operation: .copy,
    fraction: 1.0,
    respectFlipped: true,
    hints: [NSImageRep.HintKey.interpolation: NSImageInterpolation.high]
  )

  NSGraphicsContext.restoreGraphicsState()
  return rep
}

private func bestBitmapRep(for image: NSImage) -> NSBitmapImageRep? {
  image.representations
    .compactMap { $0 as? NSBitmapImageRep }
    .max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) })
}

private func exifOrientation(from bitmap: NSBitmapImageRep) -> Int {
  // Prefer reading orientation from the bitmap rep's properties. When the source is a JPEG with
  // `kCGImagePropertyOrientation` set, AppKit usually preserves this on the rep, but converting
  // through `tiffRepresentation` can drop it.
  let orientationKey = NSBitmapImageRep.PropertyKey(rawValue: kCGImagePropertyOrientation as String)
  if let n = bitmap.value(forProperty: orientationKey) as? NSNumber {
    return n.intValue
  }
  if let i = bitmap.value(forProperty: orientationKey) as? Int {
    return i
  }

  guard let data = bitmap.tiffRepresentation as CFData? else { return 1 }
  guard let src = CGImageSourceCreateWithData(data, nil) else { return 1 }
  guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return 1 }
  return (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
}

private func bestPixelSize(for image: NSImage) -> (w: Int, h: Int)? {
  // Prefer the largest bitmap rep we already have.
  if let rep = bestBitmapRep(for: image) {
    if rep.pixelsWide > 0, rep.pixelsHigh > 0 {
      // If AppKit's logical size differs from the backing rep (common with EXIF orientation=6/8),
      // derive the target pixel size from the displayed size so we don't distort/crop 90-degree rotations.
      if image.size.width > 0, image.size.height > 0, rep.size.width > 0, rep.size.height > 0 {
        let scaleX = CGFloat(rep.pixelsWide) / rep.size.width
        let scaleY = CGFloat(rep.pixelsHigh) / rep.size.height
        let scale = max(scaleX, scaleY)
        let w = Int((image.size.width * scale).rounded())
        let h = Int((image.size.height * scale).rounded())
        if w > 0, h > 0 {
          return (w, h)
        }
      }

      return (rep.pixelsWide, rep.pixelsHigh)
    }
  }

  if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    return (cg.width, cg.height)
  }

  if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
    if rep.pixelsWide > 0, rep.pixelsHigh > 0 {
      return (rep.pixelsWide, rep.pixelsHigh)
    }
  }

  let w = Int(image.size.width.rounded())
  let h = Int(image.size.height.rounded())
  if w > 0, h > 0 {
    return (w, h)
  }

  return nil
}

// Rasterize an NSImage into an RGBA bitmap, respecting EXIF orientation (and other rep transforms)
// by using AppKit's drawing pipeline.
func makeUprightBitmapRep(from image: NSImage) throws -> NSBitmapImageRep {
  guard let (w, h) = bestPixelSize(for: image) else {
    throw ImageRasterError.missingPixelSize
  }

  // Match the displayed orientation first by rasterizing through AppKit's drawing pipeline.
  // This avoids EXIF edge cases where metadata can be missing or already applied.
  if let rep = rasterizeWithAppKit(image: image, width: w, height: h) {
    return rep
  }

  // Prefer orientation-aware rasterization via Core Image when we have a bitmap-backed image.
  if let bitmap = bestBitmapRep(for: image),
     let baseCG = bitmap.cgImage {
    let raw = exifOrientation(from: bitmap)
    let orientation = CGImagePropertyOrientation(rawValue: UInt32(raw)) ?? .up

    var ci = CIImage(cgImage: baseCG).oriented(orientation)

    // If bestPixelSize derived a different target size (common when logical size differs),
    // scale the oriented CI image to match exactly.
    let extent = ci.extent.integral
    if extent.width > 0, extent.height > 0,
       Int(extent.width.rounded()) != w || Int(extent.height.rounded()) != h {
      let sx = CGFloat(w) / extent.width
      let sy = CGFloat(h) / extent.height
      ci = ci.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
    }

    let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let ctx = CIContext(options: [
      CIContextOption.workingColorSpace: cs,
      CIContextOption.outputColorSpace: cs,
    ])

    if let outCG = ctx.createCGImage(ci, from: ci.extent.integral) {
      let rep = NSBitmapImageRep(cgImage: outCG)
      // 1pt == 1px inside this rep.
      rep.size = NSSize(width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh))
      return rep
    }
    // Fall through to AppKit draw if CI fails for any reason.
  }

  throw ImageRasterError.createBitmapFailed
}
