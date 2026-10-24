#include "flashpick_platform_plugin.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <string>
#include <vector>

namespace {

unsigned ParseModifiers(const flutter::EncodableList& mods) {
  unsigned out = 0;
  for (const auto& m : mods) {
    if (const auto* s = std::get_if<std::string>(&m)) {
      if (*s == "ctrl") out |= MOD_CONTROL;
      else if (*s == "shift") out |= MOD_SHIFT;
      else if (*s == "alt") out |= MOD_ALT;
      else if (*s == "cmd") out |= MOD_WIN;
    }
  }
  return out;
}

struct HotkeySpec {
  unsigned mods = 0;
  unsigned vk = 0;
};

bool ParseHotkey(const flutter::EncodableValue* value, HotkeySpec* out) {
  if (!value) return false;
  const auto* map = std::get_if<flutter::EncodableMap>(value);
  if (!map) return false;
  auto it_code = map->find(flutter::EncodableValue("keyCode"));
  auto it_mods = map->find(flutter::EncodableValue("modifiers"));
  if (it_code == map->end() || it_mods == map->end()) return false;
  const auto* code = std::get_if<int32_t>(&it_code->second);
  const auto* mods = std::get_if<flutter::EncodableList>(&it_mods->second);
  if (!code || !mods) return false;
  unsigned vk = flashpick_platform::WinFeatures::MacKeyToVk(*code);
  if (!vk) return false;
  out->mods = ParseModifiers(*mods);
  out->vk = vk;
  return true;
}

flutter::EncodableValue TextSourceMap(const std::string& text,
                                      const std::string& source) {
  flutter::EncodableMap m;
  m[flutter::EncodableValue("text")] = flutter::EncodableValue(text);
  m[flutter::EncodableValue("source")] = flutter::EncodableValue(source);
  return flutter::EncodableValue(m);
}

}  // namespace

namespace flashpick_platform {

// static
void FlashpickPlatformPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "dev.flashpick/platform",
          &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<FlashpickPlatformPlugin>(registrar,
                                                          std::move(channel));
  registrar->AddPlugin(std::move(plugin));
}

