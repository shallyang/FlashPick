#include "include/flashpick_platform/flashpick_platform_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flashpick_platform_plugin.h"

void FlashpickPlatformPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flashpick_platform::FlashpickPlatformPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
