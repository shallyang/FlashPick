# FlashPick

[简体中文](README.md) | English

> Select text, turn it into a todo — in one keystroke.

FlashPick is a **local-first** quick-capture todo app: select any text in any app, press a global hotkey (default `⌃⇧C` / `Ctrl+Shift+C`), and that text becomes a todo — **no window, no interruption**. You can also hold the microphone button and **dictate** (on-device Chinese speech recognition). Every feature works without an account; todos can optionally be mirrored into the system Reminders app so they show up on your iPhone via iCloud.

## Features

| Feature | Description |
| --- | --- |
| ⚡ Hotkey capture | Select text anywhere → `⌃⇧C` → instantly saved, with a subtle HUD notification |
| 🎙️ Voice capture (macOS) | `⌃⇧A` opens the capture window — hold the mic and speak Chinese, on-device recognition via SFSpeechRecognizer |
| 🧷 Clipboard fallback | With no selection, the current clipboard content is captured instead (noted in the HUD) |
| 📋 Menu bar / tray | Lives in the menu bar (macOS) or system tray (Windows); check off recent todos directly |
| 🖥️ Desktop widget | A translucent todo widget pinned to your desktop: live refresh, click-to-complete, a built-in quick-add input (type + Enter), draggable, right-click to pin/close |
| ☁️ Reminders mirror (macOS) | Todos are mirrored to a "闪拾 (FlashPick)" list in Apple Reminders → synced to iPhone via iCloud (can be disabled) |
| 🔒 Local-first | SQLite storage on your machine; no account or login required (cloud sync is on the roadmap) |
| ⌨️ Custom hotkeys | Rebind freely in Settings (⌃/⇧/⌥/⌘ or Ctrl/Shift/Alt/Win + letters/digits) |
| 🚀 Launch at login | Supported on both platforms (SMAppService on macOS, HKCU Run on Windows) |

## Platform Support

