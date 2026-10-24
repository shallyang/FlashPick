import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flashpick_platform/flashpick_platform.dart';

import 'store.dart';

/// 全局应用状态：待办数据 + 设置 + 原生回调的落地。
class AppState extends ChangeNotifier {
  final store = Store.instance;

  List<Todo> todos = [];
  String keyword = '';
  bool showDone = false;

  // 设置项
  HotkeyDef captureHotkey = HotkeyDef.captureDefault;
  HotkeyDef panelHotkey = HotkeyDef.panelDefault;
  bool mirrorEnabled = true;
  bool autostart = false;
  bool desktopWidgetVisible = true;
  bool firstRun = true;
  PermissionStatus? permissions;

  String get pendingCount =>
      todos.where((t) => !t.done).length.toString().padLeft(2, '0');

  List<Todo> get visibleTodos {
    final kw = keyword.trim().toLowerCase();
    return todos
        .where((t) => showDone ? true : !t.done)
        .where((t) => kw.isEmpty || t.text.toLowerCase().contains(kw))
        .toList();
  }

  /// 启动：加载设置 → 注册原生回调 → 初始化原生侧 → 拉取列表。
  Future<void> bootstrap() async {
    await _loadSettings();
    await FlashpickPlatform.init(
      PlatformCallbacks(
        onCaptured: onCaptured,
        onPanelSubmit: onPanelSubmit,
        onMenuAction: onMenuAction,
      ),
      captureHotkey,
      panelHotkey,
    );
    autostart = await FlashpickPlatform.isAutostart();
    try {
      await FlashpickPlatform.setWidgetVisible(desktopWidgetVisible);
    } catch (_) {}
    await refreshTodos();
    await refreshPermissions();
  }

  Future<void> _loadSettings() async {
    final capture = await store.getSetting('hotkey.capture');
    final panel = await store.getSetting('hotkey.panel');
    if (capture != null) {
      try {
        captureHotkey = HotkeyDef.fromMap(
            (jsonDecode(capture) as Map).cast<Object?, Object?>());
      } catch (_) {}
    }
    if (panel != null) {
      try {
        panelHotkey = HotkeyDef.fromMap(
            (jsonDecode(panel) as Map).cast<Object?, Object?>());
      } catch (_) {}
    }
    mirrorEnabled = await store.getSetting('mirror.enabled') != 'false';
    desktopWidgetVisible = await store.getSetting('desktopWidget.visible') != 'false';
    firstRun = await store.getSetting('app.firstRunDone') != 'true';
  }

  Future<void> refreshTodos() async {
    todos = await store.listTodos();
    await _pushMenu();
    notifyListeners();
  }

  Future<void> refreshPermissions() async {
    try {
      permissions = await FlashpickPlatform.permissions();
      notifyListeners();
    } catch (_) {
      // 平台不支持时忽略
    }
  }

  Future<void> setKeyword(String kw) async {
    keyword = kw;
    notifyListeners();
  }

  Future<void> setShowDone(bool v) async {
    showDone = v;
    notifyListeners();
  }

  // ---- 原生回调 ----

  Future<void> onCaptured(String text, String source) async {
    await _addInternal(text, source == 'clipboard' ? 'clipboard' : 'hotkey');
  }

  Future<void> onPanelSubmit(String text) async {
    await _addInternal(text, 'panel');
  }

  Future<void> onMenuAction(String action, String? todoId) async {
    switch (action) {
      case 'toggle':
        if (todoId != null) {
          final todo = todos.firstWhere((t) => t.id == todoId,
              orElse: () => todos.first);
          await setDone(todo.id, !todo.done);
        }
        break;
      case 'settings':
        showMainWindow(tab: 1);
        break;
      case 'toggleWidget':
        await setDesktopWidgetVisible(!desktopWidgetVisible);
        break;
      default:
        break;
    }
  }

  // ---- 增删改 ----

  Future<void> addManual(String text) => _addInternal(text, 'panel');

  /// 打开原生快速捕捉窗（速记按钮）。
  Future<void> showQuickCapture() async {
    try {
      await FlashpickPlatform.showPanel();
    } catch (_) {}
  }

  /// 在 Finder 中显示数据库文件。
  Future<void> revealDbFolder(String path) async {
    try {
      await Process.run('open', ['-R', path]);
    } catch (_) {}
  }

