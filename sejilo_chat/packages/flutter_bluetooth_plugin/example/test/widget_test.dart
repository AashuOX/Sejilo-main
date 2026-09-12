import 'package:flutter/cupertino.dart';
import 'package:flutter_bluetooth_plugin/flutter_bluetooth_plugin.dart';
import 'package:flutter_bluetooth_plugin/flutter_bluetooth_plugin_platform_interface.dart';
import 'package:flutter_bluetooth_plugin_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBluetoothPlatform extends FlutterBluetoothPluginPlatform {
  @override
  Future<String?> getPlatformVersion() async => 'Test OS 1.0';

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<BluetoothAdapterState> getAdapterState() async {
    return BluetoothAdapterState.poweredOn;
  }

  @override
  Future<BluetoothAdapterInfo> getAdapterInfo() async {
    return const BluetoothAdapterInfo(
      isSupported: true,
      state: BluetoothAdapterState.poweredOn,
      isBleSupported: true,
      isMultipleAdvertisementSupported: true,
    );
  }

  @override
  Future<bool> isScanning() async => false;

  @override
  Future<bool> setAdapterName(String name) async => true;

  @override
  Future<bool> isPeripheralSupported() async => true;

  @override
  Future<Map<String, BluetoothPermissionStatus>> checkPermissions() async {
    return const <String, BluetoothPermissionStatus>{
      'bluetooth': BluetoothPermissionStatus.granted,
    };
  }

  @override
  Future<List<BluetoothDevice>> getConnectedDevices({
    List<String> serviceUuids = const <String>[],
  }) async {
    return const <BluetoothDevice>[];
  }

  @override
  Future<BluetoothDevice?> getDevice(String deviceId) async {
    return BluetoothDevice(id: deviceId, name: 'Test Device');
  }

  @override
  Future<List<BluetoothDevice>> getDevices(List<String> deviceIds) async {
    return deviceIds
        .map((String id) => BluetoothDevice(id: id, name: 'Test Device'))
        .toList(growable: false);
  }

  @override
  Future<BluetoothConnectionState> getConnectionState(String deviceId) async {
    return BluetoothConnectionState.disconnected;
  }

  @override
  Stream<BluetoothAdapterState> get adapterState {
    return const Stream<BluetoothAdapterState>.empty();
  }

  @override
  Stream<BluetoothScanResult> get scanResults {
    return const Stream<BluetoothScanResult>.empty();
  }

  @override
  Stream<BluetoothConnectionStateEvent> get connectionState {
    return const Stream<BluetoothConnectionStateEvent>.empty();
  }

  @override
  Stream<BluetoothCharacteristicValue> get characteristicValues {
    return const Stream<BluetoothCharacteristicValue>.empty();
  }

  @override
  Stream<BluetoothDescriptorValue> get descriptorValues {
    return const Stream<BluetoothDescriptorValue>.empty();
  }

  @override
  Stream<BluetoothRssiEvent> get rssiUpdates {
    return const Stream<BluetoothRssiEvent>.empty();
  }

  @override
  Stream<BluetoothMtuEvent> get mtuUpdates {
    return const Stream<BluetoothMtuEvent>.empty();
  }

  @override
  Stream<BluetoothBondStateEvent> get bondState {
    return const Stream<BluetoothBondStateEvent>.empty();
  }

  @override
  Stream<BluetoothAdvertisingStateEvent> get advertisingState {
    return const Stream<BluetoothAdvertisingStateEvent>.empty();
  }

  @override
  Stream<BluetoothGattServerRequest> get gattServerRequests {
    return const Stream<BluetoothGattServerRequest>.empty();
  }

  @override
  Stream<BluetoothPhyEvent> get phyUpdates {
    return const Stream<BluetoothPhyEvent>.empty();
  }

  @override
  Stream<BluetoothClassicConnectionEvent> get classicConnectionState {
    return const Stream<BluetoothClassicConnectionEvent>.empty();
  }

  @override
  Stream<BluetoothClassicDataEvent> get classicData {
    return const Stream<BluetoothClassicDataEvent>.empty();
  }
}

void main() {
  testWidgets('Bluetooth tester uses CupertinoApp', (
    WidgetTester tester,
  ) async {
    FlutterBluetoothPluginPlatform.instance = FakeBluetoothPlatform();

    await tester.pumpWidget(const BluetoothTestApp());
    await tester.pump();

    expect(find.byType(CupertinoApp), findsOneWidget);
    expect(find.text('蓝牙实验室'), findsOneWidget);
    expect(find.text('原生蓝牙测试台'), findsOneWidget);
    expect(find.text('Test OS 1.0'), findsOneWidget);
  });
}