| Platform | Status | Notes |
| --- | --- | --- |
| macOS 13+ | ✅ Full | Hotkey capture / voice / menu bar / desktop widget / Reminders mirror / launch at login |
| Windows 10+ | 🚧 Core features | Hotkey capture / text capture window / tray + balloon / **desktop widget** / launch at login; voice capture in progress; no system Reminders on Windows — cross-device sync arrives with Phase 2 cloud sync |
| Android / iOS | 📅 Planned | Single Flutter codebase; voice and mirroring via each platform's system APIs |
| HarmonyOS | 📅 Planned | Via the [flutter-ohos](https://gitee.com/openharmony-sig/flutter_flutter) fork |

### Building on Windows

```powershell
flutter pub get
flutter build windows --release
# Output: the entire build\windows\x64\runner\Release\ folder (flashpick.exe + DLLs)
```

Requires Visual Studio 2022 (with the Desktop development with C++ workload). Alternatively, just push the repo to GitHub — CI (`.github/workflows/build-windows.yml`) builds the exe automatically.

Windows implementation notes: hotkeys use `RegisterHotKey`; selection capture uses `SendInput ^C` plus clipboard sequence-number detection (with the same modifier-release wait and full clipboard backup/restore); the HUD is a tray balloon; autostart writes to the HKCU Run registry key. No extra permission is needed for capture (Windows has no Accessibility gate), but applications running elevated as administrator may reject synthetic keystrokes.

### Building on macOS

```bash
git clone https://github.com/shallyang/FlashPick.git
cd flashpick

# Mirror setup for networks in China (skip if already configured)
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

flutter pub get
flutter build macos --release        # or simply ./scripts/build-macos.sh
open build/macos/Build/Products/Release/flashpick.app
```

Requires: Flutter 3.47+ (stable), Xcode 15+ (with command-line tools), CocoaPods.

On first launch a guide window appears; grant permissions as needed:

- **Accessibility**: required for capturing selected text (simulates ⌘C, reads the clipboard, then restores it)
- **Microphone + Speech Recognition**: required for voice capture; recognition runs on-device when available
- **Reminders**: required for the mirror

> How capture works: back up the clipboard → simulate ⌘C → read the new content → restore the clipboard. A few hardened apps (e.g. password managers) may refuse to copy; FlashPick then falls back to the clipboard and says so in the HUD.
>
> Local builds are ad-hoc signed: after each rebuild, macOS treats the app as new and asks you to re-grant Accessibility once. For daily use, keep running the copy in `/Applications`.

## Usage

1. **Hotkey capture**: select text in any app → `⌃⇧C` — a "captured" HUD appears at the top of the screen
2. **Capture window**: `⌃⇧A` — type, or hold the mic and speak (macOS), press Enter to save
3. **Menu bar / tray**: click the checklist icon for recent todos, the main window, settings, and the desktop-widget toggle
4. **Desktop widget**: todos are shown live on a translucent widget; click the circle to complete, double-click text to open the main window, drag anywhere (position is remembered), right-click to pin or close; type in the input box at the bottom and press Enter to add a todo (macOS & Windows)
5. **Main window**: search, check off, delete; Settings has hotkey rebinding, mirror toggle, autostart

## Project Structure

```
flashpick/
├── lib/                          # Flutter app (UI / state / local storage)
│   ├── store.dart                #   SQLite data layer (todos + settings)
│   ├── app_state.dart            #   Global state, bridges native callbacks
│   └── ui/                       #   List page / settings / onboarding / hotkey recorder
├── packages/flashpick_platform/  # Native platform plugin (cross-platform entry)
│   ├── lib/                      #   Dart API (MethodChannel wrapper)
│   ├── macos/                    #   Swift: hotkey/capture/voice/HUD/menu bar/EventKit/autostart
│   └── windows/                  #   C++: hotkey/capture/tray/balloon/panel/widget/registry
├── supabase/schema.sql           # Cloud-sync schema (Phase 2)
├── scripts/build-macos.sh        # One-command build & install to /Applications
└── .github/workflows/            # CI: Windows exe / Android apk auto-builds
```

## Roadmap

- [ ] **Phase 2 · Cloud sync**: Supabase account system (auth + todos table + RLS + realtime); sign in for real-time multi-device sync with last-write-wins on `updated_at`; schema in [`supabase/schema.sql`](supabase/schema.sql)
- [x] **Windows**: C++ native layer (RegisterHotKey / SendInput ^C / tray / balloon HUD / capture window / desktop widget / HKCU Run autostart); exe built by GitHub Actions (voice capture to follow)
- [ ] **iOS / Android**: mobile voice (speech_to_text), platform-appropriate mirroring (Google Tasks / system calendar)
- [ ] **HarmonyOS**: integrate flutter-ohos, produce .hap via DevEco
- [ ] App icon and launch assets
- [ ] Todo pinning / notes / tags

## Design FAQ

**Why does cloud sync require signing in?** Cross-device sync must go through a server — that's physics. FlashPick gives you the choice: stay signed out = purely local + Reminders mirror (via system iCloud, never our servers); sign in (Phase 2) = official cloud sync (Supabase, open source and self-hostable).

**Why is the sandbox off?** Capturing selected text requires simulating ⌘C (Accessibility permission), which sandboxed apps cannot obtain. FlashPick is not distributed on the App Store and never touches your data — the permission surface is exactly what the system prompts show.

**My hotkey conflicts with another app.** Rebind it in Settings; global hotkeys are pre-emptive, so pick one winner per combination.

**Why doesn't the main window show at launch?** FlashPick is a menu-bar app and stays in the background. On macOS the window completes its first frame with alpha=0 and then hides (you cannot swallow `order()` calls — that prevents the Flutter engine from starting; a lesson we learned the hard way).

## Contributing

Issues and PRs are welcome. Please run `flutter analyze` and `flutter test` before submitting.

## License

[MIT](LICENSE)
