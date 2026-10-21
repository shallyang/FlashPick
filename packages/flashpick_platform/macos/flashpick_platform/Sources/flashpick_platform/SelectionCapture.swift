import ApplicationServices
import Cocoa

/// 抓取当前选中文字：暂存剪贴板 → 模拟 ⌘C → 读新内容 → 恢复剪贴板。
/// 无选中（或无辅助功能权限）时回退读取当前剪贴板。
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

  /// 返回 (文字, 来源)；抓不到返回 nil。
  static func capture(timeoutMs: Int = 250) -> (String, String)? {
    guard isTrusted() else {
      return readClipboard()
    }
    let pb = NSPasteboard.general
    let saved = snapshotPasteboard(pb)
    let changeCountBefore = pb.changeCount

    postCommandC()

    var captured = false
    let deadline = Date().addingTimeInterval(TimeInterval(timeoutMs) / 1000.0)
    while Date() < deadline {
      if pb.changeCount != changeCountBefore {
        captured = true
        break
      }
      usleep(8000)
    }

    var text: String?
    if captured {
      text = readString(pb)
    }
    saved.restore(to: pb)

    if let text, !text.isEmpty {
      return (text, "selection")
    }
    return readClipboard()
  }

  private static func postCommandC() {
    let source = CGEventSource(stateID: .combinedSessionState)
    guard
      let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(8), keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(8), keyDown: false)
    else { return }
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

  private static func readClipboard() -> (String, String)? {
    guard let s = readString(NSPasteboard.general), !s.isEmpty else { return nil }
    return (s, "clipboard")
  }
}
