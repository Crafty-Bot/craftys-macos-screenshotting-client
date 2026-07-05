import XCTest
import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@testable import CraftyCannon

final class CraftyCannonTests: XCTestCase {
    final class MemoryOCRStore: OCRHistoryStoring {
        private var records: [UploadRecord]

        init(records: [UploadRecord]) {
            self.records = records
        }

        func snapshot() -> [UploadRecord] {
            records
        }

        func record(id: String) -> UploadRecord? {
            records.first(where: { $0.id == id })
        }

        func addRecordSync(_ record: UploadRecord) {
            records.insert(record, at: 0)
        }

        func updateRecordSync(id: String, _ mutate: (inout UploadRecord) -> Void) {
            guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
            mutate(&records[idx])
        }

        func mutateRecordsSync(_ mutate: (inout [UploadRecord]) -> Void) {
            mutate(&records)
        }
    }

    final class FakeOCRRecognizer: OCRTextRecognizing {
        let engineName = "Fake OCR"
        let engineVersion = "test"
        var text: String
        var error: Error?
        private(set) var calls = 0

        init(text: String = "Alpha beta searchable text", error: Error? = nil) {
            self.text = text
            self.error = error
        }

        func recognizeText(in imageURL: URL) throws -> String {
            calls += 1
            if let error { throw error }
            return text
        }
    }

    final class FakeSmartRedactionRecognizer: SmartRedactionVisionRecognizing {
        var candidates: [(text: String, rect: CGRect)]

        init(candidates: [(text: String, rect: CGRect)]) {
            self.candidates = candidates
        }

        func recognizeFindings(
            in image: CGImage,
            settings: RedactionDetectorSettings,
            classifier: SmartRedactionPatternClassifier
        ) throws -> [RedactionFinding] {
            candidates.flatMap { candidate in
                classifier.matches(in: candidate.text, settings: settings).map { match in
                    RedactionFinding(
                        kind: .text,
                        detectorType: match.detectorType,
                        confidence: 0.95,
                        matchedTextPreview: match.text,
                        boundingBox: RedactionBoundingBox(topLeftNormalizedRect: candidate.rect),
                        metadata: ["source": "fake"]
                    )
                }
            }
        }
    }

    enum FakeOCRError: Error {
        case failed
    }

    private enum TestImageError: Error {
        case createImageDestinationFailed
        case finalizeFailed
    }

