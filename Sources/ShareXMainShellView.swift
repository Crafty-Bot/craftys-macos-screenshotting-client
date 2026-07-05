import AppKit
import SwiftUI

private struct CraftyRainbowModeKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

private struct CraftyAccentColorKey: EnvironmentKey {
  static let defaultValue: Color = .accentColor
}

private struct CraftyPaletteDataKey: EnvironmentKey {
  static let defaultValue: UIPaletteData = UIPaletteCatalog.defaultCustomSeed()
}

private struct CraftyOLEDBlackModeKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

private extension EnvironmentValues {
  var craftyRainbowMode: Bool {
    get { self[CraftyRainbowModeKey.self] }
    set { self[CraftyRainbowModeKey.self] = newValue }
  }

  var craftyAccentColor: Color {
    get { self[CraftyAccentColorKey.self] }
    set { self[CraftyAccentColorKey.self] = newValue }
  }

  var craftyPaletteData: UIPaletteData {
    get { self[CraftyPaletteDataKey.self] }
    set { self[CraftyPaletteDataKey.self] = newValue }
  }

  var craftyOLEDBlackMode: Bool {
    get { self[CraftyOLEDBlackModeKey.self] }
    set { self[CraftyOLEDBlackModeKey.self] = newValue }
  }
}

private enum CraftyLayout {
  static let sectionSpacing = 12.0
  static let formControlLabelWidth = 150.0
  static let formControlWidth = 220.0
}

private enum CraftyTheme {
  static func accent(for section: RailSection, palette: UIPalette) -> Color {
    let d = palette.data
    switch section {
    case .capture: return d.captureAccent.toSwiftUIColor()
    case .upload: return d.uploadAccent.toSwiftUIColor()
    case .workflows: return d.workflowsAccent.toSwiftUIColor()
    case .tools: return d.toolsAccent.toSwiftUIColor()
    case .afterCapture: return d.afterCaptureAccent.toSwiftUIColor()
    case .afterUpload: return d.afterUploadAccent.toSwiftUIColor()
    case .destinations: return d.destinationsAccent.toSwiftUIColor()
    case .settings: return d.settingsAccent.toSwiftUIColor()
    case .history: return d.historyAccent.toSwiftUIColor()
    }
  }

  private struct RainbowLayer: View {
    var intensity: Double
    var speedSeconds: Double
    var minimumInterval: Double
    var blurRadius: Double

