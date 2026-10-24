// flashpick_platform — 闪拾 FlashPick 的原生平台层。
//
// 负责全局热键、选中文字抓取、快速捕捉窗（含语音识别）、
// HUD 提示、菜单栏驻留、开机自启和系统提醒事项镜像。
// 目前实现 macOS，Windows/Android/iOS/鸿蒙在路线图中。

import 'package:flutter/services.dart';

/// 一条热键定义：macOS 虚拟键码 + 修饰键。
class HotkeyDef {
  const HotkeyDef({required this.keyCode, required this.modifiers});

  /// macOS 虚拟键码（如 C=8, A=0）。
  final int keyCode;

  /// 修饰键组合：["ctrl","shift"] / ["ctrl","shift","alt"] / ["cmd",...]
  final List<String> modifiers;

  Map<String, dynamic> toMap() => {'keyCode': keyCode, 'modifiers': modifiers};

  factory HotkeyDef.fromMap(Map<Object?, Object?> map) => HotkeyDef(
        keyCode: (map['keyCode'] as num?)?.toInt() ?? 0,
        modifiers: (map['modifiers'] as List?)?.cast<String>() ?? const [],
      );

  static const captureDefault = HotkeyDef(keyCode: 8, modifiers: ['ctrl', 'shift']);
  static const panelDefault = HotkeyDef(keyCode: 0, modifiers: ['ctrl', 'shift']);

  @override
  String toString() {
    final names = {0: 'A', 8: 'C'};
    final mod = modifiers
        .map((m) => {'ctrl': '⌃', 'shift': '⇧', 'alt': '⌥', 'cmd': '⌘'}[m] ?? m)
        .join();
    return '$mod${names[keyCode] ?? 'Key$keyCode'}';
  }
}

/// 权限状态快照。
class PermissionStatus {
  const PermissionStatus({
    required this.accessibility,
    required this.microphone,
    required this.speech,
    required this.reminders,
  });

  final bool accessibility;
  final bool microphone;
  final bool speech;
  final bool reminders;

  factory PermissionStatus.fromMap(Map<Object?, Object?> map) => PermissionStatus(
        accessibility: map['accessibility'] == true,
        microphone: map['microphone'] == true,
        speech: map['speech'] == true,
        reminders: map['reminders'] == true,
      );

  bool get allGranted => accessibility && microphone && speech && reminders;
}

/// 原生 → Dart 回调。
class PlatformCallbacks {
  const PlatformCallbacks({
    this.onCaptured,
    this.onPanelSubmit,
    this.onMenuAction,
  });

  /// 全局热键抓到了文字。source: "selection"（选中文本）或 "clipboard"（回退剪贴板）。
  final void Function(String text, String source)? onCaptured;

  /// 快速捕捉窗提交了文字。
  final void Function(String text)? onPanelSubmit;

  /// 菜单栏动作。action: capture / main / settings / quit / toggle，todoId 仅 toggle 有值。
  final void Function(String action, String? todoId)? onMenuAction;
}

class FlashpickPlatform {
  FlashpickPlatform._();

  static const _channel = MethodChannel('dev.flashpick/platform');
  static PlatformCallbacks? _callbacks;

  /// 注册回调并完成原生侧初始化（热键注册、菜单栏图标）。
  static Future<void> init(PlatformCallbacks callbacks, HotkeyDef capture, HotkeyDef panel) async {
    _callbacks = callbacks;
    _channel.setMethodCallHandler((call) async {
      final args = (call.arguments as Map?)?.cast<Object?, Object?>();
      switch (call.method) {
        case 'onCaptured':
          _callbacks?.onCaptured?.call(
            (args?['text'] as String?) ?? '',
            (args?['source'] as String?) ?? 'selection',
          );
          break;
        case 'onPanelSubmit':
          _callbacks?.onPanelSubmit?.call((args?['text'] as String?) ?? '');
          break;
        case 'onMenuAction':
          _callbacks?.onMenuAction?.call(
            (args?['action'] as String?) ?? '',
            args?['todoId'] as String?,
          );
          break;
      }
      return null;
    });
    await _channel.invokeMethod('init', {
      'captureHotkey': capture.toMap(),
      'panelHotkey': panel.toMap(),
    });
  }

  /// 更新全局热键。
  static Future<bool> updateHotkeys(HotkeyDef capture, HotkeyDef panel) async =>
      await _channel.invokeMethod('updateHotkeys', {
        'captureHotkey': capture.toMap(),
        'panelHotkey': panel.toMap(),
      }) == true;

  /// 推送待办快照给菜单栏（最多显示前若干条）。
  static Future<void> setMenuTodos(List<Map<String, Object?>> todos) =>
      _channel.invokeMethod('setMenuTodos', todos);

  /// 显示 HUD 轻提示。
  static Future<void> showHud(String text) => _channel.invokeMethod('showHud', {'text': text});

  /// 打开快速捕捉窗。
  static Future<void> showPanel() => _channel.invokeMethod('showPanel');

  /// 手动触发一次"抓取选中文字"（热键同款链路，测试用）。
  static Future<(String?, String)> captureSelection() async {
    final r = await _channel.invokeMethod('captureSelection');
    final map = (r as Map?)?.cast<Object?, Object?>();
    return ((map?['text'] as String?), (map?['source'] as String?) ?? '');
  }

  static Future<PermissionStatus> permissions() async {
    final r = await _channel.invokeMethod('permissions');
    return PermissionStatus.fromMap((r as Map).cast<Object?, Object?>());
  }

  /// 请求辅助功能权限（弹出系统引导窗）。
  static Future<void> requestAccessibility() => _channel.invokeMethod('requestAccessibility');

  /// 请求麦克风 + 语音识别 + 提醒事项权限。
  static Future<void> requestRuntimePermissions() =>
      _channel.invokeMethod('requestRuntimePermissions');

  static Future<void> openSystemSettings(String pane) =>
      _channel.invokeMethod('openSystemSettings', {'pane': pane});

  static Future<bool> setAutostart(bool enabled) async =>
      await _channel.invokeMethod('setAutostart', {'enabled': enabled}) == true;

  static Future<bool> isAutostart() async =>
      await _channel.invokeMethod('isAutostart') == true;

  /// 镜像一条待办到系统提醒事项的"闪拾"清单，返回 EventKit externalID（失败返回 null）。
  static Future<String?> mirrorTodo(String localId, String text) async {
    final r = await _channel.invokeMethod('mirrorTodo', {
      'id': localId,
      'text': text,
    });
    return (r as Map?)?['ekId'] as String?;
  }

  static Future<void> setMirrorCompleted(String ekId, bool completed) =>
      _channel.invokeMethod('setMirrorCompleted', {'ekId': ekId, 'completed': completed});

  static Future<void> deleteMirror(String ekId) =>
      _channel.invokeMethod('deleteMirror', {'ekId': ekId});

  /// 激活并显示 Flutter 主窗口（从菜单栏唤起用）。
  static Future<void> showMainWindow() => _channel.invokeMethod('showMainWindow');

  static Future<void> quitApp() => _channel.invokeMethod('quitApp');

  /// 显示/隐藏桌面清单小组件。
  static Future<void> setWidgetVisible(bool visible) =>
      _channel.invokeMethod('setWidgetVisible', {'visible': visible});
}
