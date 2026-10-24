#include "win_features.h"

#include <commctrl.h>
#include <shellapi.h>
#include <shlobj.h>
#include <wctype.h>

#include <algorithm>

namespace flashpick_platform {

namespace {

constexpr UINT kTrayCallback = WM_APP + 1;
constexpr int kTrayIconId = 1;
constexpr int kHotkeyCaptureId = 1;
constexpr int kHotkeyPanelId = 2;
constexpr UINT kGrabTimerId = 2;

WinFeatures* g_instance = nullptr;

std::string TrimCopy(const std::string& s) {
  size_t b = s.find_first_not_of(" \t\r\n");
  if (b == std::string::npos) return "";
  size_t e = s.find_last_not_of(" \t\r\n");
  return s.substr(b, e - b + 1);
}

// ---- 剪贴板备份/恢复（尽力保留全部格式，延迟渲染的格式会被跳过）----

struct SavedFormat {
  UINT format;
  std::vector<BYTE> bytes;
};

bool SaveClipboard(std::vector<SavedFormat>& out) {
  if (!OpenClipboard(nullptr)) return false;
  out.clear();
  UINT fmt = 0;
  std::vector<UINT> formats;
  while ((fmt = EnumClipboardFormats(fmt)) != 0) {
    formats.push_back(fmt);
  }
  for (UINT f : formats) {
    HANDLE h = GetClipboardData(f);
    if (!h) continue;  // 延迟渲染/私有格式，跳过
    SIZE_T size = GlobalSize(h);
    void* p = GlobalLock(h);
    if (!p) continue;
    SavedFormat sf;
    sf.format = f;
    sf.bytes.resize(size);
    memcpy(sf.bytes.data(), p, size);
    GlobalUnlock(h);
    out.push_back(std::move(sf));
  }
  CloseClipboard();
  return true;
}

void RestoreClipboard(const std::vector<SavedFormat>& saved) {
  int attempts = 0;
  while (!OpenClipboard(nullptr) && attempts < 20) {
    Sleep(10);
    attempts++;
  }
  if (attempts >= 20) return;
  EmptyClipboard();
  for (const auto& sf : saved) {
    SIZE_T size = sf.bytes.size();
    HANDLE h = GlobalAlloc(GMEM_MOVEABLE, size ? size : 1);
    if (!h) continue;
    void* p = GlobalLock(h);
    if (p) {
      if (size) memcpy(p, sf.bytes.data(), size);
      GlobalUnlock(h);
      SetClipboardData(sf.format, h);  // 失败则系统回收
    } else {
      GlobalFree(h);
    }
  }
  CloseClipboard();
}

std::string ReadClipboardText() {
  int attempts = 0;
  while (!OpenClipboard(nullptr) && attempts < 20) {
    Sleep(10);
    attempts++;
  }
  if (attempts >= 20) return "";
  std::string result;
  if (IsClipboardFormatAvailable(CF_UNICODETEXT)) {
    HANDLE h = GetClipboardData(CF_UNICODETEXT);
    if (h) {
      void* p = GlobalLock(h);
      if (p) {
        const wchar_t* ws = static_cast<const wchar_t*>(p);
        SIZE_T bytes = GlobalSize(h);
        size_t chars = bytes / sizeof(wchar_t);
        std::wstring w(ws, chars);
        while (!w.empty() && (w.back() == L'\0')) w.pop_back();
        result = WideToUtf8(w);
        GlobalUnlock(h);
      }
    }
  }
  CloseClipboard();
  return TrimCopy(result);
}

void SendCtrlC() {
  INPUT inputs[4] = {};
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_CONTROL;
  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = 'C';
  inputs[2].type = INPUT_KEYBOARD;
  inputs[2].ki.wVk = 'C';
  inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;
  inputs[3].type = INPUT_KEYBOARD;
  inputs[3].ki.wVk = VK_CONTROL;
  inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;
  SendInput(4, inputs, sizeof(INPUT));
}

bool AnyModifierDown() {
  return (GetAsyncKeyState(VK_CONTROL) & 0x8000) ||
         (GetAsyncKeyState(VK_SHIFT) & 0x8000) ||
         (GetAsyncKeyState(VK_MENU) & 0x8000) ||
         (GetAsyncKeyState(VK_LWIN) & 0x8000) ||
         (GetAsyncKeyState(VK_RWIN) & 0x8000);
}

void WaitModifierRelease(int timeout_ms = 400) {
  ULONGLONG deadline = GetTickCount64() + timeout_ms;
  while (GetTickCount64() < deadline) {
    if (!AnyModifierDown()) {
      Sleep(30);
      return;
    }
    Sleep(8);
  }
}

}  // namespace

// ---- 编码转换 ----

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0);
  std::wstring w(n, 0);
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &w[0], n);
  return w;
}

