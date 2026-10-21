import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'list_page.dart';
import 'onboarding_page.dart';
import 'settings_page.dart';

/// 主窗口外壳：待办 / 设置 两个标签页；首启先显示引导。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _state.addListener(_onStateChanged);
  }

  late final AppState _state;

  void _onStateChanged() {
    if (_state.requestedTab != null && _state.requestedTab != _tab) {
      setState(() => _tab = _state.requestedTab!);
      _state.requestedTab = null;
    }
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(0xFF3D7EFF),
                  child: Icon(Icons.bolt, color: Colors.white, size: 20),
                ),
              ]),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.checklist),
                label: Text('待办'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('设置'),
              ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: state.firstRun
                ? const OnboardingPage()
                : _tab == 0
                    ? const ListPage()
                    : const SettingsPage(),
          ),
        ],
      ),
    );
  }
}