    private func makeCGImageRGBA(pixels: [UInt8], width: Int, height: Int) -> CGImage {
        precondition(pixels.count == width * height * 4)
        // Test fixtures are authored in top-left-origin row order. CoreGraphics bitmap
        // contexts interpret backing rows bottom-left first, so flip rows up front.
        let rowBytes = width * 4
        var bottomLeftRows = [UInt8](repeating: 0, count: pixels.count)
        for y in 0..<height {
            let srcStart = y * rowBytes
            let dstStart = (height - 1 - y) * rowBytes
            bottomLeftRows[dstStart..<(dstStart + rowBytes)] = pixels[srcStart..<(srcStart + rowBytes)]
        }

        var copy = bottomLeftRows
        return copy.withUnsafeMutableBytes { buf in
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            )
            let ctx = CGContext(
                data: buf.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            )!
            return ctx.makeImage()!
        }
    }

    // Returns RGBA pixels in top-left origin order (row-major, y-down).
    private func rgbaTopLeftPixels(from cg: CGImage) -> [UInt8] {
        let w = cg.width
        let h = cg.height
        var out = [UInt8](repeating: 0, count: w * h * 4)

        out.withUnsafeMutableBytes { buf in
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            )

            let ctx = CGContext(
                data: buf.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            )!

            ctx.interpolationQuality = .none
            // Make the context y-down so the output buffer is in top-left origin order.
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        return out
    }

    private func rotate180RGBA(_ pixels: [UInt8], width: Int, height: Int) -> [UInt8] {
        precondition(pixels.count == width * height * 4)
        let n = width * height
        var out = [UInt8](repeating: 0, count: pixels.count)
        for i in 0..<n {
            let src = i * 4
            let dst = (n - 1 - i) * 4
            out[dst] = pixels[src]
            out[dst + 1] = pixels[src + 1]
            out[dst + 2] = pixels[src + 2]
            out[dst + 3] = pixels[src + 3]
        }
        return out
    }

    private func rotate90CW_RGBA(_ pixels: [UInt8], width: Int, height: Int) -> [UInt8] {
        precondition(pixels.count == width * height * 4)
        let outW = height
        let outH = width
        var out = [UInt8](repeating: 0, count: outW * outH * 4)

        for y in 0..<height {
            for x in 0..<width {
                let src = (y * width + x) * 4
                let dstX = height - 1 - y
                let dstY = x
                let dst = (dstY * outW + dstX) * 4
                out[dst] = pixels[src]
                out[dst + 1] = pixels[src + 1]
                out[dst + 2] = pixels[src + 2]
                out[dst + 3] = pixels[src + 3]
            }
        }

        return out
    }

    private func jpegData(cg: CGImage, exifOrientation: Int, quality: Double = 1.0) throws -> Data {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TestImageError.createImageDestinationFailed
        }
        let props = [
            kCGImagePropertyOrientation: exifOrientation,
            kCGImageDestinationLossyCompressionQuality: max(0.0, min(1.0, quality)),
        ] as CFDictionary
        CGImageDestinationAddImage(dest, cg, props)
        guard CGImageDestinationFinalize(dest) else {
            throw TestImageError.finalizeFailed
        }
        return out as Data
    }

    private func pngData(cg: CGImage) throws -> Data {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            throw TestImageError.createImageDestinationFailed
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw TestImageError.finalizeFailed
        }
        return out as Data
    }

    private func jpegDataWithMetadata(cg: CGImage, exifOrientation: Int, quality: Double = 1.0) throws -> Data {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TestImageError.createImageDestinationFailed
        }
        let props = [
            kCGImagePropertyOrientation: exifOrientation,
            kCGImageDestinationLossyCompressionQuality: max(0.0, min(1.0, quality)),
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:07:04 12:00:00",
                kCGImagePropertyExifLensModel: "Test Lens",
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 40.7128,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 74.0060,
                kCGImagePropertyGPSLongitudeRef: "W",
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Test Camera",
                kCGImagePropertyTIFFModel: "Metadata Fixture",
            ],
        ] as CFDictionary
        CGImageDestinationAddImage(dest, cg, props)
        guard CGImageDestinationFinalize(dest) else {
            throw TestImageError.finalizeFailed
        }
        return out as Data
    }

    private func imageProperties(at url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func pixelRGBA(_ pixels: [UInt8], x: Int, y: Int, width: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let idx = (y * width + x) * 4
        return (pixels[idx], pixels[idx + 1], pixels[idx + 2], pixels[idx + 3])
    }

    private func assertPixelClose(
        _ actual: (UInt8, UInt8, UInt8, UInt8),
        _ expected: (UInt8, UInt8, UInt8, UInt8),
        tolerance: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(abs(Int(actual.0) - Int(expected.0)), tolerance, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(Int(actual.1) - Int(expected.1)), tolerance, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(Int(actual.2) - Int(expected.2)), tolerance, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(Int(actual.3) - Int(expected.3)), tolerance, file: file, line: line)
    }

    private func makeBlockPatternRGBA(
        blockSize: Int,
        blocksWide: Int,
        blocksHigh: Int,
        colorForBlock: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)
    ) -> (pixels: [UInt8], width: Int, height: Int) {
        let width = blocksWide * blockSize
        let height = blocksHigh * blockSize
        var out = [UInt8](repeating: 0, count: width * height * 4)
        for by in 0..<blocksHigh {
            for bx in 0..<blocksWide {
                let c = colorForBlock(bx, by)
                for y in 0..<blockSize {
                    for x in 0..<blockSize {
                        let px = bx * blockSize + x
                        let py = by * blockSize + y
                        let idx = (py * width + px) * 4
                        out[idx] = c.0
                        out[idx + 1] = c.1
                        out[idx + 2] = c.2
                        out[idx + 3] = c.3
                    }
                }
            }
        }
        return (out, width, height)
    }

    func testTopLeftBitmapContextPreservesImageAndOverlayRows() throws {
        let block = 8
        let pattern = makeBlockPatternRGBA(blockSize: block, blocksWide: 2, blocksHigh: 2) { bx, by in
            switch (bx, by) {
            case (0, 0): return (10, 10, 10, 255)
            case (1, 0): return (80, 80, 80, 255)
            case (0, 1): return (160, 160, 160, 255)
            default: return (240, 240, 240, 255)
            }
        }
        let cg = makeCGImageRGBA(pixels: pattern.pixels, width: pattern.width, height: pattern.height)
        let ctx = try XCTUnwrap(makeTopLeftBitmapContext(width: pattern.width, height: pattern.height))

        ctx.interpolationQuality = .none
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: pattern.width, height: pattern.height))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: block, height: block))

        let outCg = try XCTUnwrap(ctx.makeImage())
        let out = rgbaTopLeftPixels(from: outCg)
        let w = pattern.width
        let cx = block / 2
        let cy = block / 2

        assertPixelClose(pixelRGBA(out, x: cx, y: cy, width: w), (255, 255, 255, 255), tolerance: 2) // TL overlay
        assertPixelClose(pixelRGBA(out, x: w - 1 - cx, y: cy, width: w), (80, 80, 80, 255), tolerance: 2) // TR base
        assertPixelClose(pixelRGBA(out, x: cx, y: w - 1 - cy, width: w), (160, 160, 160, 255), tolerance: 2) // BL base
        assertPixelClose(pixelRGBA(out, x: w - 1 - cx, y: w - 1 - cy, width: w), (240, 240, 240, 255), tolerance: 2) // BR base
    }

    private func temporaryOCRFile(named name: String = "ocr-test.png") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CraftyCannonTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data("fake image bytes".utf8).write(to: url)
        return url
    }

    func testUploadRecordDecodesLegacyJSONWithoutOCRFields() throws {
        let payload = """
        [{
          "id": "legacy",
          "createdAt": 0,
          "profileId": "profile",
          "localFilePath": "/tmp/legacy.png",
          "status": "uploaded",
          "kind": "image"
        }]
        """
        let data = try XCTUnwrap(payload.data(using: .utf8))
        let records = try JSONDecoder().decode([UploadRecord].self, from: data)
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record.id, "legacy")
        XCTAssertNil(record.ocrStatus)
        XCTAssertNil(record.ocrText)
        XCTAssertNil(record.secondaryUploadStatus)
        XCTAssertNil(record.secondaryURL)
    }

    func testSmartRedactionClassifierFindsSensitivePatterns() {
        let classifier = SmartRedactionPatternClassifier()
        var settings = RedactionDetectorSettings.defaultValue
        settings.ipv6Addresses = true
        settings.macAddresses = true
        settings.filePaths = true
        settings.usernamesHostnames = true

        let cases: [(String, RedactionDetectorType)] = [
            ("Email me at dev@example.com", .emailAddresses),
            ("Open https://example.com/private?token=abc", .urlsDomains),
            ("Internal site is app.example.dev", .urlsDomains),
            ("Server is 192.168.1.44", .ipv4Addresses),
            ("IPv6 is 2001:0db8:85a3:0000:0000:8a2e:0370:7334", .ipv6Addresses),
            ("Wi-Fi MAC 00:1A:2B:3C:4D:5E", .macAddresses),
            ("Call (212) 555-0198 today", .phoneNumbers),
            ("Card 4111 1111 1111 1111", .creditCardNumbers),
            ("AWS key AKIAIOSFODNN7EXAMPLE", .awsAccessKeys),
            ("GitHub token ghp_abcdefghijklmnopqrstuvwxyzABCDE12345", .githubTokens),
            ("OpenAI key sk-abcdefghijklmnopqrstuvwxyz", .openAIKeys),
            ("Authorization: Bearer abcdefghijklmnopqrstuvwxyz", .bearerTokens),
            ("JWT eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.signature", .jwts),
            ("password = hunter2", .passwordFields),
            ("DATABASE_URL=postgres://secret-host", .environmentVariables),
            ("Set-Cookie: sessionid=abcdef1234567890", .sessionCookies),
            ("Path /Users/example/Documents/Secret/file.txt", .filePaths),
            ("hostname = macbook-pro", .usernamesHostnames),
        ]

        for (text, category) in cases {
            XCTAssertTrue(
                classifier.matches(in: text, settings: settings).contains { $0.detectorType == category },
                "Expected \(category.rawValue) in \(text)"
            )
        }
    }

    func testSmartRedactionClassifierFindsPrivateKeyBlocks() {
        let classifier = SmartRedactionPatternClassifier()
        let text = """
        -----BEGIN PRIVATE KEY-----
        abcdefghijklmnopqrstuvwxyz
        -----END PRIVATE KEY-----
        """
        let matches = classifier.matches(in: text)

        XCTAssertTrue(matches.contains { $0.detectorType == .privateKeyBlocks })
    }

    func testSmartRedactionClassifierMatchesOCRSpacedEmail() {
        let classifier = SmartRedactionPatternClassifier()
        let matches = classifier.matches(in: "rosscran992 @ gmail . com")

        XCTAssertTrue(matches.contains { $0.detectorType == .emailAddresses })
    }

    func testSmartRedactionClassifierAvoidsCommonNonMatches() {
        let classifier = SmartRedactionPatternClassifier()
        let text = "Release 2026-06-27 build 123456 with card-ish 4111 1111 1111 1113"
        let categories = classifier.matches(in: text).map(\.detectorType)

        XCTAssertFalse(categories.contains(.creditCardNumbers))
        XCTAssertFalse(categories.contains(.apiKeys))
        XCTAssertFalse(categories.contains(.passwordFields))
    }

    func testSmartRedactionLuhnValidation() {
        XCTAssertTrue(SmartRedactionPatternClassifier.isLikelyCreditCard("4111 1111 1111 1111"))
        XCTAssertTrue(SmartRedactionPatternClassifier.isLikelyCreditCard("5555-5555-5555-4444"))
        XCTAssertFalse(SmartRedactionPatternClassifier.isLikelyCreditCard("4111 1111 1111 1113"))
        XCTAssertFalse(SmartRedactionPatternClassifier.isLikelyCreditCard("123456"))
    }

    func testSmartRedactionMergesPaddedAdjacentRegions() {
        let regions = [
            SmartRedactionRegion(rect: CGRect(x: 0.10, y: 0.10, width: 0.10, height: 0.05), category: .emailAddresses, matchedText: "a@example.com"),
            SmartRedactionRegion(rect: CGRect(x: 0.215, y: 0.10, width: 0.08, height: 0.05), category: .openAIKeys, matchedText: "sk-secret"),
            SmartRedactionRegion(rect: CGRect(x: 0.70, y: 0.70, width: 0.10, height: 0.05), category: .urlsDomains, matchedText: "https://example.com"),
        ]

        let merged = SmartRedactionDetector.paddedAndMerged(regions, padding: 0, adjacency: 0.02)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].category, .textOCR)
        XCTAssertEqual(merged[0].rect.minX, 0.10, accuracy: 0.0001)
        XCTAssertEqual(merged[0].rect.maxX, 0.295, accuracy: 0.0001)
        XCTAssertEqual(merged[1].category, .urlsDomains)
    }

    func testSmartRedactionDetectorFiltersOnlySensitiveCandidates() async throws {
        let recognizer = FakeSmartRedactionRecognizer(candidates: [
            ("no private text here", CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)),
            ("dev@example.com", CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.1)),
            ("sk-abcdefghijklmnopqrstuvwxyz", CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.1)),
        ])
        let detector = SmartRedactionDetector(recognizer: recognizer)
        let image = makeCGImageRGBA(pixels: [255, 255, 255, 255], width: 1, height: 1)

        let findings = try await detector.detectRedactions(in: image)
        let matchedText = findings.compactMap(\.matchedTextPreview).joined(separator: " ")

        XCTAssertEqual(findings.count, 2)
        XCTAssertTrue(matchedText.contains("dev@example.com"))
        XCTAssertTrue(matchedText.contains("sk-abcdefghijklmnopqrstuvwxyz"))
        XCTAssertFalse(matchedText.contains("private"))
    }

    func testRedactionBoundingBoxConvertsBetweenVisionAndTopLeftCoordinates() {
        let topLeft = CGRect(x: 0.2, y: 0.1, width: 0.3, height: 0.4)
        let box = RedactionBoundingBox(topLeftNormalizedRect: topLeft)

        XCTAssertEqual(box.normalizedVisionRect.minX, 0.2, accuracy: 0.0001)
        XCTAssertEqual(box.normalizedVisionRect.minY, 0.5, accuracy: 0.0001)
        XCTAssertEqual(box.topLeftNormalizedRect.minY, 0.1, accuracy: 0.0001)

        let pixelRect = box.imageRect(pixelWidth: 1000, pixelHeight: 500, originTopLeft: true)
        XCTAssertEqual(pixelRect.minX, 200, accuracy: 0.0001)
        XCTAssertEqual(pixelRect.minY, 50, accuracy: 0.0001)
        XCTAssertEqual(pixelRect.width, 300, accuracy: 0.0001)
        XCTAssertEqual(pixelRect.height, 200, accuracy: 0.0001)
    }

    func testTextObservationBoundingBoxConvertsVisionToTopLeftForRedaction() {
        // Vision reports text observations in bottom-left-origin normalized coordinates.
        // A box near the bottom of the image (low Vision Y) must map to a high top-left Y.
        let visionBottomText = CGRect(x: 0.18, y: 0.08, width: 0.42, height: 0.12)
        let box = VisionSmartRedactionRecognizer.textObservationBoundingBox(visionBottomText)

        XCTAssertEqual(box.topLeftNormalizedRect.minX, 0.18, accuracy: 0.0001)
        // 1 - (0.08 + 0.12) = 0.80
        XCTAssertEqual(box.topLeftNormalizedRect.minY, 0.80, accuracy: 0.0001)
        XCTAssertEqual(box.topLeftNormalizedRect.width, 0.42, accuracy: 0.0001)
        XCTAssertEqual(box.topLeftNormalizedRect.height, 0.12, accuracy: 0.0001)
    }

    // Builds a striped image through the same path real captures take (drawn upright via
    // NSGraphicsContext, encoded to PNG, reloaded with NSImage(data:)), redacts a region in
    // top-left normalized coordinates, and verifies the redaction lands in the matching half.
    // A synthetic NSImage(cgImage:) built from a hand-flipped buffer does NOT reproduce the
    // real loader's orientation, which previously masked a vertically mirrored redaction.
    private func makeStripedCaptureImage(width: Int, height: Int) throws -> NSImage {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let ctx = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor.black.setFill()
        var x = 0
        while x < width {
            NSRect(x: CGFloat(x), y: 0, width: 3, height: CGFloat(height)).fill()
            x += 6
        }
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        return try XCTUnwrap(NSImage(data: png))
    }

    private func changedFraction(
        from a: NSBitmapImageRep, to b: NSBitmapImageRep, yRange: Range<Int>, width: Int
    ) -> Double {
        var changed = 0, total = 0
        for y in yRange {
            for x in stride(from: 0, to: width, by: 3) {
                guard let ca = a.colorAt(x: x, y: y), let cb = b.colorAt(x: x, y: y) else { continue }
                let d = abs(ca.redComponent - cb.redComponent)
                    + abs(ca.greenComponent - cb.greenComponent)
                    + abs(ca.blueComponent - cb.blueComponent)
                if d > 0.15 { changed += 1 }
                total += 1
            }
        }
        return total > 0 ? Double(changed) / Double(total) : 0
    }

    func testSmartRedactionImageProcessorRedactsMatchingTopLeftRegion() throws {
        let width = 200
        let height = 200
        let image = try makeStripedCaptureImage(width: width, height: height)

        // Region covers the BOTTOM half in top-left normalized coordinates.
        let region = SmartRedactionRegion(
            rect: CGRect(x: 0, y: 0.5, width: 1, height: 0.5),
            category: .ipv4Addresses,
            matchedText: nil
        )
        let redacted = try XCTUnwrap(
            SmartRedactionImageProcessor.pixelatedImage(image, regions: [region], strength: 12))

        let inRep = try makeUprightBitmapRep(from: image)
        let outRep = try makeUprightBitmapRep(from: redacted)

        let topChanged = changedFraction(from: inRep, to: outRep, yRange: 0..<(height / 2), width: width)
        let bottomChanged = changedFraction(from: inRep, to: outRep, yRange: (height / 2)..<height, width: width)

        // The bottom-half region must be redacted; the untouched top half must stay intact.
        XCTAssertGreaterThan(bottomChanged, 0.2, "bottom-half region should be redacted")
        XCTAssertLessThan(topChanged, 0.05, "top half should be untouched (no vertical mirror)")
    }

    private func averageBrightness(_ rep: NSBitmapImageRep, yRange: Range<Int>, width: Int) -> Double {
        var total: Double = 0
        var count: Double = 0
        for y in yRange {
            for x in 0..<width {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                total += Double(color.redComponent + color.greenComponent + color.blueComponent) / 3.0
                count += 1
            }
        }
        return count > 0 ? total / count : 0
    }

    func testSmartRedactionImageProcessorBlackBoxesMatchingTopLeftRegion() throws {
        let width = 200
        let height = 200
        let image = try makeStripedCaptureImage(width: width, height: height)

        let region = SmartRedactionRegion(
            rect: CGRect(x: 0, y: 0.5, width: 1, height: 0.5),
            category: .textOCR,
            matchedText: nil
        )
        let redacted = try XCTUnwrap(SmartRedactionImageProcessor.blackBoxedImage(image, regions: [region]))

        let inRep = try makeUprightBitmapRep(from: image)
        let outRep = try makeUprightBitmapRep(from: redacted)

        let topChanged = changedFraction(from: inRep, to: outRep, yRange: 0..<(height / 2), width: width)
        let topBrightness = averageBrightness(outRep, yRange: 0..<(height / 2), width: width)
        let bottomBrightness = averageBrightness(outRep, yRange: (height / 2)..<height, width: width)

        XCTAssertLessThan(topChanged, 0.05, "top half should be untouched (no vertical mirror)")
        XCTAssertGreaterThan(topBrightness, 0.35, "top half should keep the striped source content")
        XCTAssertLessThan(bottomBrightness, 0.02, "bottom-half region should be filled black")
    }

    func testSmartRedactionTemporaryPNGSupportsBlackBoxMode() throws {
        let width = 200
        let height = 200
        let image = try makeStripedCaptureImage(width: width, height: height)
        let rep = try makeUprightBitmapRep(from: image)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("craftycannon-redaction-fixture-\(UUID().uuidString).png")
        try png.write(to: inputURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let region = SmartRedactionRegion(
            rect: CGRect(x: 0, y: 0.5, width: 1, height: 0.5),
            category: .textOCR,
            matchedText: nil
        )
        let outputURL = try SmartRedactionImageProcessor.redactedTemporaryPNG(
            from: inputURL,
            regions: [region],
            mode: .blackBox
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let redacted = try XCTUnwrap(NSImage(contentsOf: outputURL))
        let outRep = try makeUprightBitmapRep(from: redacted)
        let topBrightness = averageBrightness(outRep, yRange: 0..<(height / 2), width: width)
        let bottomBrightness = averageBrightness(outRep, yRange: (height / 2)..<height, width: width)

        XCTAssertGreaterThan(topBrightness, 0.35, "top half should keep the source content")
        XCTAssertLessThan(bottomBrightness, 0.02, "black-box mode should fill the detected region")
    }

    func testUploadProfileRoundTripsSecondaryS3ProfileId() throws {
        let profile = UploadProfile(
            id: "zipline-1",
            name: "Zipline",
            endpoint: "https://zipline.example.com",
            backend: .ziplineV4,
            secondaryS3ProfileId: "s3-1"
        )

        let encoded = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UploadProfile.self, from: encoded)

        XCTAssertEqual(decoded.secondaryS3ProfileId, "s3-1")
        XCTAssertEqual(decoded.backend, .ziplineV4)
    }

    func testUploadRecordRoundTripsSecondaryS3Metadata() throws {
        let completedAt = Date(timeIntervalSince1970: 1_714_000_000)
        let record = UploadRecord(
            profileId: "zipline-1",
            localFilePath: "/tmp/example.png",
            status: .uploaded,
            kind: .image,
            secondaryUploadStatus: .uploaded,
            secondaryProfileId: "s3-1",
            secondaryURL: "https://cdn.example.com/example.png",
            secondaryRemotePath: "mirrors/example.png",
            secondaryCompletedAt: completedAt,
            secondaryError: nil
        )

        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(UploadRecord.self, from: encoded)

        XCTAssertEqual(decoded.secondaryUploadStatus, .uploaded)
        XCTAssertEqual(decoded.secondaryProfileId, "s3-1")
        XCTAssertEqual(decoded.secondaryURL, "https://cdn.example.com/example.png")
        XCTAssertEqual(decoded.secondaryRemotePath, "mirrors/example.png")
        XCTAssertEqual(decoded.secondaryCompletedAt, completedAt)
        XCTAssertNil(decoded.secondaryError)
    }

    func testAWSCLIProfileLoaderParsesDefaultCredentialsAndConfigRegion() {
        let credentials = """
        [default]
        aws_access_key_id = AKIADEFAULT
        aws_secret_access_key = default-secret
        aws_session_token = default-session

        [deploy]
        aws_access_key_id = AKIADEPLOY
        aws_secret_access_key = deploy-secret
        """
        let config = """
        [default]
        region = us-west-2

        [profile deploy]
        region = us-east-2
        endpoint_url = https://s3.us-east-2.amazonaws.com
        """

        let profiles = AWSCLIProfileLoader.parse(credentialsText: credentials, configText: config)

        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles[0].name, "default")
        XCTAssertEqual(profiles[0].accessKeyId, "AKIADEFAULT")
        XCTAssertEqual(profiles[0].secretAccessKey, "default-secret")
        XCTAssertEqual(profiles[0].sessionToken, "default-session")
        XCTAssertEqual(profiles[0].region, "us-west-2")

        let deploy = profiles.first(where: { $0.name == "deploy" })
        XCTAssertEqual(deploy?.accessKeyId, "AKIADEPLOY")
        XCTAssertEqual(deploy?.secretAccessKey, "deploy-secret")
        XCTAssertEqual(deploy?.region, "us-east-2")
        XCTAssertEqual(deploy?.endpoint, "https://s3.us-east-2.amazonaws.com")
    }

    func testAWSCLIProfileLoaderSkipsProfilesWithoutUsableKeys() {
        let credentials = """
        [default]
        aws_access_key_id = AKIADEFAULT

        [complete]
        aws_access_key_id = AKIACOMPLETE
        aws_secret_access_key = complete-secret
        """

        let profiles = AWSCLIProfileLoader.parse(credentialsText: credentials, configText: "")

        XCTAssertEqual(profiles.map(\.name), ["complete"])
        XCTAssertEqual(profiles[0].region, "us-east-1")
        XCTAssertEqual(profiles[0].endpoint, "https://s3.amazonaws.com")
    }

    func testPasteTargetPolicyPrefersURLForDiscordDesktopApps() {
        XCTAssertTrue(PasteTargetPolicy.shouldPasteURLInsteadOfImage(
            applicationName: "Discord",
            bundleIdentifier: "com.hnc.Discord"
        ))
        XCTAssertTrue(PasteTargetPolicy.shouldPasteURLInsteadOfImage(
            applicationName: "Discord Canary",
            bundleIdentifier: "com.hnc.DiscordCanary"
        ))
        XCTAssertTrue(PasteTargetPolicy.shouldPasteURLInsteadOfImage(
            applicationName: "Discord PTB",
            bundleIdentifier: "com.hnc.DiscordPTB"
        ))
    }

    func testPasteTargetPolicyPrefersURLForDiscordInBrowserWindow() {
        XCTAssertTrue(PasteTargetPolicy.shouldPasteURLInsteadOfImage(
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Discord | #general | Crafty"
        ))
        XCTAssertTrue(PasteTargetPolicy.shouldPasteURLInsteadOfImage(
            applicationName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            windowTitle: "Discord"
        ))
    }

    func testPasteTargetPolicyAllowsImagesForNonDiscordTargets() {
        XCTAssertFalse(PasteTargetPolicy.shouldPasteURLInsteadOfImage(
            applicationName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap"
        ))
        XCTAssertFalse(PasteTargetPolicy.shouldPasteURLInsteadOfImage(
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Example Domain"
        ))
    }

    func testOCRPipelineIndexesTextWithFakeRecognizer() throws {
        let oldEnabled = RuntimePreferences.shared.ocrIndexingEnabled
        RuntimePreferences.shared.ocrIndexingEnabled = true
        defer { RuntimePreferences.shared.ocrIndexingEnabled = oldEnabled }

        let file = try temporaryOCRFile()
        let record = UploadRecord(
            id: "ocr-1",
            profileId: "profile",
            localFilePath: file.path,
            status: .uploaded,
            kind: .image,
            ocrStatus: .pending
        )
        let store = MemoryOCRStore(records: [record])
        let recognizer = FakeOCRRecognizer(text: "Invoice total banana-42")
        let manager = OCRIndexManager(recognizer: recognizer, store: store, queueLabel: "test.ocr.pipeline")

        let result = manager.indexRecordNow(id: "ocr-1")
        let updated = try XCTUnwrap(store.record(id: "ocr-1"))

        XCTAssertEqual(result, .indexed)
        XCTAssertEqual(recognizer.calls, 1)
        XCTAssertEqual(updated.ocrStatus, .indexed)
        XCTAssertEqual(updated.ocrText, "Invoice total banana-42")
        XCTAssertEqual(updated.ocrEngine, "Fake OCR")
        XCTAssertEqual(updated.ocrEngineVersion, "test")
        XCTAssertNotNil(updated.ocrIndexedAt)
        XCTAssertNotNil(updated.ocrFileSize)
        XCTAssertNotNil(updated.ocrFileModifiedAt)
    }

    func testHistorySearchMatchesOCRText() {
        let record = UploadRecord(
            id: "search-1",
            profileId: "profile",
            localFilePath: "/tmp/plain-name.png",
            status: .uploaded,
            kind: .image,
            ocrStatus: .indexed,
            ocrText: "This screenshot contains a private launch phrase"
        )

        XCTAssertTrue(UploadHistoryViewModel.record(
            record,
            matchesSearch: "launch phrase",
            profileName: "Uploads",
            filename: "plain-name.png",
            statusText: "Uploaded"
        ))
        XCTAssertFalse(UploadHistoryViewModel.record(
            record,
            matchesSearch: "not present",
            profileName: "Uploads",
            filename: "plain-name.png",
            statusText: "Uploaded"
        ))
        XCTAssertEqual(
            OCRIndexManager.snippet(for: record.ocrText, query: "launch"),
            "This screenshot contains a private launch phrase"
        )
    }

    func testDisabledOCRModeMarksRecordWithoutRunningRecognizer() throws {
        let oldEnabled = RuntimePreferences.shared.ocrIndexingEnabled
        RuntimePreferences.shared.ocrIndexingEnabled = false
        defer { RuntimePreferences.shared.ocrIndexingEnabled = oldEnabled }

        let file = try temporaryOCRFile()
        let record = UploadRecord(id: "disabled-1", profileId: "profile", localFilePath: file.path, status: .uploaded, kind: .image)
        let store = MemoryOCRStore(records: [record])
        let recognizer = FakeOCRRecognizer()
        let manager = OCRIndexManager(recognizer: recognizer, store: store, queueLabel: "test.ocr.disabled")

        let result = manager.indexRecordNow(id: "disabled-1")
        let updated = try XCTUnwrap(store.record(id: "disabled-1"))

        XCTAssertEqual(result, .skipped)
        XCTAssertEqual(recognizer.calls, 0)
        XCTAssertEqual(updated.ocrStatus, .disabled)
        XCTAssertNil(updated.ocrText)
    }

    func testBackfillSkipsUnchangedRecordsAndMarksMissingFiles() throws {
        let oldEnabled = RuntimePreferences.shared.ocrIndexingEnabled
        RuntimePreferences.shared.ocrIndexingEnabled = true
        defer { RuntimePreferences.shared.ocrIndexingEnabled = oldEnabled }

        let file = try temporaryOCRFile()
        let existing = UploadRecord(id: "existing", profileId: "profile", localFilePath: file.path, status: .uploaded, kind: .image)
        let missing = UploadRecord(id: "missing", profileId: "profile", localFilePath: "/tmp/does-not-exist-\(UUID().uuidString).png", status: .uploaded, kind: .image)
        let store = MemoryOCRStore(records: [existing, missing])
        let recognizer = FakeOCRRecognizer(text: "indexed once")
        let manager = OCRIndexManager(recognizer: recognizer, store: store, queueLabel: "test.ocr.backfill")

        let first = manager.runBatchSync(mode: .indexExisting)
        XCTAssertEqual(first.indexed, 1)
        XCTAssertEqual(first.missing, 1)
        XCTAssertEqual(recognizer.calls, 1)

        let second = manager.runBatchSync(mode: .indexExisting)
        XCTAssertEqual(second.skipped, 1)
        XCTAssertEqual(second.missing, 1)
        XCTAssertEqual(recognizer.calls, 1)
        XCTAssertEqual(store.record(id: "missing")?.ocrStatus, .missingFile)
    }

    func testClearOCRIndexRemovesOnlyOCRMetadata() throws {
        let record = UploadRecord(
            id: "clear-1",
            profileId: "profile",
            localFilePath: "/tmp/clear.png",
            status: .uploaded,
            url: "https://example.com/clear.png",
            kind: .image,
            ocrStatus: .indexed,
            ocrText: "clear me",
            ocrEngine: "Fake OCR",
            ocrEngineVersion: "test",
            ocrIndexedAt: Date(),
            ocrFileSize: 12,
            ocrFileModifiedAt: Date(),
            ocrError: "old",
            ocrRetryCount: 1
        )
        let store = MemoryOCRStore(records: [record])
        let manager = OCRIndexManager(recognizer: FakeOCRRecognizer(), store: store, queueLabel: "test.ocr.clear")

        manager.clearIndex()
        let updated = try XCTUnwrap(store.record(id: "clear-1"))

        XCTAssertEqual(updated.url, "https://example.com/clear.png")
        XCTAssertNil(updated.ocrStatus)
        XCTAssertNil(updated.ocrText)
        XCTAssertNil(updated.ocrEngine)
        XCTAssertNil(updated.ocrIndexedAt)
    }

    func testImageUploadMetadataStripperRemovesExifGpsAndTiffDictionaries() throws {
        let pattern = makeBlockPatternRGBA(blockSize: 24, blocksWide: 2, blocksHigh: 2) { bx, by in
            switch (bx, by) {
            case (0, 0): return (20, 20, 20, 255)
            case (1, 0): return (90, 90, 90, 255)
            case (0, 1): return (160, 160, 160, 255)
            default: return (230, 230, 230, 255)
            }
        }
        let cg = makeCGImageRGBA(pixels: pattern.pixels, width: pattern.width, height: pattern.height)
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("craftycannon-metadata-fixture-\(UUID().uuidString).jpg")
        try jpegDataWithMetadata(cg: cg, exifOrientation: 1).write(to: inputURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let originalProps = try imageProperties(at: inputURL)
        XCTAssertNotNil(originalProps[kCGImagePropertyExifDictionary])
        XCTAssertNotNil(originalProps[kCGImagePropertyGPSDictionary])
        XCTAssertNotNil(originalProps[kCGImagePropertyTIFFDictionary])

        let strippedURL = try XCTUnwrap(ImageUploadMetadataStripper.strippedTemporaryCopy(from: inputURL))
        defer { try? FileManager.default.removeItem(at: strippedURL) }
        let strippedProps = try imageProperties(at: strippedURL)
        let strippedExif = strippedProps[kCGImagePropertyExifDictionary] as? [CFString: Any]

        XCTAssertNil(strippedExif?[kCGImagePropertyExifDateTimeOriginal])
        XCTAssertNil(strippedExif?[kCGImagePropertyExifLensModel])
        XCTAssertNil(strippedProps[kCGImagePropertyGPSDictionary])
        XCTAssertNil(strippedProps[kCGImagePropertyTIFFDictionary])
    }

    func testImageUploadTranscoderWritesSelectedFormat() throws {
        let pattern = makeBlockPatternRGBA(blockSize: 16, blocksWide: 2, blocksHigh: 2) { bx, by in
            switch (bx, by) {
            case (0, 0): return (255, 0, 0, 255)
            case (1, 0): return (0, 255, 0, 255)
            case (0, 1): return (0, 0, 255, 255)
            default: return (255, 255, 255, 255)
            }
        }
        let cg = makeCGImageRGBA(pixels: pattern.pixels, width: pattern.width, height: pattern.height)
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("craftycannon-format-fixture-\(UUID().uuidString).png")
        try pngData(cg: cg).write(to: inputURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let convertedURL = try XCTUnwrap(ImageUploadTranscoder.convertedTemporaryCopy(from: inputURL, to: .jpeg))
        defer { try? FileManager.default.removeItem(at: convertedURL) }

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(convertedURL as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        XCTAssertEqual(convertedURL.pathExtension, ImageUploadFormat.jpeg.filenameExtension)
    }

    func testImageUploadMetadataStripperNormalizesExifOrientation() throws {
        let block = 28
        let pattern = makeBlockPatternRGBA(blockSize: block, blocksWide: 2, blocksHigh: 3) { bx, by in
            switch (bx, by) {
            case (0, 0): return (5, 5, 5, 255)
            case (1, 0): return (55, 55, 55, 255)
            case (0, 1): return (105, 105, 105, 255)
            case (1, 1): return (155, 155, 155, 255)
            case (0, 2): return (205, 205, 205, 255)
            default: return (245, 245, 245, 255)
            }
        }
        let cg = makeCGImageRGBA(pixels: pattern.pixels, width: pattern.width, height: pattern.height)
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("craftycannon-oriented-fixture-\(UUID().uuidString).jpg")
        try jpegDataWithMetadata(cg: cg, exifOrientation: 6).write(to: inputURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let strippedURL = try XCTUnwrap(ImageUploadMetadataStripper.strippedTemporaryCopy(from: inputURL))
        defer { try? FileManager.default.removeItem(at: strippedURL) }
        let strippedProps = try imageProperties(at: strippedURL)
        let strippedOrientation = (strippedProps[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        XCTAssertEqual(strippedOrientation, 1)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(strippedURL as CFURL, nil))
        let strippedCG = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(strippedCG.width, pattern.height)
        XCTAssertEqual(strippedCG.height, pattern.width)

        let out = rgbaTopLeftPixels(from: strippedCG)
        let outW = pattern.height
        let sampleX = block / 2
        let sampleY = block / 2

        func expectedColorAtOutputBlock(_ obx: Int, _ oby: Int) -> (UInt8, UInt8, UInt8, UInt8) {
            let srcBlocksWide = 2
            let srcBx = (srcBlocksWide - 1) - oby
            let srcBy = obx
            switch (srcBx, srcBy) {
            case (0, 0): return (5, 5, 5, 255)
            case (1, 0): return (55, 55, 55, 255)
            case (0, 1): return (105, 105, 105, 255)
            case (1, 1): return (155, 155, 155, 255)
            case (0, 2): return (205, 205, 205, 255)
            default: return (245, 245, 245, 255)
            }
        }

        for obx in 0..<3 {
            for oby in 0..<2 {
                let px = obx * block + sampleX
                let py = oby * block + sampleY
                assertPixelClose(
                    pixelRGBA(out, x: px, y: py, width: outW),
                    expectedColorAtOutputBlock(obx, oby),
                    tolerance: 45
                )
            }
        }
    }

    func testMakeUprightBitmapRepRespectsEXIFOrientation180() throws {
        // Use larger blocks to avoid JPEG artifacts affecting exact pixel comparisons.
        // 2x2 block pattern in top-left origin order:
        // Use grayscale levels so channel ordering (RGBA vs BGRA) doesn't matter.
        // TL = 10, TR = 80
        // BL = 160, BR = 240
        let block = 32
        let pattern = makeBlockPatternRGBA(blockSize: block, blocksWide: 2, blocksHigh: 2) { bx, by in
            switch (bx, by) {
            case (0, 0): return (10, 10, 10, 255)
            case (1, 0): return (80, 80, 80, 255)
            case (0, 1): return (160, 160, 160, 255)
            default: return (240, 240, 240, 255)
            }
        }
        let cg = makeCGImageRGBA(pixels: pattern.pixels, width: pattern.width, height: pattern.height)
        // EXIF orientation=3 means "rotate 180 to display upright".
        let data = try jpegData(cg: cg, exifOrientation: 3)
        let img = try XCTUnwrap(NSImage(data: data))
        let rep = try makeUprightBitmapRep(from: img)
        XCTAssertEqual(rep.pixelsWide, pattern.width)
        XCTAssertEqual(rep.pixelsHigh, pattern.height)
        let outCg = try XCTUnwrap(rep.cgImage)
        let out = rgbaTopLeftPixels(from: outCg)
        // Sample the center of each output quadrant.
        let cx = block / 2
        let cy = block / 2
        let w = pattern.width
        // After 180 rotation: TL<-BR(240), TR<-BL(160), BL<-TR(80), BR<-TL(10)
        assertPixelClose(pixelRGBA(out, x: cx, y: cy, width: w), (240, 240, 240, 255), tolerance: 45) // TL
        assertPixelClose(pixelRGBA(out, x: w - 1 - cx, y: cy, width: w), (160, 160, 160, 255), tolerance: 45) // TR
        assertPixelClose(pixelRGBA(out, x: cx, y: w - 1 - cy, width: w), (80, 80, 80, 255), tolerance: 45) // BL
        assertPixelClose(pixelRGBA(out, x: w - 1 - cx, y: w - 1 - cy, width: w), (10, 10, 10, 255), tolerance: 45) // BR
    }

    func testMakeUprightBitmapRepRespectsEXIFOrientation90CW() throws {
        // Use larger blocks to avoid JPEG artifacts affecting exact pixel comparisons.
        // 2x3 block pattern in top-left origin order.
        // Use grayscale levels so channel ordering (RGBA vs BGRA) doesn't matter.
        let block = 28
        let pattern = makeBlockPatternRGBA(blockSize: block, blocksWide: 2, blocksHigh: 3) { bx, by in
            switch (bx, by) {
            case (0, 0): return (5, 5, 5, 255)
            case (1, 0): return (55, 55, 55, 255)
            case (0, 1): return (105, 105, 105, 255)
            case (1, 1): return (155, 155, 155, 255)
            case (0, 2): return (205, 205, 205, 255)
            default: return (245, 245, 245, 255)
            }
        }
        let cg = makeCGImageRGBA(pixels: pattern.pixels, width: pattern.width, height: pattern.height)
        // EXIF orientation=6 (right) maps to a 90 CCW block remap in this
        // top-left-origin sampling space.
        let data = try jpegData(cg: cg, exifOrientation: 6)
        let img = try XCTUnwrap(NSImage(data: data))
        let rep = try makeUprightBitmapRep(from: img)
        XCTAssertEqual(rep.pixelsWide, pattern.height)
        XCTAssertEqual(rep.pixelsHigh, pattern.width)

        let outCg = try XCTUnwrap(rep.cgImage)
        let out = rgbaTopLeftPixels(from: outCg)

        // Sample the center of each output block and verify it matches the expected 90CCW rotation.
        let outW = pattern.height
        let sampleX = block / 2
        let sampleY = block / 2

        func expectedColorAtOutputBlock(_ obx: Int, _ oby: Int) -> (UInt8, UInt8, UInt8, UInt8) {
            // Inverse of 90CCW: srcX = (srcWidth - 1) - destY, srcY = destX
            let srcBlocksWide = 2
            let srcBx = (srcBlocksWide - 1) - oby
            let srcBy = obx
            // Map to the original grayscale levels
            switch (srcBx, srcBy) {
            case (0, 0): return (5, 5, 5, 255)
            case (1, 0): return (55, 55, 55, 255)
            case (0, 1): return (105, 105, 105, 255)
            case (1, 1): return (155, 155, 155, 255)
            case (0, 2): return (205, 205, 205, 255)
            default: return (245, 245, 245, 255)
            }
        }

        for obx in 0..<3 {
            for oby in 0..<2 {
                let px = obx * block + sampleX
                let py = oby * block + sampleY
                let actual = pixelRGBA(out, x: px, y: py, width: outW)
                let expected = expectedColorAtOutputBlock(obx, oby)
                assertPixelClose(actual, expected, tolerance: 45)
            }
        }
    }

    func testMainShellViewModelStartsWithNoSelection() throws {
        let actions = MainHubActions(
            captureRegionUpload: {},
            captureWindowUpload: {},
            captureFullscreenUpload: {},
            captureTopTaskbarUpload: {},
            recordScreenUpload: {},
            captureRegionExpiringUpload: {},
            uploadClipboardImage: {},
            uploadImageFile: {},
            uploadExpiringFile: {},
            uploadFromURL: {},
            uploadText: {},
            uploadFolder: {},
            shortenURL: {},
            openWatchFolders: {},
            openPreferences: {},
            openScreenshotsFolder: {},
            chooseScreenshotsFolder: {},
            resetScreenshotsFolder: {},
            openLatestInEditor: {},
            openHistorySection: {}
        )

        let viewModel = MainShellViewModel(actions: actions)
        XCTAssertNotNil(viewModel.currentTree)
    }

    func testRemovedBackendsDecodeAsZiplineForLegacyProfiles() throws {
        for rawBackend in ["craftyCannonWorker", "ferretsWorker", "imgur"] {
            let payload = """
            {
              "id": "\(rawBackend)",
              "name": "Legacy",
              "endpoint": "https://legacy.example.com",
              "backend": "\(rawBackend)"
            }
            """
            let data = try XCTUnwrap(payload.data(using: .utf8))
            let profile = try JSONDecoder().decode(UploadProfile.self, from: data)
            XCTAssertEqual(profile.backend, .ziplineV4)
        }
    }

    func testEndpointValidationAcceptsZiplineAuthStatusAsReachable() {
        let result = Uploader.endpointValidationResult(
            backend: .ziplineV4,
            statusCode: 401,
            body: nil
        )

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.message, "Zipline endpoint is reachable.")
    }

    func testNormalizedLocalMirrorPrefixKebabCasesValue() {
        XCTAssertEqual(UploadService.normalizedLocalMirrorPrefix("Google Chrome"), "google-chrome")
        XCTAssertEqual(UploadService.normalizedLocalMirrorPrefix("   OBS / Studio   "), "obs-studio")
    }

    func testBuildLocalMirrorFilenameUsesPrefixAndKeepsExtension() {
        let fileURL = URL(fileURLWithPath: "/tmp/example.PNG")
        let filename = UploadService.buildLocalMirrorFilename(
            fileUrl: fileURL,
            preferredPrefix: "Google Chrome",
            randomToken: "A1B2C3D4E5"
        )
        XCTAssertEqual(filename, "google-chrome-a1b2c3d4.png")
    }

    func testBuildLocalMirrorFilenameFallsBackWhenPrefixInvalid() {
        let fileURL = URL(fileURLWithPath: "/tmp/example.png")
        let filename = UploadService.buildLocalMirrorFilename(
            fileUrl: fileURL,
            preferredPrefix: "!!!",
            fallbackPrefix: "fullscreen",
            randomToken: "cafebabe"
        )
        XCTAssertEqual(filename, "fullscreen-cafebabe.png")
    }

    func testBuildLocalMirrorFilenameWithoutPrefixStaysRandomOnly() {
        let fileURL = URL(fileURLWithPath: "/tmp/example")
        let filename = UploadService.buildLocalMirrorFilename(
            fileUrl: fileURL,
            preferredPrefix: nil,
            randomToken: "ABC12345"
        )
        XCTAssertEqual(filename, "abc12345.png")
    }

    func testCloudflareTraceParserExtractsPublicIP() {
        let trace = """
        fl=123f45
        ip=203.0.113.42
        ts=1710000000.123
        """

        XCTAssertEqual(CloudflareAllowlistManager.publicIP(fromCloudflareTrace: trace), "203.0.113.42")
        XCTAssertTrue(CloudflareAllowlistManager.isValidIPAddress("203.0.113.42"))
        XCTAssertTrue(CloudflareAllowlistManager.isValidIPAddress("2001:db8::42"))
        XCTAssertFalse(CloudflareAllowlistManager.isValidIPAddress("not-an-ip"))
        XCTAssertTrue(CloudflareAllowlistManager.looksLikeCloudflareId("1ca49d1d335678c6291bd708404aee24"))
        XCTAssertFalse(CloudflareAllowlistManager.looksLikeCloudflareId("crafty"))
    }

    func testCloudflareManagedItemsReplacesOnlyThisDeviceEntry() {
        let items = [
            CloudflareAllowlistManager.ListItem(id: "1", ip: "198.51.100.10", comment: "admin"),
            CloudflareAllowlistManager.ListItem(id: "2", ip: "203.0.113.2", comment: "craftycannon-device:old-device Old Mac"),
            CloudflareAllowlistManager.ListItem(id: "3", ip: "203.0.113.3", comment: "craftycannon-device:this-device Previous IP")
        ]

        let result = CloudflareAllowlistManager.managedItems(
            currentItems: items,
            currentIP: "203.0.113.44",
            deviceMarker: "craftycannon-device:this-device",
            deviceName: "Studio Mac",
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(result.map { $0["ip"] }, ["198.51.100.10", "203.0.113.2", "203.0.113.44"])
        XCTAssertEqual(result.last?["comment"], "craftycannon-device:this-device Studio Mac updated 1970-01-01T00:00:00Z")
    }

    func testCloudflareNetworkPathSignatureIsOrderIndependent() {
        let a = CloudflareAllowlistManager.networkPathSignature(status: "satisfied", interfaces: ["en0", "utun3"])
        let b = CloudflareAllowlistManager.networkPathSignature(status: "satisfied", interfaces: ["utun3", "en0"])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, CloudflareAllowlistManager.networkPathSignature(status: "unsatisfied", interfaces: ["en0", "utun3"]))
    }

    func testCloudflareRefreshesOnlyOnRealPathChanges() {
        let wifi = CloudflareAllowlistManager.networkPathSignature(status: "satisfied", interfaces: ["en0"])
        let offline = CloudflareAllowlistManager.networkPathSignature(status: "unsatisfied", interfaces: [])
        let ethernet = CloudflareAllowlistManager.networkPathSignature(status: "satisfied", interfaces: ["en5"])

        // First callback after the monitor starts reports current state; the startup timer covers it.
        XCTAssertFalse(CloudflareAllowlistManager.shouldRefreshAfterPathChange(
            previousSignature: nil, newSignature: wifi, isSatisfied: true))
        // Repeated callbacks for the same path do nothing.
        XCTAssertFalse(CloudflareAllowlistManager.shouldRefreshAfterPathChange(
            previousSignature: wifi, newSignature: wifi, isSatisfied: true))
        // Losing connectivity does not trigger a refresh.
        XCTAssertFalse(CloudflareAllowlistManager.shouldRefreshAfterPathChange(
            previousSignature: wifi, newSignature: offline, isSatisfied: false))
        // Regaining or switching connectivity does.
        XCTAssertTrue(CloudflareAllowlistManager.shouldRefreshAfterPathChange(
            previousSignature: offline, newSignature: wifi, isSatisfied: true))
        XCTAssertTrue(CloudflareAllowlistManager.shouldRefreshAfterPathChange(
            previousSignature: wifi, newSignature: ethernet, isSatisfied: true))
    }

    func testHotKeyBindingsDecodeLegacyJSONWithoutFrozenBinding() throws {
        // Bindings persisted before captureRegionUploadFrozen existed must keep
        // the user's saved shortcuts and fill the new binding with its default.
        let legacyJSON = """
        {
          "captureRegionUpload": {"key": "K", "command": true, "shift": false, "option": false, "control": false},
          "captureRegionUploadExpiring": {"key": "K", "command": true, "shift": true, "option": false, "control": false},
          "uploadClipboard": {"key": "9", "command": true, "shift": true, "option": false, "control": false}
        }
        """
        let decoded = try JSONDecoder().decode(HotKeyBindings.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.captureRegionUpload.key, "K")
        XCTAssertEqual(decoded.captureRegionUploadExpiring.key, "K")
        XCTAssertTrue(decoded.captureRegionUploadExpiring.shift)
        XCTAssertEqual(decoded.uploadClipboard.key, "9")
        XCTAssertEqual(decoded.captureRegionUploadFrozen, HotKeyBindings.defaultValue.captureRegionUploadFrozen)
    }

    func testHotKeyBindingsRoundTripIncludesFrozenBinding() throws {
        var bindings = HotKeyBindings.defaultValue
        bindings.captureRegionUploadFrozen = HotKeyShortcut(key: "L", command: true, option: true)
        let data = try JSONEncoder().encode(bindings)
        let decoded = try JSONDecoder().decode(HotKeyBindings.self, from: data)
        XCTAssertEqual(decoded, bindings)
    }

    func testMultipartSafeFilenameStripsQuoteAndHeaderInjectionCharacters() {
        XCTAssertEqual(Uploader.multipartSafeFilename("report.pdf"), "report.pdf")
        XCTAssertEqual(Uploader.multipartSafeFilename("a\"b.png"), "a_b.png")
        XCTAssertEqual(
            Uploader.multipartSafeFilename("evil\r\nContent-Type: text/html\r\n.png"),
            "evil__Content-Type: text/html__.png"
        )
        XCTAssertEqual(Uploader.multipartSafeFilename("back\\slash.png"), "back_slash.png")
        XCTAssertEqual(Uploader.multipartSafeFilename("\"\r\n"), "file.bin")
    }

    func testZiplineFilenameHeadersOverrideServerGeneratedName() throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://zipline.example.test/api/upload")))

        Uploader.applyZiplineFilenameHeaders(to: &request, filename: "a8f3k9q2m0z7x1bc.png")

        XCTAssertEqual(request.value(forHTTPHeaderField: "x-zipline-filename"), "a8f3k9q2m0z7x1bc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-zipline-file-extension"), "png")
    }
}
