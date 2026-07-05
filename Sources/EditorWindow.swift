import AppKit
import CoreGraphics
import CoreImage
import CoreText
import Foundation
import UniformTypeIdentifiers

final class EditorWindowController: NSWindowController {
  private let vc: EditorViewController

  init(image: NSImage, suggestedFilenameExt: String, onExport: @escaping (URL) -> Void) {
    self.vc = EditorViewController(image: image, suggestedFilenameExt: suggestedFilenameExt, onExport: onExport)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Edit"
    window.center()
    window.contentViewController = vc
    super.init(window: window)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private enum EditorTool: String, CaseIterable {
  case pointer = "Pointer"
  case pen = "Freehand"
  case freehandArrow = "Freehand arrow"
  case highlighter = "Highlighter"
  case eraser = "Eraser"
  case line = "Line"
  case arrow = "Arrow"
  case rect = "Rectangle"
  case filledRect = "Filled Rectangle"
  case ellipse = "Ellipse"
  case text = "Text"
  case textOutline = "Text (Outline)"
  case textBackground = "Text (Background)"
  case speechBalloon = "Speech balloon"
  case step = "Step"
  case highlightRect = "Highlight"
  case magnify = "Magnify"
  case imageFile = "Image (File)"
  case imageScreen = "Image (Screen)"
  case sticker = "Sticker"
  case cursor = "Cursor"
  case smartEraser = "Smart eraser"
  case blur = "Blur"
  case pixelate = "Pixelate"
  case blackRedact = "Black Redact"
  case crop = "Crop image"
}

private enum OverlayKind: String {
  case line
  case arrow
  case rect
  case filledRect
  case ellipse
  case text
  case textOutline
  case textBackground
  case speechBalloon
  case step
  case highlightRect
  case magnify
  case image
  case sticker
  case cursor
}

private struct OverlayItem {
  var kind: OverlayKind
  // Normalized coordinates (0..1) relative to current base image size, origin top-left.
  var a: CGPoint
  var b: CGPoint
  var color: NSColor
  var width: CGFloat
  var text: String?
  var fontSize: CGFloat
  var fillColor: NSColor?
  var outlineColor: NSColor?
  var outlineWidth: CGFloat
  var padding: CGFloat
  var image: NSImage?
  var imageAlpha: CGFloat
  var magnifyZoom: CGFloat

  init(
    kind: OverlayKind,
    a: CGPoint,
    b: CGPoint,
    color: NSColor,
    width: CGFloat,
    text: String?,
    fontSize: CGFloat,
    fillColor: NSColor? = nil,
    outlineColor: NSColor? = nil,
    outlineWidth: CGFloat = 0,
    padding: CGFloat = 0,
    image: NSImage? = nil,
    imageAlpha: CGFloat = 1.0,
    magnifyZoom: CGFloat = 2.0
  ) {
    self.kind = kind
    self.a = a
    self.b = b
    self.color = color
    self.width = width
    self.text = text
    self.fontSize = fontSize
    self.fillColor = fillColor
    self.outlineColor = outlineColor
    self.outlineWidth = outlineWidth
    self.padding = padding
    self.image = image
    self.imageAlpha = imageAlpha
    self.magnifyZoom = magnifyZoom
  }
}

private enum InkMode {
  case draw
  case erase
}

private struct InkStroke {
  var points: [CGPoint] // normalized points
  var color: NSColor
  var width: CGFloat
  var alpha: CGFloat
  var mode: InkMode
  var arrowHead: Bool

  init(points: [CGPoint], color: NSColor, width: CGFloat, alpha: CGFloat, mode: InkMode, arrowHead: Bool = false) {
    self.points = points
    self.color = color
    self.width = width
    self.alpha = alpha
    self.mode = mode
    self.arrowHead = arrowHead
  }
}

fileprivate enum DestructiveOp {
  case crop(CGRect)     // normalized rect
  case blur(CGRect)
  case pixelate(CGRect)
  case blackRedact(CGRect)
}

fileprivate enum TransformOp {
  case rotateLeft
  case rotateRight
  case flipHorizontal
  case flipVertical
}

private final class EditorViewController: NSViewController {
  private let onExport: (URL) -> Void

  private var tool: EditorTool = .pen { didSet { applyTool() } }
  private var strokeColor: NSColor = .systemRed
  private var strokeWidth: CGFloat = 6
  private var fontSize: CGFloat = 28
  private var filterStrength: CGFloat = 14
  private var nextStepNumber: Int = 1
  private var stickerText: String = ""

  private struct Snapshot {
    var baseImage: NSImage
    var overlays: [OverlayItem]
    var strokes: [InkStroke]
    var nextStepNumber: Int
    var magnification: CGFloat
  }

  private var undoStack: [Snapshot] = []
  private var redoStack: [Snapshot] = []
  private let maxUndo: Int = 50

  private var baseImage: NSImage
  private var overlays: [OverlayItem] = []

  private let scrollView = NSScrollView()
  private let canvasContainer = NSView()
  private let imageView = NSImageView()
  private let inkView = InkView()
  private let overlayView = OverlayView()

  private let toolPop = NSPopUpButton(frame: .zero, pullsDown: false)
  private let undoButton = NSButton(frame: .zero)
  private let redoButton = NSButton(frame: .zero)
  private let actionsPop = NSPopUpButton(frame: .zero, pullsDown: true)
  private let detectSensitiveButton = NSButton(frame: .zero)
  private let colorWell = NSColorWell(frame: .zero)
  private let widthSlider = NSSlider(value: 6, minValue: 1, maxValue: 30, target: nil, action: nil)
  private let fontSlider = NSSlider(value: 28, minValue: 10, maxValue: 72, target: nil, action: nil)
  private let filterSlider = NSSlider(value: 14, minValue: 2, maxValue: 60, target: nil, action: nil)
  private let filterLabel = NSTextField(labelWithString: "Filter:")
  private let zoomOutButton = NSButton(frame: .zero)
  private let zoomInButton = NSButton(frame: .zero)
  private let zoomSlider = NSSlider(value: 1.0, minValue: 0.25, maxValue: 4.0, target: nil, action: nil)
  private let zoomLabel = NSTextField(labelWithString: "100%")
  private var smartRedactionInProgress = false

  init(image: NSImage, suggestedFilenameExt: String, onExport: @escaping (URL) -> Void) {
    self.baseImage = image
    self.onExport = onExport
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func loadView() {
    let root = EditorRootView(frame: NSRect(x: 0, y: 0, width: 1100, height: 760))
    root.controller = self
    self.view = root

    // Top bar.
    let bar = NSVisualEffectView(frame: NSRect(x: 0, y: self.view.bounds.height - 54, width: self.view.bounds.width, height: 54))
    bar.material = .titlebar
    bar.blendingMode = .withinWindow
    bar.autoresizingMask = [.width, .minYMargin]

    let barSep = NSBox(frame: NSRect(x: 0, y: 0, width: bar.bounds.width, height: 1))
    barSep.boxType = .separator
    barSep.autoresizingMask = [.width]

    // Undo/redo.
    configureIconButton(undoButton, symbol: "arrow.uturn.backward", title: "Undo", action: #selector(undoAction))
    undoButton.frame = NSRect(x: 12, y: 14, width: 28, height: 28)

    configureIconButton(redoButton, symbol: "arrow.uturn.forward", title: "Redo", action: #selector(redoAction))
    redoButton.frame = NSRect(x: 44, y: 14, width: 28, height: 28)

    toolPop.addItems(withTitles: EditorTool.allCases.map { $0.rawValue })
    toolPop.frame = NSRect(x: 78, y: 14, width: 150, height: 28)
    toolPop.target = self
    toolPop.action = #selector(onToolChange)

    colorWell.frame = NSRect(x: 238, y: 14, width: 36, height: 28)
    colorWell.color = strokeColor
    colorWell.target = self
    colorWell.action = #selector(onColorChange)

    let widthLabel = NSTextField(labelWithString: "Width:")
    widthLabel.font = .systemFont(ofSize: 11)
    widthLabel.textColor = .secondaryLabelColor
    widthLabel.frame = NSRect(x: 286, y: 18, width: 38, height: 16)

    widthSlider.frame = NSRect(x: 326, y: 14, width: 90, height: 28)
    widthSlider.target = self
    widthSlider.action = #selector(onWidthChange)

    let fontLabel = NSTextField(labelWithString: "Font:")
    fontLabel.font = .systemFont(ofSize: 11)
    fontLabel.textColor = .secondaryLabelColor
    fontLabel.frame = NSRect(x: 424, y: 18, width: 32, height: 16)

    fontSlider.frame = NSRect(x: 458, y: 14, width: 86, height: 28)
    fontSlider.target = self
    fontSlider.action = #selector(onFontChange)

    filterLabel.font = .systemFont(ofSize: 11)
    filterLabel.textColor = .secondaryLabelColor
    filterLabel.frame = NSRect(x: 552, y: 18, width: 56, height: 16)

    filterSlider.frame = NSRect(x: 590, y: 14, width: 94, height: 28)
    filterSlider.target = self
    filterSlider.action = #selector(onFilterChange)

    // Actions menu (resize/rotate/flip/zoom presets).
    actionsPop.frame = NSRect(x: 692, y: 14, width: 62, height: 28)
    actionsPop.addItem(withTitle: "More")
    actionsPop.menu?.items.first?.isEnabled = false
    addActionsMenuItems()

    configureIconButton(detectSensitiveButton, symbol: "eye.slash", title: "Detect Sensitive", action: #selector(actionDetectSensitive))
    detectSensitiveButton.frame = NSRect(x: 758, y: 14, width: 28, height: 28)

    // Zoom controls.
    configureIconButton(zoomOutButton, symbol: "minus.magnifyingglass", title: "Zoom Out", action: #selector(zoomOut))
    zoomOutButton.frame = NSRect(x: 790, y: 14, width: 28, height: 28)

    zoomSlider.frame = NSRect(x: 822, y: 14, width: 50, height: 28)
    zoomSlider.target = self
    zoomSlider.action = #selector(onZoomSlider)

    zoomLabel.frame = NSRect(x: 876, y: 18, width: 34, height: 16)
    zoomLabel.font = .systemFont(ofSize: 11)
    zoomLabel.textColor = .secondaryLabelColor
    zoomLabel.alignment = .right

    configureIconButton(zoomInButton, symbol: "plus.magnifyingglass", title: "Zoom In", action: #selector(zoomIn))
    zoomInButton.frame = NSRect(x: 914, y: 14, width: 28, height: 28)

    let save = NSButton(title: "Save & Upload", target: self, action: #selector(saveAndUpload))
    if let logo = BrandAssets.logoImage(size: NSSize(width: 14, height: 14)) {
      logo.isTemplate = false
      save.image = logo
    } else {
      save.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Save & Upload")
    }
    save.imagePosition = .imageLeading
    save.keyEquivalent = "\r"
    save.frame = NSRect(x: bar.bounds.width - 156, y: 12, width: 140, height: 32)
    save.autoresizingMask = [.minXMargin]

    bar.addSubview(barSep)
    bar.addSubview(undoButton)
    bar.addSubview(redoButton)
    bar.addSubview(toolPop)
    bar.addSubview(actionsPop)
    bar.addSubview(detectSensitiveButton)
    bar.addSubview(colorWell)
    bar.addSubview(widthLabel)
    bar.addSubview(widthSlider)
    bar.addSubview(fontLabel)
    bar.addSubview(fontSlider)
    bar.addSubview(filterLabel)
    bar.addSubview(filterSlider)
    bar.addSubview(zoomOutButton)
    bar.addSubview(zoomSlider)
    bar.addSubview(zoomLabel)
    bar.addSubview(zoomInButton)
    bar.addSubview(save)

    // Canvas area.
    let canvasFrame = NSRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height - 54)
    scrollView.frame = canvasFrame
    scrollView.autoresizingMask = [.width, .height]
    scrollView.drawsBackground = false
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.allowsMagnification = true
    scrollView.minMagnification = 0.25
    scrollView.maxMagnification = 4.0

    let imgSize = baseImagePixelSize()
    canvasContainer.frame = NSRect(x: 0, y: 0, width: imgSize.width, height: imgSize.height)

    imageView.frame = canvasContainer.bounds
    imageView.autoresizingMask = [.width, .height]
    imageView.imageAlignment = .alignCenter
    imageView.imageScaling = .scaleNone
    imageView.image = baseImage

    inkView.frame = canvasContainer.bounds
    inkView.autoresizingMask = [.width, .height]

    overlayView.frame = canvasContainer.bounds
    overlayView.autoresizingMask = [.width, .height]

    // Wire shared geometry.
    let getImgRect: () -> CGRect = { [weak self] in
      self?.imageRectInView() ?? .zero
    }

    inkView.getTool = { [weak self] in self?.tool ?? .pointer }
    inkView.getStroke = { [weak self] in (self?.strokeColor ?? .systemRed, self?.strokeWidth ?? 6) }
    inkView.getImageRect = getImgRect
    inkView.onStrokeCommitted = { [weak self] _ in
      self?.pushUndo()
    }

    overlayView.getTool = { [weak self] in self?.tool ?? .pointer }
    overlayView.getStroke = { [weak self] in
      (self?.strokeColor ?? .systemRed, self?.strokeWidth ?? 6, self?.fontSize ?? 28)
    }
    overlayView.getFilterStrength = { [weak self] in self?.filterStrength ?? 14 }
    overlayView.getImageRect = getImgRect
    overlayView.getBaseImage = { [weak self] in self?.baseImage }
    overlayView.getInkStrokes = { [weak self] in self?.inkView.snapshotStrokes() ?? [] }
    overlayView.setInkStrokes = { [weak self] items in self?.inkView.setStrokes(items) }
    overlayView.resolveStickerText = { [weak self] in
      guard let self else { return nil }
      let trimmed = self.stickerText.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
      return self.promptStickerText()
    }
    overlayView.addOverlay = { [weak self] item in
      self?.pushUndo()
      self?.overlays.append(item)
      self?.overlayView.setOverlays(self?.overlays ?? [])
    }
    overlayView.commitDestructive = { [weak self] op in
      guard let self else { return }
      self.pushUndo()
      if !self.overlays.isEmpty || !self.inkView.snapshotStrokes().isEmpty {
        self.commitToBase()
      }
      self.applyDestructive(op)
    }
    overlayView.commitTransform = { [weak self] op in
      self?.pushUndo()
      self?.commitToBase()
      self?.applyTransform(op)
    }
    overlayView.onStep = { [weak self] center in
      self?.pushUndo()
      self?.addStepOverlay(center: center)
    }
    overlayView.onOverlaysChanged = { [weak self] items, selected in
      self?.overlays = items
      self?.overlayView.setOverlays(items, selectedIndex: selected)
    }
    overlayView.requestUndoCheckpoint = { [weak self] in
      self?.pushUndo()
    }

    overlayView.setOverlays(overlays)

    canvasContainer.addSubview(imageView)
    canvasContainer.addSubview(inkView)
    canvasContainer.addSubview(overlayView)

    scrollView.documentView = canvasContainer
    self.view.addSubview(scrollView)
    self.view.addSubview(bar)

    toolPop.selectItem(withTitle: tool.rawValue)
    applyTool()

    // Initial zoom: fit-to-window.
    DispatchQueue.main.async { [weak self] in
      self?.fitToWindow()
      self?.updateUndoRedoButtons()
    }
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    // Ensure keyboard shortcuts (Cmd+Z, Delete, etc.) land on the editor when possible.
    view.window?.makeFirstResponder(view)
  }

  func handleKeyDown(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let chars = (event.charactersIgnoringModifiers ?? "").lowercased()

    if flags.contains(.command), chars == "z" {
      if flags.contains(.shift) {
        redoAction()
      } else {
        undoAction()
      }
      return true
    }

    if flags.contains(.command), (chars == "+" || chars == "=") {
      zoomIn()
      return true
    }

    if flags.contains(.command), chars == "-" {
      zoomOut()
      return true
    }

    // Delete/backspace removes the selected overlay (when using the Pointer tool).
    if (event.keyCode == 51 || event.keyCode == 117), tool == .pointer {
      if overlayView.hasSelection() {
        pushUndo()
        _ = overlayView.deleteSelectedOverlay()
      }
      return true
    }

    // Escape clears selection.
    if event.keyCode == 53 {
      overlayView.clearSelection()
      return true
    }

    return false
  }

  private func configureIconButton(_ btn: NSButton, symbol: String, title: String, action: Selector) {
    btn.title = ""
    btn.bezelStyle = .texturedRounded
    btn.controlSize = .small
    btn.imagePosition = .imageOnly
    btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
    btn.toolTip = title
    btn.target = self
    btn.action = action
  }

  private func addActionsMenuItems() {
    guard let menu = actionsPop.menu else { return }

    func addItem(_ title: String, _ action: Selector) {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }

    menu.addItem(NSMenuItem.separator())
    addItem("Fit to Window", #selector(actionFitToWindow))
    addItem("Actual Size (100%)", #selector(actionActualSize))
    menu.addItem(NSMenuItem.separator())
    addItem("Resize\u{2026}", #selector(actionResize))
    addItem("Detect Sensitive", #selector(actionDetectSensitive))
    menu.addItem(NSMenuItem.separator())
    addItem("Rotate Left", #selector(actionRotateLeft))
    addItem("Rotate Right", #selector(actionRotateRight))
    addItem("Flip Horizontal", #selector(actionFlipHorizontal))
    addItem("Flip Vertical", #selector(actionFlipVertical))
    menu.addItem(NSMenuItem.separator())
    addItem("Reset Step Counter", #selector(actionResetSteps))
    addItem("Set Sticker\u{2026}", #selector(actionSetSticker))
  }

  private func baseImagePixelSize() -> CGSize {
    let s = baseImage.size
    if s.width > 0, s.height > 0 {
      return s
    }
    if let rep = try? makeUprightBitmapRep(from: baseImage) {
      if rep.size.width > 0, rep.size.height > 0 {
        return rep.size
      }
      return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
    return CGSize(width: 1, height: 1)
  }

  private func updateCanvasForBaseImage() {
    let size = baseImagePixelSize()
    canvasContainer.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
    imageView.frame = canvasContainer.bounds
    inkView.frame = canvasContainer.bounds
    overlayView.frame = canvasContainer.bounds
    canvasContainer.needsLayout = true
  }

  private func clamp01(_ v: CGFloat) -> CGFloat {
    min(1, max(0, v))
  }

  private func currentSnapshot() -> Snapshot {
    Snapshot(
      baseImage: baseImage,
      overlays: overlays,
      strokes: inkView.snapshotStrokes(),
      nextStepNumber: nextStepNumber,
      magnification: scrollView.magnification
    )
  }

  private func pushUndo() {
    undoStack.append(currentSnapshot())
    if undoStack.count > maxUndo {
      undoStack.removeFirst(undoStack.count - maxUndo)
    }
    redoStack.removeAll()
    updateUndoRedoButtons()
  }

  private func restore(_ snap: Snapshot) {
    baseImage = snap.baseImage
    overlays = snap.overlays
    nextStepNumber = snap.nextStepNumber

    imageView.image = baseImage
    inkView.setStrokes(snap.strokes)
    overlayView.setOverlays(overlays, selectedIndex: nil)

    updateCanvasForBaseImage()
    setMagnification(snap.magnification, centeredAt: nil)
  }

  @objc private func undoAction() {
    guard let snap = undoStack.popLast() else { return }
    redoStack.append(currentSnapshot())
    restore(snap)
    updateUndoRedoButtons()
  }

  @objc private func redoAction() {
    guard let snap = redoStack.popLast() else { return }
    undoStack.append(currentSnapshot())
    restore(snap)
    updateUndoRedoButtons()
  }

  private func updateUndoRedoButtons() {
    undoButton.isEnabled = !undoStack.isEmpty
    redoButton.isEnabled = !redoStack.isEmpty
  }

  private func setMagnification(_ mag: CGFloat, centeredAt: CGPoint?) {
    let clamped = min(scrollView.maxMagnification, max(scrollView.minMagnification, mag))
    let center: CGPoint
    if let centeredAt {
      center = centeredAt
    } else {
      let vis = scrollView.contentView.documentVisibleRect
      center = CGPoint(x: vis.midX, y: vis.midY)
    }

    scrollView.setMagnification(clamped, centeredAt: center)
    zoomSlider.doubleValue = Double(clamped)
    zoomLabel.stringValue = "\(Int((clamped * 100).rounded()))%"
  }

  private func fitToWindow() {
    let viewport = scrollView.contentView.bounds.size
    let doc = canvasContainer.bounds.size
    if viewport.width <= 0 || viewport.height <= 0 || doc.width <= 0 || doc.height <= 0 { return }
    let scale = min(viewport.width / doc.width, viewport.height / doc.height)
    setMagnification(scale, centeredAt: CGPoint(x: doc.width / 2, y: doc.height / 2))
  }

  @objc private func onZoomSlider() {
    setMagnification(CGFloat(zoomSlider.doubleValue), centeredAt: nil)
  }

  @objc private func zoomIn() {
    setMagnification(scrollView.magnification * 1.15, centeredAt: nil)
  }

  @objc private func zoomOut() {
    setMagnification(scrollView.magnification / 1.15, centeredAt: nil)
  }

  private func addStepOverlay(center: CGPoint) {
    let diameterPx: CGFloat = 44
    var pxW: CGFloat = 0
    var pxH: CGFloat = 0
    if let rep = try? makeUprightBitmapRep(from: baseImage) {
      pxW = CGFloat(rep.pixelsWide)
      pxH = CGFloat(rep.pixelsHigh)
    }
    if pxW <= 0 || pxH <= 0 {
      pxW = max(1, baseImage.size.width)
      pxH = max(1, baseImage.size.height)
    }

    let halfW = (diameterPx / pxW) / 2
    let halfH = (diameterPx / pxH) / 2

    let a = CGPoint(x: clamp01(center.x - halfW), y: clamp01(center.y - halfH))
    let b = CGPoint(x: clamp01(center.x + halfW), y: clamp01(center.y + halfH))

    let n = nextStepNumber
    nextStepNumber += 1
    let item = OverlayItem(kind: .step, a: a, b: b, color: strokeColor, width: 2, text: "\(n)", fontSize: fontSize)
    overlays.append(item)
    overlayView.setOverlays(overlays, selectedIndex: overlays.count - 1)
  }

  // MARK: Actions menu

  @objc private func actionFitToWindow() {
    actionsPop.selectItem(at: 0)
    fitToWindow()
  }

  @objc private func actionActualSize() {
    actionsPop.selectItem(at: 0)
    setMagnification(1.0, centeredAt: nil)
  }

  @objc private func actionResize() {
    actionsPop.selectItem(at: 0)
    promptResize()
  }

  @objc private func actionDetectSensitive() {
    actionsPop.selectItem(at: 0)
    guard !smartRedactionInProgress else { return }
    guard let composite = renderCompositeImage() else {
      Notifier.shared.notify(title: "CraftyCannon", body: "Failed to render image for redaction")
      return
    }

    let imageURL: URL
    do {
      imageURL = try exportToTemp(image: composite)
    } catch {
      Notifier.shared.notify(title: "CraftyCannon", body: "Failed to prepare image for redaction")
      return
    }

    smartRedactionInProgress = true
    detectSensitiveButton.isEnabled = false
    Notifier.shared.notify(title: "CraftyCannon", body: "Detecting sensitive text...")

    Task { [weak self] in
      let result: Result<[SmartRedactionRegion], Error>
      do {
        result = .success(try await SmartRedactionDetector.shared.detectSensitiveRegions(in: imageURL))
      } catch {
        result = .failure(error)
      }
      try? FileManager.default.removeItem(at: imageURL)

      await MainActor.run {
        guard let self else { return }
        self.smartRedactionInProgress = false
        self.detectSensitiveButton.isEnabled = true
        self.applyDetectedSmartRedactions(result, to: composite)
      }
    }
  }

  @objc private func actionRotateLeft() {
    actionsPop.selectItem(at: 0)
    pushUndo()
    commitToBase()
    applyTransform(.rotateLeft)
  }

  @objc private func actionRotateRight() {
    actionsPop.selectItem(at: 0)
    pushUndo()
    commitToBase()
    applyTransform(.rotateRight)
  }

  @objc private func actionFlipHorizontal() {
    actionsPop.selectItem(at: 0)
    pushUndo()
    commitToBase()
    applyTransform(.flipHorizontal)
  }

  @objc private func actionFlipVertical() {
    actionsPop.selectItem(at: 0)
    pushUndo()
    commitToBase()
    applyTransform(.flipVertical)
  }

  @objc private func actionResetSteps() {
    actionsPop.selectItem(at: 0)
    pushUndo()
    nextStepNumber = 1
  }

  @objc private func actionSetSticker() {
    actionsPop.selectItem(at: 0)
    _ = promptStickerText(force: true)
  }

  private func promptStickerText(force: Bool = false) -> String? {
    if !force {
      let trimmed = stickerText.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }

    let alert = NSAlert()
    alert.messageText = "Sticker"
    alert.informativeText = "Enter sticker text (emoji or short label)."
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")

    let field = NSTextField(string: stickerText)
    field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
    alert.accessoryView = field
    alert.ensureResizable()

    NSApp.activate(ignoringOtherApps: true)
    let resp = alert.runModal()
    guard resp == .alertFirstButtonReturn else { return nil }
    let txt = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    stickerText = txt
    return txt.isEmpty ? nil : txt
  }

  private func promptResize() {
    guard let rep = try? makeUprightBitmapRep(from: baseImage) else { return }

    let w0 = rep.pixelsWide
    let h0 = rep.pixelsHigh

    let alert = NSAlert()
    alert.messageText = "Resize"
    alert.informativeText = "Enter new pixel dimensions."
    alert.addButton(withTitle: "Resize")
    alert.addButton(withTitle: "Cancel")

    let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 86))

    let wLabel = NSTextField(labelWithString: "Width")
    wLabel.frame = NSRect(x: 0, y: 58, width: 60, height: 18)
    let wField = NSTextField(string: "\(w0)")
    wField.frame = NSRect(x: 70, y: 54, width: 170, height: 24)

    let hLabel = NSTextField(labelWithString: "Height")
    hLabel.frame = NSRect(x: 0, y: 28, width: 60, height: 18)
    let hField = NSTextField(string: "\(h0)")
    hField.frame = NSRect(x: 70, y: 24, width: 170, height: 24)

    let lock = NSButton(checkboxWithTitle: "Lock aspect ratio", target: nil, action: nil)
    lock.state = .on
    lock.frame = NSRect(x: 0, y: 2, width: 240, height: 20)

    accessory.addSubview(wLabel)
    accessory.addSubview(wField)
    accessory.addSubview(hLabel)
    accessory.addSubview(hField)
    accessory.addSubview(lock)
    alert.accessoryView = accessory
    alert.ensureResizable()

    guard let window = view.window else {
      if alert.runModal() == .alertFirstButtonReturn {
        applyResizeFromFields(wField: wField, hField: hField, lock: lock, w0: w0, h0: h0)
      }
      return
    }

    alert.beginSheetModal(for: window) { [weak self] resp in
      guard let self else { return }
      if resp == .alertFirstButtonReturn {
        self.applyResizeFromFields(wField: wField, hField: hField, lock: lock, w0: w0, h0: h0)
      }
    }
  }

  private func applyResizeFromFields(wField: NSTextField, hField: NSTextField, lock: NSButton, w0: Int, h0: Int) {
    guard var w = Int(wField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
          var h = Int(hField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      return
    }

    w = max(1, w)
    h = max(1, h)

    if lock.state == .on, w0 > 0, h0 > 0 {
      let aspect = Double(h0) / Double(w0)
      let wChanged = w != w0
      let hChanged = h != h0
      if wChanged && !hChanged {
        h = Int((Double(w) * aspect).rounded())
      } else if hChanged && !wChanged {
        w = Int((Double(h) / aspect).rounded())
      } else {
        h = Int((Double(w) * aspect).rounded())
      }
      h = max(1, h)
      w = max(1, w)
    }

    pushUndo()
    commitToBase()

    if let out = resizePixels(image: baseImage, newPixelSize: CGSize(width: w, height: h)) {
      baseImage = out
      imageView.image = out
      updateCanvasForBaseImage()
      fitToWindow()
    }
  }

  private func applyTransform(_ op: TransformOp) {
    let out: NSImage?
    switch op {
    case .rotateLeft:
      out = rotate90(image: baseImage, clockwise: false)
    case .rotateRight:
      out = rotate90(image: baseImage, clockwise: true)
    case .flipHorizontal:
      out = flip(image: baseImage, horizontal: true)
    case .flipVertical:
      out = flip(image: baseImage, horizontal: false)
    }

    if let out {
      baseImage = out
      imageView.image = out
      updateCanvasForBaseImage()
      fitToWindow()
    }
  }

  private func applyDetectedSmartRedactions(_ result: Result<[SmartRedactionRegion], Error>, to composite: NSImage) {
    let regions: [SmartRedactionRegion]
    switch result {
    case .success(let detected):
      regions = detected
    case .failure:
      Notifier.shared.notify(title: "CraftyCannon", body: "Sensitive text detection failed")
      return
    }

    guard !regions.isEmpty else {
      Notifier.shared.notify(title: "CraftyCannon", body: "No sensitive text detected")
      return
    }

    guard let redacted = SmartRedactionImageProcessor.redactedImage(
      composite,
      regions: regions,
      mode: RuntimePreferences.shared.smartRedactionRenderMode,
      strength: filterStrength
    ) else {
      Notifier.shared.notify(title: "CraftyCannon", body: "No redaction regions could be applied")
      return
    }

    pushUndo()
    baseImage = redacted
    imageView.image = redacted
    inkView.clearAll()
    overlays.removeAll()
    overlayView.setOverlays([], selectedIndex: nil)
    updateCanvasForBaseImage()
    Notifier.shared.notify(title: "CraftyCannon", body: "Redacted \(regions.count) sensitive region(s)")
  }

  private func rotate90(image: NSImage, clockwise: Bool) -> NSImage? {
    guard let rep = try? makeUprightBitmapRep(from: image), let cg = rep.cgImage else { return nil }
    let pxW = CGFloat(rep.pixelsWide)
    let pxH = CGFloat(rep.pixelsHigh)
    let sx = (pxW > 0) ? (image.size.width / pxW) : 1
    let sy = (pxH > 0) ? (image.size.height / pxH) : 1

    let ci = CIImage(cgImage: cg)
    let angle: CGFloat = clockwise ? (.pi / 2) : (-.pi / 2)
    let rotated = ci.transformed(by: CGAffineTransform(rotationAngle: angle))
    let normalized = rotated.transformed(by: CGAffineTransform(translationX: -rotated.extent.origin.x, y: -rotated.extent.origin.y))

    let ciCtx = CIContext(options: nil)
    guard let outCg = ciCtx.createCGImage(normalized, from: normalized.extent) else { return nil }

    // Swap point scales for 90-degree rotation.
    return NSImage(
      cgImage: outCg,
      size: NSSize(width: normalized.extent.width * sy, height: normalized.extent.height * sx)
    )
  }

  private func flip(image: NSImage, horizontal: Bool) -> NSImage? {
    guard let rep = try? makeUprightBitmapRep(from: image), let cg = rep.cgImage else { return nil }
    let pxW = CGFloat(rep.pixelsWide)
    let pxH = CGFloat(rep.pixelsHigh)
    let sx = (pxW > 0) ? (image.size.width / pxW) : 1
    let sy = (pxH > 0) ? (image.size.height / pxH) : 1

    let ci = CIImage(cgImage: cg)

    var t = CGAffineTransform.identity
    if horizontal {
      t = t.translatedBy(x: ci.extent.width, y: 0)
      t = t.scaledBy(x: -1, y: 1)
    } else {
      t = t.translatedBy(x: 0, y: ci.extent.height)
      t = t.scaledBy(x: 1, y: -1)
    }

    let flipped = ci.transformed(by: t)
    let normalized = flipped.transformed(by: CGAffineTransform(translationX: -flipped.extent.origin.x, y: -flipped.extent.origin.y))

    let ciCtx = CIContext(options: nil)
    guard let outCg = ciCtx.createCGImage(normalized, from: normalized.extent) else { return nil }
    return NSImage(cgImage: outCg, size: NSSize(width: normalized.extent.width * sx, height: normalized.extent.height * sy))
  }

  private func resizePixels(image: NSImage, newPixelSize: CGSize) -> NSImage? {
    guard let rep = try? makeUprightBitmapRep(from: image), let cg = rep.cgImage else { return nil }
    let outW = max(1, Int(newPixelSize.width.rounded()))
    let outH = max(1, Int(newPixelSize.height.rounded()))

    let pxW = CGFloat(rep.pixelsWide)
    let pxH = CGFloat(rep.pixelsHigh)
    let sx = (pxW > 0) ? (image.size.width / pxW) : 1
    let sy = (pxH > 0) ? (image.size.height / pxH) : 1

    guard let ctx = makeTopLeftBitmapContext(width: outW, height: outH) else { return nil }

    ctx.interpolationQuality = .high

    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(outW), height: CGFloat(outH)))
    guard let outCg = ctx.makeImage() else { return nil }
    return NSImage(cgImage: outCg, size: NSSize(width: CGFloat(outW) * sx, height: CGFloat(outH) * sy))
  }

  private func imageRectInView() -> CGRect {
    guard let img = imageView.image else { return .zero }

    let viewSize = imageView.bounds.size
    let imgSize = img.size

    if imgSize.width <= 0 || imgSize.height <= 0 { return .zero }

    let scale = min(viewSize.width / imgSize.width, viewSize.height / imgSize.height)
    let w = imgSize.width * scale
    let h = imgSize.height * scale
    let x = (viewSize.width - w) / 2
    let y = (viewSize.height - h) / 2
    return CGRect(x: x, y: y, width: w, height: h)
  }

  @objc private func onToolChange() {
    if let title = toolPop.selectedItem?.title, let t = EditorTool(rawValue: title) {
      tool = t
    }
  }

  @objc private func onColorChange() {
    strokeColor = colorWell.color
    applyTool()
    overlayView.needsDisplay = true
  }

  @objc private func onWidthChange() {
    strokeWidth = CGFloat(widthSlider.doubleValue)
    applyTool()
    overlayView.needsDisplay = true
  }

  @objc private func onFontChange() {
    fontSize = CGFloat(fontSlider.doubleValue)
    overlayView.needsDisplay = true
  }

  @objc private func onFilterChange() {
    filterStrength = CGFloat(filterSlider.doubleValue)
    overlayView.needsDisplay = true
  }

  private func applyTool() {
    switch tool {
    case .pen, .freehandArrow, .highlighter, .eraser:
      inkView.isHidden = false
    default:
      inkView.isHidden = true
    }
    filterSlider.isEnabled = (tool == .blur || tool == .pixelate || tool == .magnify)
    filterLabel.stringValue = (tool == .magnify) ? "Zoom:" : "Filter:"
    overlayView.needsDisplay = true
  }

  private func commitToBase() {
    if overlays.isEmpty, inkView.snapshotStrokes().isEmpty {
      return
    }
    guard let composite = renderCompositeImage() else { return }
    baseImage = composite
    imageView.image = baseImage

    inkView.clearAll()

    overlays.removeAll()
    overlayView.setOverlays([], selectedIndex: nil)
  }

  private func applyDestructive(_ op: DestructiveOp) {
    switch op {
    case .crop(let normRect):
      if let out = crop(image: baseImage, normRect: normRect) {
        baseImage = out
        imageView.image = out
        updateCanvasForBaseImage()
        fitToWindow()
      }
    case .blur(let normRect):
      if let out = filterRegion(image: baseImage, normRect: normRect, kind: .blur, strength: filterStrength) {
        baseImage = out
        imageView.image = out
      }
    case .pixelate(let normRect):
      if let out = filterRegion(image: baseImage, normRect: normRect, kind: .pixelate, strength: filterStrength) {
        baseImage = out
        imageView.image = out
      }
    case .blackRedact(let normRect):
      let region = SmartRedactionRegion(rect: normRect, category: .textOCR, matchedText: nil)
      if let out = SmartRedactionImageProcessor.blackBoxedImage(baseImage, regions: [region]) {
        baseImage = out
        imageView.image = out
      }
    }
  }

  @objc private func saveAndUpload() {
    guard let composite = renderCompositeImage() else {
      Notifier.shared.notify(title: "CraftyCannon", body: "Failed to render")
      return
    }

    do {
      let url = try exportToTemp(image: composite)
      self.onExport(url)
      self.view.window?.performClose(nil)
    } catch {
      Notifier.shared.notify(title: "CraftyCannon", body: "Export failed")
    }
  }

  private func exportToTemp(image: NSImage) throws -> URL {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("CraftyCannon", isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

    let outUrl = tmpDir.appendingPathComponent("edited-\(UUID().uuidString)").appendingPathExtension("png")

    let rep = try makeUprightBitmapRep(from: image)
    guard let png = rep.representation(using: .png, properties: [:]) else {
      throw NSError(domain: "export", code: 1)
    }
    try png.write(to: outUrl, options: [.atomic])
    return outUrl
  }

  private func renderCompositeImage() -> NSImage? {
    guard let rep = try? makeUprightBitmapRep(from: baseImage),
          let baseCg = rep.cgImage else {
      return nil
    }

    let w = rep.pixelsWide
    let h = rep.pixelsHigh

    guard let ctx = makeTopLeftBitmapContext(width: w, height: h) else {
      return nil
    }

    ctx.draw(baseCg, in: CGRect(x: 0, y: 0, width: w, height: h))

    // Ink strokes.
    for s in inkView.snapshotStrokes() {
      drawInk(ctx: ctx, stroke: s, w: CGFloat(w), h: CGFloat(h))
    }

    // Overlays.
    for o in overlays {
      drawOverlay(ctx: ctx, overlay: o, w: CGFloat(w), h: CGFloat(h), baseCg: baseCg)
    }

    guard let outCg = ctx.makeImage() else { return nil }
    let outSize: NSSize
    if baseImage.size.width > 0, baseImage.size.height > 0 {
      outSize = baseImage.size
    } else {
      outSize = NSSize(width: CGFloat(w), height: CGFloat(h))
    }
    return NSImage(cgImage: outCg, size: outSize)
  }

  private func drawInk(ctx: CGContext, stroke: InkStroke, w: CGFloat, h: CGFloat) {
    guard stroke.points.count >= 2 else { return }

    ctx.saveGState()
    if stroke.mode == .erase {
      ctx.setBlendMode(.clear)
      ctx.setStrokeColor(NSColor.white.cgColor)
    } else {
      ctx.setStrokeColor(stroke.color.withAlphaComponent(stroke.alpha).cgColor)
    }
    ctx.setLineWidth(stroke.width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    func inkPoint(_ p: CGPoint) -> CGPoint {
      CGPoint(x: p.x * w, y: (1 - p.y) * h)
    }

    ctx.beginPath()
    ctx.move(to: inkPoint(stroke.points[0]))
    for p in stroke.points.dropFirst() {
      ctx.addLine(to: inkPoint(p))
    }
    ctx.strokePath()

    if stroke.mode == .draw, stroke.arrowHead, stroke.points.count >= 2 {
      let p0 = stroke.points[stroke.points.count - 2]
      let p1 = stroke.points[stroke.points.count - 1]
      let a = inkPoint(p0)
      let b = inkPoint(p1)
      let ax = a.x
      let ay = a.y
      let bx = b.x
      let by = b.y

      let dx = bx - ax
      let dy = by - ay
      let len = max(1, hypot(dx, dy))
      let ux = dx / len
      let uy = dy / len
      let headLen = max(10, stroke.width * 2.5)
      let angle: CGFloat = .pi / 7

      func rot(_ x: CGFloat, _ y: CGFloat, _ a: CGFloat) -> (CGFloat, CGFloat) {
        (x * cos(a) - y * sin(a), x * sin(a) + y * cos(a))
      }

      let (lx, ly) = rot(-ux, -uy, angle)
      let (rx, ry) = rot(-ux, -uy, -angle)

      ctx.beginPath()
      ctx.move(to: CGPoint(x: bx, y: by))
      ctx.addLine(to: CGPoint(x: bx + lx * headLen, y: by + ly * headLen))
      ctx.move(to: CGPoint(x: bx, y: by))
      ctx.addLine(to: CGPoint(x: bx + rx * headLen, y: by + ry * headLen))
      ctx.strokePath()
    }
    ctx.restoreGState()
  }

  private func drawOverlay(ctx: CGContext, overlay: OverlayItem, w: CGFloat, h: CGFloat, baseCg: CGImage) {
    let ax = overlay.a.x * w
    let bx = overlay.b.x * w
    // Overlay points are stored in top-left normalized coordinates. The bitmap context is
    // y-up (origin bottom-left), so geometry must flip y. The text helpers take the
    // top-down y directly (they convert internally), so keep the raw values for them.
    let ayTop = overlay.a.y * h
    let byTop = overlay.b.y * h
    let ay = h - ayTop
    let by = h - byTop

    ctx.setStrokeColor(overlay.color.cgColor)
    ctx.setLineWidth(overlay.width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    switch overlay.kind {
    case .line:
      ctx.beginPath()
      ctx.move(to: CGPoint(x: ax, y: ay))
      ctx.addLine(to: CGPoint(x: bx, y: by))
      ctx.strokePath()

    case .arrow:
      ctx.beginPath()
      ctx.move(to: CGPoint(x: ax, y: ay))
      ctx.addLine(to: CGPoint(x: bx, y: by))
      ctx.strokePath()

      let dx = bx - ax
      let dy = by - ay
      let len = max(1, hypot(dx, dy))
      let ux = dx / len
      let uy = dy / len
      let headLen = max(10, overlay.width * 3)
      let angle: CGFloat = .pi / 7

      func rot(_ x: CGFloat, _ y: CGFloat, _ a: CGFloat) -> (CGFloat, CGFloat) {
        (x * cos(a) - y * sin(a), x * sin(a) + y * cos(a))
      }

      let (lx, ly) = rot(-ux, -uy, angle)
      let (rx, ry) = rot(-ux, -uy, -angle)

      ctx.beginPath()
      ctx.move(to: CGPoint(x: bx, y: by))
      ctx.addLine(to: CGPoint(x: bx + lx * headLen, y: by + ly * headLen))
      ctx.move(to: CGPoint(x: bx, y: by))
      ctx.addLine(to: CGPoint(x: bx + rx * headLen, y: by + ry * headLen))
      ctx.strokePath()

    case .rect, .ellipse, .highlightRect:
      let x = min(ax, bx)
      let y = min(ay, by)
      let rw = abs(bx - ax)
      let rh = abs(by - ay)
      let r = CGRect(x: x, y: y, width: rw, height: rh)

      if overlay.kind == .highlightRect {
        ctx.setFillColor(overlay.color.withAlphaComponent(0.25).cgColor)
        ctx.fill(r)
      }

      if overlay.kind == .rect || overlay.kind == .highlightRect {
        ctx.stroke(r)
      } else {
        ctx.strokeEllipse(in: r)
      }

    case .filledRect:
      let x = min(ax, bx)
      let y = min(ay, by)
      let rw = abs(bx - ax)
      let rh = abs(by - ay)
      let r = CGRect(x: x, y: y, width: rw, height: rh)
      ctx.setFillColor(overlay.color.cgColor)
      ctx.fill(r)

    case .step:
      let x = min(ax, bx)
      let y = min(ay, by)
      let rw = abs(bx - ax)
      let rh = abs(by - ay)
      let r = CGRect(x: x, y: y, width: rw, height: rh)

      ctx.setFillColor(overlay.color.cgColor)
      ctx.fillEllipse(in: r)
      ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.15).cgColor)
      ctx.setLineWidth(max(2, overlay.width))
      ctx.strokeEllipse(in: r)

      guard let text = overlay.text else { return }
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      let drawSize = max(12, min(overlay.fontSize, r.height * 0.6))
      let font = CTFontCreateWithName("Helvetica-Bold" as CFString, drawSize, nil)
      let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
      ]
      let astr = NSAttributedString(string: text, attributes: attrs)
      let line = CTLineCreateWithAttributedString(astr)
      let lineW = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))

      // Flip for CoreText only.
      ctx.saveGState()
      ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
      let centerYUp = r.midY
      let baselineYUp = centerYUp - (ascent - descent) / 2
      ctx.textPosition = CGPoint(x: r.midX - lineW / 2, y: baselineYUp)
      CTLineDraw(line, ctx)
      ctx.restoreGState()

    case .text:
      guard let text = overlay.text else { return }
      drawTextTopLeft(ctx: ctx, text: text, x: ax, y: ayTop, h: h, fontName: "Helvetica", fontSize: overlay.fontSize, color: overlay.color)

    case .textOutline:
      guard let text = overlay.text else { return }
      let outline = overlay.outlineColor ?? NSColor.black
      let strokeW = max(2, overlay.outlineWidth)
      drawOutlinedTextTopLeft(
        ctx: ctx,
        text: text,
        x: ax,
        y: ayTop,
        h: h,
        fontName: "Helvetica-Bold",
        fontSize: overlay.fontSize,
        fill: overlay.color,
        stroke: outline,
        strokeWidth: strokeW
      )

    case .textBackground:
      guard let text = overlay.text else { return }
      let pad = max(6, overlay.padding)
      let fill = overlay.fillColor ?? NSColor.black.withAlphaComponent(0.70)
      drawTextBoxTopLeft(
        ctx: ctx,
        text: text,
        x: ax,
        y: ayTop,
        h: h,
        fontName: "Helvetica-Bold",
        fontSize: overlay.fontSize,
        textColor: overlay.color,
        fillColor: fill,
        outlineColor: nil,
        outlineWidth: 0,
        padding: pad,
        tail: false
      )

    case .speechBalloon:
      guard let text = overlay.text else { return }
      let pad = max(8, overlay.padding)
      let fill = overlay.fillColor ?? NSColor.black.withAlphaComponent(0.70)
      drawTextBoxTopLeft(
        ctx: ctx,
        text: text,
        x: ax,
        y: ayTop,
        h: h,
        fontName: "Helvetica-Bold",
        fontSize: overlay.fontSize,
        textColor: overlay.color,
        fillColor: fill,
        outlineColor: overlay.outlineColor,
        outlineWidth: max(2, overlay.outlineWidth),
        padding: pad,
        tail: true
      )

    case .sticker:
      guard let text = overlay.text else { return }
      drawTextCentered(ctx: ctx, text: text, x: ax, y: ayTop, w: w, h: h, fontName: "Helvetica", fontSize: overlay.fontSize, color: overlay.color)

    case .cursor:
      let sizePx = max(18, overlay.fontSize)
      // `a` is the cursor's top-left in top-down coordinates; convert to a y-up rect origin.
      let r = CGRect(x: ax, y: ay - sizePx, width: sizePx, height: sizePx)
      let img = tintedSymbol(name: "cursorarrow", pointSize: sizePx, color: overlay.color)
      if let rep = img.flatMap({ try? makeUprightBitmapRep(from: $0) }), let cg = rep.cgImage {
        ctx.draw(cg, in: r)
      }

    case .image:
      guard let img = overlay.image, let rep = try? makeUprightBitmapRep(from: img), let cg = rep.cgImage else { return }
      let r = CGRect(x: min(ax, bx), y: min(ay, by), width: abs(bx - ax), height: abs(by - ay))
      let fit = aspectFitRect(content: CGSize(width: rep.pixelsWide, height: rep.pixelsHigh), into: r.insetBy(dx: 2, dy: 2))
      ctx.saveGState()
      ctx.setAlpha(max(0, min(1, overlay.imageAlpha)))
      ctx.draw(cg, in: fit)
      ctx.restoreGState()

    case .magnify:
      let lens = CGRect(x: min(ax, bx), y: min(ay, by), width: abs(bx - ax), height: abs(by - ay))
      let zoom = max(1.2, overlay.magnifyZoom)
      if lens.width < 2 || lens.height < 2 { return }

      // `lens` and the base CGImage are both y-up here, so the crop region is simply the
      // zoomed box centered on the lens — no y-flip needed.
      var srcCI = CGRect(
        x: lens.midX - lens.width / (2 * zoom),
        y: lens.midY - lens.height / (2 * zoom),
        width: lens.width / zoom,
        height: lens.height / zoom
      ).integral

      let full = CGRect(x: 0, y: 0, width: w, height: h).integral
      srcCI = srcCI.intersection(full)
      guard srcCI.width > 1, srcCI.height > 1 else { return }

      let ci = CIImage(cgImage: baseCg).cropped(to: srcCI)
      let ciCtx = CIContext(options: nil)
      guard let cropped = ciCtx.createCGImage(ci, from: srcCI) else { return }

      ctx.saveGState()
      ctx.addEllipse(in: lens)
      ctx.clip()
      ctx.interpolationQuality = .high
      ctx.draw(cropped, in: lens)
      ctx.restoreGState()

      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: NSColor.black.withAlphaComponent(0.25).cgColor)
      ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.20).cgColor)
      ctx.setLineWidth(max(2, overlay.width))
      ctx.strokeEllipse(in: lens)
      ctx.restoreGState()
    }
  }

  private func aspectFitRect(content: CGSize, into: CGRect) -> CGRect {
    guard content.width > 0, content.height > 0, into.width > 0, into.height > 0 else { return into }
    let sx = into.width / content.width
    let sy = into.height / content.height
    let s = min(sx, sy)
    let w = content.width * s
    let h = content.height * s
    return CGRect(x: into.midX - w / 2, y: into.midY - h / 2, width: w, height: h)
  }

  private func drawTextTopLeft(ctx: CGContext, text: String, x: CGFloat, y: CGFloat, h: CGFloat, fontName: String, fontSize: CGFloat, color: NSColor) {
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
    ]
    let astr = NSAttributedString(string: text, attributes: attrs)
    let line = CTLineCreateWithAttributedString(astr)
    _ = CTLineGetTypographicBounds(line, &ascent, &descent, nil)

    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    let baselineYUp = (h - y) - ascent
    ctx.textPosition = CGPoint(x: x, y: baselineYUp)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
  }

  private func drawOutlinedTextTopLeft(
    ctx: CGContext,
    text: String,
    x: CGFloat,
    y: CGFloat,
    h: CGFloat,
    fontName: String,
    fontSize: CGFloat,
    fill: NSColor,
    stroke: NSColor,
    strokeWidth: CGFloat
  ) {
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: fill,
      .strokeColor: stroke,
      .strokeWidth: -min(14, max(2, strokeWidth) * 2),
    ]
    let astr = NSAttributedString(string: text, attributes: attrs)
    let line = CTLineCreateWithAttributedString(astr)
    _ = CTLineGetTypographicBounds(line, &ascent, &descent, nil)

    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    let baselineYUp = (h - y) - ascent
    ctx.textPosition = CGPoint(x: x, y: baselineYUp)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
  }

  private func drawTextBoxTopLeft(
    ctx: CGContext,
    text: String,
    x: CGFloat,
    y: CGFloat,
    h: CGFloat,
    fontName: String,
    fontSize: CGFloat,
    textColor: NSColor,
    fillColor: NSColor,
    outlineColor: NSColor?,
    outlineWidth: CGFloat,
    padding: CGFloat,
    tail: Bool
  ) {
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: textColor,
    ]
    let astr = NSAttributedString(string: text, attributes: attrs)
    let line = CTLineCreateWithAttributedString(astr)
    let lineW = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
    let textH = ascent + descent

    let box = CGRect(x: x, y: y, width: lineW + padding * 2, height: textH + padding * 2)
    let radius: CGFloat = 12

    ctx.saveGState()
    ctx.setFillColor(fillColor.cgColor)
    let path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.fillPath()

    if tail {
      let tailH: CGFloat = 12
      ctx.beginPath()
      ctx.move(to: CGPoint(x: box.minX + 18, y: box.maxY))
      ctx.addLine(to: CGPoint(x: box.minX + 6, y: box.maxY + tailH))
      ctx.addLine(to: CGPoint(x: box.minX + 34, y: box.maxY))
      ctx.closePath()
      ctx.setFillColor(fillColor.cgColor)
      ctx.fillPath()
    }

    if let outlineColor, outlineWidth > 0 {
      ctx.setStrokeColor(outlineColor.cgColor)
      ctx.setLineWidth(outlineWidth)
      ctx.addPath(path)
      ctx.strokePath()
    }
    ctx.restoreGState()

    // Text (flip y for CoreText).
    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    let baselineYUp = (h - (box.minY + padding)) - ascent
    ctx.textPosition = CGPoint(x: box.minX + padding, y: baselineYUp)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
  }

  private func drawTextCentered(ctx: CGContext, text: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, fontName: String, fontSize: CGFloat, color: NSColor) {
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
    ]
    let astr = NSAttributedString(string: text, attributes: attrs)
    let line = CTLineCreateWithAttributedString(astr)
    let lineW = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
    _ = ascent + descent

    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    let originYDown = y
    let centerYUp = h - originYDown
    let baselineYUp = centerYUp - (ascent - descent) / 2
    ctx.textPosition = CGPoint(x: x - lineW / 2, y: baselineYUp)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
  }

  private func tintedSymbol(name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    let base = symbol.withSymbolConfiguration(cfg) ?? symbol
    let size = base.size
    let out = NSImage(size: size)
    out.lockFocus()
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()
    base.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0)
    color.setFill()
    let prev = NSGraphicsContext.current?.compositingOperation
    NSGraphicsContext.current?.compositingOperation = .sourceAtop
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    NSGraphicsContext.current?.compositingOperation = prev ?? .sourceOver
    out.unlockFocus()
    return out
  }

  private func crop(image: NSImage, normRect: CGRect) -> NSImage? {
    guard let rep = try? makeUprightBitmapRep(from: image), let cg = rep.cgImage else { return nil }
    let w = CGFloat(rep.pixelsWide)
    let h = CGFloat(rep.pixelsHigh)

    let rx = normRect.origin.x * w
    let ry = normRect.origin.y * h
    let rw = normRect.size.width * w
    let rh = normRect.size.height * h

    let regionYDown = CGRect(x: rx, y: ry, width: rw, height: rh).integral
    // CIImage coordinate space is y-up (origin bottom-left).
    let regionCI = CGRect(x: rx, y: h - (ry + rh), width: rw, height: rh).integral

    let ci = CIImage(cgImage: cg).cropped(to: regionCI)
    let ciCtx = CIContext(options: nil)
    guard let outCg = ciCtx.createCGImage(ci, from: regionCI) else { return nil }
    let sx = (w > 0) ? (image.size.width / w) : 1
    let sy = (h > 0) ? (image.size.height / h) : 1
    return NSImage(cgImage: outCg, size: NSSize(width: regionYDown.width * sx, height: regionYDown.height * sy))
  }

  private enum FilterKind {
    case blur
    case pixelate
  }

  private func filterRegion(image: NSImage, normRect: CGRect, kind: FilterKind, strength: CGFloat) -> NSImage? {
    guard let rep = try? makeUprightBitmapRep(from: image), let cg = rep.cgImage else { return nil }
    let w = CGFloat(rep.pixelsWide)
    let h = CGFloat(rep.pixelsHigh)

    let rx = normRect.origin.x * w
    let ry = normRect.origin.y * h
    let rw = normRect.size.width * w
    let rh = normRect.size.height * h
    let regionCI = CGRect(x: rx, y: h - (ry + rh), width: rw, height: rh).integral

    let ci = CIImage(cgImage: cg)
    let cropped = ci.cropped(to: regionCI)

    let filtered: CIImage
    switch kind {
    case .blur:
      let f = CIFilter(name: "CIGaussianBlur")
      f?.setValue(cropped, forKey: kCIInputImageKey)
      f?.setValue(strength, forKey: kCIInputRadiusKey)
      filtered = (f?.outputImage ?? cropped).cropped(to: regionCI)
    case .pixelate:
      let f = CIFilter(name: "CIPixellate")
      f?.setValue(cropped, forKey: kCIInputImageKey)
      f?.setValue(max(2, strength), forKey: kCIInputScaleKey)
      filtered = (f?.outputImage ?? cropped).cropped(to: regionCI)
    }

    let ciCtx = CIContext(options: nil)
    guard let filteredCg = ciCtx.createCGImage(filtered, from: regionCI) else { return nil }

    guard let ctx = makeTopLeftBitmapContext(width: Int(w), height: Int(h)) else {
      return nil
    }

    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    // The bitmap context is y-up (origin bottom-left). normRect is top-left, so the patch
    // must be drawn at the flipped y the region was cropped from (regionCI), not raw `ry`.
    let drawRect = CGRect(x: rx, y: h - (ry + rh), width: rw, height: rh).integral
    ctx.draw(filteredCg, in: drawRect)

    guard let outCg = ctx.makeImage() else { return nil }
    return NSImage(cgImage: outCg, size: image.size)
  }
}

private final class EditorRootView: NSView {
  weak var controller: EditorViewController?

  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    if controller?.handleKeyDown(event) == true {
      return
    }
    super.keyDown(with: event)
  }
}

private final class InkView: NSView {
  var getTool: (() -> EditorTool)?
  var getStroke: (() -> (NSColor, CGFloat))?
  var getImageRect: (() -> CGRect)?
  var onStrokeCommitted: ((InkStroke) -> Void)?

  private var strokes: [InkStroke] = []
  private var activePoints: [CGPoint] = [] // normalized

  override var isFlipped: Bool { true }

  func clearAll() {
    strokes.removeAll()
    activePoints.removeAll()
    needsDisplay = true
  }

  func snapshotStrokes() -> [InkStroke] { strokes }
  func setStrokes(_ items: [InkStroke]) {
    strokes = items
    activePoints.removeAll()
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let imgRect = getImageRect?() ?? .zero
    let (color, width) = getStroke?() ?? (.systemRed, 6)
    let ctx = NSGraphicsContext.current?.cgContext

    // Draw committed strokes.
    for s in strokes {
      let p = NSBezierPath()
      p.lineWidth = s.width
      p.lineCapStyle = .round
      p.lineJoinStyle = .round

      let first = denormPoint(s.points[0], imgRect: imgRect)
      p.move(to: first)
      for pt in s.points.dropFirst() {
        p.line(to: denormPoint(pt, imgRect: imgRect))
      }

      if s.mode == .erase {
        ctx?.saveGState()
        ctx?.setBlendMode(.clear)
        NSColor.white.setStroke()
        p.stroke()
        ctx?.restoreGState()
      } else {
        s.color.withAlphaComponent(s.alpha).setStroke()
        p.stroke()
      }

      if s.mode == .draw, s.arrowHead, s.points.count >= 2 {
        drawArrowHead(
          from: denormPoint(s.points[s.points.count - 2], imgRect: imgRect),
          to: denormPoint(s.points[s.points.count - 1], imgRect: imgRect),
          color: s.color.withAlphaComponent(s.alpha),
          width: s.width
        )
      }
    }

    // Draw active stroke.
    let tool = getTool?() ?? .pointer
    if (tool == .pen || tool == .freehandArrow || tool == .highlighter || tool == .eraser) && activePoints.count >= 2 {
      let alpha: CGFloat = (tool == .highlighter) ? 0.35 : 1.0
      let finalWidth: CGFloat
      if tool == .highlighter {
        finalWidth = max(width, 10)
      } else if tool == .eraser {
        finalWidth = max(width, 18)
      } else {
        finalWidth = width
      }

      let p = NSBezierPath()
      p.lineWidth = finalWidth
      p.lineCapStyle = .round
      p.lineJoinStyle = .round

      let first = denormPoint(activePoints[0], imgRect: imgRect)
      p.move(to: first)
      for pt in activePoints.dropFirst() {
        p.line(to: denormPoint(pt, imgRect: imgRect))
      }

      if tool == .eraser {
        ctx?.saveGState()
        ctx?.setBlendMode(.clear)
        NSColor.white.setStroke()
        p.stroke()
        ctx?.restoreGState()
      } else {
        color.withAlphaComponent(alpha).setStroke()
        p.stroke()
      }

      if tool == .freehandArrow {
        let pts = activePoints
        if pts.count >= 2 {
          drawArrowHead(
            from: denormPoint(pts[pts.count - 2], imgRect: imgRect),
            to: denormPoint(pts[pts.count - 1], imgRect: imgRect),
            color: color.withAlphaComponent(alpha),
            width: finalWidth
          )
        }
      }
    }
  }

  override func mouseDown(with event: NSEvent) {
    let tool = getTool?() ?? .pointer
    if tool != .pen && tool != .freehandArrow && tool != .highlighter && tool != .eraser { return }

    let p = convert(event.locationInWindow, from: nil)
    let imgRect = getImageRect?() ?? .zero
    if !imgRect.contains(p) { return }

    activePoints = [normPoint(p, imgRect: imgRect)]
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    let tool = getTool?() ?? .pointer
    if tool != .pen && tool != .freehandArrow && tool != .highlighter && tool != .eraser { return }

    guard !activePoints.isEmpty else { return }

    let p = convert(event.locationInWindow, from: nil)
    let imgRect = getImageRect?() ?? .zero
    if !imgRect.contains(p) { return }

    activePoints.append(normPoint(p, imgRect: imgRect))
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    let tool = getTool?() ?? .pointer
    if tool != .pen && tool != .freehandArrow && tool != .highlighter && tool != .eraser { return }

    guard activePoints.count >= 2 else {
      activePoints.removeAll()
      needsDisplay = true
      return
    }

    let (color, width) = getStroke?() ?? (.systemRed, 6)
    let alpha: CGFloat = (tool == .highlighter) ? 0.35 : 1.0
    let finalWidth: CGFloat
    if tool == .highlighter {
      finalWidth = max(width, 10)
    } else if tool == .eraser {
      finalWidth = max(width, 18)
    } else {
      finalWidth = width
    }

    let mode: InkMode = (tool == .eraser) ? .erase : .draw
    let stroke = InkStroke(
      points: activePoints,
      color: color,
      width: finalWidth,
      alpha: alpha,
      mode: mode,
      arrowHead: (tool == .freehandArrow)
    )
    onStrokeCommitted?(stroke)
    strokes.append(stroke)

    activePoints.removeAll()
    needsDisplay = true
  }

  private func normPoint(_ p: CGPoint, imgRect: CGRect) -> CGPoint {
    if imgRect.width <= 0 || imgRect.height <= 0 { return .zero }
    let x = (p.x - imgRect.origin.x) / imgRect.width
    let y = (p.y - imgRect.origin.y) / imgRect.height
    return CGPoint(x: clamp01(x), y: clamp01(y))
  }

  private func denormPoint(_ p: CGPoint, imgRect: CGRect) -> CGPoint {
    CGPoint(x: imgRect.origin.x + p.x * imgRect.width, y: imgRect.origin.y + p.y * imgRect.height)
  }

  private func clamp01(_ v: CGFloat) -> CGFloat {
    min(1, max(0, v))
  }

  private func drawArrowHead(from a: CGPoint, to b: CGPoint, color: NSColor, width: CGFloat) {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let len = max(1, hypot(dx, dy))
    let ux = dx / len
    let uy = dy / len
    let headLen = max(10, width * 2.5)
    let angle: CGFloat = .pi / 7

    func rot(_ x: CGFloat, _ y: CGFloat, _ a: CGFloat) -> (CGFloat, CGFloat) {
      (x * cos(a) - y * sin(a), x * sin(a) + y * cos(a))
    }

    let (lx, ly) = rot(-ux, -uy, angle)
    let (rx, ry) = rot(-ux, -uy, -angle)

    let p = NSBezierPath()
    p.lineWidth = max(1, width)
    p.lineCapStyle = .round
    p.move(to: b)
    p.line(to: CGPoint(x: b.x + lx * headLen, y: b.y + ly * headLen))
    p.move(to: b)
    p.line(to: CGPoint(x: b.x + rx * headLen, y: b.y + ry * headLen))
    color.setStroke()
    p.stroke()
  }
}

private final class OverlayView: NSView {
  var getTool: (() -> EditorTool)?
  var getStroke: (() -> (NSColor, CGFloat, CGFloat))?
  var getFilterStrength: (() -> CGFloat)?
  var getImageRect: (() -> CGRect)?
  var getBaseImage: (() -> NSImage?)?
  var getInkStrokes: (() -> [InkStroke])?
  var setInkStrokes: (([InkStroke]) -> Void)?
  var resolveStickerText: (() -> String?)?

  var addOverlay: ((OverlayItem) -> Void)?
  var commitDestructive: ((DestructiveOp) -> Void)?
  var commitTransform: ((TransformOp) -> Void)?
  var onStep: ((CGPoint) -> Void)? // normalized center point
  var onOverlaysChanged: (([OverlayItem], Int?) -> Void)?
  var requestUndoCheckpoint: (() -> Void)?

  private var overlays: [OverlayItem] = []
  private var selectedIndex: Int? = nil
  private var movingIndex: Int? = nil
  private var lastMovePoint: CGPoint? = nil
  private var didRequestMoveUndo: Bool = false

  private var dragStart: CGPoint? = nil
  private var dragCurrent: CGPoint? = nil

  private var textField: NSTextField? = nil
  private var textAnchor: CGPoint? = nil
  private var textKind: OverlayKind? = nil

  private var smartErasing: Bool = false
  private var didRequestSmartEraserUndo: Bool = false

  override var isFlipped: Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // Let InkView receive mouse events for ink tools.
    let tool = getTool?() ?? .pointer
    if tool == .pen || tool == .freehandArrow || tool == .highlighter || tool == .eraser {
      return nil
    }
    return super.hitTest(point)
  }

  func setOverlays(_ items: [OverlayItem], selectedIndex: Int? = nil) {
    overlays = items
    if let selectedIndex, selectedIndex >= 0, selectedIndex < overlays.count {
      self.selectedIndex = selectedIndex
    } else if let sel = self.selectedIndex, sel >= overlays.count {
      self.selectedIndex = nil
    }
    needsDisplay = true
  }

  func clearSelection() {
    selectedIndex = nil
    needsDisplay = true
  }

  func hasSelection() -> Bool {
    selectedIndex != nil
  }

  func deleteSelectedOverlay() -> Bool {
    guard let idx = selectedIndex, idx >= 0, idx < overlays.count else { return false }
    overlays.remove(at: idx)
    selectedIndex = nil
    onOverlaysChanged?(overlays, selectedIndex)
    needsDisplay = true
    return true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    NSColor.clear.setFill()
    dirtyRect.fill()

    let imgRect = getImageRect?() ?? .zero

    for o in overlays {
      drawOverlay(o, imgRect: imgRect)
    }

    if let idx = selectedIndex, idx >= 0, idx < overlays.count {
      let o = overlays[idx]
      if let r = overlayBounds(o, imgRect: imgRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        let p = NSBezierPath(rect: r.insetBy(dx: -4, dy: -4))
        p.setLineDash([4, 3], count: 2, phase: 0)
        p.lineWidth = 1.5
        p.stroke()
      }
    }

    if let s = dragStart, let c = dragCurrent {
      let tool = getTool?() ?? .pointer
      let (color, width, _) = getStroke?() ?? (.systemRed, 6, 28)

      switch tool {
      case .line, .arrow, .rect, .filledRect, .ellipse, .highlightRect, .blur, .pixelate, .blackRedact, .crop, .magnify, .imageFile, .imageScreen:
        let r = rectBetween(s, c)
        if tool == .line || tool == .arrow {
          let p = NSBezierPath()
          p.move(to: s)
          p.line(to: c)
          color.setStroke()
          p.lineWidth = width
          p.stroke()
        } else {
          let stroke: NSColor
          if tool == .crop {
            stroke = NSColor.systemBlue
          } else if tool == .magnify {
            stroke = NSColor.systemPurple
          } else if tool == .imageFile || tool == .imageScreen {
            stroke = NSColor.systemTeal
          } else if tool == .blackRedact {
            stroke = NSColor.black
          } else {
            stroke = color.withAlphaComponent(0.6)
          }
          stroke.setStroke()
          let p = NSBezierPath(rect: r)
          p.lineWidth = 2
          p.stroke()
        }
      default:
        break
      }
    }
  }

  override func mouseDown(with event: NSEvent) {
    guard textField == nil else { return }

    let tool = getTool?() ?? .pointer
    let p = convert(event.locationInWindow, from: nil)
    if !(getImageRect?() ?? .zero).contains(p) {
      if tool == .pointer {
        selectedIndex = nil
        onOverlaysChanged?(overlays, selectedIndex)
        needsDisplay = true
      }
      return
    }

    if tool == .pointer {
      selectedIndex = hitTestOverlays(at: p, imgRect: getImageRect?() ?? .zero)
      movingIndex = selectedIndex
      lastMovePoint = p
      didRequestMoveUndo = false
      onOverlaysChanged?(overlays, selectedIndex)
      needsDisplay = true
      return
    }

    if tool == .step {
      let imgRect = getImageRect?() ?? .zero
      onStep?(normPoint(p, imgRect: imgRect))
      return
    }

    if tool == .pen || tool == .freehandArrow || tool == .highlighter || tool == .eraser {
      return
    }

    if tool == .smartEraser {
      smartErasing = true
      didRequestSmartEraserUndo = false
      smartErase(at: p)
      return
    }

    if tool == .sticker {
      placeSticker(at: p)
      return
    }

    if tool == .cursor {
      placeCursor(at: p)
      return
    }

    if tool == .text || tool == .textOutline || tool == .textBackground || tool == .speechBalloon {
      startText(at: p, kind: tool)
      return
    }

    dragStart = p
    dragCurrent = p
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    let tool = getTool?() ?? .pointer
    if tool == .pointer {
      guard let idx = movingIndex,
            idx >= 0, idx < overlays.count,
            let last = lastMovePoint else {
        return
      }
      let now = convert(event.locationInWindow, from: nil)
      let imgRect = getImageRect?() ?? .zero
      if imgRect.width <= 0 || imgRect.height <= 0 { return }

      let dx = (now.x - last.x) / imgRect.width
      let dy = (now.y - last.y) / imgRect.height

      if !didRequestMoveUndo, hypot(dx, dy) > 0.001 {
        didRequestMoveUndo = true
        requestUndoCheckpoint?()
      }

      overlays[idx].a = CGPoint(x: clamp01(overlays[idx].a.x + dx), y: clamp01(overlays[idx].a.y + dy))
      overlays[idx].b = CGPoint(x: clamp01(overlays[idx].b.x + dx), y: clamp01(overlays[idx].b.y + dy))
      lastMovePoint = now

      onOverlaysChanged?(overlays, selectedIndex)
      needsDisplay = true
      return
    }

    if smartErasing, tool == .smartEraser {
      smartErase(at: convert(event.locationInWindow, from: nil))
      return
    }

    if tool == .pen || tool == .freehandArrow || tool == .highlighter || tool == .eraser
      || tool == .text || tool == .textOutline || tool == .textBackground || tool == .speechBalloon
      || tool == .step || tool == .sticker || tool == .cursor || tool == .smartEraser {
      return
    }

    guard dragStart != nil else { return }
    dragCurrent = convert(event.locationInWindow, from: nil)
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    let tool = getTool?() ?? .pointer
    if tool == .smartEraser {
      smartErase(at: convert(event.locationInWindow, from: nil))
      smartErasing = false
      didRequestSmartEraserUndo = false
      return
    }
    if tool == .pointer {
      movingIndex = nil
      lastMovePoint = nil
      didRequestMoveUndo = false
      return
    }

    if tool == .pen || tool == .freehandArrow || tool == .highlighter || tool == .eraser
      || tool == .text || tool == .textOutline || tool == .textBackground || tool == .speechBalloon
      || tool == .step || tool == .sticker || tool == .cursor {
      return
    }

    guard let s = dragStart else { return }
    let c = convert(event.locationInWindow, from: nil)

    defer {
      dragStart = nil
      dragCurrent = nil
      needsDisplay = true
    }

    let imgRect = getImageRect?() ?? .zero
    var rView = rectBetween(s, c)
    if rView.width < 5 || rView.height < 5 {
      rView = CGRect(x: s.x - 160, y: s.y - 120, width: 320, height: 240)
    }
    let ns = normPoint(CGPoint(x: rView.minX, y: rView.minY), imgRect: imgRect)
    let nc = normPoint(CGPoint(x: rView.maxX, y: rView.maxY), imgRect: imgRect)

    let (color, width, fontSize) = getStroke?() ?? (.systemRed, 6, 28)

    switch tool {
    case .line:
      addOverlay?(OverlayItem(kind: .line, a: ns, b: nc, color: color, width: width, text: nil, fontSize: fontSize))
    case .arrow:
      addOverlay?(OverlayItem(kind: .arrow, a: ns, b: nc, color: color, width: width, text: nil, fontSize: fontSize))
    case .rect:
      addOverlay?(OverlayItem(kind: .rect, a: ns, b: nc, color: color, width: width, text: nil, fontSize: fontSize))
    case .filledRect:
      addOverlay?(OverlayItem(kind: .filledRect, a: ns, b: nc, color: color, width: 0, text: nil, fontSize: fontSize))
    case .ellipse:
      addOverlay?(OverlayItem(kind: .ellipse, a: ns, b: nc, color: color, width: width, text: nil, fontSize: fontSize))
    case .highlightRect:
      addOverlay?(OverlayItem(kind: .highlightRect, a: ns, b: nc, color: .systemYellow, width: 2, text: nil, fontSize: fontSize))
    case .blur:
      commitDestructive?(.blur(normRectBetween(ns, nc)))
    case .pixelate:
      commitDestructive?(.pixelate(normRectBetween(ns, nc)))
    case .blackRedact:
      commitDestructive?(.blackRedact(normRectBetween(ns, nc)))
    case .crop:
      commitDestructive?(.crop(normRectBetween(ns, nc)))
    case .magnify:
      let raw = getFilterStrength?() ?? 14
      let zoom = max(1.2, raw / 10.0)
      addOverlay?(OverlayItem(kind: .magnify, a: ns, b: nc, color: .white, width: 2, text: nil, fontSize: fontSize, magnifyZoom: zoom))
    case .imageFile:
      insertImageFromFile(a: ns, b: nc)
    case .imageScreen:
      insertImageFromScreen(a: ns, b: nc)
    default:
      break
    }
  }

  private func startText(at p: CGPoint, kind: EditorTool) {
    let (color, _, fontSize) = getStroke?() ?? (.systemRed, 6, 28)

    let tf = NSTextField(string: "")
    tf.placeholderString = "Text"
    tf.frame = NSRect(x: p.x, y: p.y, width: 260, height: 26)
    tf.font = NSFont.systemFont(ofSize: fontSize)
    if kind == .textBackground || kind == .speechBalloon {
      tf.textColor = contrastingTextColor(background: color.withAlphaComponent(0.75))
    } else {
      tf.textColor = color
    }

    addSubview(tf)
    window?.makeFirstResponder(tf)

    textField = tf
    textAnchor = p
    switch kind {
    case .text: textKind = .text
    case .textOutline: textKind = .textOutline
    case .textBackground: textKind = .textBackground
    case .speechBalloon: textKind = .speechBalloon
    default: textKind = .text
    }

    tf.target = self
    tf.action = #selector(finishText)
  }

  @objc private func finishText() {
    guard let tf = textField, let anchor = textAnchor else { return }
    let txt = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

    defer {
      tf.removeFromSuperview()
      textField = nil
      textAnchor = nil
      textKind = nil
      needsDisplay = true
    }

    if txt.isEmpty {
      return
    }

    let imgRect = getImageRect?() ?? .zero
    let np = normPoint(anchor, imgRect: imgRect)
    let (color, width, fontSize) = getStroke?() ?? (.systemRed, 6, 28)

    let kind = textKind ?? .text
    switch kind {
    case .text:
      addOverlay?(OverlayItem(kind: .text, a: np, b: np, color: color, width: width, text: txt, fontSize: fontSize))
    case .textOutline:
      let outline = contrastingTextColor(background: color).withAlphaComponent(0.95)
      addOverlay?(OverlayItem(
        kind: .textOutline,
        a: np,
        b: np,
        color: color,
        width: width,
        text: txt,
        fontSize: fontSize,
        fillColor: nil,
        outlineColor: outline,
        outlineWidth: max(2, width * 0.6),
        padding: 0
      ))
    case .textBackground:
      let fill = color.withAlphaComponent(0.75)
      let textColor = contrastingTextColor(background: fill)
      addOverlay?(OverlayItem(
        kind: .textBackground,
        a: np,
        b: np,
        color: textColor,
        width: width,
        text: txt,
        fontSize: fontSize,
        fillColor: fill,
        outlineColor: nil,
        outlineWidth: 0,
        padding: 10
      ))
    case .speechBalloon:
      let fill = color.withAlphaComponent(0.75)
      let textColor = contrastingTextColor(background: fill)
      addOverlay?(OverlayItem(
        kind: .speechBalloon,
        a: np,
        b: np,
        color: textColor,
        width: width,
        text: txt,
        fontSize: fontSize,
        fillColor: fill,
        outlineColor: color.withAlphaComponent(0.95),
        outlineWidth: max(2, width * 0.4),
        padding: 12
      ))
    default:
      addOverlay?(OverlayItem(kind: .text, a: np, b: np, color: color, width: width, text: txt, fontSize: fontSize))
    }
  }

  private func drawOverlay(_ o: OverlayItem, imgRect: CGRect) {
    let a = denormPoint(o.a, imgRect: imgRect)
    let b = denormPoint(o.b, imgRect: imgRect)

    o.color.setStroke()

    switch o.kind {
    case .line:
      let p = NSBezierPath()
      p.move(to: a)
      p.line(to: b)
      p.lineWidth = o.width
      p.stroke()

    case .arrow:
      let p = NSBezierPath()
      p.move(to: a)
      p.line(to: b)
      p.lineWidth = o.width
      p.stroke()

    case .rect:
      let r = rectBetween(a, b)
      let p = NSBezierPath(rect: r)
      p.lineWidth = o.width
      p.stroke()

    case .filledRect:
      let r = rectBetween(a, b)
      o.color.setFill()
      NSBezierPath(rect: r).fill()

    case .ellipse:
      let r = rectBetween(a, b)
      let p = NSBezierPath(ovalIn: r)
      p.lineWidth = o.width
      p.stroke()

    case .step:
      let r = rectBetween(a, b)
      o.color.setFill()
      NSBezierPath(ovalIn: r).fill()

      let outline = NSBezierPath(ovalIn: r)
      NSColor.black.withAlphaComponent(0.15).setStroke()
      outline.lineWidth = max(2, o.width)
      outline.stroke()

      guard let t = o.text else { return }
      let drawFont = NSFont.boldSystemFont(ofSize: max(12, min(o.fontSize, r.height * 0.6)))
      let attrs: [NSAttributedString.Key: Any] = [
        .font: drawFont,
        .foregroundColor: NSColor.white,
      ]
      let size = (t as NSString).size(withAttributes: attrs)
      let pos = CGPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2)
      (t as NSString).draw(at: pos, withAttributes: attrs)

    case .highlightRect:
      let r = rectBetween(a, b)
      o.color.withAlphaComponent(0.25).setFill()
      NSBezierPath(rect: r).fill()
      o.color.withAlphaComponent(0.6).setStroke()
      let p = NSBezierPath(rect: r)
      p.lineWidth = 2
      p.stroke()

    case .text:
      guard let t = o.text else { return }
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: o.fontSize),
        .foregroundColor: o.color,
      ]
      (t as NSString).draw(at: a, withAttributes: attrs)

    case .textOutline:
      guard let t = o.text else { return }
      let outline = o.outlineColor ?? NSColor.black
      let strokeW = max(2, o.outlineWidth)
      // strokeWidth is treated as a percent of font size by NSAttributedString.
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: o.fontSize, weight: .semibold),
        .foregroundColor: o.color,
        .strokeColor: outline,
        .strokeWidth: -min(12, strokeW * 2),
      ]
      (t as NSString).draw(at: a, withAttributes: attrs)

    case .textBackground:
      guard let t = o.text else { return }
      let pad = max(6, o.padding)
      let font = NSFont.systemFont(ofSize: o.fontSize, weight: .semibold)
      let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: o.color,
      ]
      let size = (t as NSString).size(withAttributes: attrs)
      let box = CGRect(x: a.x, y: a.y, width: size.width + pad * 2, height: size.height + pad * 2)
      (o.fillColor ?? NSColor.black.withAlphaComponent(0.70)).setFill()
      NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
      (t as NSString).draw(at: CGPoint(x: box.minX + pad, y: box.minY + pad), withAttributes: attrs)

