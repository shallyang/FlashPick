import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'hotkey_recorder.dart';

/// 设置页：热键、镜像同步、开机自启、权限、数据位置。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      children: [
        Text('设置',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 18),

        _section(context, '全局热键', [
          HotkeyRecorder(
            label: '抓取选中文字 → 待办',
            hotkey: state.captureHotkey,
            onChanged: state.setCaptureHotkey,
          ),
          const Divider(height: 20),
          HotkeyRecorder(
            label: '打开快速捕捉窗',
            hotkey: state.panelHotkey,
            onChanged: state.setPanelHotkey,
          ),
          const SizedBox(height: 6),
          Text(
            '热键在所有应用里生效；如与其他软件冲突，请修改后重试。抓取原理是模拟 ⌘C，需要辅助功能权限。',
            style: TextStyle(fontSize: 11.5, color: colorScheme.outline),
          ),
        ]),

        _section(context, '同步', [
          if (Platform.isMacOS) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('镜像到系统提醒事项'),
              subtitle: const Text('每条待办同步写入「提醒事项」的「闪拾」清单，经 iCloud 到 iPhone'),
              value: state.mirrorEnabled,
              onChanged: (v) => state.setMirrorEnabled(v),
            ),
            const Divider(height: 8),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: false,
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('登录账号 · 跨设备云同步'),
            subtitle: const Text('Phase 2 开发中：Supabase 账号体系，登录后多端实时同步'),
            trailing: const Icon(Icons.chevron_right),
          ),
        ]),

        _section(context, '通用', [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('桌面清单'),
            subtitle: const Text('在桌面常驻显示待办小组件，可拖动、右键置顶'),
            value: state.desktopWidgetVisible,
            onChanged: (v) => state.setDesktopWidgetVisible(v),
          ),
          const Divider(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('开机自动启动'),
            value: state.autostart,
            onChanged: (v) => state.setAutostart(v),
          ),
          const Divider(height: 8),
          FutureBuilder<String>(
            future: state.dbPath(),
            builder: (context, snap) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('数据存储位置'),
              subtitle: Text(snap.data ?? '…',
                  style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
              trailing: IconButton(
                tooltip: '在资源管理器中显示',
                icon: const Icon(Icons.folder_open, size: 20),
                onPressed: snap.data == null
                    ? null
                    : () => state.revealDbFolder(snap.data!),
              ),
            ),
          ),
        ]),

        if (Platform.isMacOS)
          _section(context, '权限', [
            _permissionRow(context, state, '辅助功能（抓取选中文字）', 'accessibility'),
            _permissionRow(context, state, '麦克风（语音输入）', 'microphone'),
            _permissionRow(context, state, '语音识别', 'speech'),
            _permissionRow(context, state, '提醒事项（镜像）', 'reminders'),
          ]),

        const SizedBox(height: 8),
        Center(
          child: Text(
            '闪拾 FlashPick v1.0.0 · 开源软件（MIT）',
            style: TextStyle(fontSize: 11.5, color: colorScheme.outline),
          ),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _permissionRow(
      BuildContext context, AppState state, String label, String pane) {
    final granted = switch (pane) {
      'accessibility' => state.permissions?.accessibility,
      'microphone' => state.permissions?.microphone,
      'speech' => state.permissions?.speech,
      'reminders' => state.permissions?.reminders,
      _ => false,
    };
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            granted == true ? Icons.check_circle : Icons.error_outline,
            size: 17,
            color: granted == true ? Colors.green : colorScheme.error,
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          TextButton(
            onPressed: () => state.openPermissionSettings(pane),
            child: Text(granted == true ? '已授权' : '去授权'),
          ),
        ],
      ),
    );
  }
}
