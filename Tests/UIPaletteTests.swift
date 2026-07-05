import XCTest
import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

@testable import CraftyCannon

final class UIPaletteTests: XCTestCase {
  private let paletteIdKey = "runtime.ui.paletteId.v1"
  private let customPaletteKey = "runtime.ui.customPalette.v1"
  private let fileNameUsePatternKey = "runtime.upload.fileName.usePattern.v1"
  private let fileNameUseRandom16Key = "runtime.upload.fileName.useRandom16.v1"
  private let fileNamePatternKey = "runtime.upload.fileName.pattern.v1"

  override func setUp() {
    super.setUp()
    UserDefaults.standard.removeObject(forKey: paletteIdKey)
    UserDefaults.standard.removeObject(forKey: customPaletteKey)
    UserDefaults.standard.removeObject(forKey: fileNameUsePatternKey)
    UserDefaults.standard.removeObject(forKey: fileNameUseRandom16Key)
    UserDefaults.standard.removeObject(forKey: fileNamePatternKey)
  }

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: paletteIdKey)
    UserDefaults.standard.removeObject(forKey: customPaletteKey)
    UserDefaults.standard.removeObject(forKey: fileNameUsePatternKey)
    UserDefaults.standard.removeObject(forKey: fileNameUseRandom16Key)
    UserDefaults.standard.removeObject(forKey: fileNamePatternKey)
    super.tearDown()
  }

  private func noopActions() -> MainHubActions {
    MainHubActions(
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
  }

  func testPaletteDataJSONRoundTrip() throws {
    let data = UIPaletteCatalog.presets.first(where: { $0.id == .classic })!.data
    let encoded = try JSONEncoder().encode(data)
    let decoded = try JSONDecoder().decode(UIPaletteData.self, from: encoded)
    XCTAssertEqual(decoded, data)
  }

  func testPresetCatalogHasExpectedPresets() {
    XCTAssertEqual(UIPaletteCatalog.presets.count, 7)
    XCTAssertEqual(Set(UIPaletteCatalog.presets.map(\.id)), Set([.classic, .nord, .gruvbox, .mono, .megaDark, .oledBlack, .rainbow]))
    XCTAssertFalse(UIPaletteCatalog.presets.contains(where: { $0.id == .custom }))
  }

  func testOLEDBlackPresetUsesTrueBlackWindowBase() {
    let data = UIPaletteCatalog.presets.first(where: { $0.id == .oledBlack })!.data
    XCTAssertEqual(data.windowGradientA, .rgb255(0, 0, 0))
    XCTAssertEqual(data.windowGradientB, .rgb255(0, 0, 0))
    XCTAssertEqual(data.windowGradientC, .rgb255(0, 0, 0))
    XCTAssertEqual(data.windowRadialSpot, .rgb255(0, 0, 0))
  }

  func testRuntimePreferencesFallbacks() {
    UserDefaults.standard.removeObject(forKey: paletteIdKey)
    UserDefaults.standard.removeObject(forKey: customPaletteKey)

    XCTAssertEqual(RuntimePreferences.shared.uiPaletteId, .classic)
    XCTAssertEqual(RuntimePreferences.shared.uiCustomPalette, UIPaletteCatalog.defaultCustomSeed())
  }

  func testRuntimePreferencesInvalidPaletteIdFallsBackToClassic() {
    UserDefaults.standard.set("not-a-real-palette", forKey: paletteIdKey)
    XCTAssertEqual(RuntimePreferences.shared.uiPaletteId, .classic)
  }

  func testMainShellViewModelTracksRuntimePaletteChanges() {
    let viewModel = MainShellViewModel(actions: noopActions())
    XCTAssertEqual(viewModel.uiPaletteId, .classic)

    RuntimePreferences.shared.uiPaletteId = .gruvbox

    XCTAssertEqual(viewModel.uiPaletteId, .gruvbox)
    XCTAssertEqual(viewModel.effectivePalette.id, .gruvbox)
  }

  func testDefaultFilenameTemplateEnablesCustomNaming() {
    let viewModel = MainShellViewModel(actions: noopActions())
    XCTAssertFalse(RuntimePreferences.shared.fileUploadUseNamePattern)

    viewModel.defaultFileNamePattern = "{name}-{date}"

    XCTAssertTrue(RuntimePreferences.shared.fileUploadUseNamePattern)
    XCTAssertEqual(RuntimePreferences.shared.fileNamePattern, "{name}-{date}")
  }

  func testRandom16FilenamePreferenceGeneratesAlphanumericBase() {
    RuntimePreferences.shared.fileUploadUseRandom16Name = true

    let first = RuntimePreferences.shared.generateUploadFilenameBase(originalFilename: "example screenshot.png")
    let second = RuntimePreferences.shared.generateUploadFilenameBase(originalFilename: "example screenshot.png")

    XCTAssertEqual(first.count, 16)
    XCTAssertTrue(first.allSatisfy { $0.isLetter || $0.isNumber })
    XCTAssertEqual(second.count, 16)
    XCTAssertTrue(second.allSatisfy { $0.isLetter || $0.isNumber })
    XCTAssertNotEqual(first, second)
  }

  func testStatusBarPreferencesNavigationShowsMainSettings() {
    let viewModel = MainShellViewModel(actions: noopActions())
    XCTAssertEqual(viewModel.railSelection, .capture)

    NotificationCenter.default.post(name: .mainHubShowSettings, object: nil)

    XCTAssertEqual(viewModel.railSelection, .settings)
    XCTAssertEqual(viewModel.nodeSelection, .settingsApplication)
  }

#if canImport(SwiftUI)
  func testColorConversionSanity() {
    let rgba = RGBAColor.rgb255(18, 52, 86, 200)
    let c = rgba.toSwiftUIColor()
    let roundTrip = RGBAColor.fromSwiftUIColor(c)
    XCTAssertNotNil(roundTrip)
    if let rt = roundTrip {
      XCTAssertEqual(rt.r, rgba.r, accuracy: 0.01)
      XCTAssertEqual(rt.g, rgba.g, accuracy: 0.01)
      XCTAssertEqual(rt.b, rgba.b, accuracy: 0.01)
      XCTAssertEqual(rt.a, rgba.a, accuracy: 0.01)
    }
  }
#endif
}
