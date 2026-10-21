import Cocoa
import ServiceManagement

/// 开机自启（LoginItem，macOS 13+ 的 SMAppService）。
enum Autostart {
  static var isEnabled: Bool {
    if #available(macOS 13.0, *) {
      return SMAppService.mainApp.status == .enabled
    }
    return false
  }

  @discardableResult
  static func setEnabled(_ on: Bool) -> Bool {
    if #available(macOS 13.0, *) {
      do {
        if on {
          try SMAppService.mainApp.register()
        } else {
          try SMAppService.mainApp.unregister()
        }
        return true
      } catch {
        NSLog("[FlashPick] autostart %@ failed: %@", on ? "enable" : "disable", error.localizedDescription)
        return false
      }
    }
    return false
  }
}