std::string WideToUtf8(const std::wstring& w) {
  if (w.empty()) return std::string();
  int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), nullptr, 0,
                              nullptr, nullptr);
  std::string s(n, 0);
  WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), &s[0], n, nullptr,
                      nullptr);
  return s;
}

// ---- 初始化 / 窗口 ----

void WinFeatures::Init(HWND flutter_view) {
  flutter_view_ = flutter_view;
  g_instance = this;
  EnsureHostWindow();
}

void WinFeatures::Shutdown() {
  if (tray_added_ && host_) {
    NOTIFYICONDATAW nid = {};
    nid.cbSize = sizeof(nid);
    nid.uID = kTrayIconId;
    nid.hWnd = host_;
    Shell_NotifyIconW(NIM_DELETE, &nid);
    tray_added_ = false;
  }
  if (g_instance == this) g_instance = nullptr;
}

void WinFeatures::EnsureHostWindow() {
  if (host_) return;
  WNDCLASSW wc = {};
  wc.lpfnWndProc = &WinFeatures::WndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = L"FlashpickHostWindow";
  RegisterClassW(&wc);
  host_ = CreateWindowExW(0, L"FlashpickHostWindow", L"FlashPick Host",
                          WS_OVERLAPPED, CW_USEDEFAULT, CW_USEDEFAULT, 100, 100,
                          nullptr, nullptr, GetModuleHandle(nullptr), nullptr);
  // 托盘图标（隐藏窗口可正常接收回调）
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = host_;
  nid.uID = kTrayIconId;
  nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  nid.uCallbackMessage = kTrayCallback;
  nid.hIcon = LoadIconW(nullptr, (LPCWSTR)IDI_APPLICATION);
  wcscpy_s(nid.szTip, L"闪拾 FlashPick");
  tray_added_ = Shell_NotifyIconW(NIM_ADD, &nid) == TRUE;
}

