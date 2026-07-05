import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(SwiftUI)
import SwiftUI
#endif

enum UIPaletteID: String, CaseIterable, Identifiable, Codable {
  case classic
  case nord
  case gruvbox
  case mono
  case megaDark
  case oledBlack
  case rainbow
  case custom

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .classic: return "Classic"
    case .nord: return "Nord"
    case .gruvbox: return "Gruvbox"
    case .mono: return "Mono"
    case .megaDark: return "Mega Dark"
    case .oledBlack: return "OLED Black"
    case .rainbow: return "Rainbow"
    case .custom: return "Custom"
    }
  }
}

struct RGBAColor: Codable, Equatable {
  var r: Double
  var g: Double
  var b: Double
  var a: Double

  init(r: Double, g: Double, b: Double, a: Double = 1.0) {
    func clamp(_ v: Double) -> Double { max(0.0, min(1.0, v)) }
    self.r = clamp(r)
    self.g = clamp(g)
    self.b = clamp(b)
    self.a = clamp(a)
  }

  static func rgb255(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) -> RGBAColor {
    RGBAColor(
      r: Double(max(0, min(255, r))) / 255.0,
      g: Double(max(0, min(255, g))) / 255.0,
      b: Double(max(0, min(255, b))) / 255.0,
      a: Double(max(0, min(255, a))) / 255.0
    )
  }

#if canImport(SwiftUI)
  func toSwiftUIColor() -> Color {
    Color(.sRGB, red: r, green: g, blue: b, opacity: a)
  }

  static func fromSwiftUIColor(_ c: Color) -> RGBAColor? {
#if canImport(AppKit)
    let ns = NSColor(c)
    guard let srgb = ns.usingColorSpace(.sRGB) else { return nil }
    return RGBAColor(
      r: Double(srgb.redComponent),
      g: Double(srgb.greenComponent),
      b: Double(srgb.blueComponent),
      a: Double(srgb.alphaComponent)
    )
#else
    _ = c
    return nil
#endif
  }
#endif
}

struct UIPaletteData: Codable, Equatable {
  var windowGradientA: RGBAColor
  var windowGradientB: RGBAColor
  var windowGradientC: RGBAColor
  var windowRadialSpot: RGBAColor
  var railPanelAccent: RGBAColor
  var contextPanelAccent: RGBAColor

  var captureAccent: RGBAColor
  var uploadAccent: RGBAColor
  var workflowsAccent: RGBAColor
  var toolsAccent: RGBAColor
  var afterCaptureAccent: RGBAColor
  var afterUploadAccent: RGBAColor
  var destinationsAccent: RGBAColor
  var settingsAccent: RGBAColor
  var historyAccent: RGBAColor
}

struct UIPalette: Equatable {
  var id: UIPaletteID
  var displayName: String
  var data: UIPaletteData
}

enum UIPaletteCatalog {
  static let presets: [UIPalette] = [
    UIPalette(id: .classic, displayName: UIPaletteID.classic.displayName, data: classic),
    UIPalette(id: .nord, displayName: UIPaletteID.nord.displayName, data: nord),
    UIPalette(id: .gruvbox, displayName: UIPaletteID.gruvbox.displayName, data: gruvbox),
    UIPalette(id: .mono, displayName: UIPaletteID.mono.displayName, data: mono),
    UIPalette(id: .megaDark, displayName: UIPaletteID.megaDark.displayName, data: megaDark),
    UIPalette(id: .oledBlack, displayName: UIPaletteID.oledBlack.displayName, data: oledBlack),
    UIPalette(id: .rainbow, displayName: UIPaletteID.rainbow.displayName, data: rainbow),
  ]

  static func defaultCustomSeed() -> UIPaletteData {
    classic
  }

  static func effectivePalette(selected: UIPaletteID, custom: UIPaletteData) -> UIPalette {
    if selected == .custom {
      return UIPalette(id: .custom, displayName: UIPaletteID.custom.displayName, data: custom)
    }
    if let preset = presets.first(where: { $0.id == selected }) {
      return preset
    }
    return UIPalette(id: .classic, displayName: UIPaletteID.classic.displayName, data: classic)
  }

  private static let classic = UIPaletteData(
    windowGradientA: .rgb255(26, 115, 242),
    windowGradientB: .rgb255(64, 217, 179),
    windowGradientC: .rgb255(250, 199, 56),
    windowRadialSpot: .rgb255(242, 77, 89),
    railPanelAccent: .rgb255(26, 115, 242),
    contextPanelAccent: .rgb255(64, 217, 179),
    captureAccent: .rgb255(242, 140, 51),
    uploadAccent: .rgb255(38, 179, 217),
    workflowsAccent: .rgb255(64, 199, 115),
    toolsAccent: .rgb255(242, 77, 89),
    afterCaptureAccent: .rgb255(250, 199, 56),
    afterUploadAccent: .rgb255(89, 217, 179),
    destinationsAccent: .rgb255(64, 166, 140),
    settingsAccent: .rgb255(140, 153, 179),
    historyAccent: .rgb255(64, 115, 242)
  )

