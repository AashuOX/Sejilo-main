import 'package:flutter_bluetooth_plugin/flutter_bluetooth_plugin.dart';
import 'package:flutter_bluetooth_plugin/flutter_bluetooth_plugin_method_channel.dart';
import 'package:flutter_bluetooth_plugin/flutter_bluetooth_plugin_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

class MockFlutterBluetoothPluginPlatform
    extends FlutterBluetoothPluginPlatform {
  @override
  Future<String?> getPlatformVersion() => Future<String>.value('42');
}

void main() {
  final FlutterBluetoothPluginPlatform initialPlatform =
      FlutterBluetoothPluginPlatform.instance;

  test('$MethodChannelFlutterBluetoothPlugin is the default instance', () {
    expect(
      initialPlatform,
      isInstanceOf<MethodChannelFlutterBluetoothPlugin>(),
    );
  });

  test('getPlatformVersion', () async {
    const flutterBluetoothPlugin = FlutterBluetoothPlugin();
    final fakePlatform = MockFlutterBluetoothPluginPlatform();
    FlutterBluetoothPluginPlatform.instance = fakePlatform;

    expect(await flutterBluetoothPlugin.getPlatformVersion(), '42');
  });
}