LRESULT CALLBACK WinFeatures::WndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                      LPARAM lparam) {
  if (g_instance) {
    return g_instance->HandleMessage(hwnd, msg, wparam, lparam);
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

LRESULT WinFeatures::HandleMessage(HWND hwnd, UINT msg, WPARAM wparam,
                                   LPARAM lparam) {
  switch (msg) {
    case WM_HOTKEY:
      if (wparam == kHotkeyCaptureId) {
        SendEventAsync("captureHotkey");
      } else if (wparam == kHotkeyPanelId) {
        // 直接在平台线程弹速记窗
        ShowPanel();
      }
      return 0;

    case WM_APP + 1: {
      if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU ||
          lparam == WM_LBUTTONUP) {
        BuildAndShowTrayMenu();
      }
      return 0;
    }

    case WM_TIMER:
      if (wparam == kGrabTimerId && panel_) {
        KillTimer(host_, kGrabTimerId);
        SetFocus(panel_edit_);
      }
      return 0;

    case WM_COMMAND: {
      int id = LOWORD(wparam);
      if (id == 101) {
        ShowPanel();
      } else if (id == 102) {
        SendEventAsync("captureHotkey");
      } else if (id == 110) {
        SendEventAsync("menuAction", "main");
      } else if (id == 111) {
        SendEventAsync("menuAction", "settings");
      } else if (id == 113) {
        SendEventAsync("menuAction", "toggleWidget");
      } else if (id == 112) {
        Quit();
      } else if (id >= 200) {
        size_t idx = (size_t)(id - 200);
        if (idx < todos_.size()) {
          SendEventAsync("toggleTodo", todos_[idx].id);
        }
      }
      return 0;
    }

    default:
      break;
  }
  if (panel_ && msg == WM_DESTROY && hwnd == panel_) {
    panel_ = nullptr;
    panel_edit_ = nullptr;
    return 0;
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

void WinFeatures::SendEvent(const std::string& e, const std::string& a,
                            const std::string& b) {
  if (on_event) on_event(e, a, b);
}

void WinFeatures::SendEventAsync(const std::string& e, const std::string& a,
                                 const std::string& b) {
  // WM_HOTKEY/托盘回调内直接调用 Flutter channel（平台线程）即可，
  // 这里通过后台投递避免在系统回调里做重活
  struct Ctx {
    WinFeatures* self;
    std::string e, a, b;
  };
  auto* ctx = new Ctx{this, e, a, b};
  QueueUserWorkItem(
      [](LPVOID p) -> DWORD {
        auto* c = static_cast<Ctx*>(p);
        c->self->SendEvent(c->e, c->a, c->b);
        delete c;
        return 0;
      },
      ctx, WT_EXECUTELONGFUNCTION);
}

// ---- 热键 ----

bool WinFeatures::RegisterHotkeys(unsigned capture_mods, unsigned capture_vk,
                                  unsigned panel_mods, unsigned panel_vk) {
  UnregisterHotKey(host_, kHotkeyCaptureId);
  UnregisterHotKey(host_, kHotkeyPanelId);
  bool ok1 = RegisterHotKey(host_, kHotkeyCaptureId, capture_mods,
                            capture_vk) == TRUE;
  bool ok2 = RegisterHotKey(host_, kHotkeyPanelId, panel_mods, panel_vk) ==
             TRUE;
  return ok1 && ok2;
}

unsigned WinFeatures::MacKeyToVk(int mac) {
  static const struct {
    int mac;
    unsigned vk;
  } map[] = {
      {0x00, 'A'}, {0x0B, 'B'}, {0x08, 'C'}, {0x02, 'D'}, {0x0E, 'E'},
      {0x03, 'F'}, {0x05, 'G'}, {0x04, 'H'}, {0x22, 'I'}, {0x26, 'J'},
      {0x28, 'K'}, {0x25, 'L'}, {0x2E, 'M'}, {0x2D, 'N'}, {0x1F, 'O'},
      {0x23, 'P'}, {0x0C, 'Q'}, {0x0F, 'R'}, {0x01, 'S'}, {0x11, 'T'},
      {0x20, 'U'}, {0x09, 'V'}, {0x0D, 'W'}, {0x07, 'X'}, {0x10, 'Y'},
      {0x06, 'Z'},
      {0x12, '1'}, {0x13, '2'}, {0x14, '3'}, {0x15, '4'}, {0x17, '5'},
      {0x16, '6'}, {0x1A, '7'}, {0x1C, '8'}, {0x19, '9'}, {0x1D, '0'},
      {0x31, VK_SPACE},
  };
  for (const auto& m : map) {
    if (m.mac == mac) return m.vk;
  }
  return 0;
}

// ---- 托盘菜单 ----

void WinFeatures::SetMenuTodos(std::vector<TodoItem> todos) {
  todos_ = std::move(todos);
  if (widget_visible_) UpdateWidgetLayout();
}

void WinFeatures::BuildAndShowTrayMenu() {
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, 101, L"快速捕捉");
  AppendMenuW(menu, MF_STRING, 102, L"抓取选中文字");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

  int shown = 0;
  for (const auto& t : todos_) {
    if (t.done) continue;
    if (shown >= 6) break;
    std::wstring text = Utf8ToWide(t.text);
    if (text.size() > 30) text = text.substr(0, 30) + L"…";
    std::replace(text.begin(), text.end(), L'&', L'＋');  // 转义菜单助记符
    AppendMenuW(menu, MF_STRING, 200 + shown, (L"○  " + text).c_str());
    shown++;
  }
  if (shown == 0) AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, L"暂无待办");

  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, 110, L"打开主窗口");
  AppendMenuW(menu, MF_STRING, 111, L"设置…");
  AppendMenuW(menu, MF_STRING | (widget_visible_ ? MF_CHECKED : 0), 113,
              L"桌面清单");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, 112, L"退出闪拾");

  POINT pt;
  GetCursorPos(&pt);
  SetForegroundWindow(host_);
  TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, host_, nullptr);
  PostMessage(host_, WM_NULL, 0, 0);
  DestroyMenu(menu);
}

