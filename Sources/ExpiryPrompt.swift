import AppKit
import Foundation

enum ExpiryPrompt {
  // Returns expiry in seconds, or nil if cancelled.
  static func promptSeconds(maxDays: Int, title: String = "Link expiry", message: String? = nil) -> Int? {
    let maxSeconds = maxDays * 24 * 60 * 60
    let promptMessage = message ?? "Set expiry time for the downloaded link (maximum \(maxDays) days)."

    while true {
      let alert = NSAlert()
      alert.messageText = title
      alert.informativeText = promptMessage
      alert.addButton(withTitle: "OK")
      alert.addButton(withTitle: "Cancel")

      let field = NSTextField(string: "1")
      field.frame = NSRect(x: 0, y: 0, width: 80, height: 24)

      let unit = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 120, height: 26), pullsDown: false)
      unit.addItems(withTitles: ["hours", "days", "minutes"])
      unit.selectItem(withTitle: "days")

      let stack = NSStackView(views: [field, unit])
      stack.orientation = .horizontal
      stack.spacing = 8
      stack.alignment = .centerY

      alert.accessoryView = stack
      alert.ensureResizable()

      let resp = alert.runModal()
      if resp != .alertFirstButtonReturn {
        return nil
      }

      let raw = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      let n = Int(raw)
      if n == nil || n! <= 0 {
        _ = errorAlert("Enter a positive number")
        continue
      }

      let seconds: Int
      switch unit.selectedItem?.title {
      case "minutes":
        seconds = n! * 60
      case "hours":
        seconds = n! * 60 * 60
      case "days":
        seconds = n! * 24 * 60 * 60
      default:
        seconds = n! * 24 * 60 * 60
      }

      if seconds <= 0 {
        _ = errorAlert("Invalid duration")
        continue
      }

      if seconds > maxSeconds {
        _ = errorAlert("Max is \(maxDays) days")
        continue
      }

      return seconds
    }
  }

  @discardableResult
  private static func errorAlert(_ msg: String) -> NSApplication.ModalResponse {
    let a = NSAlert()
    a.messageText = "Invalid expiry"
    a.informativeText = msg
    a.addButton(withTitle: "OK")
    a.ensureResizable()
    return a.runModal()
  }
}
