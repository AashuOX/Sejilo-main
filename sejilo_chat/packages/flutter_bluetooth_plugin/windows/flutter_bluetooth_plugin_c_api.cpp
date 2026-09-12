#include "include/flutter_bluetooth_plugin/flutter_bluetooth_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_bluetooth_plugin.h"

void FlutterBluetoothPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_bluetooth_plugin::FlutterBluetoothPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
