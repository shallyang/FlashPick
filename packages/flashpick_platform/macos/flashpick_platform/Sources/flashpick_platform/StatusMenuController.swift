import Cocoa

/// 菜单栏常驻图标 + 菜单：最近待办、快速捕捉、主窗口、设置、开机自启、退出。
final class StatusMenuController: NSObject {
  static let shared = StatusMenuController()

  /// action: capture / main / settings / quit / toggle（toggle 时携带 todoId）
  var onAction: ((String, String?) -> Void)?

  private var statusItem: NSStatusItem?
  private var autostartItem: NSMenuItem?
  private var todoStartIndex = 0
  private var menu: NSMenu?
  private var actionTargets: [MenuItemTarget] = []

  final class MenuItemTarget: NSObject {
    let closure: () -> Void
    init(_ closure: @escaping () -> Void) {
      self.closure = closure
    }
    @objc func invoke() {
      closure()
    }
  }

  func setup() {
    DispatchQueue.main.async { [self] in
      guard statusItem == nil else { return }
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      if let button = item.button {
        button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "闪拾")
        button.image?.isTemplate = true
      }
      let m = NSMenu()
      m.autoenablesItems = false
      item.menu = m
      menu = m
      statusItem = item
      rebuildMenu(todos: [])
    }
  }

  /// 用待办快照重建菜单。
  func updateTodos(_ todos: [[String: Any]]) {
    DispatchQueue.main.async { [self] in
      rebuildMenu(todos: todos)
    }
  }

  func refreshAutostartState() {
    DispatchQueue.main.async { [self] in
      autostartItem?.state = Autostart.isEnabled ? .on : .off
    }
  }

  private func rebuildMenu(todos: [[String: Any]]) {
    guard let menu else { return }
    actionTargets.removeAll()
    menu.removeAllItems()

    add(menu, title: "快速捕捉", action: { [weak self] in self?.onAction?("capture", nil) })
    add(menu, title: "抓取选中文字", action: { [weak self] in self?.onAction?("hotkeyCapture", nil) })
    menu.addItem(.separator())

    let pending = todos.filter { ($0["done"] as? Bool) != true }
    if pending.isEmpty {
      let empty = NSMenuItem(title: "暂无待办", action: nil, keyEquivalent: "")
      empty.isEnabled = false
      menu.addItem(empty)
    } else {
      for todo in pending.prefix(6) {
        let id = (todo["id"] as? String) ?? ""
        var title = (todo["text"] as? String) ?? ""
        let firstLine = title.split(separator: "\n").first.map(String.init) ?? title
        if firstLine.count > 32 {
          title = String(firstLine.prefix(32)) + "…"
        } else {
          title = firstLine
        }
        add(menu, title: "○  \(title)", action: { [weak self] in
          self?.onAction?("toggle", id)
        })
      }
    }
    menu.addItem(.separator())

    add(menu, title: "打开主窗口", action: { [weak self] in self?.onAction?("main", nil) })
    add(menu, title: "设置…", action: { [weak self] in self?.onAction?("settings", nil) })

    let auto = NSMenuItem(title: "开机自启", action: nil, keyEquivalent: "")
    auto.target = self
    auto.action = #selector(toggleAutostart)
    auto.state = Autostart.isEnabled ? .on : .off
    menu.addItem(auto)
    autostartItem = auto

    menu.addItem(.separator())
    add(menu, title: "退出闪拾", action: { [weak self] in self?.onAction?("quit", nil) })
  }

  @objc private func toggleAutostart() {
    let newValue = !Autostart.isEnabled
    if Autostart.setEnabled(newValue) {
      autostartItem?.state = newValue ? .on : .off
    }
  }

  private func add(_ menu: NSMenu, title: String, action: @escaping () -> Void) {
    let target = MenuItemTarget(action)
    let item = NSMenuItem(title: title, action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
    item.target = target
    menu.addItem(item)
    actionTargets.append(target)
  }
}
