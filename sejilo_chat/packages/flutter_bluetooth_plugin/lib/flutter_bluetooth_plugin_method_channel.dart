import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_bluetooth_plugin_models.dart';
import 'flutter_bluetooth_plugin_platform_interface.dart';

/// 基于 Flutter MethodChannel 的默认平台实现。
///
/// 该类主要供插件注册和测试使用；业务侧通常直接使用 `FlutterBluetoothPlugin`。
class MethodChannelFlutterBluetoothPlugin
    extends FlutterBluetoothPluginPlatform {
  /// 与原生平台通信的 MethodChannel。
  ///
  /// 默认通道名为 `flutter_bluetooth_plugin`，仅测试或自定义平台实现通常需要直接访问。
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_bluetooth_plugin');

  /// 接收扫描、状态、通知、RSSI、MTU 等事件的 EventChannel。
  ///
  /// 默认通道名为 `flutter_bluetooth_plugin/events`。
  @visibleForTesting
  final eventChannel = const EventChannel('flutter_bluetooth_plugin/events');

  Stream<Map<String, dynamic>>? _events;

  Stream<Map<String, dynamic>> get _eventStream {
    _events ??= eventChannel.receiveBroadcastStream().map((Object? event) {
      return Map<String, dynamic>.from(event as Map<dynamic, dynamic>);
    }).asBroadcastStream();
    return _events!;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.getPlatformVersion]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.isSupported]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<bool> isSupported() async {
    return await methodChannel.invokeMethod<bool>('isSupported') ?? false;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.getAdapterState]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<BluetoothAdapterState> getAdapterState() async {
    final state = await methodChannel.invokeMethod<String>('getAdapterState');
    return bluetoothAdapterStateFromString(state);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.getAdapterInfo]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<BluetoothAdapterInfo> getAdapterInfo() async {
    final response = await methodChannel.invokeMapMethod<String, dynamic>(
      'getAdapterInfo',
    );
    return BluetoothAdapterInfo.fromMap(response ?? <String, dynamic>{});
  }

  /// 实现 [FlutterBluetoothPluginPlatform.isScanning]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<bool> isScanning() async {
    return await methodChannel.invokeMethod<bool>('isScanning') ?? false;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.setAdapterName]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<bool> setAdapterName(String name) async {
    return await methodChannel.invokeMethod<bool>(
          'setAdapterName',
          <String, dynamic>{'name': name},
        ) ??
        false;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.adapterState]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Stream<BluetoothAdapterState> get adapterState {
    return _eventStream.where((event) => event['type'] == 'adapterState').map(
          (event) =>
              bluetoothAdapterStateFromString(event['state']?.toString()),
        );
  }

  /// 实现 [FlutterBluetoothPluginPlatform.checkPermissions]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<Map<String, BluetoothPermissionStatus>> checkPermissions() async {
    final response = await methodChannel.invokeMapMethod<String, dynamic>(
      'checkPermissions',
    );
    return _permissionMapFromPlatform(response);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.requestPermissions]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<Map<String, BluetoothPermissionStatus>> requestPermissions() async {
    final response = await methodChannel.invokeMapMethod<String, dynamic>(
      'requestPermissions',
    );
    return _permissionMapFromPlatform(response);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.requestEnable]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<bool> requestEnable() async {
    return await methodChannel.invokeMethod<bool>('requestEnable') ?? false;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.openBluetoothSettings]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> openBluetoothSettings() async {
    await methodChannel.invokeMethod<void>('openBluetoothSettings');
  }

  /// 实现 [FlutterBluetoothPluginPlatform.startScan]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> startScan({
    List<String> serviceUuids = const <String>[],
    Duration? timeout,
    bool allowDuplicates = false,
    BluetoothScanMode scanMode = BluetoothScanMode.ble,
  }) async {
    await methodChannel.invokeMethod<void>('startScan', <String, dynamic>{
      'serviceUuids': serviceUuids,
      'timeoutMs': timeout?.inMilliseconds,
      'allowDuplicates': allowDuplicates,
      'scanMode': scanMode.name,
    });
  }

  /// 实现 [FlutterBluetoothPluginPlatform.stopScan]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> stopScan() async {
    await methodChannel.invokeMethod<void>('stopScan');
  }

  /// 实现 [FlutterBluetoothPluginPlatform.scanResults]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Stream<BluetoothScanResult> get scanResults {
    return _eventStream
        .where((event) => event['type'] == 'scanResult')
        .map(BluetoothScanResult.fromMap);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.getBondedDevices]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<List<BluetoothDevice>> getBondedDevices() async {
    final response = await methodChannel.invokeListMethod<dynamic>(
      'getBondedDevices',
    );
    return _deviceListFromPlatform(response);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.getConnectedDevices]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<List<BluetoothDevice>> getConnectedDevices({
    List<String> serviceUuids = const <String>[],
  }) async {
    final response = await methodChannel.invokeListMethod<dynamic>(
      'getConnectedDevices',
      <String, dynamic>{'serviceUuids': serviceUuids},
    );
    return _deviceListFromPlatform(response);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.getDevice]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<BluetoothDevice?> getDevice(String deviceId) async {
    final response = await methodChannel.invokeMapMethod<String, dynamic>(
      'getDevice',
      <String, dynamic>{'deviceId': deviceId},
    );
    if (response == null || response.isEmpty) {
      return null;
    }
    return BluetoothDevice.fromMap(response);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.getDevices]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<List<BluetoothDevice>> getDevices(List<String> deviceIds) async {
    final response = await methodChannel.invokeListMethod<dynamic>(
      'getDevices',
      <String, dynamic>{'deviceIds': deviceIds},
    );
    return _deviceListFromPlatform(response);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.connect]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> connect(
    String deviceId, {
    bool autoConnect = false,
    Duration? timeout,
  }) async {
    await methodChannel.invokeMethod<void>('connect', <String, dynamic>{
      'deviceId': deviceId,
      'autoConnect': autoConnect,
      'timeoutMs': timeout?.inMilliseconds,
    });
  }

  /// 实现 [FlutterBluetoothPluginPlatform.disconnect]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> disconnect(String deviceId) async {
    await methodChannel.invokeMethod<void>('disconnect', <String, dynamic>{
      'deviceId': deviceId,
    });
  }

  /// 实现 [FlutterBluetoothPluginPlatform.getConnectionState]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<BluetoothConnectionState> getConnectionState(String deviceId) async {
    final state = await methodChannel.invokeMethod<String>(
      'getConnectionState',
      <String, dynamic>{'deviceId': deviceId},
    );
    return bluetoothConnectionStateFromString(state);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.connectionState]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Stream<BluetoothConnectionStateEvent> get connectionState {
    return _eventStream
        .where((event) => event['type'] == 'connectionState')
        .map(BluetoothConnectionStateEvent.fromMap);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.discoverServices]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<List<BluetoothGattService>> discoverServices(String deviceId) async {
    final response = await methodChannel.invokeListMethod<dynamic>(
      'discoverServices',
      <String, dynamic>{'deviceId': deviceId},
    );
    return (response ?? const <dynamic>[])
        .map((item) => BluetoothGattService.fromMap(_asStringMap(item)))
        .toList(growable: false);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.readCharacteristic]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<Uint8List> readCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    final response = await methodChannel.invokeMethod<Object?>(
      'readCharacteristic',
      <String, dynamic>{
        'deviceId': deviceId,
        'serviceUuid': serviceUuid,
        'characteristicUuid': characteristicUuid,
      },
    );
    return _byteListFromPlatform(response);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.writeCharacteristic]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> writeCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    BluetoothWriteType writeType = BluetoothWriteType.withResponse,
  }) async {
    await methodChannel
        .invokeMethod<void>('writeCharacteristic', <String, dynamic>{
      'deviceId': deviceId,
      'serviceUuid': serviceUuid,
      'characteristicUuid': characteristicUuid,
      'value': value,
      'writeType': writeType.name,
    });
  }

  /// 实现 [FlutterBluetoothPluginPlatform.setCharacteristicNotification]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> setCharacteristicNotification({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required bool enable,
  }) async {
    await methodChannel
        .invokeMethod<void>('setCharacteristicNotification', <String, dynamic>{
      'deviceId': deviceId,
      'serviceUuid': serviceUuid,
      'characteristicUuid': characteristicUuid,
      'enable': enable,
    });
  }

  /// 实现 [FlutterBluetoothPluginPlatform.characteristicValues]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Stream<BluetoothCharacteristicValue> get characteristicValues {
    return _eventStream
        .where((event) => event['type'] == 'characteristicValue')
        .map(BluetoothCharacteristicValue.fromMap);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.readDescriptor]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<Uint8List> readDescriptor({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
  }) async {
    final response = await methodChannel.invokeMethod<Object?>(
      'readDescriptor',
      <String, dynamic>{
        'deviceId': deviceId,
        'serviceUuid': serviceUuid,
        'characteristicUuid': characteristicUuid,
        'descriptorUuid': descriptorUuid,
      },
    );
    return _byteListFromPlatform(response);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.writeDescriptor]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> writeDescriptor({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
    required Uint8List value,
  }) async {
    await methodChannel.invokeMethod<void>('writeDescriptor', <String, dynamic>{
      'deviceId': deviceId,
      'serviceUuid': serviceUuid,
      'characteristicUuid': characteristicUuid,
      'descriptorUuid': descriptorUuid,
      'value': value,
    });
  }

  /// 实现 [FlutterBluetoothPluginPlatform.descriptorValues]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Stream<BluetoothDescriptorValue> get descriptorValues {
    return _eventStream
        .where((event) => event['type'] == 'descriptorValue')
        .map(BluetoothDescriptorValue.fromMap);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.readRssi]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<int> readRssi(String deviceId) async {
    return await methodChannel.invokeMethod<int>('readRssi', <String, dynamic>{
          'deviceId': deviceId,
        }) ??
        0;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.rssiUpdates]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Stream<BluetoothRssiEvent> get rssiUpdates {
    return _eventStream
        .where((event) => event['type'] == 'rssi')
        .map(BluetoothRssiEvent.fromMap);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.requestMtu]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    return await methodChannel.invokeMethod<int>(
          'requestMtu',
          <String, dynamic>{'deviceId': deviceId, 'mtu': mtu},
        ) ??
        0;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.getMaximumWriteLength]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<int> getMaximumWriteLength(
    String deviceId, {
    bool withoutResponse = true,
  }) async {
    return await methodChannel.invokeMethod<int>(
          'getMaximumWriteLength',
          <String, dynamic>{
            'deviceId': deviceId,
            'withoutResponse': withoutResponse,
          },
        ) ??
        0;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.mtuUpdates]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Stream<BluetoothMtuEvent> get mtuUpdates {
    return _eventStream
        .where((event) => event['type'] == 'mtu')
        .map(BluetoothMtuEvent.fromMap);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.setPreferredPhy]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> setPreferredPhy({
    required String deviceId,
    required BluetoothPhy txPhy,
    required BluetoothPhy rxPhy,
    int phyOptions = 0,
  }) async {
    await methodChannel.invokeMethod<void>('setPreferredPhy', <String, dynamic>{
      'deviceId': deviceId,
      'txPhy': txPhy.name,
      'rxPhy': rxPhy.name,
      'phyOptions': phyOptions,
    });
  }

  /// 实现 [FlutterBluetoothPluginPlatform.readPhy]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<BluetoothPhyEvent> readPhy(String deviceId) async {
    final response = await methodChannel.invokeMapMethod<String, dynamic>(
      'readPhy',
      <String, dynamic>{'deviceId': deviceId},
    );
    return BluetoothPhyEvent.fromMap(response ?? <String, dynamic>{});
  }

  /// 实现 [FlutterBluetoothPluginPlatform.phyUpdates]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Stream<BluetoothPhyEvent> get phyUpdates {
    return _eventStream
        .where((event) => event['type'] == 'phy')
        .map(BluetoothPhyEvent.fromMap);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.requestConnectionPriority]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<bool> requestConnectionPriority(
    String deviceId,
    BluetoothConnectionPriority priority,
  ) async {
    return await methodChannel.invokeMethod<bool>(
          'requestConnectionPriority',
          <String, dynamic>{'deviceId': deviceId, 'priority': priority.name},
        ) ??
        false;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.createBond]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<bool> createBond(String deviceId) async {
    return await methodChannel.invokeMethod<bool>(
          'createBond',
          <String, dynamic>{'deviceId': deviceId},
        ) ??
        false;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.removeBond]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<bool> removeBond(String deviceId) async {
    return await methodChannel.invokeMethod<bool>(
          'removeBond',
          <String, dynamic>{'deviceId': deviceId},
        ) ??
        false;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.bondState]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Stream<BluetoothBondStateEvent> get bondState {
    return _eventStream
        .where((event) => event['type'] == 'bondState')
        .map(BluetoothBondStateEvent.fromMap);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.isPeripheralSupported]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<bool> isPeripheralSupported() async {
    return await methodChannel.invokeMethod<bool>('isPeripheralSupported') ??
        false;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.startAdvertising]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> startAdvertising({
    BluetoothAdvertisementData advertisementData =
        const BluetoothAdvertisementData(),
    BluetoothAdvertisementData? scanResponse,
    BluetoothAdvertisingSettings settings =
        const BluetoothAdvertisingSettings(),
  }) async {
    await methodChannel
        .invokeMethod<void>('startAdvertising', <String, dynamic>{
      'advertisementData': advertisementData.toMap(),
      'scanResponse': scanResponse?.toMap(),
      'settings': settings.toMap(),
    });
  }

  /// 实现 [FlutterBluetoothPluginPlatform.stopAdvertising]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> stopAdvertising() async {
    await methodChannel.invokeMethod<void>('stopAdvertising');
  }

  /// 实现 [FlutterBluetoothPluginPlatform.advertisingState]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Stream<BluetoothAdvertisingStateEvent> get advertisingState {
    return _eventStream
        .where((event) => event['type'] == 'advertisingState')
        .map(BluetoothAdvertisingStateEvent.fromMap);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.setGattServerServices]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> setGattServerServices(
    List<BluetoothGattService> services,
  ) async {
    await methodChannel.invokeMethod<void>(
      'setGattServerServices',
      <String, dynamic>{
        'services': services.map((service) => service.toMap()).toList(),
      },
    );
  }

  /// 实现 [FlutterBluetoothPluginPlatform.clearGattServerServices]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> clearGattServerServices() async {
    await methodChannel.invokeMethod<void>('clearGattServerServices');
  }

  /// 实现 [FlutterBluetoothPluginPlatform.updateLocalCharacteristicValue]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> updateLocalCharacteristicValue({
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
  }) async {
    await methodChannel
        .invokeMethod<void>('updateLocalCharacteristicValue', <String, dynamic>{
      'serviceUuid': serviceUuid,
      'characteristicUuid': characteristicUuid,
      'value': value,
    });
  }

  /// 实现 [FlutterBluetoothPluginPlatform.notifyGattServerCharacteristic]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<bool> notifyGattServerCharacteristic({
    String? deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    bool confirm = false,
  }) async {
    return await methodChannel.invokeMethod<bool>(
          'notifyGattServerCharacteristic',
          <String, dynamic>{
            'deviceId': deviceId,
            'serviceUuid': serviceUuid,
            'characteristicUuid': characteristicUuid,
            'value': value,
            'confirm': confirm,
          },
        ) ??
        false;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.gattServerRequests]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Stream<BluetoothGattServerRequest> get gattServerRequests {
    return _eventStream
        .where((event) => event['type'] == 'gattServerRequest')
        .map(BluetoothGattServerRequest.fromMap);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.connectClassic]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> connectClassic({
    required String deviceId,
    required String serviceUuid,
    bool secure = true,
    Duration? timeout,
  }) async {
    await methodChannel.invokeMethod<void>('connectClassic', <String, dynamic>{
      'deviceId': deviceId,
      'serviceUuid': serviceUuid,
      'secure': secure,
      'timeoutMs': timeout?.inMilliseconds,
    });
  }

  /// 实现 [FlutterBluetoothPluginPlatform.startClassicServer]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> startClassicServer({
    required String serviceUuid,
    String serviceName = 'FlutterBluetoothPlugin',
    bool secure = true,
  }) async {
    await methodChannel.invokeMethod<void>(
      'startClassicServer',
      <String, dynamic>{
        'serviceUuid': serviceUuid,
        'serviceName': serviceName,
        'secure': secure,
      },
    );
  }

  /// 实现 [FlutterBluetoothPluginPlatform.stopClassicServer]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> stopClassicServer() async {
    await methodChannel.invokeMethod<void>('stopClassicServer');
  }

  /// 实现 [FlutterBluetoothPluginPlatform.disconnectClassic]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> disconnectClassic(String deviceId) async {
    await methodChannel.invokeMethod<void>(
      'disconnectClassic',
      <String, dynamic>{'deviceId': deviceId},
    );
  }

  /// 实现 [FlutterBluetoothPluginPlatform.writeClassic]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Future<void> writeClassic(String deviceId, Uint8List value) async {
    await methodChannel.invokeMethod<void>('writeClassic', <String, dynamic>{
      'deviceId': deviceId,
      'value': value,
    });
  }

  /// 实现 [FlutterBluetoothPluginPlatform.classicConnectionState]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Stream<BluetoothClassicConnectionEvent> get classicConnectionState {
    return _eventStream
        .where((event) => event['type'] == 'classicConnection')
        .map(BluetoothClassicConnectionEvent.fromMap);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.classicData]。
  ///
  /// 参数、默认值、平台差异和推荐值见平台接口文档。
  @override
  Stream<BluetoothClassicDataEvent> get classicData {
    return _eventStream
        .where((event) => event['type'] == 'classicData')
        .map(BluetoothClassicDataEvent.fromMap);
  }

  Map<String, BluetoothPermissionStatus> _permissionMapFromPlatform(
    Map<String, dynamic>? response,
  ) {
    return (response ?? const <String, dynamic>{}).map(
      (key, value) =>
          MapEntry(key, bluetoothPermissionStatusFromString(value?.toString())),
    );
  }

  List<BluetoothDevice> _deviceListFromPlatform(List<dynamic>? response) {
    return (response ?? const <dynamic>[])
        .map((item) => BluetoothDevice.fromMap(_asStringMap(item)))
        .toList(growable: false);
  }

  Uint8List _byteListFromPlatform(Object? response) {
    if (response == null) {
      return Uint8List(0);
    }
    if (response is Uint8List) {
      return response;
    }
    if (response is ByteData) {
      return response.buffer.asUint8List(
        response.offsetInBytes,
        response.lengthInBytes,
      );
    }
    if (response is List<int>) {
      return Uint8List.fromList(response);
    }
    return Uint8List.fromList(
      (response as List<dynamic>).map((item) => (item as num).toInt()).toList(),
    );
  }

  Map<String, dynamic> _asStringMap(Object? value) {
    return Map<String, dynamic>.from(value as Map<dynamic, dynamic>);
  }
}