// ---- 气泡 HUD ----

void WinFeatures::ShowHud(const std::string& message) {
  if (!tray_added_) return;
  std::wstring w = Utf8ToWide(message);
  if (w.size() > 250) w = w.substr(0, 250) + L"…";
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = host_;
  nid.uID = kTrayIconId;
  nid.uFlags = NIF_INFO;
  nid.dwInfoFlags = NIIF_INFO;
  wcscpy_s(nid.szInfoTitle, L"闪拾 FlashPick");
  wcscpy_s(nid.szInfo, w.c_str());
  Shell_NotifyIconW(NIM_MODIFY, &nid);
}

// ---- 快速捕捉窗 ----

namespace {

LRESULT CALLBACK PanelEditProc(HWND hwnd, UINT msg, WPARAM wparam,
                               LPARAM lparam, UINT_PTR id, DWORD_PTR ref) {
  WinFeatures* self = reinterpret_cast<WinFeatures*>(ref);
  if (msg == WM_KEYDOWN && wparam == VK_RETURN) {
    wchar_t buf[2048];
    GetWindowTextW(hwnd, buf, 2048);
    std::string text = TrimCopy(WideToUtf8(buf));
    if (self) {
      struct Ctx {
        WinFeatures* self;
        std::string text;
      };
      auto* ctx = new Ctx{self, text};
      QueueUserWorkItem(
          [](LPVOID p) -> DWORD {
            auto* c = static_cast<Ctx*>(p);
            c->self->SendEvent("panelSubmit", c->text);
            delete c;
            return 0;
          },
          ctx, WT_EXECUTELONGFUNCTION);
    }
    PostMessage(GetParent(hwnd), WM_CLOSE, 0, 0);
    return 0;
  }
  if (msg == WM_KEYDOWN && wparam == VK_ESCAPE) {
    PostMessage(GetParent(hwnd), WM_CLOSE, 0, 0);
    return 0;
  }
  return DefSubclassProc(hwnd, msg, wparam, lparam);
}

LRESULT CALLBACK PanelWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                              LPARAM lparam) {
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

}  // namespace

void WinFeatures::ShowPanel() {
  if (panel_) {
    SetForegroundWindow(panel_);
    SetFocus(panel_edit_);
    return;
  }
  WNDCLASSW wc = {};
  wc.lpfnWndProc = &PanelWndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.hbrBackground = (HBRUSH)GetSysColorBrush(COLOR_WINDOW);
  wc.lpszClassName = L"FlashpickPanel";
  RegisterClassW(&wc);

  RECT work;
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  int w = 520, h = 150;
  int x = work.left + ((work.right - work.left) - w) / 2;
  int y = work.top + ((work.bottom - work.top) / 3);

  panel_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, L"FlashpickPanel",
                          L"闪拾 · 速记", WS_POPUP | WS_BORDER, x, y, w, h,
                          nullptr, nullptr, GetModuleHandle(nullptr), nullptr);

  HFONT font = CreateFontW(-20, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                           DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                           CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                           DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei UI");
  HFONT hint_font = CreateFontW(-13, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                                CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                DEFAULT_PITCH | FF_DONTCARE,
                                L"Microsoft YaHei UI");

  panel_edit_ =
      CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
                      WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_MULTILINE,
                      14, 12, w - 28, 88, panel_, nullptr,
                      GetModuleHandle(nullptr), nullptr);
  SendMessage(panel_edit_, WM_SETFONT, (WPARAM)font, TRUE);

  HWND hint = CreateWindowExW(0, L"STATIC",
                              L"回车保存 · Esc 取消 · 语音速记 Windows 版开发中",
                              WS_CHILD | WS_VISIBLE, 16, h - 30, w - 32, 20,
                              panel_, nullptr, GetModuleHandle(nullptr), nullptr);
  SendMessage(hint, WM_SETFONT, (WPARAM)hint_font, TRUE);
  SendMessage(hint, WM_SETTEXT, 0,
              (LPARAM)L"回车保存 · Esc 取消 · 语音速记 Windows 版开发中");

  SetWindowSubclass(panel_edit_, PanelEditProc, 1, (DWORD_PTR)this);

  ShowWindow(panel_, SW_SHOW);
  SetForegroundWindow(panel_);
  // 焦点竞态兜底：短暂延时后再聚焦输入框
  panel_grab_timer_ = SetTimer(host_, kGrabTimerId, 120, nullptr);
  (void)panel_grab_timer_;
}

