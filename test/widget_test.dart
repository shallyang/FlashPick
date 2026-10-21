import 'package:flutter_test/flutter_test.dart';

import 'package:flashpick/store.dart';
import 'package:flashpick_platform/flashpick_platform.dart';

void main() {
  test('HotkeyDef 序列化往返', () {
    const hk = HotkeyDef(keyCode: 8, modifiers: ['ctrl', 'shift']);
    final map = hk.toMap();
    final back = HotkeyDef.fromMap(
        (map.map((k, v) => MapEntry<Object?, Object?>(k, v))));
    expect(back.keyCode, 8);
    expect(back.modifiers, ['ctrl', 'shift']);
    expect(hk.toString(), '⌃⇧C');
  });

  test('Todo 行映射', () {
    final todo = Todo(
      id: 't1',
      text: 'hello',
      createdAt: 100,
      updatedAt: 100,
    );
    final row = todo.toRow();
    final back = Todo.fromRow(row);
    expect(back.id, 't1');
    expect(back.text, 'hello');
    expect(back.done, false);
    expect(back.source, 'hotkey');
  });
}
