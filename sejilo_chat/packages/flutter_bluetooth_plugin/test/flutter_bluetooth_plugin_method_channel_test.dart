import 'package:flutter_bluetooth_plugin/flutter_bluetooth_plugin_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelFlutterBluetoothPlugin platform =
      MethodChannelFlutterBluetoothPlugin();
  const MethodChannel channel = MethodChannel('flutter_bluetooth_plugin');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('readCharacteristic returns typed byte data', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      expect(methodCall.method, 'readCharacteristic');
      return Uint8List.fromList(<int>[1, 2, 3]);
    });

    final value = await platform.readCharacteristic(
      deviceId: 'device-1',
      serviceUuid: '0000fff0-0000-1000-8000-00805f9b34fb',
      characteristicUuid: '0000fff1-0000-1000-8000-00805f9b34fb',
    );

    expect(value, isA<Uint8List>());
    expect(value, <int>[1, 2, 3]);
  });
}