// ---- 开机自启（HKCU Run）----

void WinFeatures::SetAutostart(bool enabled) {
  HKEY key;
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
                    KEY_SET_VALUE, &key) != ERROR_SUCCESS) {
    return;
  }
  if (enabled) {
    wchar_t path[MAX_PATH];
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    std::wstring value = L"\"" + std::wstring(path) + L"\"";
    RegSetValueExW(key, L"FlashPick", 0, REG_SZ,
                   (const BYTE*)value.c_str(),
                   (DWORD)((value.size() + 1) * sizeof(wchar_t)));
  } else {
    RegDeleteValueW(key, L"FlashPick");
  }
  RegCloseKey(key);
}

bool WinFeatures::IsAutostart() const {
  HKEY key;
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
                    KEY_QUERY_VALUE, &key) != ERROR_SUCCESS) {
    return false;
  }
  bool found = RegQueryValueExW(key, L"FlashPick", nullptr, nullptr, nullptr,
                                nullptr) == ERROR_SUCCESS;
  RegCloseKey(key);
  return found;
}

// ---- 主窗口 / 设置 / 退出 ----

void WinFeatures::ShowMainWindow() {
  HWND main = GetAncestor(flutter_view_, GA_ROOT);
  if (main) {
    ShowWindow(main, SW_SHOW);
    SetForegroundWindow(main);
  }
}

void WinFeatures::OpenSystemSettings(const std::string& pane) {
  std::wstring uri = L"ms-settings:";
  if (pane == "microphone") uri += L"privacy-microphone";
  else if (pane == "speech") uri += L"privacy-speech";
  ShellExecuteW(nullptr, L"open", uri.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}

void WinFeatures::Quit() {
  HWND main = GetAncestor(flutter_view_, GA_ROOT);
  if (main) PostMessage(main, WM_CLOSE, 0, 0);
}

// ---- 桌面清单小组件 ----

namespace {
constexpr int kWidgetWidth = 272;
constexpr int kWidgetRowH = 26;
constexpr int kWidgetHeaderH = 34;
constexpr int kWidgetMaxRows = 8;
constexpr int kWidgetInputH = 26;

// 小组件内嵌输入框：点击时解除 NOACTIVATE 以获得真实键盘输入
LRESULT CALLBACK WidgetInputProc(HWND hwnd, UINT msg, WPARAM wparam,
                                 LPARAM lparam, UINT_PTR id, DWORD_PTR ref) {
  WinFeatures* self = reinterpret_cast<WinFeatures*>(ref);
  switch (msg) {
    case WM_LBUTTONDOWN: {
      HWND parent = GetParent(hwnd);
      LONG_PTR style = GetWindowLongPtrW(parent, GWL_EXSTYLE);
      if (style & WS_EX_NOACTIVATE) {
        SetWindowLongPtrW(parent, GWL_EXSTYLE, style & ~WS_EX_NOACTIVATE);
        SetForegroundWindow(parent);
      }
      break;
    }
    case WM_KILLFOCUS: {
      // 输入框失焦后恢复 NOACTIVATE，点击组件不再抢激活
      HWND parent = GetParent(hwnd);
      LONG_PTR style = GetWindowLongPtrW(parent, GWL_EXSTYLE);
      SetWindowLongPtrW(parent, GWL_EXSTYLE, style | WS_EX_NOACTIVATE);
      break;
    }
    case WM_KEYDOWN:
      if (wparam == VK_RETURN) {
        wchar_t buf[1024];
        GetWindowTextW(hwnd, buf, 1024);
        std::wstring w(buf);
        // 去首尾空白
        while (!w.empty() && iswspace(w.front())) w.erase(w.begin());
        while (!w.empty() && iswspace(w.back())) w.pop_back();
        if (!w.empty() && self) {
          self->SendEventAsync("quickAdd", WideToUtf8(w));
        }
        SetWindowTextW(hwnd, L"");
        return 0;
      }
      if (wparam == VK_ESCAPE) {
        SetWindowTextW(hwnd, L"");
        SetFocus(nullptr);
        return 0;
      }
      break;
    default:
      break;
  }
  return DefSubclassProc(hwnd, msg, wparam, lparam);
}
}  // namespace
constexpr COLORREF kWidgetBg = RGB(28, 28, 32);
constexpr COLORREF kWidgetText = RGB(238, 238, 242);
constexpr COLORREF kWidgetDim = RGB(150, 150, 158);

void LoadWidgetPrefs(int& x, int& y, bool& has_pos, bool& pinned) {
  HKEY key;
  has_pos = false;
  pinned = true;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\FlashPick", 0, KEY_QUERY_VALUE,
                    &key) != ERROR_SUCCESS) {
    return;
  }
  DWORD vx = 0, vy = 0, vp = 1, sx = 0, sy = 0;
  if (RegQueryValueExW(key, L"WidgetX", nullptr, nullptr, (LPBYTE)&vx, &sx) ==
          ERROR_SUCCESS &&
      RegQueryValueExW(key, L"WidgetY", nullptr, nullptr, (LPBYTE)&vy, &sy) ==
          ERROR_SUCCESS) {
    x = (int)vx;
    y = (int)vy;
    has_pos = true;
  }
  DWORD szp = sizeof(vp);
  RegQueryValueExW(key, L"WidgetPinned", nullptr, nullptr, (LPBYTE)&vp, &szp);
  pinned = vp != 0;
  RegCloseKey(key);
}

