import Cocoa

/// 桌面清单小组件：常驻桌面角落的半透明待办列表。
/// 圆圈点击=完成，双击文字=打开主窗口，右键=置顶开关/关闭，可整体拖动。
final class DesktopWidgetController: NSObject {
  static let shared = DesktopWidgetController()

  private var panel: NSPanel?
  private var container: NSStackView!
  private var todos: [[String: Any]] = []
  private(set) var isVisible = false

  var onToggleTodo: ((String) -> Void)?
  var onOpenMain: (() -> Void)?
  var onToggleVisibility: (() -> Void)?

  private let width: CGFloat = 268
  private let maxRows = 8

  final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
  }

  final class WidgetView: NSVisualEffectView {
    var contextMenuProvider: (() -> NSMenu)?

    override func menu(for event: NSEvent) -> NSMenu? {
      contextMenuProvider?()
    }

    override var mouseDownCanMoveWindow: Bool { true }
  }

  private var pinned: Bool {
    get { UserDefaults.standard.bool(forKey: "flashpick.widget.pinned") }
    set { UserDefaults.standard.set(newValue, forKey: "flashpick.widget.pinned") }
  }

  func setVisible(_ on: Bool) {
    DispatchQueue.main.async { [self] in
      if on {
        buildIfNeeded()
        reLayout()
        panel?.orderFrontRegardless()
      } else {
        panel?.orderOut(nil)
      }
      isVisible = on
    }
  }

  func updateTodos(_ list: [[String: Any]]) {
    DispatchQueue.main.async { [self] in
      todos = list
      if isVisible {
        reLayout()
      }
    }
  }

  // MARK: - 构建

  private func buildIfNeeded() {
    guard panel == nil else { return }

    let effect = WidgetView(frame: NSRect(x: 0, y: 0, width: width, height: 120))
    effect.material = .sidebar
    effect.blendingMode = .behindWindow
    effect.state = .active
    effect.wantsLayer = true
    effect.layer?.cornerRadius = 14
    effect.contextMenuProvider = { [weak self] in self?.buildContextMenu() ?? NSMenu() }

    container = NSStackView()
    container.orientation = .vertical
    container.alignment = .leading
    container.spacing = 2
    container.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
    container.translatesAutoresizingMaskIntoConstraints = false
    effect.addSubview(container)
    NSLayoutConstraint.activate([
      container.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
      container.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
      container.topAnchor.constraint(equalTo: effect.topAnchor),
      container.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
    ])

    let p = WidgetPanel(
      contentRect: NSRect(x: 0, y: 0, width: width, height: 120),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false)
    p.contentView = effect
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = true
    p.isMovableByWindowBackground = true
    p.level = pinned ? .floating : .normal
    p.ignoresMouseEvents = false
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel = p

    if !p.setFrameUsingName("FlashPickDesktopWidget") {
      // 首次出现：桌面右上角，避开 HUD 区域
      if let screen = NSScreen.main {
        let vis = screen.visibleFrame
        let h: CGFloat = 140
        p.setFrame(
          NSRect(x: vis.maxX - width - 20, y: vis.maxY - h - 60, width: width, height: h),
          display: false)
      }
    }
  }

  private func buildContextMenu() -> NSMenu {
    let menu = NSMenu()
    let pin = NSMenuItem(
      title: pinned ? "取消置顶" : "始终置顶",
      action: #selector(togglePin),
      keyEquivalent: "")
    pin.target = self
    menu.addItem(pin)
    let close = NSMenuItem(
      title: "关闭桌面清单", action: #selector(closeSelf), keyEquivalent: "")
    close.target = self
    menu.addItem(close)
    return menu
  }

  @objc private func togglePin() {
    pinned.toggle()
    panel?.level = pinned ? .floating : .normal
  }

  @objc private func closeSelf() {
    onToggleVisibility?()
  }

  // MARK: - 布局

  private func reLayout() {
    guard let panel, container != nil else { return }
    for view in container.arrangedSubviews {
      container.removeView(view)
    }

    let pending = todos.filter { ($0["done"] as? Bool) != true }

    // 头部
    let header = makeHeader(count: pending.count)
    container.addView(header, in: .leading)

    if pending.isEmpty {
      let empty = NSTextField(labelWithString: "全部完成，歇口气 ✓")
      empty.font = NSFont.systemFont(ofSize: 12)
      empty.textColor = .secondaryLabelColor
      container.addView(empty, in: .leading)
      container.setCustomSpacing(6, after: header)
    } else {
      for todo in pending.prefix(maxRows) {
        let row = makeRow(id: (todo["id"] as? String) ?? "",
                          text: (todo["text"] as? String) ?? "")
        container.addView(row, in: .leading)
      }
      if pending.count > maxRows {
        let more = NSTextField(labelWithString: "还有 \(pending.count - maxRows) 项…")
        more.font = NSFont.systemFont(ofSize: 11)
        more.textColor = .secondaryLabelColor
        container.addView(more, in: .leading)
      }
    }

    // 依据内容自适应高度（锚定左上角）
    let contentSize = container.fittingSize
    let height = max(contentSize.height, 64)
    var frame = panel.frame
    let newY = frame.maxY - height
    frame.origin.y = newY
    frame.size.height = height
    panel.setFrame(frame, display: true)
  }

  private func makeHeader(count: Int) -> NSView {
    let title = NSTextField(labelWithString: "闪拾 · 待办")
    title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    title.textColor = .labelColor

    let badge = NSTextField(labelWithString: count > 0 ? "\(count)" : "✓")
    badge.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    badge.textColor = .secondaryLabelColor

    let row = NSStackView(views: [title, badge])
    row.orientation = .horizontal
    row.spacing = 6
    row.alignment = .centerY
    row.translatesAutoresizingMaskIntoConstraints = false
    return row
  }

  private func makeRow(id: String, text: String) -> NSView {
    let circle = NSButton()
    circle.bezelStyle = .inline
    circle.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "完成")
    circle.imagePosition = .imageOnly
    circle.imageScaling = .scaleProportionallyDown
    circle.contentTintColor = .secondaryLabelColor
    circle.target = self
    circle.action = #selector(circleTapped(_:))

    var firstLine = text.split(separator: "\n").first.map(String.init) ?? text
    if firstLine.count > 22 {
      firstLine = String(firstLine.prefix(22)) + "…"
    }
    let label = NSTextField(labelWithString: firstLine)
    label.font = NSFont.systemFont(ofSize: 12.5)
    label.textColor = .labelColor
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1

    let double = NSClickGestureRecognizer(target: self, action: #selector(rowDoubleClicked(_:)))
    double.numberOfClicksRequired = 2
    label.addGestureRecognizer(double)

    let row = NSStackView(views: [circle, label])
    row.orientation = .horizontal
    row.spacing = 7
    row.alignment = .centerY
    row.translatesAutoresizingMaskIntoConstraints = false
    row.identifier = NSUserInterfaceItemIdentifier(id)
    return row
  }

  @objc private func circleTapped(_ sender: NSButton) {
    guard let stackRow = sender.superview,
          let id = stackRow.identifier?.rawValue, !id.isEmpty
    else { return }
    onToggleTodo?(id)
  }

  @objc private func rowDoubleClicked(_ g: NSClickGestureRecognizer) {
    onOpenMain?()
  }
}
