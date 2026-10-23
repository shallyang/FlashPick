import ApplicationServices
import Cocoa

/// 抓取当前选中文字：暂存剪贴板 → 模拟 ⌘C → 读新内容 → 恢复剪贴板。
/// 无辅助功能权限或复制超时时回退读取当前剪贴板，并在 source 中注明原因。
enum SelectionCapture {
  static func isTrusted() -> Bool {
    AXIsProcessTrusted()
  }

  /// 弹出系统的辅助功能授权引导窗。
  static func promptTrust() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  struct SavedPasteboard {
    let items: [[(NSPasteboard.PasteboardType, Data)]]

    func restore(to pb: NSPasteboard) {
      pb.clearContents()
      let newItems: [NSPasteboardItem] = items.map { types in
        let item = NSPasteboardItem()
        for (type, data) in types {
          item.setData(data, forType: type)
        }
        return item
      }
      if !newItems.isEmpty {
        pb.writeObjects(newItems)
      }
    }
  }

  static func snapshotPasteboard(_ pb: NSPasteboard) -> SavedPasteboard {
    let items = (pb.pasteboardItems ?? []).map { item in
      item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
        guard let data = item.data(forType: type) else { return nil }
        return (type, data)
      }
    }
    return SavedPasteboard(items: items)
  }

  /// 返回 (文字, 来源)；来源为 selection / clipboard / clipboard-untrusted / clipboard-timeout。
  static func capture(timeoutMs: Int = 350) -> (String, String)? {
    guard isTrusted() else {
      NSLog("[FlashPick] capture: 无辅助功能权限，回退剪贴板")
      return readClipboard("clipboard-untrusted")
    }
    let pb = NSPasteboard.general
    let saved = snapshotPasteboard(pb)
    let changeCountBefore = pb.changeCount

    // 关键：等用户松开热键修饰键再发 ⌘C，
    // 否则目标应用会把合成事件与仍按着的 ⌃⇧ 合并，复制被丢弃
    waitModifierRelease()

    // 两次尝试：部分应用（Electron/微信等）响应较慢
    postCommandC()
    var captured = waitChange(pb, since: changeCountBefore, ms: 180)
    if !captured {
      postCommandC()
      captured = waitChange(pb, since: changeCountBefore, ms: timeoutMs - 180)
    }

    var text: String?
    if captured {
      text = readString(pb)
    }
    saved.restore(to: pb)

    if let text, !text.isEmpty {
      NSLog("[FlashPick] capture: 选中文字抓取成功 (%d 字)", text.count)
      return (text, "selection")
    }
    NSLog("[FlashPick] capture: 复制未生效(captured=%d)，回退剪贴板", captured ? 1 : 0)
    return readClipboard(captured ? "clipboard" : "clipboard-timeout")
  }

  /// 等待热键修饰键（⌃/⇧/⌥/⌘）物理释放，最多 timeoutMs。
  private static func waitModifierRelease(timeoutMs: Int = 400) {
    let modifiers: [CGKeyCode] = [0x3B /*ctrl*/, 0x38 /*shift*/, 0x3A /*opt*/, 0x37 /*cmd*/]
    let start = Date()
    let deadline = start.addingTimeInterval(TimeInterval(timeoutMs) / 1000.0)
    while Date() < deadline {
      let anyDown = modifiers.contains {
        CGEventSource.keyState(.combinedSessionState, key: $0)
      }
      if !anyDown {
        // 等 keyUp 事件传播完毕再合成 ⌘C
        usleep(30000)
        NSLog("[FlashPick] capture: 修饰键已松开，等待 %dms",
              Int(Date().timeIntervalSince(start) * 1000))
        return
      }
      usleep(8000)
    }
    NSLog("[FlashPick] capture: 修饰键未松开，超时后仍尝试 ⌘C")
  }

  private static func waitChange(_ pb: NSPasteboard, since count: Int, ms: Int) -> Bool {
    let deadline = Date().addingTimeInterval(TimeInterval(ms) / 1000.0)
    while Date() < deadline {
      if pb.changeCount != count {
        return true
      }
      usleep(5000)
    }
    return pb.changeCount != count
  }

  private static func postCommandC() {
    let source = CGEventSource(stateID: .combinedSessionState)
    guard
      let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(8), keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(8), keyDown: false)
    else { return }
    // 显式覆盖修饰键集合，避免叠加用户尚未松开的 ⌃⇧
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
  }

  private static func readString(_ pb: NSPasteboard) -> String? {
    if let s = pb.string(forType: .string) {
      return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    for type in [NSPasteboard.PasteboardType.rtf, .rtfd] {
      if let data = pb.data(forType: type),
         let attr = try? NSAttributedString(
           data: data,
           options: [.documentType: NSAttributedString.DocumentType.rtf],
           documentAttributes: nil) {
        return attr.string.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
    return nil
  }

  private static func readClipboard(_ source: String) -> (String, String)? {
    guard let s = readString(NSPasteboard.general), !s.isEmpty else { return nil }
    return (s, source)
  }
}
