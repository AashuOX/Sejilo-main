#ifndef FLUTTER_PLUGIN_FLUTTER_BLUETOOTH_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_BLUETOOTH_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace flutter_bluetooth_plugin {

/// Windows implementation of the Flutter Bluetooth plugin.
///
/// The plugin exposes the same MethodChannel API as the Dart platform
/// interface. Windows Runtime Bluetooth APIs are used for BLE adapter state,
/// advertisement scanning, GATT client connections, service discovery,
/// characteristic/descriptor I/O, and notification streams. APIs that Windows
/// desktop does not expose through this implementation return a documented
/// unsupported, false, empty, or no-op result rather than MethodNotImplemented.
class FlutterBluetoothPlugin : public flutter::Plugin {
 public:
  /// Registers the plugin channels with the Windows Flutter registrar.
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  /// Creates a Windows Bluetooth plugin instance.
  FlutterBluetoothPlugin();

  /// Stops active Bluetooth resources and releases stream subscriptions.
  virtual ~FlutterBluetoothPlugin();

  // Disallow copy and assign.
  FlutterBluetoothPlugin(const FlutterBluetoothPlugin&) = delete;
  FlutterBluetoothPlugin& operator=(const FlutterBluetoothPlugin&) = delete;

  /// Handles a Dart MethodChannel call on `flutter_bluetooth_plugin`.
  ///
  /// All public Dart APIs are recognized here. Supported Windows BLE APIs map
  /// to WinRT calls; unsupported cross-platform APIs return stable fallback
  /// results so callers can feature-detect with the normal plugin methods.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  class Impl;
  std::shared_ptr<Impl> impl_;
};

}  // namespace flutter_bluetooth_plugin

#endif  // FLUTTER_PLUGIN_FLUTTER_BLUETOOTH_PLUGIN_H_
