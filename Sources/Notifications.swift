import Foundation
import UserNotifications

final class Notifier {
  static let shared = Notifier()
  private let center = UNUserNotificationCenter.current()
  private let authLock = NSLock()
  private var didRequestAuth = false

  private init() {}

  func requestAuthIfNeeded() {
    authLock.lock()
    if didRequestAuth {
      authLock.unlock()
      return
    }
    didRequestAuth = true
    authLock.unlock()

    center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
      // Best effort: if denied, notifications will simply be skipped.
    }
  }

  func notify(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
    center.add(request, withCompletionHandler: nil)
  }
}
