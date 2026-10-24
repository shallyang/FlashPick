import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../store.dart';

const _sourceLabels = {
  'hotkey': '热键',
  'panel': '捕捉窗',
  'widget': '组件',
  'clipboard': '剪贴板',
  'menu': '菜单',
};

/// 待办列表页：搜索、勾选、删除、手动速记。
class ListPage extends StatelessWidget {
  const ListPage({super.key});

  String _timeLabel(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1 && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final todos = state.visibleTodos;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('待办',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${state.pendingCount} 项进行中',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onPrimaryContainer)),
              ),
              const Spacer(),
              IconButton(
                tooltip: '显示/隐藏已完成',
                isSelected: state.showDone,
                onPressed: () => state.setShowDone(!state.showDone),
                icon: const Icon(Icons.visibility_outlined),
                selectedIcon: const Icon(Icons.visibility),
              ),
              const SizedBox(width: 4),
              FilledButton.tonalIcon(
                onPressed: () => state.showQuickCapture(),
                icon: const Icon(Icons.edit_note),
                label: const Text('速记'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            onChanged: state.setKeyword,
            decoration: InputDecoration(
              hintText: '搜索待办…',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: todos.isEmpty
                ? _EmptyView(showDone: state.showDone)
                : ListView.separated(
                    itemCount: todos.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, i) {
                      final todo = todos[i];
                      return _TodoTile(
                        todo: todo,
                        timeLabel: _timeLabel(todo.createdAt),
                        onToggle: () => state.setDone(todo.id, !todo.done),
                        onDelete: () => state.remove(todo.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.showDone});

  final bool showDone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 52, color: Theme.of(context).disabledColor),
          const SizedBox(height: 10),
          Text(showDone ? '没有待办' : '暂无进行中的待办',
              style: TextStyle(color: Theme.of(context).disabledColor)),
          const SizedBox(height: 6),
          Text('在任意应用里选中文字，按热键一键收进闪拾',
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).disabledColor)),
        ],
      ),
    );
  }
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({
    required this.todo,
    required this.timeLabel,
    required this.onToggle,
    required this.onDelete,
  });

  final Todo todo;
  final String timeLabel;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: todo.done, onChanged: (_) => onToggle()),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  SelectableText(
                    todo.text,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      decoration:
                          todo.done ? TextDecoration.lineThrough : null,
                      color: todo.done ? colorScheme.outline : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _chip(context, _sourceLabels[todo.source] ?? todo.source),
                      if (todo.mirrorId != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _chip(context, '已镜像', tinted: true),
                        ),
                      const SizedBox(width: 6),
                      Text(timeLabel,
                          style: TextStyle(
                              fontSize: 11, color: colorScheme.outline)),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline,
                  size: 18, color: colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, {bool tinted = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: tinted
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              color: tinted
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.outline)),
    );
  }
}
