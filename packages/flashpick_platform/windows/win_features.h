// flashpick_platform Windows 原生功能层（纯 Win32）：
// 全局热键 RegisterHotKey、选中抓取 SendInput^C+剪贴板序列号、
// 托盘图标+菜单、气泡 HUD、快速捕捉窗（文字）、注册表开机自启。
#ifndef FLASHPICK_PLATFORM_WIN_FEATURES_H_
#define FLASHPICK_PLATFORM_WIN_FEATURES_H_

#include <windows.h>
#include <functional>
#include <string>
#include <vector>

namespace flashpick_platform {

class WinFeatures {
 public:
  struct TodoItem {
    std::string id;
    std::string text;
    bool done;
  };

  // 原生事件回调：event ∈ {captureHotkey, panelHotkey, panelSubmit,
  // menuAction, toggleTodo}；参数随事件携带
  std::function<void(const std::string& event, const std::string& arg1,
                     const std::string& arg2)>
      on_event;

  void Init(HWND flutter_view);
  void Shutdown();

  // modifiers: MOD_CONTROL|MOD_SHIFT|MOD_ALT|MOD_WIN 组合
  bool RegisterHotkeys(unsigned capture_mods, unsigned capture_vk,
                       unsigned panel_mods, unsigned panel_vk);

  void SetMenuTodos(std::vector<TodoItem> todos);

  // 桌面清单小组件
  void SetWidgetVisible(bool on);
  bool widget_visible() const { return widget_visible_; }

  void ShowHud(const std::string& message);

  void ShowPanel();

  void SetAutostart(bool enabled);
  bool IsAutostart() const;

  void ShowMainWindow();
  void OpenSystemSettings(const std::string& pane);
  void Quit();

  // 抓取选中文字；成功时 ok=true，source ∈ {selection, clipboard,
  // clipboard-timeout, clipboard-untrusted(Windows 无此概念,不产生)}
  void CaptureSelection(std::string& text, std::string& source, bool& ok);

  // mac 虚拟键码 → Windows VK（字母/数字/空格），失败返回 0
  static unsigned MacKeyToVk(int mac_keycode);

  // 供内部回调（匿名命名空间 lambda）触发事件
  void SendEvent(const std::string& e, const std::string& a = "",
                 const std::string& b = "");

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                  LPARAM lparam);
  static LRESULT CALLBACK WidgetWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                        LPARAM lparam);
  LRESULT HandleMessage(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);
  LRESULT HandleWidgetMessage(HWND hwnd, UINT msg, WPARAM wparam,
                              LPARAM lparam);

  void EnsureHostWindow();
  void BuildAndShowTrayMenu();
  void SendEventAsync(const std::string& e, const std::string& a = "",
                      const std::string& b = "");

  // 桌面小组件
  void EnsureWidgetWindow();
  void UpdateWidgetLayout();
  void PaintWidget(HWND hwnd, HDC dc);
  void ShowWidgetContextMenu();
  void SaveWidgetPosition();

  HWND flutter_view_ = nullptr;
  HWND host_ = nullptr;      // 承接热键/托盘消息的隐藏窗口
  HWND panel_ = nullptr;     // 快速捕捉窗
  HWND panel_edit_ = nullptr;
  WNDPROC panel_edit_orig_proc_ = nullptr;
  UINT_PTR panel_grab_timer_ = 0;
  bool tray_added_ = false;
  std::vector<TodoItem> todos_;

  // 桌面小组件状态
  HWND widget_ = nullptr;
  bool widget_visible_ = false;
  bool widget_pinned_ = true;
  bool widget_created_ = false;
  HFONT widget_font_ = nullptr;
  HFONT widget_bold_ = nullptr;
  struct WidgetRow {
    RECT circle;
    RECT row;
    std::string id;
  };
  std::vector<WidgetRow> widget_rows_;
};

// UTF-8 / UTF-16 转换
std::wstring Utf8ToWide(const std::string& s);
std::string WideToUtf8(const std::wstring& w);

}  // namespace flashpick_platform

#endif  // FLASHPICK_PLATFORM_WIN_FEATURES_H_
