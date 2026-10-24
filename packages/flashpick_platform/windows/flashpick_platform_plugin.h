#ifndef FLUTTER_PLUGIN_FLASHPICK_PLATFORM_PLUGIN_H_
#define FLUTTER_PLUGIN_FLASHPICK_PLATFORM_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

#include "win_features.h"

namespace flashpick_platform {

class FlashpickPlatformPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FlashpickPlatformPlugin(
      flutter::PluginRegistrarWindows *registrar,
      std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel);
  virtual ~FlashpickPlatformPlugin();

  FlashpickPlatformPlugin(const FlashpickPlatformPlugin&) = delete;
  FlashpickPlatformPlugin& operator=(const FlashpickPlatformPlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // WinFeatures 的原生事件入口（可能在 worker 线程回调）
  void OnNativeEvent(const std::string& event, const std::string& arg1,
                     const std::string& arg2);

 private:
  void RunCapture();

  flutter::PluginRegistrarWindows *registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  WinFeatures win_;
  bool initialized_ = false;
};

}  // namespace flashpick_platform

#endif  // FLUTTER_PLUGIN_FLASHPICK_PLATFORM_PLUGIN_H_
