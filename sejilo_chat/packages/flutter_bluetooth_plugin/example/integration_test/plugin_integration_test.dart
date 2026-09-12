// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_bluetooth_plugin/flutter_bluetooth_plugin.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const sejiloServiceUuid = 'f47ac10b-58cc-4372-a567-0e02b2c3d479';
  const sejiloDataUuid = 'f47ac10b-58cc-4372-a567-0e02b2c3d47a';

  testWidgets('getPlatformVersion test', (WidgetTester tester) async {
    // Build a minimal widget so the Flutter engine is initialized.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );

    final FlutterBluetoothPlugin plugin = FlutterBluetoothPlugin();
    final String? version = await plugin.getPlatformVersion();
    // The version string depends on the host platform running the test, so
    // just assert that some non-empty string is returned.
    expect(version?.isNotEmpty, true);
  });

  testWidgets('powered-on BLE adapter emits scan results', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Scanning'))),
    );

    final FlutterBluetoothPlugin plugin = FlutterBluetoothPlugin();
    final adapter = await plugin.getAdapterInfo();
    expect(adapter.isSupported, true);
    expect(adapter.isBleSupported, true);
    expect(adapter.state, BluetoothAdapterState.poweredOn);

    final result = plugin.scanResults.first.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw TimeoutException(
        'No BLE advertisements reached the plugin in 20 seconds.',
      ),
    );
    await plugin.startScan(
      serviceUuids: const [sejiloServiceUuid],
      allowDuplicates: true,
    );
    try {
      final device = await result;
      expect(device.device.id, isNotEmpty);
      expect(device.rssi, lessThanOrEqualTo(0));
    } finally {
      await plugin.stopScan();
    }
  });

  testWidgets('Sejilo peer establishes GATT link and emits an app frame', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Connecting'))),
    );

    final FlutterBluetoothPlugin plugin = FlutterBluetoothPlugin();
    // Windows reports known-service fallback candidates with RSSI -127.
    // Require an over-the-air advertisement for this physical link test so a
    // stale GATT cache entry cannot masquerade as the attached Android peer.
    final scanFuture = plugin.scanResults
        .where(
          (result) =>
              result.rssi > -127 &&
              result.serviceUuids.any(
                (uuid) => uuid.toLowerCase() == sejiloServiceUuid,
              ),
        )
        .first
        .timeout(
          const Duration(seconds: 25),
          onTimeout: () => throw TimeoutException(
            'No live Sejilo BLE advertisement reached the plugin in 25 seconds.',
          ),
        );
    await plugin.startScan(
      serviceUuids: const [sejiloServiceUuid],
      allowDuplicates: true,
    );
    final scan = await scanFuture;
    await plugin.stopScan();

    await plugin.connect(scan.device.id, timeout: const Duration(seconds: 20));
    try {
      final services = await plugin.discoverServices(scan.device.id);
      final service = services.where(
        (item) => item.uuid.toLowerCase() == sejiloServiceUuid,
      );
      expect(
        service,
        isNotEmpty,
        reason: 'The discovered endpoint must expose Sejilo GATT.',
      );
      expect(
        service.first.characteristics.any(
          (item) => item.uuid.toLowerCase() == sejiloDataUuid,
        ),
        true,
        reason: 'The Sejilo data characteristic must be discoverable.',
      );

      final incoming = plugin.characteristicValues
          .where(
            (event) =>
                event.deviceId == scan.device.id &&
                event.characteristicUuid.toLowerCase() == sejiloDataUuid,
          )
          .first
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw TimeoutException(
              'Subscribed successfully, but no Sejilo frame arrived in 20 seconds.',
            ),
          );
      await plugin.setCharacteristicNotification(
        deviceId: scan.device.id,
        serviceUuid: sejiloServiceUuid,
        characteristicUuid: sejiloDataUuid,
        enable: true,
      );
      final frame = await incoming;
      expect(frame.value, isNotEmpty);
      expect(frame.value.length, lessThanOrEqualTo(180));
      expect(frame.value.take(3), orderedEquals(const [0x53, 0x4a, 0x02]));
    } finally {
      await plugin.disconnect(scan.device.id);
    }
  });
}
