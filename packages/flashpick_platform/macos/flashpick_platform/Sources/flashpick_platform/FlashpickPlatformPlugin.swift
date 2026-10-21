import Cocoa
import FlutterMacOS

/// 闪拾原生平台层入口：MethodChannel 分发 + 各能力模块的组装。
public class FlashpickPlatformPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.flashpick/platform",
      binaryMessenger: registrar.messenger)
    let instance = FlashpickPlatformPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private let channel: FlutterMethodChannel
  private let hotkeys = HotkeyManager()
  private let hud = HudController.shared
  private let panel = CapturePanelController.shared
  private let statusMenu = StatusMenuController.shared
  private let mirror = RemindersMirror.shared

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = (call.arguments as? [String: Any]) ?? [:]
    switch call.method {
    case "init":
      let capture = (args["captureHotkey"] as? [String: Any]) ?? [:]
      let panelHk = (args["panelHotkey"] as? [String: Any]) ?? [:]
      wireActions()
      if let c = HotkeyManager.Hotkey.parse(capture),
         let p = HotkeyManager.Hotkey.parse(panelHk) {
        hotkeys.register(capture: c, panel: p)
      }
      statusMenu.setup()
      statusMenu.refreshAutostartState()
      result(nil)

    case "updateHotkeys":
      let capture = (args["captureHotkey"] as? [String: Any]) ?? [:]
      let panelHk = (args["panelHotkey"] as? [String: Any]) ?? [:]
      if let c = HotkeyManager.Hotkey.parse(capture),
         let p = HotkeyManager.Hotkey.parse(panelHk) {
        hotkeys.register(capture: c, panel: p)
        result(true)
      } else {
        result(false)
      }

    case "setMenuTodos":
      let todos = (call.arguments as? [[String: Any]]) ?? []
      statusMenu.updateTodos(todos)
      result(nil)

    case "showHud":
      hud.show((args["text"] as? String) ?? "")
      result(nil)

    case "showPanel":
      panel.show()
      result(nil)

    case "captureSelection":
      if let (text, source) = SelectionCapture.capture() {
        result(["text": text, "source": source])
      } else {
        result(["text": nil, "source": "none"])
      }

    case "permissions":
      result([
        "accessibility": SelectionCapture.isTrusted(),
        "microphone": VoiceEngine.micGranted(),
        "speech": VoiceEngine.speechGranted(),
        "reminders": RemindersMirror.permissionGranted(),
      ])

    case "requestAccessibility":
      SelectionCapture.promptTrust()
      result(nil)

    case "requestRuntimePermissions":
      VoiceEngine.requestAll { micAndSpeech in
        self.mirror.requestAccess { _ in
          _ = micAndSpeech
          result(nil)
        }
      }

    case "openSystemSettings":
      openSettings((args["pane"] as? String) ?? "")
      result(nil)

    case "setAutostart":
      let ok = Autostart.setEnabled((args["enabled"] as? Bool) ?? false)
      statusMenu.refreshAutostartState()
      result(ok)

    case "isAutostart":
      result(Autostart.isEnabled)

    case "mirrorTodo":
      let id = (args["id"] as? String) ?? ""
      let text = (args["text"] as? String) ?? ""
      mirror.addReminder(text: text, notes: "来自闪拾 FlashPick") { [weak self] ekId in
        _ = self
        _ = id
        result(["ekId": ekId])
      }

    case "setMirrorCompleted":
      mirror.setCompleted(
        externalID: (args["ekId"] as? String) ?? "",
        completed: (args["completed"] as? Bool) ?? true)
      result(nil)

    case "deleteMirror":
      mirror.delete(externalID: (args["ekId"] as? String) ?? "")
      result(nil)

    case "showMainWindow":
      showMainWindow()
      result(nil)

    case "quitApp":
      NSApp.terminate(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - 组装

  private func wireActions() {
    hotkeys.onCapture = { [weak self] in
      self?.runCapture()
    }
    hotkeys.onPanel = { [weak self] in
      self?.panel.show()
    }
    panel.onSubmit = { [weak self] text in
      self?.channel.invokeMethod("onPanelSubmit", arguments: ["text": text])
    }
    statusMenu.onAction = { [weak self] action, todoId in
      guard let self else { return }
      switch action {
      case "capture":
        self.panel.show()
      case "hotkeyCapture":
        self.runCapture()
      case "main":
        self.showMainWindow()
      case "settings":
        self.channel.invokeMethod("onMenuAction", arguments: ["action": "settings"])
      case "quit":
        NSApp.terminate(nil)
      case "toggle":
        self.channel.invokeMethod(
          "onMenuAction",
          arguments: ["action": "toggle", "todoId": todoId ?? ""])
      default:
        break
      }
    }
  }

  private func runCapture() {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let captured = SelectionCapture.capture()
      DispatchQueue.main.async {
        guard let self else { return }
        if let (text, source) = captured {
          self.channel.invokeMethod("onCaptured", arguments: ["text": text, "source": source])
        } else {
          self.hud.show("没有抓到文字（未选中且剪贴板为空）")
        }
      }
    }
  }

  private func showMainWindow() {
    DispatchQueue.main.async {
      // 主窗口（app target）监听该通知：解锁 order 吞噬并前置显示
      NotificationCenter.default.post(
        name: Notification.Name("dev.flashpick.showMainWindow"), object: nil)
    }
  }

  private func openSettings(_ pane: String) {
    let query: String
    switch pane {
    case "accessibility": query = "Privacy_Accessibility"
    case "microphone": query = "Privacy_Microphone"
    case "speech": query = "Privacy_SpeechRecognition"
    case "reminders": query = "Privacy_Reminders"
    default: query = "Privacy_All"
    }
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(query)") {
      NSWorkspace.shared.open(url)
    }
  }
}
