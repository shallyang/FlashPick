import Cocoa

/// 快速捕捉窗：无边框 NSPanel，顶部居中，输入文字或按住麦克风语音，
/// 回车提交、Esc 取消。
final class CapturePanelController: NSObject, NSTextViewDelegate {
  static let shared = CapturePanelController()

  var onSubmit: ((String) -> Void)?

  private var panel: KeyablePanel?
  private var textView: PanelTextView!
  private var micButton: HoldButton!
  private var hintLabel: NSTextField!
  private let voice = VoiceEngine()
  private var voiceBaseText = ""

  final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
  }

  /// 按住说话的按钮。
  final class HoldButton: NSButton {
    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?
    private var holding = false

    override func mouseDown(with event: NSEvent) {
      holding = true
      onHoldStart?()
    }

    override func mouseUp(with event: NSEvent) {
      guard holding else { return }
      holding = false
      onHoldEnd?()
    }
  }

  /// 处理回车/Esc 的文本视图。
  final class PanelTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
      switch event.keyCode {
      case 36: // Return
        onCommit?()
      case 53: // Esc
        onCancel?()
      default:
        super.keyDown(with: event)
      }
    }
  }

  func show() {
    DispatchQueue.main.async { [self] in
      buildIfNeeded()
      textView.string = ""
      hintLabel.stringValue = "回车保存 · Esc 取消 · 按住麦克风说话"
      guard let panel else { return }
      if let screen = NSScreen.main {
        let vis = screen.visibleFrame
        let w: CGFloat = 560
        let h: CGFloat = 172
        let x = vis.midX - w / 2
        let y = vis.midY + vis.height * 0.18
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
      }
      NSApp.activate(ignoringOtherApps: true)
      panel.makeKeyAndOrderFront(nil)
      DispatchQueue.main.async { [self] in
        _ = self.panel?.makeFirstResponder(textView)
      }
    }
  }

  private func windowDidBecomeActive() {
    DispatchQueue.main.async { [self] in
      _ = panel?.makeFirstResponder(textView)
    }
  }

  private func commit() {
    let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
    panel?.orderOut(nil)
    guard !text.isEmpty else { return }
    onSubmit?(text)
  }

  private func cancel() {
    voice.stop()
    setMicRecording(false)
    panel?.orderOut(nil)
  }

  private func setMicRecording(_ on: Bool) {
    let symbol = on ? "stop.circle.fill" : "mic.fill"
    micButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "麦克风")
    micButton.contentTintColor = on ? NSColor.systemRed : NSColor.labelColor
    hintLabel.stringValue = on ? "正在听…松开结束" : "回车保存 · Esc 取消 · 按住麦克风说话"
  }

  // MARK: - 构建 UI

  private func buildIfNeeded() {
    guard panel == nil else { return }

    let p = KeyablePanel(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 172),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false)
    p.isFloatingPanel = true
    p.level = .floating
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = true
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 560, height: 172))
    effect.material = .hudWindow
    effect.blendingMode = .behindWindow
    effect.state = .active
    effect.wantsLayer = true
    effect.layer?.cornerRadius = 12

    // 文本输入区
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    scroll.borderType = .noBorder

    textView = PanelTextView(frame: .zero)
    textView.autoresizingMask = []
    textView.font = NSFont.systemFont(ofSize: 16)
    textColorAdapt(textView)
    textView.drawsBackground = false
    textView.isRichText = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.allowsUndo = true
    textView.onCommit = { [weak self] in self?.commit() }
    textView.onCancel = { [weak self] in self?.cancel() }
    scroll.documentView = textView

    // 麦克风按钮（按住说话）
    micButton = HoldButton(frame: NSRect(x: 0, y: 0, width: 34, height: 34))
    micButton.bezelStyle = .texturedRounded
    micButton.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "麦克风")
    micButton.imagePosition = .imageOnly
    micButton.contentTintColor = .labelColor
    micButton.onHoldStart = { [weak self] in self?.voiceStart() }
    micButton.onHoldEnd = { [weak self] in self?.voice.stop() }

    hintLabel = NSTextField(labelWithString: "回车保存 · Esc 取消 · 按住麦克风说话")
    hintLabel.font = NSFont.systemFont(ofSize: 11)
    hintLabel.textColor = .secondaryLabelColor

    let bottom = NSStackView(views: [micButton, hintLabel])
    bottom.orientation = .horizontal
    bottom.spacing = 10
    bottom.alignment = .centerY
    bottom.translatesAutoresizingMaskIntoConstraints = false

    effect.addSubview(scroll)
    effect.addSubview(bottom)
    scroll.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 18),
      scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -18),
      scroll.topAnchor.constraint(equalTo: effect.topAnchor, constant: 16),
      scroll.heightAnchor.constraint(equalToConstant: 84),
      bottom.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 18),
      bottom.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -12),
      bottom.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -18),
    ])

    p.contentView = effect
    panel = p

    // 语音回调
    voice.onPartial = { [weak self] text in
      guard let self else { return }
      self.textView.string = self.voiceBaseText + text
      self.textView.scrollToEndOfDocument(nil)
    }
    voice.onFinal = { [weak self] text in
      guard let self else { return }
      let merged = (self.voiceBaseText + text).trimmingCharacters(in: .whitespacesAndNewlines)
      if !merged.isEmpty {
        self.textView.string = merged + " "
        self.textView.moveToEndOfDocument(nil)
      }
      self.setMicRecording(false)
    }
    voice.onError = { [weak self] message in
      guard let self else { return }
      self.setMicRecording(false)
      self.hintLabel.stringValue = message
    }
  }

  private func voiceStart() {
    voiceBaseText = textView.string
    setMicRecording(true)
    voice.start()
  }

  private func textColorAdapt(_ tv: NSTextView) {
    // 深色 HUD 窗体上使用亮色文字
    tv.textColor = .white
  }
}