    var body: some View {
      TimelineView(AnimationTimelineSchedule(minimumInterval: minimumInterval, paused: false)) { ctx in
        let t = ctx.date.timeIntervalSinceReferenceDate
        let phase = (t.truncatingRemainder(dividingBy: speedSeconds)) / speedSeconds
        let angle = Angle.degrees(phase * 360.0)

        ZStack {
          LinearGradient(
            colors: [
              Color.red, Color.orange, Color.yellow, Color.green, Color.mint, Color.cyan, Color.blue, Color.purple, Color.pink, Color.red,
            ].map { $0.opacity(0.78 * intensity) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
          AngularGradient(
            colors: [Color.pink, Color.purple, Color.blue, Color.cyan, Color.green, Color.yellow, Color.orange, Color.red, Color.pink]
              .map { $0.opacity(0.62 * intensity) },
            center: .center
          )
          RadialGradient(
            colors: [
              Color.white.opacity(0.45 * intensity),
              Color.clear,
            ],
            center: .topTrailing,
            startRadius: 20,
            endRadius: 520
          )
        }
        .hueRotation(angle)
        .saturation(2.9)
        .contrast(1.12)
        .brightness(0.10 * intensity)
        .blur(radius: blurRadius)
      }
    }
  }

  static func windowBackground(palette: UIPalette, rainbowMode: Bool) -> some View {
    let d = palette.data
    let oledBlack = palette.id == .oledBlack
    return ZStack {
      oledBlack ? Color.black : Color(nsColor: .windowBackgroundColor)
      LinearGradient(
        colors: [
          d.windowGradientA.toSwiftUIColor().opacity(oledBlack ? 0.0 : 0.16),
          d.windowGradientB.toSwiftUIColor().opacity(oledBlack ? 0.0 : 0.10),
          d.windowGradientC.toSwiftUIColor().opacity(oledBlack ? 0.0 : 0.08),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      RadialGradient(
        colors: [
          d.windowRadialSpot.toSwiftUIColor().opacity(0.10),
          Color.clear,
        ],
        center: .topTrailing,
        startRadius: 40,
        endRadius: 540
      )
      if rainbowMode {
        RainbowLayer(intensity: 1.15, speedSeconds: 16.0, minimumInterval: 1.0 / 30.0, blurRadius: 26)
          .blendMode(.screen)
          .opacity(0.98)
        RainbowLayer(intensity: 0.85, speedSeconds: 9.0, minimumInterval: 1.0 / 20.0, blurRadius: 34)
          .blendMode(.plusLighter)
          .opacity(0.72)
      }
    }
  }

  static func panelBackground(_ accent: Color, rainbowMode: Bool) -> some View {
    panelBackground(accent, rainbowMode: rainbowMode, oledBlack: false)
  }

  static func panelBackground(_ accent: Color, rainbowMode: Bool, oledBlack: Bool) -> some View {
    ZStack {
      oledBlack ? Color.black : Color(nsColor: .underPageBackgroundColor)
      LinearGradient(
        colors: [accent.opacity(oledBlack ? 0.08 : 0.14), Color.clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      if rainbowMode {
        RainbowLayer(intensity: 0.90, speedSeconds: 14.0, minimumInterval: 1.0 / 20.0, blurRadius: 22)
          .blendMode(.screen)
          .opacity(0.78)
      }
    }
  }

  static func cardBackground(_ accent: Color, rainbowMode: Bool) -> some View {
    cardBackground(accent, rainbowMode: rainbowMode, oledBlack: false)
  }

  static func cardBackground(_ accent: Color, rainbowMode: Bool, oledBlack: Bool) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(oledBlack ? Color(red: 0.015, green: 0.015, blue: 0.018) : Color(nsColor: .windowBackgroundColor))
      if rainbowMode {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                Color.red, Color.orange, Color.yellow, Color.green, Color.mint, Color.cyan, Color.blue, Color.purple, Color.pink,
              ].map { $0.opacity(0.22) },
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .blendMode(.screen)
          .opacity(0.95)

        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(
            AngularGradient(
              colors: [Color.pink, Color.purple, Color.blue, Color.cyan, Color.green, Color.yellow, Color.orange, Color.red, Color.pink],
              center: .center
            ),
            lineWidth: 2
          )
          .blendMode(.plusLighter)
          .opacity(0.95)
          .shadow(color: Color.pink.opacity(0.35), radius: 6, x: 0, y: 0)
          .shadow(color: Color.cyan.opacity(0.25), radius: 10, x: 0, y: 0)
      } else {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(
            LinearGradient(
              colors: [accent.opacity(oledBlack ? 0.055 : 0.08), Color.clear],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
      }
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke((rainbowMode ? Color.white.opacity(0.20) : accent.opacity(oledBlack ? 0.30 : 0.22)), lineWidth: 1)
    }
  }
}

struct ShareXMainShellView: View {
  @StateObject private var vm: MainShellViewModel
  @StateObject private var historyVM = UploadHistoryViewModel()

  init(actions: MainHubActions) {
    _vm = StateObject(wrappedValue: MainShellViewModel(actions: actions))
  }

  var body: some View {
    let palette = vm.effectivePalette
    let accent = CraftyTheme.accent(for: vm.railSelection, palette: palette)
    return HSplitView {
      CommandRailView(selection: $vm.railSelection, palette: palette, accentColor: accent, rainbowMode: vm.uiRainbowMode)
        .frame(minWidth: 160, idealWidth: 185, maxWidth: 210)

      CommandContextTreeView(nodes: vm.currentTree, selection: $vm.nodeSelection, palette: palette, accentColor: accent, rainbowMode: vm.uiRainbowMode)
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

      CommandDetailRouterView(vm: vm, historyVM: historyVM)
        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
    }
    .tint(accent)
    .background(CraftyTheme.windowBackground(palette: palette, rainbowMode: vm.uiRainbowMode))
    .environment(\.craftyAccentColor, accent)
    .environment(\.craftyPaletteData, palette.data)
    .environment(\.craftyRainbowMode, vm.uiRainbowMode)
    .environment(\.craftyOLEDBlackMode, palette.id == .oledBlack)
    .preferredColorScheme(palette.id == .oledBlack ? .dark : nil)
    .animation(.easeInOut(duration: 0.25), value: vm.uiRainbowMode)
    .animation(.easeInOut(duration: 0.25), value: vm.uiPaletteId)
    .onAppear {
      vm.refreshProfileInfo()
      vm.syncNodeSelectionForCurrentRail()
    }
  }
}

private struct CommandRailView: View {
  @Binding var selection: RailSection
  var palette: UIPalette
  var accentColor: Color
  var rainbowMode: Bool

  var body: some View {
    VStack(spacing: 0) {
      panelHeader(title: "Commands", subtitle: "", accentColor: accentColor, rainbowMode: rainbowMode)
      Divider()

      // This fixed rail mirrors ShareX MainForm's vertical command strip.
      List(RailSection.allCases, selection: $selection) { section in
        Label(section.title, systemImage: section.symbol)
          .font(.system(size: 13, weight: section == selection ? .semibold : .regular))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .tag(section)
          .listRowInsets(EdgeInsets())
          .listRowBackground(section == selection ? accentColor.opacity(0.18) : Color.clear)
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
    }
    .background(CraftyTheme.panelBackground(palette.data.railPanelAccent.toSwiftUIColor(), rainbowMode: rainbowMode, oledBlack: palette.id == .oledBlack))
  }
}

private struct CommandContextTreeView: View {
  let nodes: [ContextNode]
  @Binding var selection: ContextNodeID?
  var palette: UIPalette
  var accentColor: Color
  var rainbowMode: Bool

  var body: some View {
    VStack(spacing: 0) {
      panelHeader(title: "Context", subtitle: "", accentColor: accentColor, rainbowMode: rainbowMode)
      Divider()

      // Mirrors ShareX TabToTreeView behavior with explicit parent/child pages.
      List(selection: $selection) {
        OutlineGroup(nodes, children: \.childNodes) { node in
          Label(node.title, systemImage: node.symbol)
            .tag(node.id)
            .font(.system(size: 13, weight: node.children.isEmpty ? .regular : .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .listRowInsets(EdgeInsets())
            .listRowBackground(node.id == selection ? accentColor.opacity(0.16) : Color.clear)
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
    }
    .background(CraftyTheme.panelBackground(palette.data.contextPanelAccent.toSwiftUIColor(), rainbowMode: rainbowMode, oledBlack: palette.id == .oledBlack))
  }
}

private struct CommandDetailRouterView: View {
  @ObservedObject var vm: MainShellViewModel
  @ObservedObject var historyVM: UploadHistoryViewModel
  @Environment(\.craftyAccentColor) private var accentColor
  @Environment(\.craftyPaletteData) private var paletteData

  var body: some View {
    Group {
      if vm.railSelection == .history || vm.nodeSelection == .historyUploads {
        UploadHistoryPaneView(vm: historyVM)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
              HStack(spacing: 10) {
                if let logoImage = BrandAssets.logoImage(size: NSSize(width: 24, height: 24)) {
                  Image(nsImage: logoImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                  Text(vm.currentNodeTitle)
                    .font(.title3.weight(.semibold))
                }
              }
              Spacer()
              TextField("Search commands", text: $vm.contextSearchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: CraftyLayout.formControlWidth)
                .help("Filter command context items.")
            }
            Divider()
            commandToolstrip
            Divider()

            page(for: vm.nodeSelection)
          }
          .padding(16)
        }
      }
    }
  }

  @ViewBuilder
  private var commandToolstrip: some View {
    HStack(spacing: 6) {
      Button("Capture") { runQuickCapture() }
        .buttonStyle(.bordered)
        .disabled(!canRunQuickCapture)
        .help("Run the selected capture action.")

      Button("Upload") { runQuickUpload() }
        .buttonStyle(.bordered)
        .disabled(!canRunQuickUpload)
        .help("Run the selected upload action.")

      Button("Shorten") { runQuickShorten() }
        .buttonStyle(.bordered)
        .disabled(!canRunQuickShorten)
        .help("Run the selected URL shortener action.")
    }
    .padding(8)
    .background(
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(
          LinearGradient(
            colors: [
              paletteData.captureAccent.toSwiftUIColor().opacity(0.18),
              paletteData.uploadAccent.toSwiftUIColor().opacity(0.16),
              paletteData.toolsAccent.toSwiftUIColor().opacity(0.14),
            ],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
    )
    .overlay(
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .stroke(accentColor.opacity(0.24), lineWidth: 1)
    )
  }

  private var canRunQuickCapture: Bool {
    switch vm.nodeSelection {
    case .captureRegion, .captureWindow, .captureFullscreen, .captureExpiringRegion, .captureTopTaskbar, .captureScreenRecording:
      return true
    default:
      return false
    }
  }

  private var canRunQuickUpload: Bool {
    switch vm.nodeSelection {
    case .uploadClipboardImage, .uploadImageFile, .uploadExpiringFile, .uploadFromURL,
         .uploadText, .uploadFolder, .workflowRegionToUrl, .workflowClipboardToUrl:
      return true
    default:
      return false
    }
  }

  private var canRunQuickShorten: Bool {
    switch vm.nodeSelection {
    case .uploadURLShortener, .uploadText:
      return true
    default:
      return false
    }
  }

  private func runQuickCapture() {
    switch vm.nodeSelection {
    case .captureRegion:
      vm.runCaptureRegion()
    case .captureWindow:
      vm.runCaptureWindow()
    case .captureFullscreen:
      vm.runCaptureFullscreen()
    case .captureTopTaskbar:
      vm.runCaptureTopTaskbar()
    case .captureScreenRecording:
      vm.runCaptureScreenRecording()
    case .captureExpiringRegion:
      vm.runCaptureRegionExpiring()
    default:
      break
    }
  }

  private func runQuickUpload() {
    switch vm.nodeSelection {
    case .uploadClipboardImage:
      vm.runUploadClipboard()
    case .uploadImageFile:
      vm.runUploadImageFile()
    case .uploadExpiringFile:
      vm.runUploadExpiringFile()
    case .uploadFromURL:
      vm.runUploadFromURL()
    case .uploadText:
      vm.runUploadText()
    case .uploadFolder:
      vm.runUploadFolder()
    case .workflowRegionToUrl:
      vm.runCaptureRegion()
    case .workflowClipboardToUrl:
      vm.runUploadClipboard()
    default:
      break
    }
  }

  private func runQuickShorten() {
    vm.runShortenURL()
  }

  @ViewBuilder
  private func page(for node: ContextNodeID?) -> some View {
    switch node {
    case .captureRegion:
      ShareXSectionCard(title: "Capture region", subtitle: "Direct command action with explicit controls.") {
        HStack(spacing: 8) {
          Button("Capture Region and upload") { vm.runCaptureRegion() }
            .buttonStyle(.borderedProminent)
          Button("Capture Region with expiring link") { vm.runCaptureRegionExpiring() }
            .buttonStyle(.bordered)
        }
      }

    case .captureWindow:
      ShareXSectionCard(title: "Capture window", subtitle: "Matches ShareX capture menu affordance.") {
        Button("Capture Window and upload") { vm.runCaptureWindow() }
          .buttonStyle(.borderedProminent)
      }

    case .captureFullscreen:
      ShareXSectionCard(title: "Capture fullscreen", subtitle: "Runs one-step fullscreen capture and upload.") {
        Button("Capture Fullscreen and upload") { vm.runCaptureFullscreen() }
          .buttonStyle(.borderedProminent)
      }

    case .captureTopTaskbar:
      ShareXSectionCard(title: "Capture top taskbar", subtitle: "Grab the macOS menu bar and its dropdown menus.") {
        Button("Capture Top Taskbar and upload") { vm.runCaptureTopTaskbar() }
          .buttonStyle(.borderedProminent)
      }

    case .captureScreenRecording:
      ShareXSectionCard(title: "Screen recording", subtitle: "Interactive recording with an automatic stop at 30 seconds.") {
        Button("Record Screen (Max 30 sec) and upload") { vm.runCaptureScreenRecording() }
          .buttonStyle(.borderedProminent)
      }

    case .captureExpiringRegion:
      ShareXSectionCard(title: "Expiring capture", subtitle: "Prompts for expiry duration, then uploads the capture immediately.") {
        Button("Capture Region and upload expiring link") { vm.runCaptureRegionExpiring() }
          .buttonStyle(.borderedProminent)
      }

    case .captureCursorDelay:
      ShareXSectionCard(title: "Cursor and delay", subtitle: "Capture options for cursor visibility and delay.") {
        Toggle("Include cursor while capturing", isOn: $vm.includeCursorOnCapture)
          .toggleStyle(.checkbox)
        HStack {
          Text("Screenshot delay")
            .lineLimit(1)
            .truncationMode(.tail)
          Picker("Screenshot delay", selection: $vm.captureDelaySeconds) {
            ForEach([0, 1, 2, 3, 4, 5], id: \.self) { value in
              Text("\(value) sec").tag(value)
            }
          }
          .pickerStyle(.menu)
          .frame(width: CraftyLayout.formControlWidth)
        }
      }

    case .captureRegionFixedSize:
      ShareXSectionCard(title: "Region fixed size", subtitle: "Mirrors ShareX custom region and snap-size tuning.") {
        Toggle("Use fixed region for region capture", isOn: $vm.captureFixedRegionEnabled)
          .toggleStyle(.checkbox)

        HStack(spacing: 8) {
          regionStepper("X", value: $vm.captureFixedRegionX, range: -10000...10000)
          regionStepper("Y", value: $vm.captureFixedRegionY, range: -10000...10000)
          regionStepper("Width", value: $vm.captureFixedRegionWidth, range: 1...10000)
          regionStepper("Height", value: $vm.captureFixedRegionHeight, range: 1...10000)
        }
        .disabled(!vm.captureFixedRegionEnabled)

        Toggle("Show region info overlay", isOn: $vm.captureShowInfoOverlay)
          .toggleStyle(.checkbox)

        VStack(alignment: .leading, spacing: 4) {
          Text("Snap sizes (comma-separated)")
            .foregroundStyle(.secondary)
          TextField("320x240, 640x480, 1280x720", text: $vm.captureSnapSizesText)
            .textFieldStyle(.roundedBorder)
          Text("Used for region snap presets (format: WIDTHxHEIGHT).")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }

    case .uploadClipboardImage:
      ShareXSectionCard(title: "Clipboard image upload", subtitle: "Uploads the image currently on the clipboard.") {
        Button("Upload Clipboard Image") { vm.runUploadClipboard() }
          .buttonStyle(.borderedProminent)
      }

    case .uploadImageFile:
      ShareXSectionCard(title: "Image file upload", subtitle: "Opens file chooser and uploads selected image.") {
        Button("Upload Image File...") { vm.runUploadImageFile() }
          .buttonStyle(.borderedProminent)
      }

    case .uploadExpiringFile:
      ShareXSectionCard(title: "Expiring file upload", subtitle: "Generates an expiring link for file uploads.") {
        Button("Upload File (Expiring Link)...") { vm.runUploadExpiringFile() }
          .buttonStyle(.borderedProminent)
      }

    case .uploadFromURL:
      ShareXSectionCard(title: "Upload from URL", subtitle: "Downloads a remote URL and uploads the resulting file.") {
        Button("Upload from URL...") { vm.runUploadFromURL() }
          .buttonStyle(.borderedProminent)
      }

    case .uploadText:
      ShareXSectionCard(title: "Upload text", subtitle: "Converts clipboard text to a file and uploads it.") {
        Button("Upload Text...") { vm.runUploadText() }
          .buttonStyle(.borderedProminent)
      }

    case .uploadFolder:
      ShareXSectionCard(title: "Upload folder", subtitle: "Recursively queues folder content as a batch upload.") {
        Button("Upload Folder...") { vm.runUploadFolder() }
          .buttonStyle(.borderedProminent)
      }

    case .uploadClipboardRules:
      ShareXSectionCard(title: "Clipboard smart rules", subtitle: "Clipboard routing order: image, folder URLs, web URLs, then plain text.") {
        Toggle("Upload clipboard URLs", isOn: $vm.uploadClipboardURLContents)
          .toggleStyle(.checkbox)
        Toggle("Shorten clipboard URLs instead of uploading", isOn: $vm.uploadShortenURL)
          .toggleStyle(.checkbox)
        Toggle("Copy links only when clipboard is a URL", isOn: $vm.uploadShareURLAfterClipboard)
          .toggleStyle(.checkbox)
        Toggle("Auto-index URLs found in folders", isOn: $vm.uploadClipboardAutoIndexFolder)
          .toggleStyle(.checkbox)
        Toggle("Upload clipboard text", isOn: $vm.uploadClipboardTextContents)
          .toggleStyle(.checkbox)
        Toggle("Strip image metadata before upload", isOn: $vm.stripImageMetadataBeforeUpload)
          .toggleStyle(.checkbox)
        Divider()
        Button("Run Clipboard Upload Now") { vm.runUploadClipboard() }
          .buttonStyle(.borderedProminent)
      }

    case .uploadURLShortener:
      ShareXSectionCard(title: "URL shortener", subtitle: "Choose TinyURL or a custom template provider.") {
        HStack {
          Text("Provider")
            .lineLimit(1)
            .truncationMode(.tail)
          Picker(
            "Provider",
            selection: Binding(
              get: { vm.shortenerProviderRawValue },
              set: { vm.updateShortenerProvider($0) }
            )
          ) {
            Text("TinyURL (public)").tag(URLShortenerProvider.tinyURL.rawValue)
            Text("Custom GET template").tag(URLShortenerProvider.customGetTemplate.rawValue)
          }
          .pickerStyle(.menu)
          .frame(width: CraftyLayout.formControlWidth)
        }

        HStack {
          Text("Template")
            .lineLimit(1)
            .truncationMode(.tail)
          TextField(
            "https://short.example.com/create?url={url}",
            text: Binding(
              get: { vm.shortenerCustomTemplate },
              set: { vm.updateShortenerTemplate($0) }
            )
          )
          .textFieldStyle(.roundedBorder)
          .frame(width: CraftyLayout.formControlWidth)
        }
        .disabled(vm.shortenerProviderRawValue != URLShortenerProvider.customGetTemplate.rawValue)

        HStack {
          Button("Shorten URL...") { vm.runShortenURL() }
            .buttonStyle(.borderedProminent)
        }
      }

    case .uploadWatchFolders:
      ShareXSectionCard(title: "Watch folders", subtitle: "Auto-uploads files when created or renamed. Debounce and dedupe prevent duplicate uploads.") {
        Toggle("Enable watch folders globally", isOn: Binding(
          get: { vm.watchFoldersEnabled },
          set: { vm.setWatchFoldersEnabled($0) }
        ))
        .toggleStyle(.checkbox)

        List(selection: Binding(get: { vm.selectedWatchFolderRuleId }, set: { vm.selectWatchFolderRule($0) })) {
          ForEach(vm.watchFolderRules) { rule in
            HStack {
              Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { vm.toggleWatchFolderRuleEnabled(rule.id, enabled: $0) }
              ))
              .labelsHidden()
              Text(rule.path)
                .lineLimit(1)
              Spacer()
              Text(rule.mode.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .tag(rule.id)
          }
        }
        .frame(height: 150)
        .listStyle(.inset)

        HStack {
          Text("Path")
            .lineLimit(1)
            .truncationMode(.tail)
          TextField("/path/to/folder", text: $vm.watchFolderPathInput)
            .textFieldStyle(.roundedBorder)
            .frame(width: CraftyLayout.formControlWidth)
        }
        HStack {
          Text("Filter")
            .lineLimit(1)
            .truncationMode(.tail)
          TextField("*, png, jpg, mp4", text: $vm.watchFolderFilterInput)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .frame(width: CraftyLayout.formControlWidth)
        }
        Toggle("Include subdirectories", isOn: $vm.watchFolderIncludeSubdirectories)
          .toggleStyle(.checkbox)
        HStack {
          Text("Mode")
            .lineLimit(1)
            .truncationMode(.tail)
          Picker("Mode", selection: $vm.watchFolderModeRawValue) {
            ForEach(WatchFolderMode.allCases, id: \.rawValue) { mode in
              Text(mode.rawValue).tag(mode.rawValue)
            }
          }
          .pickerStyle(.menu)
          .frame(width: CraftyLayout.formControlWidth)
          Text("Expiry (seconds)")
            .lineLimit(1)
            .truncationMode(.tail)
          Stepper(value: $vm.watchFolderExpirySeconds, in: 0...432_000, step: 60) {
            Text(vm.watchFolderExpirySeconds == 0 ? "Default" : "\(vm.watchFolderExpirySeconds)")
              .font(.system(.body, design: .monospaced))
          }
          .frame(width: CraftyLayout.formControlWidth - 40, alignment: .leading)
        }

        HStack(spacing: 8) {
          Button("Add") { vm.addWatchFolderRule() }
            .buttonStyle(.borderedProminent)
          Button("Update") { vm.updateSelectedWatchFolderRule() }
            .buttonStyle(.bordered)
            .disabled(vm.selectedWatchFolderRuleId == nil)
          Button("Remove") { vm.removeSelectedWatchFolderRule() }
            .buttonStyle(.bordered)
            .disabled(vm.selectedWatchFolderRuleId == nil)
        }

        Button("Open Watch Folders Section") { vm.openWatchFolders() }
          .buttonStyle(.bordered)
      }

    case .uploadFileNaming:
      ShareXSectionCard(title: "File naming and URL regex", subtitle: "Based on ShareX upload/file naming task settings.") {
        HStack {
          Text("Image upload format")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          Picker("Image upload format", selection: $vm.imageUploadFormat) {
            ForEach(ImageUploadFormat.allCases) { format in
              Text(format.displayName).tag(format)
            }
          }
          .pickerStyle(.menu)
          .frame(width: CraftyLayout.formControlWidth)
        }

        Toggle("Use 16-character random filenames", isOn: $vm.fileUploadUseRandom16Name)
          .toggleStyle(.checkbox)

        Toggle("Use custom filename pattern for uploads", isOn: $vm.fileUploadUseNamePattern)
          .toggleStyle(.checkbox)

        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("Filename pattern")
              .lineLimit(1)
              .truncationMode(.tail)
            TextField("{date}-{time}-{rand}", text: $vm.fileNamePattern)
              .textFieldStyle(.roundedBorder)
              .frame(width: CraftyLayout.formControlWidth)
          }

          HStack {
            Text("Auto increment")
              .lineLimit(1)
              .truncationMode(.tail)
            Stepper(value: $vm.fileNameAutoIncrement, in: 1...1_000_000) {
              Text("\(vm.fileNameAutoIncrement)")
                .font(.system(.body, design: .monospaced))
            }
            .frame(width: CraftyLayout.formControlWidth, alignment: .leading)
          }

          Toggle("Replace problematic filename characters", isOn: $vm.fileUploadReplaceProblematicCharacters)
            .toggleStyle(.checkbox)

          Text("Tokens: {date} {time} {datetime} {rand} {name} {inc}")
            .font(.caption)
            .foregroundStyle(.secondary)

          settingPair("Preview", vm.fileNamingPreview)
        }
        .disabled(vm.fileUploadUseRandom16Name || !vm.fileUploadUseNamePattern)

        Divider()

        Toggle("Enable URL regex replacement", isOn: $vm.urlRegexReplaceEnabled)
          .toggleStyle(.checkbox)

        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("Regex pattern")
              .lineLimit(1)
              .truncationMode(.tail)
            TextField("https://(.*)", text: $vm.urlRegexPattern)
              .textFieldStyle(.roundedBorder)
              .font(.system(.body, design: .monospaced))
              .frame(width: CraftyLayout.formControlWidth)
          }
          HStack {
            Text("Replacement")
              .lineLimit(1)
              .truncationMode(.tail)
            TextField("https://cdn.example.com/$1", text: $vm.urlRegexReplacement)
              .textFieldStyle(.roundedBorder)
              .font(.system(.body, design: .monospaced))
              .frame(width: CraftyLayout.formControlWidth)
          }
        }
        .disabled(!vm.urlRegexReplaceEnabled)
      }

    case .uploadUploaderFilters:
      ShareXSectionCard(title: "Uploader filters", subtitle: "ShareX-like extension rules that route uploads to specific destinations.") {
        List(selection: Binding(get: { vm.selectedUploaderFilterId }, set: { vm.selectUploaderFilter($0) })) {
          ForEach(vm.uploaderFilters) { rule in
            HStack {
              Text(vm.uploaderFilterProfileName(rule.profileId))
                .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
              Text(rule.extensions.joined(separator: ", "))
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tag(rule.id)
          }
        }
        .frame(height: 160)
        .listStyle(.inset)

        HStack {
          Text("Destination")
            .lineLimit(1)
            .truncationMode(.tail)
          Picker("Destination", selection: $vm.uploaderFilterProfileId) {
            ForEach(vm.profiles, id: \.id) { profile in
              Text(profile.name).tag(profile.id)
            }
          }
          .pickerStyle(.menu)
          .frame(width: CraftyLayout.formControlWidth)
        }

        HStack {
          Text("Extensions")
          TextField("png, jpg, gif, mp4", text: $vm.uploaderFilterExtensionsInput)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .frame(width: CraftyLayout.formControlWidth)
        }

        HStack(spacing: 8) {
          Button("Add") { vm.addUploaderFilter() }
            .buttonStyle(.borderedProminent)
          Button("Update") { vm.updateSelectedUploaderFilter() }
            .buttonStyle(.bordered)
            .disabled(vm.selectedUploaderFilterId == nil)
          Button("Remove") { vm.removeSelectedUploaderFilter() }
            .buttonStyle(.bordered)
            .disabled(vm.selectedUploaderFilterId == nil)
        }

        Text("Example: `png, jpg` routes those file extensions to the selected destination profile.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

    case .workflowRegionToUrl:
      ShareXSectionCard(title: "Workflow: region to URL", subtitle: "Captures a region, uploads it, and copies the URL.") {
        Button("Run Region -> Upload -> Copy URL") { vm.runCaptureRegion() }
          .buttonStyle(.borderedProminent)
      }

    case .workflowClipboardToUrl:
      ShareXSectionCard(title: "Workflow: clipboard to URL", subtitle: "Uploads clipboard content and copies the resulting URL.") {
        Button("Run Clipboard -> Upload -> Copy URL") { vm.runUploadClipboard() }
          .buttonStyle(.borderedProminent)
      }

    case .toolsHotkeys:
      ShareXSectionCard(title: "Hotkeys", subtitle: "Configured shortcuts for capture and upload actions.") {
        hotkeyEditorRow("Capture Region and upload", binding: $vm.hotkeyCaptureRegionUpload)
        hotkeyEditorRow("Capture Region and upload expiring link", binding: $vm.hotkeyCaptureRegionUploadExpiring)
        hotkeyEditorRow("Capture Region (frozen screen) and upload", binding: $vm.hotkeyCaptureRegionUploadFrozen)
        hotkeyEditorRow("Upload Clipboard Image", binding: $vm.hotkeyUploadClipboard)
        Text("Changes apply immediately. Each shortcut must include at least one modifier.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

    case .toolsProductivity:
      ShareXSectionCard(title: "Folders and productivity", subtitle: "Open common tools and workspace actions from the shell.") {
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 8) {
            Button("Open Screenshots Folder") { vm.openScreenshotsFolder() }
              .buttonStyle(.bordered)
            Button("Open Preferences") { vm.openPreferences() }
              .buttonStyle(.bordered)
            Button("View image upload history") { vm.openHistoryWorkspace() }
              .buttonStyle(.bordered)
          }

          HStack(spacing: 8) {
            Button("Color Picker") { ToolsCoordinator.shared.openColorPicker() }
              .buttonStyle(.bordered)
            Button("QR Code") { ToolsCoordinator.shared.openQRCodeTool() }
              .buttonStyle(.bordered)
            Button("Hash Checker") { ToolsCoordinator.shared.openHashChecker() }
              .buttonStyle(.bordered)
            Button("Directory Indexer") { ToolsCoordinator.shared.openDirectoryIndexer() }
              .buttonStyle(.bordered)
            Button("Pin Clipboard Image") { ToolsCoordinator.shared.pinClipboardImage() }
              .buttonStyle(.bordered)
          }
        }
      }

    case .toolsEditor:
      ShareXSectionCard(title: "Editor entry", subtitle: "Open the latest captured image in the editor.") {
        Button("Open Latest Image in Editor") { vm.openLatestEditor() }
          .buttonStyle(.borderedProminent)
      }

    case .afterCaptureBehavior:
      ShareXSectionCard(title: "After capture defaults", subtitle: "Actions applied immediately after each capture upload.") {
        Toggle("Save local copy", isOn: $vm.afterCaptureSaveLocalCopy).toggleStyle(.checkbox)
        Toggle("Copy URL", isOn: $vm.afterCaptureCopyURL).toggleStyle(.checkbox)
        Toggle("Copy image + URL", isOn: $vm.afterCaptureCopyImageAndURL).toggleStyle(.checkbox)
        Toggle("Open editor after upload", isOn: $vm.afterCaptureOpenEditor).toggleStyle(.checkbox)
        Divider()
        settingPair("Screenshots folder", vm.screenshotsFolderPathDisplay.isEmpty ? "-" : vm.screenshotsFolderPathDisplay)
        HStack(spacing: 8) {
          Button("Choose Folder...") { vm.chooseScreenshotsFolder() }
            .buttonStyle(.bordered)
          Button("Use Default Folder") { vm.resetScreenshotsFolder() }
            .buttonStyle(.bordered)
            .disabled(!vm.screenshotsFolderIsCustom)
          Button("Open Folder") { vm.openScreenshotsFolder() }
            .buttonStyle(.bordered)
        }
      }

    case .afterUploadBehavior:
      ShareXSectionCard(title: "After upload defaults", subtitle: "Upload completion options are always visible.") {
        Toggle("Copy URL to clipboard", isOn: $vm.afterUploadCopyURL).toggleStyle(.checkbox)
        Toggle("Copy image to clipboard", isOn: $vm.afterUploadCopyImage).toggleStyle(.checkbox)
        Toggle("Open URL in browser", isOn: $vm.afterUploadOpenURL).toggleStyle(.checkbox)
        Toggle("Show completion notification", isOn: $vm.afterUploadShowNotification).toggleStyle(.checkbox)
      }

    case .destinationsActiveProfile:
      ShareXSectionCard(title: "Active profile", subtitle: "Uses existing profile store and preference editor.") {
        settingPair("Profile", vm.activeProfileName)
        settingPair("Backend", vm.activeBackendText)
        Button("Manage Profiles...") { vm.openPreferences() }
          .buttonStyle(.bordered)
      }

    case .destinationsEndpointBackend:
      ShareXSectionCard(title: "Endpoint and backend", subtitle: "Current destination values are surfaced directly.") {
        settingPair("Endpoint", vm.activeEndpoint)
        settingPair("Backend", vm.activeBackendText)
        Button("Open Add and edit endpoints") { vm.openPreferences() }
          .buttonStyle(.bordered)
      }

    case .destinationsBehavior:
      ShareXSectionCard(title: "Destination behavior", subtitle: "Desktop-style dropdowns and toggles for clarity.") {
        HStack {
          Text("Upload behavior")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          Picker("Upload behavior", selection: $vm.selectedUploadBehavior) {
            Text("Use active destination").tag("Use active destination")
            Text("Prefer image destination").tag("Prefer image destination")
            Text("Prefer file destination").tag("Prefer file destination")
          }
          .pickerStyle(.menu)
          .frame(width: CraftyLayout.formControlWidth)
        }
        Divider()

        HStack {
          Text("Image destination")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          Picker("Image destination", selection: Binding(
            get: { vm.routingImageProfileId },
            set: { vm.setRoutingProfile($0, for: .image) }
          )) {
            Text("Use active profile").tag("")
            ForEach(vm.profiles, id: \.id) { profile in
              Text(profile.name).tag(profile.id)
            }
          }
          .pickerStyle(.menu)
          .frame(width: CraftyLayout.formControlWidth)
        }

        HStack {
          Text("File destination")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          Picker("File destination", selection: Binding(
            get: { vm.routingFileProfileId },
            set: { vm.setRoutingProfile($0, for: .file) }
          )) {
            Text("Use active profile").tag("")
            ForEach(vm.profiles, id: \.id) { profile in
              Text(profile.name).tag(profile.id)
            }
          }
          .pickerStyle(.menu)
          .frame(width: CraftyLayout.formControlWidth)
        }

        HStack {
          Text("Text destination")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          Picker("Text destination", selection: Binding(
            get: { vm.routingTextProfileId },
            set: { vm.setRoutingProfile($0, for: .text) }
          )) {
            Text("Use active profile").tag("")
            ForEach(vm.profiles, id: \.id) { profile in
              Text(profile.name).tag(profile.id)
            }
          }
          .pickerStyle(.menu)
          .frame(width: CraftyLayout.formControlWidth)
        }

        HStack {
          Text("Shortener destination")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          Picker("Shortener destination", selection: Binding(
            get: { vm.routingShortenerProfileId },
            set: { vm.setRoutingProfile($0, for: .shortener) }
          )) {
            Text("Use active profile").tag("")
            ForEach(vm.profiles, id: \.id) { profile in
              Text(profile.name).tag(profile.id)
            }
          }
          .pickerStyle(.menu)
          .frame(width: CraftyLayout.formControlWidth)
        }

        Divider()
        Toggle("Share URL after clipboard upload", isOn: $vm.uploadShareURLAfterClipboard)
          .toggleStyle(.checkbox)
        Toggle("Shorten URLs when available", isOn: $vm.uploadShortenURL)
          .toggleStyle(.checkbox)
      }

    case .settingsApplication:
      ShareXSectionCard(title: "Application-like settings", subtitle: "Application behavior settings are grouped by function.", rainbowMode: vm.uiRainbowMode) {
        Toggle("Open the GUI on launch", isOn: $vm.appShowMainWindowOnLaunch).toggleStyle(.checkbox)
        HStack {
          Text("Color palette")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          Picker("Color palette", selection: $vm.uiPaletteId) {
            ForEach(UIPaletteID.allCases) { p in
              Text(p.displayName).tag(p)
            }
          }
          .pickerStyle(.menu)
          .frame(width: CraftyLayout.formControlWidth)
        }

        Toggle("Rainbow overlay", isOn: $vm.uiRainbowMode)
          .toggleStyle(.checkbox)
        Text("Animated rainbow overlay. If it feels loud, turn it off.")
          .font(.caption)
          .foregroundStyle(.secondary)

        if vm.uiPaletteId == .custom {
          DisclosureGroup("Customize palette") {
            VStack(alignment: .leading, spacing: 10) {
              Text("Backgrounds")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              ColorPicker("Window gradient A", selection: rgbaBinding(\.windowGradientA))
              ColorPicker("Window gradient B", selection: rgbaBinding(\.windowGradientB))
              ColorPicker("Window gradient C", selection: rgbaBinding(\.windowGradientC))
              ColorPicker("Window spot", selection: rgbaBinding(\.windowRadialSpot))

              Divider()
              Text("Panels")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              ColorPicker("Rail panel accent", selection: rgbaBinding(\.railPanelAccent))
              ColorPicker("Context panel accent", selection: rgbaBinding(\.contextPanelAccent))

              Divider()
              Text("Section accents")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              ColorPicker("Capture", selection: rgbaBinding(\.captureAccent))
              ColorPicker("Upload", selection: rgbaBinding(\.uploadAccent))
              ColorPicker("Workflows", selection: rgbaBinding(\.workflowsAccent))
              ColorPicker("Tools", selection: rgbaBinding(\.toolsAccent))
              ColorPicker("After capture", selection: rgbaBinding(\.afterCaptureAccent))
              ColorPicker("After upload", selection: rgbaBinding(\.afterUploadAccent))
              ColorPicker("Destinations", selection: rgbaBinding(\.destinationsAccent))
              ColorPicker("Settings", selection: rgbaBinding(\.settingsAccent))
              ColorPicker("History", selection: rgbaBinding(\.historyAccent))

              Divider()
              HStack(spacing: 8) {
                Button("Reset Custom Palette to Classic") {
                  vm.uiCustomPalette = UIPaletteCatalog.defaultCustomSeed()
                }
                Button("Use Classic Palette") {
                  vm.uiPaletteId = .classic
                }
              }
            }
            .padding(.top, 4)
          }
        }
        HStack {
          Text("Default filename pattern")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          TextField("{date}-{rand}", text: $vm.defaultFileNamePattern)
            .textFieldStyle(.roundedBorder)
            .frame(width: CraftyLayout.formControlWidth)
        }
      }

    case .settingsTask:
      ShareXSectionCard(title: "Task-like settings", subtitle: "Mimics task-level override model from ShareX.", rainbowMode: vm.uiRainbowMode) {
        Toggle("Override task-level defaults", isOn: $vm.taskOverrideEnabled)
          .toggleStyle(.checkbox)
        HStack {
          Text("Task preset")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          Picker("Task preset", selection: $vm.captureDelaySeconds) {
            Text("Default").tag(0)
            Text("Capture focused").tag(1)
            Text("Upload focused").tag(2)
          }
          .pickerStyle(.menu)
          .frame(width: CraftyLayout.formControlWidth)
        }
      }

    case .settingsCloudflareAllowlist:
      ShareXSectionCard(title: "Cloudflare allowlist", subtitle: "Keeps this Mac's public IP in a Cloudflare IP list.", rainbowMode: vm.uiRainbowMode) {
        Toggle("Keep this device allowlisted", isOn: $vm.cloudflareAllowlistEnabled)
          .toggleStyle(.checkbox)

        HStack {
          Text("Account ID")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          TextField("Cloudflare account ID", text: $vm.cloudflareAccountId)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .frame(width: 360)
        }

        HStack {
          Text("IP list")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          TextField("crafty or 32-character list ID", text: $vm.cloudflareListId)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .frame(width: 360)
        }

        HStack {
          Text("Device name")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          TextField("This Mac", text: $vm.cloudflareDeviceName)
            .textFieldStyle(.roundedBorder)
            .frame(width: 360)
        }

        HStack {
          Text("Check interval")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          Stepper(value: $vm.cloudflareCheckIntervalMinutes, in: 5...1440, step: 5) {
            Text("\(vm.cloudflareCheckIntervalMinutes) minutes")
              .font(.system(.body, design: .monospaced))
          }
          .frame(width: 220, alignment: .leading)
        }

        Divider()

        HStack {
          Text("API token")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          SecureField(vm.cloudflareTokenStored ? "Token stored in Keychain" : "Cloudflare API token", text: $vm.cloudflareApiToken)
            .textFieldStyle(.roundedBorder)
            .frame(width: 360)
        }

        HStack(spacing: 8) {
          Button("Save Token") { vm.saveCloudflareApiToken() }
            .buttonStyle(.bordered)
          Button("Clear Token") { vm.clearCloudflareApiToken() }
            .buttonStyle(.bordered)
            .disabled(!vm.cloudflareTokenStored && vm.cloudflareApiToken.isEmpty)
          Button("Update Now") { vm.runCloudflareAllowlistUpdate() }
            .buttonStyle(.borderedProminent)
            .disabled(vm.cloudflareAllowlistUpdateInProgress)
        }

        Text(vm.cloudflareAllowlistStatus)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }

    case .settingsAdvanced:
      ShareXSectionCard(title: "Advanced settings", subtitle: "Advanced section is shown at all times.", rainbowMode: vm.uiRainbowMode) {
        Toggle("Enable debug logging", isOn: $vm.advancedDebugLogging)
          .toggleStyle(.checkbox)
        HStack {
          Text("Upload retry count")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          Stepper(value: $vm.advancedRetryCount, in: 0...5) {
            Text("\(vm.advancedRetryCount)")
          }
          .frame(width: CraftyLayout.formControlWidth - 80)
        }
        Divider()
        Toggle("Enable local OCR indexing", isOn: $vm.ocrIndexingEnabled)
          .toggleStyle(.checkbox)
        Text("OCR text is stored only in local upload history metadata and is never uploaded.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(vm.ocrProgressLine)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(2)
        HStack(spacing: 8) {
          Button("Index Existing") { vm.indexExistingOCR() }
            .buttonStyle(.bordered)
          Button("Rebuild Index") { vm.rebuildOCRIndex() }
            .buttonStyle(.bordered)
          Button("Clear OCR") { vm.clearOCRIndex() }
            .buttonStyle(.bordered)
        }
        HStack(spacing: 8) {
          Button("Pause") { vm.pauseOCRIndexing() }
            .buttonStyle(.bordered)
          Button("Resume") { vm.resumeOCRIndexing() }
            .buttonStyle(.bordered)
          Button("Cancel") { vm.cancelOCRIndexing() }
            .buttonStyle(.bordered)
        }

        Divider()

        HStack {
          Text("Before image upload")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          Picker("", selection: $vm.uploadRedactionPolicy) {
            ForEach(UploadRedactionPolicy.allCases, id: \.self) { policy in
              Text(policy.displayName).tag(policy)
            }
          }
          .labelsHidden()
          .frame(width: 180)
        }

        Toggle(
          "Use black boxes for auto redaction",
          isOn: Binding(
            get: { vm.smartRedactionRenderMode == .blackBox },
            set: { vm.smartRedactionRenderMode = $0 ? .blackBox : .pixelate }
          )
        )
        .toggleStyle(.checkbox)

        HStack {
          Text("Redaction confidence")
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
          Slider(
            value: Binding(
              get: { Double(vm.redactionDetectorSettings.minimumConfidence) },
              set: {
                var updated = vm.redactionDetectorSettings
                updated.minimumConfidence = Float($0)
                vm.redactionDetectorSettings = updated
              }
            ),
            in: 0...1,
            step: 0.05
          )
          .frame(width: 180)
          Text("\(Int((vm.redactionDetectorSettings.minimumConfidence * 100).rounded()))%")
            .font(.system(.body, design: .monospaced))
            .frame(width: 52, alignment: .leading)
        }

        Toggle("Use fast OCR mode", isOn: redactionSettingsBoolBinding(\.useFastTextRecognition))
          .toggleStyle(.checkbox)
        Toggle("Allow raw match previews", isOn: redactionSettingsBoolBinding(\.allowSensitiveTextPreviews))
          .toggleStyle(.checkbox)

        Text("Visual detectors")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        redactionToggleGrid([.faces, .barcodes])

        Text("Text detectors")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        redactionToggleGrid([
          .textOCR,
          .emailAddresses,
          .phoneNumbers,
          .creditCardNumbers,
          .ipv4Addresses,
          .urlsDomains,
          .apiKeys,
          .awsAccessKeys,
          .githubTokens,
          .openAIKeys,
          .bearerTokens,
          .jwts,
          .privateKeyBlocks,
          .sessionCookies,
          .passwordFields,
          .environmentVariables,
        ])

        Text("Additional detectors")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        redactionToggleGrid([.filePaths, .usernamesHostnames, .macAddresses, .ipv6Addresses])

        HStack(spacing: 8) {
          Button("Reset Redaction Defaults") { vm.resetRedactionDetectorDefaults() }
            .buttonStyle(.bordered)
        }

        Text("Debug logging and retry count are placeholders until dedicated persistence is implemented.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

    case .captureModesGroup, .captureOptionsGroup, .uploadQuickGroup, .uploadSettingsGroup, .workflowsQuickGroup,
         .toolsGroups, .afterCaptureGroup, .afterUploadGroup, .destinationGroup,
         .settingsGroup, .historyGroup, .historyUploads, nil:
      ShareXSectionCard(title: "Select an item", subtitle: "Choose a child item in the context tree to view controls.", rainbowMode: vm.uiRainbowMode) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Select a child command to view controls and action buttons.")
            .font(.callout)
          Text("Root nodes represent categories like capture, upload, and tools.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
    }
  }

  private func hotkeyEditorRow(_ title: String, binding: Binding<HotKeyShortcut>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
        Spacer()
        Text(binding.wrappedValue.displayText)
          .font(.system(.body, design: .monospaced))
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(accentColor.opacity(0.14))
          .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .stroke(accentColor.opacity(0.32), lineWidth: 1)
          )
          .clipShape(RoundedRectangle(cornerRadius: 4))
      }
      HStack(spacing: 12) {
        Picker("Key", selection: binding.key) {
          ForEach(HotKeyShortcut.allowedKeys, id: \.self) { key in
            Text(key).tag(key)
          }
        }
        .pickerStyle(.menu)
        .frame(width: 100)

        Toggle("Cmd", isOn: binding.command)
          .toggleStyle(.checkbox)
        Toggle("Shift", isOn: binding.shift)
          .toggleStyle(.checkbox)
        Toggle("Opt", isOn: binding.option)
          .toggleStyle(.checkbox)
        Toggle("Ctrl", isOn: binding.control)
          .toggleStyle(.checkbox)
      }
    }
  }

  private func redactionToggleGrid(_ types: [RedactionDetectorType]) -> some View {
    LazyVGrid(
      columns: [
        GridItem(.adaptive(minimum: 210), alignment: .leading),
      ],
      alignment: .leading,
      spacing: 6
    ) {
      ForEach(types, id: \.self) { type in
        Toggle(type.title, isOn: Binding(
          get: { vm.redactionDetectorEnabled(type) },
          set: { vm.setRedactionDetector(type, enabled: $0) }
        ))
        .toggleStyle(.checkbox)
      }
    }
  }

  private func redactionSettingsBoolBinding(_ keyPath: WritableKeyPath<RedactionDetectorSettings, Bool>) -> Binding<Bool> {
    Binding(
      get: { vm.redactionDetectorSettings[keyPath: keyPath] },
      set: {
        var updated = vm.redactionDetectorSettings
        updated[keyPath: keyPath] = $0
        vm.redactionDetectorSettings = updated
      }
    )
  }

  private func settingPair(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(width: CraftyLayout.formControlLabelWidth, alignment: .leading)
      Text(value)
        .font(.system(.body, design: .monospaced))
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func regionStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Stepper(value: value, in: range) {
        Text("\(value.wrappedValue)")
          .font(.system(.body, design: .monospaced))
      }
      .frame(width: CraftyLayout.formControlWidth, alignment: .leading)
    }
  }
}

struct ShareXSectionCard<Content: View>: View {
  let title: String
  let subtitle: String?
  let content: Content
  var rainbowMode: Bool? = nil
  @Environment(\.craftyAccentColor) private var accentColor
  @Environment(\.craftyRainbowMode) private var globalRainbowMode
  @Environment(\.craftyOLEDBlackMode) private var oledBlackMode

  init(title: String, subtitle: String? = nil, rainbowMode: Bool? = nil, @ViewBuilder _ content: () -> Content) {
    self.title = title
    self.subtitle = subtitle
    self.content = content()
    self.rainbowMode = rainbowMode
  }

  var body: some View {
    let resolvedRainbowMode = rainbowMode ?? globalRainbowMode
    VStack(alignment: .leading, spacing: CraftyLayout.sectionSpacing) {
      Text(title)
        .font(.headline)
        .foregroundStyle(resolvedRainbowMode ? AnyShapeStyle(Color.primary) : AnyShapeStyle(accentColor))
      Divider()
      content
    }
    .padding(12)
    .background(CraftyTheme.cardBackground(accentColor, rainbowMode: resolvedRainbowMode, oledBlack: oledBlackMode))
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(accentColor.opacity(resolvedRainbowMode ? 0.16 : 0.34), lineWidth: 1)
    )
  }
}

private extension CommandDetailRouterView {
  func rgbaBinding(_ keyPath: WritableKeyPath<UIPaletteData, RGBAColor>) -> Binding<Color> {
    Binding(
      get: { vm.uiCustomPalette[keyPath: keyPath].toSwiftUIColor() },
      set: { newColor in
        guard let rgba = RGBAColor.fromSwiftUIColor(newColor) else { return }
        var updated = vm.uiCustomPalette
        updated[keyPath: keyPath] = rgba
        vm.uiCustomPalette = updated
      }
    )
  }
}

private extension Binding where Value == HotKeyShortcut {
  var key: Binding<String> {
    Binding<String>(
      get: { wrappedValue.key },
      set: { newValue in
        var updated = wrappedValue
        updated.key = newValue
        wrappedValue = updated
      }
    )
  }

  var command: Binding<Bool> {
    boolBinding(\.command)
  }

  var shift: Binding<Bool> {
    boolBinding(\.shift)
  }

  var option: Binding<Bool> {
    boolBinding(\.option)
  }

  var control: Binding<Bool> {
    boolBinding(\.control)
  }

  private func boolBinding(_ keyPath: WritableKeyPath<HotKeyShortcut, Bool>) -> Binding<Bool> {
    Binding<Bool>(
      get: { wrappedValue[keyPath: keyPath] },
      set: { newValue in
        var updated = wrappedValue
        updated[keyPath: keyPath] = newValue
        wrappedValue = updated
      }
    )
  }
}

private func panelHeader(title: String, subtitle: String, accentColor: Color, rainbowMode: Bool = false) -> some View {
  VStack(alignment: .leading, spacing: 4) {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
    Text(subtitle)
      .font(.system(size: 10.5))
      .foregroundStyle(.secondary)
  }
  .frame(maxWidth: .infinity, alignment: .leading)
  .padding(.horizontal, 10)
  .padding(.vertical, 7)
  .background(
    ZStack(alignment: .bottomLeading) {
      Color.clear
      Rectangle()
        .fill(
          rainbowMode
            ? AnyShapeStyle(LinearGradient(
              colors: [Color.pink, Color.purple, Color.blue, Color.cyan, Color.green, Color.yellow, Color.orange, Color.red],
              startPoint: .leading,
              endPoint: .trailing
            ))
            : AnyShapeStyle(accentColor.opacity(0.55))
        )
        .frame(height: 2)
    }
  )
}
