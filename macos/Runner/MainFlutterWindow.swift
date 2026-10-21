import Cocoa
import FlutterMacOS

/// 闪拾是菜单栏驻留应用：主窗口默认不显示。
/// 做法：启动时 alpha=0（引擎正常启动、无可见闪现），稍后 orderOut 隐藏；
/// 由插件侧通过 "dev.flashpick.showMainWindow" 通知唤起。
/// 注意：不能重写 order() 吞掉显示事件——那会阻止 Flutter 引擎启动。
class MainFlutterWindow: NSWindow {
  static let showNotification = Notification.Name("dev.flashpick.showMainWindow")

  private var observer: Any?
  private var shownByRequest = false

  override func awakeFromNib() {
    alphaValue = 0
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    observer = NotificationCenter.default.addObserver(
      forName: MainFlutterWindow.showNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.shownByRequest = true
      self.alphaValue = 1
      NSApp.activate(ignoringOtherApps: true)
      self.makeKeyAndOrderFront(nil)
    }

    // 引擎完成首帧排序后真正隐藏（0.5s 内对用户不可见）
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      guard let self, !self.shownByRequest else { return }
      self.orderOut(nil)
    }

    super.awakeFromNib()
  }
}