  /// 引导授权：辅助功能弹系统引导窗，runtime 走系统弹窗请求，其余打开对应设置面板。
  Future<void> openPermissionSettings(String pane) async {
    try {
      if (pane == 'accessibility') {
        await FlashpickPlatform.requestAccessibility();
      } else if (pane == 'runtime') {
        await FlashpickPlatform.requestRuntimePermissions();
      } else {
        await FlashpickPlatform.openSystemSettings(pane);
      }
    } catch (_) {}
    // 用户操作完回来刷新状态
    Future.delayed(const Duration(seconds: 3), refreshPermissions);
    Future.delayed(const Duration(seconds: 10), refreshPermissions);
  }

  Future<void> _addInternal(String text, String source) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final todo = Todo(
      id: newId(),
      text: trimmed,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      source: source,
    );
    await store.insertTodo(todo);
    todos.insert(0, todo);

    // 镜像到系统提醒事项
    if (mirrorEnabled) {
      try {
        final ekId = await FlashpickPlatform.mirrorTodo(todo.id, trimmed);
        if (ekId != null) {
          todo.mirrorId = ekId;
          await store.setMirrorId(todo.id, ekId);
        }
      } catch (_) {}
    }

    final preview = trimmed.split('\n').first;
    final suffix = switch (source) {
      'clipboard' => '（未选中文字，已存剪贴板内容）',
      'clipboard-timeout' => '（复制超时，已存剪贴板内容）',
      _ => '',
    };
    try {
      await FlashpickPlatform.showHud('$preview$suffix');
    } catch (_) {}

    await _pushMenu();
    notifyListeners();
  }

  Future<void> setDone(String id, bool done) async {
    await store.setDone(id, done);
    final todo = todos.where((t) => t.id == id).firstOrNull;
    if (todo != null) {
      todo.done = done;
      todo.doneAt = done ? DateTime.now().millisecondsSinceEpoch : null;
      if (mirrorEnabled && todo.mirrorId != null) {
        try {
          await FlashpickPlatform.setMirrorCompleted(todo.mirrorId!, done);
        } catch (_) {}
      }
    }
    await _pushMenu();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    await store.remove(id);
    final todo = todos.where((t) => t.id == id).firstOrNull;
    if (mirrorEnabled && todo?.mirrorId != null) {
      try {
        await FlashpickPlatform.deleteMirror(todo!.mirrorId!);
      } catch (_) {}
    }
    todos.removeWhere((t) => t.id == id);
    await _pushMenu();
    notifyListeners();
  }

  // ---- 设置变更 ----

  Future<void> setCaptureHotkey(HotkeyDef hk) async {
    captureHotkey = hk;
    await store.setSetting('hotkey.capture', jsonEncode(hk.toMap()));
    await FlashpickPlatform.updateHotkeys(captureHotkey, panelHotkey);
    notifyListeners();
  }

  Future<void> setPanelHotkey(HotkeyDef hk) async {
    panelHotkey = hk;
    await store.setSetting('hotkey.panel', jsonEncode(hk.toMap()));
    await FlashpickPlatform.updateHotkeys(captureHotkey, panelHotkey);
    notifyListeners();
  }

  Future<void> setMirrorEnabled(bool v) async {
    mirrorEnabled = v;
    await store.setSetting('mirror.enabled', v ? 'true' : 'false');
    notifyListeners();
  }

  Future<void> setDesktopWidgetVisible(bool v) async {
    desktopWidgetVisible = v;
    await store.setSetting('desktopWidget.visible', v ? 'true' : 'false');
    try {
      await FlashpickPlatform.setWidgetVisible(v);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setAutostart(bool v) async {
    final ok = await FlashpickPlatform.setAutostart(v);
    if (ok) autostart = v;
    notifyListeners();
  }

  Future<void> finishFirstRun() async {
    firstRun = false;
    await store.setSetting('app.firstRunDone', 'true');
    notifyListeners();
  }

  Future<String> dbPath() => store.dbPath();

  Future<void> _pushMenu() async {
    try {
      await FlashpickPlatform.setMenuTodos(
          todos.take(20).map((t) => {'id': t.id, 'text': t.text, 'done': t.done}).toList());
    } catch (_) {}
  }

  void showMainWindow({int tab = 0}) {
    FlashpickPlatform.showMainWindow();
    if (tab != 0) {
      // 交给 UI 层监听 tab 切换
      requestedTab = tab;
      notifyListeners();
    }
  }

  int? requestedTab;
}
