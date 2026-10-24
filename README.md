# 闪拾 FlashPick

> 选中文字，一键变待办。

闪拾是一款**本地优先**的速记待办工具：在任何应用里选中文字，按一下全局热键（默认 `⌃⇧C`），这段文字就变成一条待办——**零弹窗、不打断**。也支持按住麦克风**语音速记**（设备端中文识别）。不登录任何账号即可使用全部功能；每条待办可镜像写入系统「提醒事项」，经 iCloud 自动出现在 iPhone 上。

## 核心特性

| 特性 | 说明 |
| --- | --- |
| ⚡ 全局热键抓取 | 任意应用选中文字 → `⌃⇧C` → 直接入库，顶部 HUD 轻提示 |
| 🎙️ 语音速记 | `⌃⇧A` 呼出捕捉窗，按住麦克风说中文，SFSpeechRecognizer 设备端识别 |
| 🧷 剪贴板回退 | 无选中文字时自动读取剪贴板（HUD 会注明来源） |
| 📋 菜单栏驻留 | 常驻菜单栏，最近待办直接勾选完成；主窗口按需唤起 |
| 🖥️ 桌面清单小组件 | 半透明待办小组件常驻桌面：实时刷新、圆圈点击完成、可拖动、右键置顶/关闭 |
| ☁️ 提醒事项镜像 | 写入「提醒事项」的「闪拾」清单 → iCloud 同步 iPhone（可关闭） |
| 🔒 本地优先 | SQLite 本地存储，无需注册/登录；登录云同步在路线图中 |
| ⌨️ 热键可自定义 | 设置页按下新组合键即可更换（⌃/⇧/⌥/⌘ + 字母/数字） |
| 🚀 开机自启 | 系统登录项（SMAppService），重启后自动驻留菜单栏 |

