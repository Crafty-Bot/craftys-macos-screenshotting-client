import Carbon
import Foundation

final class HotKeyManager {
  private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
  private var handler: EventHandlerRef?

  enum Action: UInt32 {
    case captureRegionUpload = 1
    case uploadClipboard = 2
    case captureRegionUploadExpiring = 3
    case captureRegionUploadFrozen = 4
  }

  private static let keyCodeByKey: [String: UInt32] = [
    "A": UInt32(kVK_ANSI_A),
    "B": UInt32(kVK_ANSI_B),
    "C": UInt32(kVK_ANSI_C),
    "D": UInt32(kVK_ANSI_D),
    "E": UInt32(kVK_ANSI_E),
    "F": UInt32(kVK_ANSI_F),
    "G": UInt32(kVK_ANSI_G),
    "H": UInt32(kVK_ANSI_H),
    "I": UInt32(kVK_ANSI_I),
    "J": UInt32(kVK_ANSI_J),
    "K": UInt32(kVK_ANSI_K),
    "L": UInt32(kVK_ANSI_L),
    "M": UInt32(kVK_ANSI_M),
    "N": UInt32(kVK_ANSI_N),
    "O": UInt32(kVK_ANSI_O),
    "P": UInt32(kVK_ANSI_P),
    "Q": UInt32(kVK_ANSI_Q),
    "R": UInt32(kVK_ANSI_R),
    "S": UInt32(kVK_ANSI_S),
    "T": UInt32(kVK_ANSI_T),
    "U": UInt32(kVK_ANSI_U),
    "V": UInt32(kVK_ANSI_V),
    "W": UInt32(kVK_ANSI_W),
    "X": UInt32(kVK_ANSI_X),
    "Y": UInt32(kVK_ANSI_Y),
    "Z": UInt32(kVK_ANSI_Z),
    "0": UInt32(kVK_ANSI_0),
    "1": UInt32(kVK_ANSI_1),
    "2": UInt32(kVK_ANSI_2),
    "3": UInt32(kVK_ANSI_3),
    "4": UInt32(kVK_ANSI_4),
    "5": UInt32(kVK_ANSI_5),
    "6": UInt32(kVK_ANSI_6),
    "7": UInt32(kVK_ANSI_7),
    "8": UInt32(kVK_ANSI_8),
    "9": UInt32(kVK_ANSI_9),
  ]

  var onAction: ((Action) -> Void)?

  func install(bindings: HotKeyBindings = .defaultValue) {
    if handler == nil {
      installHandler()
    }
    applyBindings(bindings)
  }

  func updateBindings(_ bindings: HotKeyBindings) {
    install(bindings: bindings)
  }

  deinit {
    clearRegisteredHotKeys()
  }

  private func installHandler() {
    var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

    let callback: EventHandlerUPP = { _, eventRef, userData in
      guard let userData else { return noErr }
      let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

      var hotKeyID = EventHotKeyID()
      let status = GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
      )
      if status == noErr, let action = Action(rawValue: hotKeyID.id) {
        mgr.onAction?(action)
      }
      return noErr
    }

    InstallEventHandler(
      GetApplicationEventTarget(),
      callback,
      1,
      &eventSpec,
      Unmanaged.passUnretained(self).toOpaque(),
      &handler
    )
  }

  private func applyBindings(_ bindings: HotKeyBindings) {
    clearRegisteredHotKeys()
    register(shortcut: bindings.captureRegionUploadFrozen, action: .captureRegionUploadFrozen)
    register(shortcut: bindings.captureRegionUpload, action: .captureRegionUpload)
    register(shortcut: bindings.captureRegionUploadExpiring, action: .captureRegionUploadExpiring)
    register(shortcut: bindings.uploadClipboard, action: .uploadClipboard)
  }

  private func register(shortcut: HotKeyShortcut, action: Action) {
    let normalized = shortcut.normalized
    guard let keyCode = Self.keyCodeByKey[normalized.key] else { return }
    let modifiers = Self.modifierFlags(from: normalized)
    register(keyCode: keyCode, modifiers: modifiers, action: action)
  }

  private static func modifierFlags(from shortcut: HotKeyShortcut) -> UInt32 {
    var flags: UInt32 = 0
    if shortcut.command { flags |= UInt32(cmdKey) }
    if shortcut.shift { flags |= UInt32(shiftKey) }
    if shortcut.option { flags |= UInt32(optionKey) }
    if shortcut.control { flags |= UInt32(controlKey) }
    return flags
  }

  private func clearRegisteredHotKeys() {
    for (_, ref) in hotKeyRefs {
      UnregisterEventHotKey(ref)
    }
    hotKeyRefs.removeAll()
  }

  private func register(keyCode: UInt32, modifiers: UInt32, action: Action) {
    // 'FRUP'
    let signature = OSType(0x46525550)
    let hotKeyID = EventHotKeyID(signature: signature, id: action.rawValue)
    var ref: EventHotKeyRef?

    let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
    if status == noErr, let ref {
      hotKeyRefs[action.rawValue] = ref
    }
  }
}