FlashpickPlatformPlugin::FlashpickPlatformPlugin(
    flutter::PluginRegistrarWindows *registrar,
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel)
    : registrar_(registrar), channel_(std::move(channel)) {
  channel_->SetMethodCallHandler(
      [this](const auto &call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
  win_.on_event = [this](const std::string& e, const std::string& a,
                         const std::string& b) { OnNativeEvent(e, a, b); };
}

FlashpickPlatformPlugin::~FlashpickPlatformPlugin() {
  win_.Shutdown();
}

void FlashpickPlatformPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();
  const flutter::EncodableValue* args = method_call.arguments();

  if (method == "init") {
    HotkeySpec capture, panel;
    const auto* map = std::get_if<flutter::EncodableMap>(args);
    if (map) {
      auto it_c = map->find(flutter::EncodableValue("captureHotkey"));
      auto it_p = map->find(flutter::EncodableValue("panelHotkey"));
      ParseHotkey(it_c != map->end() ? &it_c->second : nullptr, &capture);
      ParseHotkey(it_p != map->end() ? &it_p->second : nullptr, &panel);
    }
    win_.Init(registrar_->GetView()->GetNativeWindow());
    bool ok =
        win_.RegisterHotkeys(capture.mods, capture.vk, panel.mods, panel.vk);
    initialized_ = true;
    result->Success(flutter::EncodableValue(ok));
    return;
  }

  if (method == "updateHotkeys") {
    HotkeySpec capture, panel;
    const auto* map = std::get_if<flutter::EncodableMap>(args);
    if (map) {
      auto it_c = map->find(flutter::EncodableValue("captureHotkey"));
      auto it_p = map->find(flutter::EncodableValue("panelHotkey"));
      ParseHotkey(it_c != map->end() ? &it_c->second : nullptr, &capture);
      ParseHotkey(it_p != map->end() ? &it_p->second : nullptr, &panel);
    }
    bool ok =
        win_.RegisterHotkeys(capture.mods, capture.vk, panel.mods, panel.vk);
    result->Success(flutter::EncodableValue(ok));
    return;
  }

  if (method == "setMenuTodos") {
    std::vector<WinFeatures::TodoItem> todos;
    if (const auto* list = std::get_if<flutter::EncodableList>(args)) {
      for (const auto& item : *list) {
        const auto* m = std::get_if<flutter::EncodableMap>(&item);
        if (!m) continue;
        WinFeatures::TodoItem t;
        auto it_id = m->find(flutter::EncodableValue("id"));
        auto it_text = m->find(flutter::EncodableValue("text"));
        auto it_done = m->find(flutter::EncodableValue("done"));
        if (it_id != m->end()) {
          if (const auto* s = std::get_if<std::string>(&it_id->second))
            t.id = *s;
        }
        if (it_text != m->end()) {
          if (const auto* s = std::get_if<std::string>(&it_text->second))
            t.text = *s;
        }
        if (it_done != m->end()) {
          if (const auto* b = std::get_if<bool>(&it_done->second)) t.done = *b;
        }
        todos.push_back(std::move(t));
      }
    }
    win_.SetMenuTodos(std::move(todos));
    result->Success();
    return;
  }

  if (method == "showHud") {
    std::string text;
    if (const auto* map = std::get_if<flutter::EncodableMap>(args)) {
      auto it = map->find(flutter::EncodableValue("text"));
      if (it != map->end()) {
        if (const auto* s = std::get_if<std::string>(&it->second)) text = *s;
      }
    }
    win_.ShowHud(text);
    result->Success();
    return;
  }

  if (method == "showPanel") {
    win_.ShowPanel();
    result->Success();
    return;
  }

  if (method == "setWidgetVisible") {
    bool on = true;
    if (const auto* map = std::get_if<flutter::EncodableMap>(args)) {
      auto it = map->find(flutter::EncodableValue("visible"));
      if (it != map->end()) {
        if (const auto* b = std::get_if<bool>(&it->second)) on = *b;
      }
    }
    win_.SetWidgetVisible(on);
    result->Success(flutter::EncodableValue(on));
    return;
  }

  if (method == "captureSelection") {
    std::string text, source;
    bool ok = false;
    win_.CaptureSelection(text, source, ok);
    if (ok) {
      result->Success(TextSourceMap(text, source));
    } else {
      result->Success(TextSourceMap("", "none"));
    }
    return;
  }

  if (method == "setAutostart") {
    bool enabled = false;
    if (const auto* map = std::get_if<flutter::EncodableMap>(args)) {
      auto it = map->find(flutter::EncodableValue("enabled"));
      if (it != map->end()) {
        if (const auto* b = std::get_if<bool>(&it->second)) enabled = *b;
      }
    }
    win_.SetAutostart(enabled);
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "isAutostart") {
    result->Success(flutter::EncodableValue(win_.IsAutostart()));
    return;
  }

  if (method == "showMainWindow") {
    win_.ShowMainWindow();
    result->Success();
    return;
  }

  if (method == "openSystemSettings") {
    std::string pane;
    if (const auto* map = std::get_if<flutter::EncodableMap>(args)) {
      auto it = map->find(flutter::EncodableValue("pane"));
      if (it != map->end()) {
        if (const auto* s = std::get_if<std::string>(&it->second)) pane = *s;
      }
    }
    win_.OpenSystemSettings(pane);
    result->Success();
    return;
  }

  if (method == "quitApp") {
    win_.Quit();
    result->Success();
    return;
  }

  // Windows 暂不实现：permissions（mac 专属权限模型）、mirrorTodo 系列、
  // requestAccessibility、requestRuntimePermissions。
  // Dart 侧已按平台隐藏相关 UI，并保留 try/catch 兜底。
  result->Error("unimplemented", "Not implemented on Windows");
}

void FlashpickPlatformPlugin::OnNativeEvent(const std::string& event,
                                            const std::string& arg1,
                                            const std::string& arg2) {
  if (event == "captureHotkey") {
    RunCapture();
    return;
  }
  if (event == "panelSubmit") {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("text")] = flutter::EncodableValue(arg1);
    channel_->InvokeMethod("onPanelSubmit",
                           std::make_unique<flutter::EncodableValue>(m));
    return;
  }
  if (event == "menuAction") {
    if (arg1 == "main") {
      win_.ShowMainWindow();
      return;
    }
    if (arg1 == "settings" || arg1 == "toggleWidget") {
      flutter::EncodableMap m;
      m[flutter::EncodableValue("action")] = flutter::EncodableValue(arg1);
      channel_->InvokeMethod("onMenuAction",
                             std::make_unique<flutter::EncodableValue>(m));
      return;
    }
    return;
  }
  if (event == "toggleTodo") {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("action")] = flutter::EncodableValue("toggle");
    m[flutter::EncodableValue("todoId")] = flutter::EncodableValue(arg1);
    channel_->InvokeMethod("onMenuAction",
                           std::make_unique<flutter::EncodableValue>(m));
    return;
  }
}

void FlashpickPlatformPlugin::RunCapture() {
  std::string text, source;
  bool ok = false;
  win_.CaptureSelection(text, source, ok);
  if (ok && !text.empty()) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("text")] = flutter::EncodableValue(text);
    m[flutter::EncodableValue("source")] = flutter::EncodableValue(source);
    channel_->InvokeMethod("onCaptured",
                           std::make_unique<flutter::EncodableValue>(m));
  } else {
    win_.ShowHud("没有抓到文字（未选中且剪贴板为空）");
  }
}

}  // namespace flashpick_platform
