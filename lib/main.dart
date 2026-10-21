import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'package:flashpick_platform/flashpick_platform.dart';

import 'app_state.dart';
import 'ui/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final state = AppState();
  // 后台启动（菜单栏驻留）；调试模式或首启时再唤起主窗口
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: '闪拾 FlashPick',
      size: Size(880, 620),
      minimumSize: Size(520, 420),
      center: true,
      titleBarStyle: TitleBarStyle.normal,
    ),
    () async {
      await state.bootstrap();
      if (kDebugMode || state.firstRun) {
        await FlashpickPlatform.showMainWindow();
      }
    },
  );

  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const FlashpickApp(),
    ),
  );
}

class FlashpickApp extends StatefulWidget {
  const FlashpickApp({super.key});

  @override
  State<FlashpickApp> createState() => _FlashpickAppState();
}

class _FlashpickAppState extends State<FlashpickApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // 点关闭 = 隐藏到菜单栏，不退出
    windowManager.setPreventClose(true);
  }

  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '闪拾 FlashPick',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D7EFF)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3D7EFF), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}
