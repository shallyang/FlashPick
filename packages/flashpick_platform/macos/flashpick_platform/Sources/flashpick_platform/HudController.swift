import Cocoa

/// 顶部居中的轻提示（HUD）：保存待办后短暂浮现。
final class HudController {
  static let shared = HudController()

  private var window: NSWindow?
  private var label: NSTextField!
  private var hideWork: DispatchWorkItem?

  private let maxWidth: CGFloat = 420

  func show(_ text: String) {
    DispatchQueue.main.async { [self] in
      buildIfNeeded()
      let preview = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
      let shown = preview.count > 60 ? String(preview.prefix(60)) + "…" : preview
      label.stringValue = shown.isEmpty ? "已收进闪拾" : "已收进闪拾 · \(shown)"

      let size = label.fittingSize
      let w = min(max(size.width + 44, 160), maxWidth + 44)
      let h: CGFloat = 44
      if let screen = NSScreen.main {
        let vis = screen.visibleFrame
        window?.setFrame(
          NSRect(x: vis.midX - w / 2, y: vis.maxY - 64, width: w, height: h),
          display: true)
      }
      guard let window else { return }
      hideWork?.cancel()
      window.alphaValue = 0
      window.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.15
        window.animator().alphaValue = 1
      })
      let work = DispatchWorkItem { [weak self] in
        self?.fadeOut()
      }
      hideWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }
  }

  private func fadeOut() {
    guard let window else { return }
    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = 0.25
      window.animator().alphaValue = 0
    }, completionHandler: {
      window.orderOut(nil)
    })
  }

  private func buildIfNeeded() {
    guard window == nil else { return }
    let w = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 44),
      styleMask: .borderless,
      backing: .buffered,
      defer: false)
    w.level = .statusBar
    w.isOpaque = false
    w.backgroundColor = .clear
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    w.hasShadow = true

    let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 300, height: 44))
    effect.material = .hudWindow
    effect.blendingMode = .behindWindow
    effect.state = .active
    effect.wantsLayer = true
    effect.layer?.cornerRadius = 10

    label = NSTextField(labelWithString: "")
    label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    label.textColor = .white
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    label.translatesAutoresizingMaskIntoConstraints = false
    effect.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
      label.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -16),
      label.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
    ])

    w.contentView = effect
    window = w
  }
}