void WinFeatures::SetWidgetVisible(bool on) {
  widget_visible_ = on;
  if (!on) {
    if (widget_) ShowWindow(widget_, SW_HIDE);
    return;
  }
  EnsureWidgetWindow();
  UpdateWidgetLayout();
  ShowWindow(widget_, SW_SHOWNOACTIVATE);
}

void WinFeatures::EnsureWidgetWindow() {
  if (widget_created_) return;
  widget_created_ = true;

  WNDCLASSW wc = {};
  wc.lpfnWndProc = &WinFeatures::WidgetWndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.lpszClassName = L"FlashpickWidget";
  wc.style = CS_DBLCLKS;
  RegisterClassW(&wc);

  int x = 0, y = 0;
  bool has_pos = false;
  LoadWidgetPrefs(x, y, widget_pinned_, has_pos);
  if (!has_pos) {
    RECT work;
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    x = work.right - kWidgetWidth - 24;
    y = work.top + 120;
  }

  widget_ = CreateWindowExW(
      WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_NOACTIVATE |
          (widget_pinned_ ? WS_EX_TOPMOST : 0),
      L"FlashpickWidget", L"FlashPick Widget", WS_POPUP, x, y, kWidgetWidth,
      96, nullptr, nullptr, GetModuleHandle(nullptr), nullptr);
  SetLayeredWindowAttributes(widget_, 0, 244, LWA_ALPHA);

  widget_font_ = CreateFontW(-15, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                             DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                             CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                             DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei UI");
  widget_bold_ = CreateFontW(-14, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
                             DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                             CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                             DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei UI");

  // 底部快速录入框
  widget_input_ = CreateWindowExW(
      0, L"EDIT", nullptr, WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 14, 0,
      kWidgetWidth - 28, kWidgetInputH, widget_, nullptr,
      GetModuleHandle(nullptr), nullptr);
  SetWindowSubclass(widget_input_, WidgetInputProc, 1, (DWORD_PTR)this);
  SendMessage(widget_input_, EM_SETCUEBANNER, TRUE,
              (LPARAM)L"＋ 输入新待办，回车保存");
  SendMessage(widget_input_, WM_SETFONT, (WPARAM)widget_font_, TRUE);
}

void WinFeatures::UpdateWidgetLayout() {
  if (!widget_) return;
  int pending = 0;
  for (const auto& t : todos_) {
    if (!t.done) pending++;
  }
  int rows = std::min(pending, kWidgetMaxRows);
  int extra = pending > kWidgetMaxRows ? 1 : 0;
  int height = kWidgetHeaderH + 10 +
               (pending == 0 ? kWidgetRowH
                             : rows * kWidgetRowH + extra * kWidgetRowH) +
               8 + kWidgetInputH + 6;
  RECT rc;
  GetWindowRect(widget_, &rc);
  int w = rc.right - rc.left;
  int h = rc.bottom - rc.top;
  if (w != kWidgetWidth || h != height) {
    SetWindowPos(widget_, nullptr, 0, 0, kWidgetWidth, height,
                 SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    HRGN rgn = CreateRoundRectRgn(0, 0, kWidgetWidth, height, 14, 14);
    SetWindowRgn(widget_, rgn, TRUE);
  }
  if (widget_input_) {
    SetWindowPos(widget_input_, nullptr, 14, height - kWidgetInputH - 10,
                 kWidgetWidth - 28, kWidgetInputH, SWP_NOZORDER);
  }
  InvalidateRect(widget_, nullptr, TRUE);
}

void WinFeatures::PaintWidget(HWND hwnd, HDC dc) {
  RECT rc;
  GetClientRect(hwnd, &rc);
  HBRUSH bg = CreateSolidBrush(kWidgetBg);
  FillRect(dc, &rc, bg);
  DeleteObject(bg);

  SetBkMode(dc, TRANSPARENT);
  widget_rows_.clear();

  // 头部
  HFONT old = (HFONT)SelectObject(dc, widget_bold_);
  SetTextColor(dc, kWidgetText);
  RECT rTitle = {14, 10, rc.right - 60, 10 + 22};
  DrawTextW(dc, L"闪拾 · 待办", -1, &rTitle,
            DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
  SelectObject(dc, widget_font_);

  int pending = 0;
  for (const auto& t : todos_) {
    if (!t.done) pending++;
  }
  wchar_t count[16];
  _snwprintf_s(count, 16, _TRUNCATE, pending > 0 ? L"%d" : L"✓", pending);
  SetTextColor(dc, kWidgetDim);
  RECT rCount = {rc.right - 60, 10, rc.right - 14, 10 + 22};
  DrawTextW(dc, count, -1, &rCount,
            DT_RIGHT | DT_VCENTER | DT_SINGLELINE);

  int y = kWidgetHeaderH + 4;
  if (pending == 0) {
    SetTextColor(dc, kWidgetDim);
    RECT rEmpty = {14, y, rc.right - 14, y + kWidgetRowH};
    DrawTextW(dc, L"全部完成，歇口气 ✓", -1, &rEmpty, DT_LEFT | DT_VCENTER);
  } else {
    int shown = 0;
    for (const auto& t : todos_) {
      if (t.done) continue;
      if (shown >= kWidgetMaxRows) break;
      WidgetRow row;
      SetRect(&row.circle, 14, y, 34, y + kWidgetRowH);
      SetRect(&row.row, 14, y, rc.right - 14, y + kWidgetRowH);
      row.id = t.id;
      widget_rows_.push_back(row);

      SetTextColor(dc, kWidgetDim);
      DrawTextW(dc, L"○", -1, &row.circle,
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
      std::wstring text = Utf8ToWide(t.text);
      RECT rText = {38, y, rc.right - 14, y + kWidgetRowH};
      SetTextColor(dc, kWidgetText);
      DrawTextW(dc, text.c_str(), -1, &rText,
                DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
      y += kWidgetRowH;
      shown++;
    }
    if (pending > kWidgetMaxRows) {
      wchar_t more[32];
      _snwprintf_s(more, 32, _TRUNCATE, L"还有 %d 项…",
                   pending - kWidgetMaxRows);
      SetTextColor(dc, kWidgetDim);
      RECT rMore = {38, y, rc.right - 14, y + kWidgetRowH};
      DrawTextW(dc, more, -1, &rMore, DT_LEFT | DT_VCENTER);
    }
  }
  SelectObject(dc, old);
}

void WinFeatures::ShowWidgetContextMenu() {
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING | (widget_pinned_ ? MF_CHECKED : 0), 301,
              widget_pinned_ ? L"始终置顶" : L"始终置顶（当前关）");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, 302, L"关闭桌面清单");
  POINT pt;
  GetCursorPos(&pt);
  SetForegroundWindow(widget_ ? widget_ : host_);
  TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, widget_, nullptr);
  PostMessage(widget_, WM_NULL, 0, 0);
  DestroyMenu(menu);
}

void WinFeatures::SaveWidgetPosition() {
  if (!widget_) return;
  RECT rc;
  GetWindowRect(widget_, &rc);
  HKEY key;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\FlashPick", 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  DWORD x = (DWORD)rc.left, y = (DWORD)rc.top, p = widget_pinned_ ? 1 : 0;
  RegSetValueExW(key, L"WidgetX", 0, REG_DWORD, (const BYTE*)&x, sizeof(x));
  RegSetValueExW(key, L"WidgetY", 0, REG_DWORD, (const BYTE*)&y, sizeof(y));
  RegSetValueExW(key, L"WidgetPinned", 0, REG_DWORD, (const BYTE*)&p,
                 sizeof(p));
  RegCloseKey(key);
}

LRESULT CALLBACK WinFeatures::WidgetWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                            LPARAM lparam) {
  if (g_instance) {
    return g_instance->HandleWidgetMessage(hwnd, msg, wparam, lparam);
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

LRESULT WinFeatures::HandleWidgetMessage(HWND hwnd, UINT msg, WPARAM wparam,
                                         LPARAM lparam) {
  switch (msg) {
    case WM_ERASEBKGND:
      return 1;
    case WM_CTLCOLOREDIT: {
      // 快速录入框的深色主题
      HDC dc = (HDC)wparam;
      SetBkColor(dc, RGB(44, 44, 50));
      SetTextColor(dc, RGB(238, 238, 242));
      static HBRUSH edit_brush = CreateSolidBrush(RGB(44, 44, 50));
      return (LRESULT)edit_brush;
    }
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC dc = BeginPaint(hwnd, &ps);
      PaintWidget(hwnd, dc);
      EndPaint(hwnd, &ps);
      return 0;
    }
    case WM_LBUTTONDOWN: {
      POINTS pt = MAKEPOINTS(lparam);
      for (const auto& row : widget_rows_) {
        if (PtInRect(&row.circle, POINT{pt.x, pt.y})) {
          SendEventAsync("toggleTodo", row.id);
          return 0;
        }
      }
      // 空白/标题区域按下 = 拖动窗口
      ReleaseCapture();
      SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      SaveWidgetPosition();
      return 0;
    }
    case WM_LBUTTONDBLCLK: {
      // 双击任意行文字 → 打开主窗口
      ShowMainWindow();
      return 0;
    }
    case WM_RBUTTONUP:
      ShowWidgetContextMenu();
      return 0;
    case WM_COMMAND: {
      int id = LOWORD(wparam);
      if (id == 301) {
        widget_pinned_ = !widget_pinned_;
        SetWindowPos(widget_, widget_pinned_ ? HWND_TOPMOST : HWND_NOTOPMOST, 0,
                     0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        SaveWidgetPosition();
      } else if (id == 302) {
        SendEventAsync("menuAction", "toggleWidget");
      }
      return 0;
    }
    case WM_DESTROY:
      widget_ = nullptr;
      widget_input_ = nullptr;
      widget_created_ = false;
      return 0;
    default:
      break;
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

// ---- 选中文字抓取 ----

void WinFeatures::CaptureSelection(std::string& text, std::string& source,
                                   bool& ok) {
  text.clear();
  source.clear();
  ok = false;

  std::vector<SavedFormat> saved;
  SaveClipboard(saved);
  DWORD seq_before = GetClipboardSequenceNumber();

  WaitModifierRelease();

  SendCtrlC();

  bool changed = false;
  ULONGLONG deadline = GetTickCount64() + 180;
  while (GetTickCount64() < deadline) {
    if (GetClipboardSequenceNumber() != seq_before) {
      changed = true;
      break;
    }
    Sleep(5);
  }
  if (!changed) {
    SendCtrlC();
    deadline = GetTickCount64() + 170;
    while (GetTickCount64() < deadline) {
      if (GetClipboardSequenceNumber() != seq_before) {
        changed = true;
        break;
      }
      Sleep(5);
    }
  }

  std::string captured = changed ? ReadClipboardText() : "";
  RestoreClipboard(saved);

  if (!captured.empty()) {
    text = captured;
    source = "selection";
    ok = true;
    return;
  }
  std::string clip = ReadClipboardText();
  if (!clip.empty()) {
    text = clip;
    source = changed ? "clipboard" : "clipboard-timeout";
    ok = true;
  }
}

}  // namespace flashpick_platform