    case .speechBalloon:
      guard let t = o.text else { return }
      let pad = max(8, o.padding)
      let font = NSFont.systemFont(ofSize: o.fontSize, weight: .semibold)
      let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: o.color,
      ]
      let size = (t as NSString).size(withAttributes: attrs)
      let box = CGRect(x: a.x, y: a.y, width: size.width + pad * 2, height: size.height + pad * 2)

      let fill = (o.fillColor ?? NSColor.black.withAlphaComponent(0.70))
      fill.setFill()
      let bubble = NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12)
      bubble.fill()

      // Auto tail at bottom-left.
      let tailH: CGFloat = 12
      let tail = NSBezierPath()
      tail.move(to: CGPoint(x: box.minX + 18, y: box.maxY))
      tail.line(to: CGPoint(x: box.minX + 6, y: box.maxY + tailH))
      tail.line(to: CGPoint(x: box.minX + 34, y: box.maxY))
      tail.close()
      tail.fill()

      if let outline = o.outlineColor {
        outline.setStroke()
        bubble.lineWidth = max(2, o.outlineWidth)
        bubble.stroke()
      }

      (t as NSString).draw(at: CGPoint(x: box.minX + pad, y: box.minY + pad), withAttributes: attrs)

    case .sticker:
      guard let t = o.text else { return }
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: o.fontSize),
        .foregroundColor: o.color,
      ]
      let size = (t as NSString).size(withAttributes: attrs)
      let origin = CGPoint(x: a.x - size.width / 2, y: a.y - size.height / 2)
      (t as NSString).draw(at: origin, withAttributes: attrs)

    case .cursor:
      let sizePx = max(18, o.fontSize)
      let r = CGRect(x: a.x, y: a.y, width: sizePx, height: sizePx)
      if let img = tintedSymbol(name: "cursorarrow", pointSize: sizePx, color: o.color) {
        img.draw(in: r, from: .zero, operation: .sourceOver, fraction: max(0, min(1, o.imageAlpha)))
      } else if let fallback = NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: "Cursor") {
        fallback.draw(in: r)
      }

    case .image:
      guard let img = o.image else { return }
      let r = rectBetween(a, b)
      let fit = aspectFitRect(content: img.size, into: r.insetBy(dx: 2, dy: 2))
      img.draw(in: fit, from: .zero, operation: .sourceOver, fraction: max(0, min(1, o.imageAlpha)))

    case .magnify:
      let lens = rectBetween(a, b)
      let zoom = max(1.2, o.magnifyZoom)
      guard let base = getBaseImage?() else {
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(ovalIn: lens).fill()
        NSColor.white.setStroke()
        NSBezierPath(ovalIn: lens).stroke()
        return
      }

      let source = CGRect(
        x: (lens.midX - lens.width / (2 * zoom)),
        y: (lens.midY - lens.height / (2 * zoom)),
        width: lens.width / zoom,
        height: lens.height / zoom
      )

      let clip = NSBezierPath(ovalIn: lens)
      NSGraphicsContext.current?.cgContext.saveGState()
      clip.addClip()
      base.draw(in: lens, from: source, operation: .copy, fraction: 1.0)
      NSGraphicsContext.current?.cgContext.restoreGState()

      NSColor.black.withAlphaComponent(0.20).setStroke()
      let border = NSBezierPath(ovalIn: lens)
      border.lineWidth = max(2, o.width)
      border.stroke()
    }
  }

  private func overlayBounds(_ o: OverlayItem, imgRect: CGRect) -> CGRect? {
    let a = denormPoint(o.a, imgRect: imgRect)
    let b = denormPoint(o.b, imgRect: imgRect)
    switch o.kind {
    case .line, .arrow:
      let x = min(a.x, b.x)
      let y = min(a.y, b.y)
      let w = abs(a.x - b.x)
      let h = abs(a.y - b.y)
      return CGRect(x: x, y: y, width: w, height: h).insetBy(dx: -max(6, o.width), dy: -max(6, o.width))
    case .rect, .filledRect, .ellipse, .highlightRect, .step, .image, .magnify:
      return rectBetween(a, b)
    case .text, .textOutline:
      guard let t = o.text else { return nil }
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: o.fontSize),
      ]
      let size = (t as NSString).size(withAttributes: attrs)
      return CGRect(x: a.x, y: a.y, width: size.width, height: size.height)
    case .textBackground, .speechBalloon:
      guard let t = o.text else { return nil }
      let pad = max(6, o.padding)
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: o.fontSize, weight: .semibold),
      ]
      let size = (t as NSString).size(withAttributes: attrs)
      // + tail allowance for balloon.
      let tailH: CGFloat = (o.kind == .speechBalloon) ? 14 : 0
      return CGRect(x: a.x, y: a.y, width: size.width + pad * 2, height: size.height + pad * 2 + tailH)
    case .sticker:
      guard let t = o.text else { return nil }
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: o.fontSize),
      ]
      let size = (t as NSString).size(withAttributes: attrs)
      return CGRect(x: a.x - size.width / 2, y: a.y - size.height / 2, width: size.width, height: size.height)
    case .cursor:
      let sizePx = max(18, o.fontSize)
      return CGRect(x: a.x, y: a.y, width: sizePx, height: sizePx)
    }
  }

  private func hitTestOverlays(at p: CGPoint, imgRect: CGRect) -> Int? {
    if overlays.isEmpty { return nil }

    // Prefer "topmost" overlay.
    for i in overlays.indices.reversed() {
      let o = overlays[i]
      switch o.kind {
      case .line, .arrow:
        let a = denormPoint(o.a, imgRect: imgRect)
        let b = denormPoint(o.b, imgRect: imgRect)
        let dist = distancePointToSegment(p, a, b)
        if dist <= max(6, o.width + 2) {
          return i
        }
      default:
        if let r = overlayBounds(o, imgRect: imgRect)?.insetBy(dx: -4, dy: -4), r.contains(p) {
          return i
        }
      }
    }
    return nil
  }

  private func distancePointToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let abx = b.x - a.x
    let aby = b.y - a.y
    let apx = p.x - a.x
    let apy = p.y - a.y
    let abLen2 = abx * abx + aby * aby
    if abLen2 <= 0.0001 {
      return hypot(apx, apy)
    }
    var t = (apx * abx + apy * aby) / abLen2
    t = min(1, max(0, t))
    let cx = a.x + t * abx
    let cy = a.y + t * aby
    return hypot(p.x - cx, p.y - cy)
  }

  private func rectBetween(_ a: CGPoint, _ b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
  }

  private func normRectBetween(_ a: CGPoint, _ b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
  }

  private func normPoint(_ p: CGPoint, imgRect: CGRect) -> CGPoint {
    if imgRect.width <= 0 || imgRect.height <= 0 { return .zero }
    let x = (p.x - imgRect.origin.x) / imgRect.width
    let y = (p.y - imgRect.origin.y) / imgRect.height
    return CGPoint(x: clamp01(x), y: clamp01(y))
  }

  private func denormPoint(_ p: CGPoint, imgRect: CGRect) -> CGPoint {
    CGPoint(x: imgRect.origin.x + p.x * imgRect.width, y: imgRect.origin.y + p.y * imgRect.height)
  }

  private func clamp01(_ v: CGFloat) -> CGFloat {
    min(1, max(0, v))
  }

  private func aspectFitRect(content: NSSize, into: CGRect) -> CGRect {
    guard content.width > 0, content.height > 0, into.width > 0, into.height > 0 else { return into }
    let sx = into.width / content.width
    let sy = into.height / content.height
    let s = min(sx, sy)
    let w = content.width * s
    let h = content.height * s
    return CGRect(x: into.midX - w / 2, y: into.midY - h / 2, width: w, height: h)
  }

  private func contrastingTextColor(background: NSColor) -> NSColor {
    let c = background.usingColorSpace(.sRGB) ?? background
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    c.getRed(&r, green: &g, blue: &b, alpha: &a)
    // Relative luminance.
    let y = (0.2126 * r + 0.7152 * g + 0.0722 * b)
    return (y > 0.55) ? NSColor.black : NSColor.white
  }

  private func placeSticker(at p: CGPoint) {
    guard let imgRect = getImageRect?(), imgRect.contains(p) else { return }
    guard let txt = resolveStickerText?(), !txt.isEmpty else { return }
    let (color, _, fontSize) = getStroke?() ?? (.systemRed, 6, 28)
    let np = normPoint(p, imgRect: imgRect)
    addOverlay?(OverlayItem(kind: .sticker, a: np, b: np, color: color, width: 0, text: txt, fontSize: fontSize))
  }

  private func placeCursor(at p: CGPoint) {
    guard let imgRect = getImageRect?(), imgRect.contains(p) else { return }
    let (color, width, fontSize) = getStroke?() ?? (.systemRed, 6, 28)
    let np = normPoint(p, imgRect: imgRect)
    let sizePx = max(18, fontSize)
    addOverlay?(OverlayItem(kind: .cursor, a: np, b: np, color: color, width: width, text: nil, fontSize: sizePx, image: nil, imageAlpha: 1.0))
  }

  private func insertImageFromFile(a: CGPoint, b: CGPoint) {
    let panel = NSOpenPanel()
    panel.title = "Choose Image"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [UTType.image]

    let commit: (URL) -> Void = { [weak self] url in
      guard let self else { return }
      guard let img = NSImage(contentsOf: url) else {
        Notifier.shared.notify(title: "CraftyCannon", body: "Failed to load image")
        return
      }
      self.addOverlay?(OverlayItem(kind: .image, a: a, b: b, color: .white, width: 0, text: nil, fontSize: 0, image: img, imageAlpha: 1.0))
    }

    if let win = window {
      panel.beginSheetModal(for: win) { resp in
        guard resp == .OK, let url = panel.url else { return }
        commit(url)
      }
    } else {
      panel.begin { resp in
        guard resp == .OK, let url = panel.url else { return }
        commit(url)
      }
    }
  }

  private func insertImageFromScreen(a: CGPoint, b: CGPoint) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        let url = try Screenshotter.shared.capture(mode: .region)
        guard let img = NSImage(contentsOf: url) else {
          DispatchQueue.main.async {
            Notifier.shared.notify(title: "CraftyCannon", body: "Failed to load captured image")
          }
          return
        }
        DispatchQueue.main.async {
          self?.addOverlay?(OverlayItem(kind: .image, a: a, b: b, color: .white, width: 0, text: nil, fontSize: 0, image: img, imageAlpha: 1.0))
        }
      } catch ScreenshotError.screenRecordingPermissionDenied {
        DispatchQueue.main.async {
          Notifier.shared.notify(title: "CraftyCannon", body: "Screen recording permission required for screen capture")
        }
      } catch ScreenshotError.cancelled {
        // no-op
      } catch {
        DispatchQueue.main.async {
          Notifier.shared.notify(title: "CraftyCannon", body: "Screen capture failed")
        }
      }
    }
  }

  private func smartErase(at p: CGPoint) {
    guard let imgRect = getImageRect?(), imgRect.contains(p) else { return }
    let (_, width, _) = getStroke?() ?? (.systemRed, 6, 28)
    let radius = max(12, width * 2.4)

    if !didRequestSmartEraserUndo {
      didRequestSmartEraserUndo = true
      requestUndoCheckpoint?()
    }

    // Overlays: delete any overlay whose bounds intersects the brush circle.
    let center = p
    let beforeCount = overlays.count
    overlays.removeAll { o in
      guard let r = overlayBounds(o, imgRect: imgRect) else { return false }
      return circleIntersectsRect(center: center, radius: radius, rect: r.insetBy(dx: -2, dy: -2))
    }
    if overlays.count != beforeCount {
      selectedIndex = nil
      onOverlaysChanged?(overlays, selectedIndex)
    }

    // Ink strokes: remove strokes that intersect the brush circle.
    if let getInkStrokes, let setInkStrokes {
      let strokes = getInkStrokes()
      let kept = strokes.filter { stroke in
        guard stroke.points.count >= 2 else { return true }
        // Intersect test in view coordinates for consistent radius.
        var last = denormPoint(stroke.points[0], imgRect: imgRect)
        for pt in stroke.points.dropFirst() {
          let now = denormPoint(pt, imgRect: imgRect)
          if distancePointToSegment(center, last, now) <= radius {
            return false
          }
          last = now
        }
        return true
      }
      if kept.count != strokes.count {
        setInkStrokes(kept)
      }
    }

    needsDisplay = true
  }

  private func circleIntersectsRect(center: CGPoint, radius: CGFloat, rect: CGRect) -> Bool {
    let cx = max(rect.minX, min(center.x, rect.maxX))
    let cy = max(rect.minY, min(center.y, rect.maxY))
    return hypot(center.x - cx, center.y - cy) <= radius
  }

  private func tintedSymbol(name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    let base = symbol.withSymbolConfiguration(cfg) ?? symbol
    let size = base.size
    let out = NSImage(size: size)
    out.lockFocus()
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()
    base.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0)
    color.setFill()
    let prev = NSGraphicsContext.current?.compositingOperation
    NSGraphicsContext.current?.compositingOperation = .sourceAtop
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    NSGraphicsContext.current?.compositingOperation = prev ?? .sourceOver
    out.unlockFocus()
    return out
  }
}
