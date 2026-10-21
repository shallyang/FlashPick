import Carbon.HIToolbox
import Foundation

/// 全局热键（Carbon RegisterEventHotKey，无需辅助功能权限）。
final class HotkeyManager: NSObject {
  struct Hotkey {
    let keyCode: UInt32
    let modifiers: UInt32

    static func parse(_ dict: [String: Any]) -> Hotkey? {
      guard let code = (dict["keyCode"] as? NSNumber)?.uint32Value else { return nil }
      var mods: UInt32 = 0
      for m in (dict["modifiers"] as? [String]) ?? [] {
        switch m {
        case "cmd": mods |= UInt32(cmdKey)
        case "shift": mods |= UInt32(shiftKey)
        case "alt": mods |= UInt32(optionKey)
        case "ctrl": mods |= UInt32(controlKey)
        default: break
        }
      }
      return Hotkey(keyCode: code, modifiers: mods)
    }
  }

  var onCapture: (() -> Void)?
  var onPanel: (() -> Void)?

  private var captureRef: EventHotKeyRef?
  private var panelRef: EventHotKeyRef?
  private var handlerInstalled = false

  private let signature: OSType = 0x4650434B // 'FPCK'

  func register(capture: Hotkey, panel: Hotkey) {
    DispatchQueue.main.async { [self] in
      installHandlerIfNeeded()
      unregisterAll()
      var id1 = EventHotKeyID(signature: signature, id: 1)
      RegisterEventHotKey(capture.keyCode, capture.modifiers, id1,
                          GetApplicationEventTarget(), 0, &captureRef)
      var id2 = EventHotKeyID(signature: signature, id: 2)
      RegisterEventHotKey(panel.keyCode, panel.modifiers, id2,
                          GetApplicationEventTarget(), 0, &panelRef)
    }
  }

  func unregisterAll() {
    if let r = captureRef { UnregisterEventHotKey(r); captureRef = nil }
    if let r = panelRef { UnregisterEventHotKey(r); panelRef = nil }
  }

  private func installHandlerIfNeeded() {
    guard !handlerInstalled else { return }
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed))
    let callback: EventHandlerUPP = { _, event, userData in
      var hkID = EventHotKeyID()
      GetEventParameter(event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hkID)
      let manager = Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
      switch hkID.id {
      case 1: DispatchQueue.main.async { manager.onCapture?() }
      case 2: DispatchQueue.main.async { manager.onPanel?() }
      default: break
      }
      return noErr
    }
    InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                        Unmanaged.passUnretained(self).toOpaque(), nil)
    handlerInstalled = true
  }
}