  private static let nord = UIPaletteData(
    windowGradientA: .rgb255(46, 52, 64),
    windowGradientB: .rgb255(94, 129, 172),
    windowGradientC: .rgb255(163, 190, 140),
    windowRadialSpot: .rgb255(191, 97, 106),
    railPanelAccent: .rgb255(94, 129, 172),
    contextPanelAccent: .rgb255(136, 192, 208),
    captureAccent: .rgb255(208, 135, 112),
    uploadAccent: .rgb255(136, 192, 208),
    workflowsAccent: .rgb255(163, 190, 140),
    toolsAccent: .rgb255(191, 97, 106),
    afterCaptureAccent: .rgb255(235, 203, 139),
    afterUploadAccent: .rgb255(143, 188, 187),
    destinationsAccent: .rgb255(129, 161, 193),
    settingsAccent: .rgb255(229, 233, 240),
    historyAccent: .rgb255(94, 129, 172)
  )

  private static let gruvbox = UIPaletteData(
    windowGradientA: .rgb255(251, 73, 52),
    windowGradientB: .rgb255(184, 187, 38),
    windowGradientC: .rgb255(250, 189, 47),
    windowRadialSpot: .rgb255(211, 134, 155),
    railPanelAccent: .rgb255(250, 189, 47),
    contextPanelAccent: .rgb255(131, 165, 152),
    captureAccent: .rgb255(251, 73, 52),
    uploadAccent: .rgb255(131, 165, 152),
    workflowsAccent: .rgb255(184, 187, 38),
    toolsAccent: .rgb255(211, 134, 155),
    afterCaptureAccent: .rgb255(250, 189, 47),
    afterUploadAccent: .rgb255(142, 192, 124),
    destinationsAccent: .rgb255(254, 128, 25),
    settingsAccent: .rgb255(213, 196, 161),
    historyAccent: .rgb255(131, 165, 152)
  )

  private static let mono = UIPaletteData(
    windowGradientA: .rgb255(90, 90, 92),
    windowGradientB: .rgb255(140, 140, 145),
    windowGradientC: .rgb255(200, 200, 205),
    windowRadialSpot: .rgb255(120, 120, 125),
    railPanelAccent: .rgb255(110, 110, 115),
    contextPanelAccent: .rgb255(150, 150, 155),
    captureAccent: .rgb255(210, 210, 214),
    uploadAccent: .rgb255(190, 190, 194),
    workflowsAccent: .rgb255(170, 170, 175),
    toolsAccent: .rgb255(155, 155, 160),
    afterCaptureAccent: .rgb255(200, 200, 205),
    afterUploadAccent: .rgb255(180, 180, 185),
    destinationsAccent: .rgb255(160, 160, 165),
    settingsAccent: .rgb255(140, 140, 145),
    historyAccent: .rgb255(120, 120, 125)
  )

  private static let megaDark = UIPaletteData(
    windowGradientA: .rgb255(2, 3, 6),
    windowGradientB: .rgb255(6, 9, 15),
    windowGradientC: .rgb255(10, 14, 22),
    windowRadialSpot: .rgb255(24, 18, 42),
    railPanelAccent: .rgb255(36, 40, 58),
    contextPanelAccent: .rgb255(42, 52, 74),
    captureAccent: .rgb255(255, 106, 61),
    uploadAccent: .rgb255(0, 230, 255),
    workflowsAccent: .rgb255(97, 255, 170),
    toolsAccent: .rgb255(255, 64, 184),
    afterCaptureAccent: .rgb255(255, 214, 64),
    afterUploadAccent: .rgb255(118, 114, 255),
    destinationsAccent: .rgb255(189, 111, 255),
    settingsAccent: .rgb255(150, 161, 186),
    historyAccent: .rgb255(76, 180, 255)
  )

  private static let oledBlack = UIPaletteData(
    windowGradientA: .rgb255(0, 0, 0),
    windowGradientB: .rgb255(0, 0, 0),
    windowGradientC: .rgb255(0, 0, 0),
    windowRadialSpot: .rgb255(0, 0, 0),
    railPanelAccent: .rgb255(20, 24, 28),
    contextPanelAccent: .rgb255(18, 22, 26),
    captureAccent: .rgb255(255, 126, 65),
    uploadAccent: .rgb255(45, 212, 255),
    workflowsAccent: .rgb255(70, 255, 174),
    toolsAccent: .rgb255(255, 78, 174),
    afterCaptureAccent: .rgb255(255, 219, 82),
    afterUploadAccent: .rgb255(134, 125, 255),
    destinationsAccent: .rgb255(198, 118, 255),
    settingsAccent: .rgb255(185, 195, 214),
    historyAccent: .rgb255(92, 188, 255)
  )

  private static let rainbow = UIPaletteData(
    windowGradientA: .rgb255(255, 64, 64),
    windowGradientB: .rgb255(255, 184, 48),
    windowGradientC: .rgb255(76, 220, 120),
    windowRadialSpot: .rgb255(122, 92, 255),
    railPanelAccent: .rgb255(255, 64, 64),
    contextPanelAccent: .rgb255(76, 220, 120),
    captureAccent: .rgb255(255, 106, 61),
    uploadAccent: .rgb255(63, 197, 255),
    workflowsAccent: .rgb255(92, 235, 156),
    toolsAccent: .rgb255(255, 76, 187),
    afterCaptureAccent: .rgb255(255, 214, 64),
    afterUploadAccent: .rgb255(97, 113, 255),
    destinationsAccent: .rgb255(177, 92, 255),
    settingsAccent: .rgb255(147, 160, 255),
    historyAccent: .rgb255(0, 215, 255)
  )
}
