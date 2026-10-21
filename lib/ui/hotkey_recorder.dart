import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flashpick_platform/flashpick_platform.dart';

/// USB HID usage → macOS 虚拟键码（常用按键）。
const _hidToMac = <int, int>{
  0x04: 0x00, // a
  0x05: 0x0B, // b
  0x06: 0x08, // c
  0x07: 0x02, // d
  0x08: 0x0E, // e
  0x09: 0x03, // f
  0x0A: 0x05, // g
  0x0B: 0x04, // h
  0x0C: 0x22, // i
  0x0D: 0x26, // j
  0x0E: 0x28, // k
  0x0F: 0x25, // l
  0x10: 0x2E, // m
  0x11: 0x2D, // n
  0x12: 0x1F, // o
  0x13: 0x23, // p
  0x14: 0x0C, // q
  0x15: 0x0F, // r
  0x16: 0x01, // s
  0x17: 0x11, // t
  0x18: 0x20, // u
  0x19: 0x09, // v
  0x1A: 0x0D, // w
  0x1B: 0x07, // x
  0x1C: 0x10, // y
  0x1D: 0x06, // z
  0x1E: 0x12, // 1
  0x1F: 0x13, // 2
  0x20: 0x14, // 3
  0x21: 0x15, // 4
  0x22: 0x17, // 5
  0x23: 0x16, // 6
  0x24: 0x1A, // 7
  0x25: 0x1C, // 8
  0x26: 0x19, // 9
  0x27: 0x1D, // 0
  0x2C: 0x31, // space
};

/// 热键录制控件：点击"修改"后按下新组合键。
class HotkeyRecorder extends StatefulWidget {
  const HotkeyRecorder({
    super.key,
    required this.label,
    required this.hotkey,
    required this.onChanged,
  });

  final String label;
  final HotkeyDef hotkey;
  final ValueChanged<HotkeyDef> onChanged;

  @override
  State<HotkeyRecorder> createState() => _HotkeyRecorderState();
}

class _HotkeyRecorderState extends State<HotkeyRecorder> {
  bool _armed = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 200,
          child: Text(widget.label,
              style: const TextStyle(fontSize: 13.5)),
        ),
        _armed
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.primary, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('按下新组合键…（Esc 取消）',
                    style: TextStyle(
                        fontSize: 13, color: colorScheme.primary)),
              )
            : Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(widget.hotkey.toString(),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
        const SizedBox(width: 10),
        if (_error != null)
          Expanded(
            child: Text(_error!,
                style: TextStyle(fontSize: 11.5, color: colorScheme.error)),
          )
        else
          const Spacer(),
        TextButton(
          onPressed: () {
            setState(() {
              _armed = !_armed;
              _error = null;
            });
          },
          child: Text(_armed ? '取消' : '修改'),
        ),
        if (_armed)
          Focus(
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                setState(() => _armed = false);
                return KeyEventResult.handled;
              }
              final macCode = _hidToMac[event.physicalKey.usbHidUsage];
              if (macCode == null) {
                setState(() => _error = '不支持的按键，请换字母/数字键');
                return KeyEventResult.handled;
              }
              final pressed = HardwareKeyboard.instance.logicalKeysPressed;
              final mods = <String>[
                if (pressed.any((k) =>
                    k == LogicalKeyboardKey.controlLeft ||
                    k == LogicalKeyboardKey.controlRight))
                  'ctrl',
                if (pressed.any((k) =>
                    k == LogicalKeyboardKey.shiftLeft ||
                    k == LogicalKeyboardKey.shiftRight))
                  'shift',
                if (pressed.any((k) =>
                    k == LogicalKeyboardKey.altLeft ||
                    k == LogicalKeyboardKey.altRight))
                  'alt',
                if (pressed.any((k) =>
                    k == LogicalKeyboardKey.metaLeft ||
                    k == LogicalKeyboardKey.metaRight))
                  'cmd',
              ];
              if (mods.isEmpty) {
                setState(() => _error = '需要至少一个修饰键（⌃/⇧/⌥/⌘）');
                return KeyEventResult.handled;
              }
              setState(() {
                _armed = false;
                _error = null;
              });
              widget.onChanged(HotkeyDef(keyCode: macCode, modifiers: mods));
              return KeyEventResult.handled;
            },
            child: const SizedBox.expand(),
          ),
      ],
    );
  }
}
