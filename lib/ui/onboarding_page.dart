import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

/// 首启引导：三步认识闪拾 + 权限引导 + 开始使用。
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final colorScheme = Theme.of(context).colorScheme;
    final perms = state.permissions;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: Color(0xFF3D7EFF),
                  child: Icon(Icons.bolt, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('欢迎使用闪拾 FlashPick',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const Text('选中文字，一键变待办',
                        style: TextStyle(fontSize: 13, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 26),
            _step(context, '1', '热键抓取',
                '在任何应用里选中文字，按 ${state.captureHotkey} 直接收进闪拾，全程零弹窗。'),
            _step(context, '2', '语音速记',
                '按 ${state.panelHotkey} 打开捕捉窗，按住麦克风说中文，松开自动转成文字。'),
            _step(context, '3', '自动同步 iPhone',
                '待办会镜像到系统「提醒事项」的「闪拾」清单，经 iCloud 出现在手机上（可在设置中关闭）。'),
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('授权（都是本地权限，不联网）',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  _permRow(context, '辅助功能 — 抓取选中文字必需',
                      perms?.accessibility == true, 'accessibility'),
                  _permRow(context, '麦克风 + 语音识别 — 语音速记必需',
                      perms?.microphone == true && perms?.speech == true, 'runtime'),
                  _permRow(context, '提醒事项 — 镜像同步必需',
                      perms?.reminders == true, 'reminders'),
                ],
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () async {
                  await state.finishFirstRun();
                  await state.refreshTodos();
                },
                child: const Text('开始使用（闪拾会驻留在菜单栏）'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(
      BuildContext context, String n, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(n,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color:
                        Theme.of(context).colorScheme.onPrimaryContainer)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(desc,
                    style: const TextStyle(fontSize: 12.5, color: Colors.grey),
              )],
            ),
          ),
        ],
      ),
    );
  }

  Widget _permRow(BuildContext context, String label, bool granted, String pane) {
    final state = context.read<AppState>();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(granted ? Icons.check_circle : Icons.circle_outlined,
              size: 17, color: granted ? Colors.green : Colors.grey),
          const SizedBox(width: 9),
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 12.5))),
          TextButton(
            onPressed: granted ? null : () => state.openPermissionSettings(pane),
            child: Text(granted ? '已授权' : '去授权'),
          ),
        ],
      ),
    );
  }
}