## 平台支持

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| macOS 13+ | ✅ 功能完整 | 热键抓取 / 语音速记 / 菜单栏 / 桌面清单 / 提醒事项镜像 / 开机自启 |
| Windows 10+ | 🚧 核心可用 | 热键抓取 / 文字速记窗 / 托盘+气泡 / 开机自启；语音与桌面清单开发中；无系统提醒事项，跨设备同步等 Phase 2 云同步 |
| Android / iOS | 📅 计划 | Flutter 单代码库，语音与镜像走各平台系统 API |
| HarmonyOS | 📅 计划 | 接入 [flutter-ohos](https://gitee.com/openharmony-sig/flutter_flutter) 分支 |

### 在 Windows 上构建

```powershell
flutter pub get
flutter build windows --release
# 产物：build\windows\x64\runner\Release\ 整个目录（含 flashpick.exe 与 DLL）
```

要求：Visual Studio 2022（含 C++ 桌面开发工作负载）。或直接推送仓库到 GitHub，CI（`.github/workflows/build-windows.yml`）自动产出 exe。

Windows 实现说明：热键走 `RegisterHotKey`，抓取走 `SendInput ^C` + 剪贴板序列号探测（同样等待修饰键释放、同样保留并恢复剪贴板全部格式），HUD 为托盘气泡通知，自启写 HKCU Run 注册表。抓取不需要额外授权（Windows 无辅助功能门槛），但以管理员权限运行的目标窗口可能拒绝合成按键。

## 从源码构建（macOS）

```bash
git clone <本仓库>
cd flashpick

# 国内网络建议先配置镜像（已配置可跳过）
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

flutter pub get
flutter build macos --release        # 或直接 ./scripts/build-macos.sh
open build/macos/Build/Products/Release/flashpick.app
```

要求：Flutter 3.47+（stable）、Xcode 15+（含命令行工具）、CocoaPods。

首次启动会弹出引导页，请按需授权：

- **辅助功能**：热键抓取选中文字的必需权限（模拟 ⌘C 并读剪贴板，随后恢复原剪贴板内容）
- **麦克风 + 语音识别**：语音速记必需，识别优先在设备端完成
- **提醒事项**：镜像同步必需

> 抓取原理：暂存剪贴板 → 模拟 ⌘C → 读取新内容 → 恢复剪贴板。个别安全要求极高的应用（如密码管理器）可能拒绝复制，此时回退读取剪贴板并在 HUD 注明。
>
> 本地构建为 ad-hoc 签名：每次重新编译后系统会视为新应用，需要重新授权一次辅助功能。日常使用请固定运行 `/Applications` 里的那一份。

## 使用

1. **热键抓取**：任意应用选中文字 → `⌃⇧C`，顶部弹出「已收进闪拾」
2. **快速捕捉窗**：`⌃⇧A`，输入文字或按住麦克风说话，回车保存
3. **菜单栏**：点击菜单栏清单图标，勾选/查看最近待办、打开主窗口、开关桌面清单
4. **桌面清单**：待办实时显示在桌面角落的半透明小组件上，圆圈点击即完成，双击文字打开主窗口，拖动任意摆放（位置自动记住），右键可置顶或关闭
5. **主窗口**：搜索、勾选、删除；设置页可改热键、关镜像、开自启

## 项目结构

```
flashpick/
├── lib/                          # Flutter 应用（UI / 状态 / 本地存储）
│   ├── store.dart                #   SQLite 数据层（todos + settings）
│   ├── app_state.dart            #   全局状态，桥接原生回调
│   └── ui/                       #   列表页 / 设置页 / 首启引导 / 热键录制
├── packages/flashpick_platform/  # 原生平台层插件（跨平台接入点）
│   ├── lib/                      #   Dart API（MethodChannel 封装）
│   └── macos/                    #   Swift：热键/抓取/语音/HUD/菜单栏/EventKit/自启
├── supabase/schema.sql           # 云同步库表设计（Phase 2）
├── scripts/build-macos.sh        # 一键构建并安装到 /Applications
└── .github/workflows/            # CI：Windows exe / Android apk 自动构建
```

## 路线图

- [ ] **Phase 2 · 云同步**：Supabase 账号体系（auth + todos 表 + RLS + realtime），登录后多端实时同步，冲突策略 updated_at LWW；库表见 [`supabase/schema.sql`](supabase/schema.sql)
- [x] **Windows**：C++ 原生层（RegisterHotKey / SendInput ^C / 托盘 / 气泡 HUD / 速记窗 / HKCU Run 自启），GitHub Actions 出 exe（Windows 语音速记、桌面清单为后续项）
- [ ] **iOS / Android**：移动端语音（speech_to_text）、桌面镜像对应（Google Tasks / 系统日历）
- [ ] **HarmonyOS**：接入 flutter-ohos，DevEco 出 hap
- [ ] 应用图标与启动渲染资源
- [ ] 待办置顶 / 备注 / 标签

## 设计决策 FAQ

**为什么"登录才能云同步"？** 跨设备同步必须经过云端，这是物理约束。闪拾把选择权给你：不登录 = 纯本地 + 提醒事项镜像（经系统 iCloud，不经我们的服务器）；登录（Phase 2）= 官方云同步（Supabase，开源可自托管）。

**为什么要关沙盒？** 抓取选中文字需要模拟 ⌘C（辅助功能权限），沙盒应用无法获得该权限。闪拾不上架 App Store、不经手你的任何数据，权限边界就是系统弹窗里那几项。

**热键冲突了怎么办？** 设置页随意换键；Carbon 全局热键优先级高，若与其他软件冲突请二选一。

**为什么主窗口启动时不显示？** 闪拾是菜单栏应用，启动即驻留后台。实现上窗口以 alpha=0 完成首帧后隐藏（不能吞掉 `order` 调用，否则 Flutter 引擎不会启动——这是我们踩过的坑）。

## 贡献

欢迎 Issue / PR。提交前请跑 `flutter analyze` 与 `flutter test`。

## License

[MIT](LICENSE)
