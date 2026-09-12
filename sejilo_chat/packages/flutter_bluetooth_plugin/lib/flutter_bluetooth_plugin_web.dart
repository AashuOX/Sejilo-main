// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter
@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'flutter_bluetooth_plugin_models.dart';
import 'flutter_bluetooth_plugin_platform_interface.dart';

extension type _BluetoothDeviceFilter._(JSObject _) implements JSObject {
  external factory _BluetoothDeviceFilter({JSArray<JSString> services});
}

extension type _RequestDeviceOptions._(JSObject _) implements JSObject {
  external factory _RequestDeviceOptions({
    bool acceptAllDevices,
    JSArray<_BluetoothDeviceFilter> filters,
    JSArray<JSString> optionalServices,
  });
}

extension type _WebBluetooth._(JSObject _)
    implements web.EventTarget, JSObject {
  external JSPromise<JSBoolean> getAvailability();
  external JSPromise<_WebBluetoothDevice> requestDevice(
    _RequestDeviceOptions options,
  );
  external JSPromise<JSArray<_WebBluetoothDevice>> getDevices();
}

extension type _WebBluetoothDevice._(JSObject _)
    implements web.EventTarget, JSObject {
  external String get id;
  external String? get name;
  external _WebBluetoothRemoteGATTServer? get gatt;
}

extension type _WebBluetoothRemoteGATTServer._(JSObject _) implements JSObject {
  external bool get connected;
  external _WebBluetoothDevice get device;
  external JSPromise<_WebBluetoothRemoteGATTServer> connect();
  external void disconnect();
  external JSPromise<_WebBluetoothRemoteGATTService> getPrimaryService(
    String service,
  );
  external JSPromise<JSArray<_WebBluetoothRemoteGATTService>>
      getPrimaryServices([
    String service,
  ]);
}

extension type _WebBluetoothRemoteGATTService._(JSObject _)
    implements JSObject {
  external String get uuid;
  external bool get isPrimary;
  external _WebBluetoothDevice get device;
  external JSPromise<_WebBluetoothRemoteGATTCharacteristic> getCharacteristic(
    String characteristic,
  );
  external JSPromise<JSArray<_WebBluetoothRemoteGATTCharacteristic>>
      getCharacteristics([
    String characteristic,
  ]);
}

extension type _WebBluetoothCharacteristicProperties._(JSObject _)
    implements JSObject {
  external bool get broadcast;
  external bool get read;
  external bool get writeWithoutResponse;
  external bool get write;
  external bool get notify;
  external bool get indicate;
  external bool get authenticatedSignedWrites;
  external bool get reliableWrite;
  external bool get writableAuxiliaries;
}

extension type _WebBluetoothRemoteGATTCharacteristic._(JSObject _)
    implements web.EventTarget, JSObject {
  external String get uuid;
  external _WebBluetoothRemoteGATTService get service;
  external _WebBluetoothCharacteristicProperties get properties;
  external JSDataView? get value;
  external JSPromise<JSDataView> readValue();
  external JSPromise<JSAny?> writeValue(JSAny value);
  external JSPromise<JSAny?> writeValueWithResponse(JSAny value);
  external JSPromise<JSAny?> writeValueWithoutResponse(JSAny value);
  external JSPromise<_WebBluetoothRemoteGATTCharacteristic>
      startNotifications();
  external JSPromise<_WebBluetoothRemoteGATTCharacteristic> stopNotifications();
  external JSPromise<_WebBluetoothRemoteGATTDescriptor> getDescriptor(
    String descriptor,
  );
  external JSPromise<JSArray<_WebBluetoothRemoteGATTDescriptor>>
      getDescriptors([
    String descriptor,
  ]);
}

extension type _WebBluetoothRemoteGATTDescriptor._(JSObject _)
    implements JSObject {
  external String get uuid;
  external _WebBluetoothRemoteGATTCharacteristic get characteristic;
  external JSDataView? get value;
  external JSPromise<JSDataView> readValue();
  external JSPromise<JSAny?> writeValue(JSAny value);
}

/// Web 平台实现。
///
/// Web 端基于浏览器 Web Bluetooth API 实现 BLE Central/GATT Client 能力：
/// `startScan` 会打开浏览器设备选择器并把用户选中的设备作为一次扫描结果发送。
/// Web 不支持后台/被动扫描、RSSI、MTU 协商、PHY、配对管理、BLE 外设/广播和
/// Classic Bluetooth。
class FlutterBluetoothPluginWeb extends FlutterBluetoothPluginPlatform {
  /// 创建 Web 平台实现。
  ///
  /// 无参数、无默认值。
  FlutterBluetoothPluginWeb() {
    _attachAvailabilityListener();
  }

  final StreamController<BluetoothAdapterState> _adapterStateController =
      StreamController<BluetoothAdapterState>.broadcast();
  final StreamController<BluetoothScanResult> _scanResultsController =
      StreamController<BluetoothScanResult>.broadcast();
  final StreamController<BluetoothConnectionStateEvent>
      _connectionStateController =
      StreamController<BluetoothConnectionStateEvent>.broadcast();
  final StreamController<BluetoothCharacteristicValue>
      _characteristicValuesController =
      StreamController<BluetoothCharacteristicValue>.broadcast();
  final StreamController<BluetoothDescriptorValue> _descriptorValuesController =
      StreamController<BluetoothDescriptorValue>.broadcast();

  final Map<String, _WebBluetoothDevice> _knownDevices =
      <String, _WebBluetoothDevice>{};
  final Map<String, _WebBluetoothRemoteGATTServer> _gattServers =
      <String, _WebBluetoothRemoteGATTServer>{};
  final Map<String, List<_WebBluetoothRemoteGATTService>> _serviceCache =
      <String, List<_WebBluetoothRemoteGATTService>>{};
  final Map<String, web.EventListener> _disconnectListeners =
      <String, web.EventListener>{};
  final Map<String, web.EventListener> _notificationListeners =
      <String, web.EventListener>{};

  web.EventListener? _availabilityListener;
  bool _isSelectingDevice = false;

  /// 注册 Web 平台实现。
  ///
  /// 参数：
  /// - [registrar]：Flutter Web 插件注册器，无默认值。
  static void registerWith(Registrar registrar) {
    FlutterBluetoothPluginPlatform.instance = FlutterBluetoothPluginWeb();
  }

  /// 返回浏览器 User-Agent 作为平台版本字符串。
  ///
  /// 无参数；其它 API 的参数、默认值和平台差异见平台接口文档。
  @override
  Future<String?> getPlatformVersion() async {
    return web.window.navigator.userAgent;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.isSupported]。
  ///
  /// Web 端需要安全上下文（HTTPS 或 localhost）且浏览器提供 Web Bluetooth API。
  @override
  Future<bool> isSupported() async => _isWebBluetoothSupported;

  /// 实现 [FlutterBluetoothPluginPlatform.getAdapterState]。
  ///
  /// Web 端通过 `navigator.bluetooth.getAvailability()` 映射为 poweredOn/poweredOff；
  /// 浏览器不支持 Web Bluetooth 或非安全上下文时返回 unsupported。
  @override
  Future<BluetoothAdapterState> getAdapterState() async {
    if (!_isWebBluetoothSupported) {
      return BluetoothAdapterState.unsupported;
    }
    final available = await _getAvailability();
    if (available == null) {
      return BluetoothAdapterState.unknown;
    }
    return available
        ? BluetoothAdapterState.poweredOn
        : BluetoothAdapterState.poweredOff;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.getAdapterInfo]。
  ///
  /// Web 不公开适配器名称、地址或 Android 专属硬件能力。
  @override
  Future<BluetoothAdapterInfo> getAdapterInfo() async {
    final supported = _isWebBluetoothSupported;
    final state = await getAdapterState();
    return BluetoothAdapterInfo(
      isSupported: supported,
      state: state,
      isBleSupported: supported,
      isDiscovering: _isSelectingDevice,
      raw: <String, dynamic>{
        'platform': 'web',
        'secureContext': web.window.isSecureContext,
        'hasWebBluetooth': _bluetooth != null,
      },
    );
  }

  /// 实现 [FlutterBluetoothPluginPlatform.isScanning]。
  ///
  /// Web 没有持续扫描状态；这里只在浏览器设备选择器打开期间返回 `true`。
  @override
  Future<bool> isScanning() async => _isSelectingDevice;

  /// 实现 [FlutterBluetoothPluginPlatform.setAdapterName]。
  ///
  /// Web Bluetooth 不允许网页修改主机蓝牙适配器名称。
  @override
  Future<bool> setAdapterName(String name) async => false;

  /// 实现 [FlutterBluetoothPluginPlatform.adapterState]。
  ///
  /// 订阅时先发送当前映射状态，随后转发浏览器 availabilitychanged 事件。
  @override
  Stream<BluetoothAdapterState> get adapterState async* {
    yield await getAdapterState();
    yield* _adapterStateController.stream;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.checkPermissions]。
  ///
  /// Web Bluetooth 没有全局预授权；已授权过设备时返回 granted，否则返回 notDetermined。
  @override
  Future<Map<String, BluetoothPermissionStatus>> checkPermissions() async {
    if (!_isWebBluetoothSupported) {
      return const <String, BluetoothPermissionStatus>{
        'bluetooth': BluetoothPermissionStatus.notApplicable,
      };
    }
    final devices = await _authorizedDevices();
    return <String, BluetoothPermissionStatus>{
      'bluetooth': devices.isEmpty
          ? BluetoothPermissionStatus.notDetermined
          : BluetoothPermissionStatus.granted,
    };
  }

  /// 实现 [FlutterBluetoothPluginPlatform.requestPermissions]。
  ///
  /// Web 端不能脱离用户手势预先弹出蓝牙授权；请通过 [startScan] 打开设备选择器。
  @override
  Future<Map<String, BluetoothPermissionStatus>> requestPermissions() {
    return checkPermissions();
  }

  /// 实现 [FlutterBluetoothPluginPlatform.requestEnable]。
  ///
  /// 浏览器不允许网页直接开启系统蓝牙。
  @override
  Future<bool> requestEnable() async => false;

  /// 实现 [FlutterBluetoothPluginPlatform.openBluetoothSettings]。
  ///
  /// Web 端没有可标准化打开的蓝牙设置页。
  @override
  Future<void> openBluetoothSettings() async {}

  /// 实现 [FlutterBluetoothPluginPlatform.startScan]。
  ///
  /// Web 会打开设备选择器并返回用户选中的单个 BLE 设备；不是被动扫描。
  @override
  Future<void> startScan({
    List<String> serviceUuids = const <String>[],
    Duration? timeout,
    bool allowDuplicates = false,
    BluetoothScanMode scanMode = BluetoothScanMode.ble,
  }) async {
    if (scanMode == BluetoothScanMode.classic) {
      throw UnsupportedError('Web Bluetooth supports BLE devices only.');
    }

    final bluetooth = _requireBluetooth();
    final state = await getAdapterState();
    if (state == BluetoothAdapterState.poweredOff) {
      throw StateError(
          'Bluetooth is not available or powered on in the browser.');
    }

    _isSelectingDevice = true;
    try {
      final device = await bluetooth
          .requestDevice(_requestDeviceOptions(serviceUuids))
          .toDart;
      _rememberDevice(device);
      _scanResultsController.add(
        BluetoothScanResult(
          device: _deviceFromWeb(device),
          rssi: 0,
          localName: device.name,
          serviceUuids: serviceUuids,
          raw: <String, dynamic>{
            'platform': 'web',
            'chooserResult': true,
            'allowDuplicatesIgnored': allowDuplicates,
            'timeoutIgnored': timeout != null,
            'scanMode': scanMode.name,
          },
        ),
      );
    } finally {
      _isSelectingDevice = false;
    }
  }

  /// 实现 [FlutterBluetoothPluginPlatform.stopScan]。
  ///
  /// Web 设备选择器无法由网页主动关闭；本方法仅清理本地 selecting 标记。
  @override
  Future<void> stopScan() async {
    _isSelectingDevice = false;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.scanResults]。
  ///
  /// Web 端每次 [startScan] 成功只产生一条用户选择的设备结果。
  @override
  Stream<BluetoothScanResult> get scanResults => _scanResultsController.stream;

  /// 实现 [FlutterBluetoothPluginPlatform.getBondedDevices]。
  ///
  /// Web 不公开系统配对列表；这里返回浏览器已授权给当前站点的设备。
  @override
  Future<List<BluetoothDevice>> getBondedDevices() async {
    final devices = await _authorizedDevices();
    return devices.map(_deviceFromWeb).toList(growable: false);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.getConnectedDevices]。
  ///
  /// Web 返回当前站点已知且 GATT 已连接的设备；服务过滤只对已授权服务有效。
  @override
  Future<List<BluetoothDevice>> getConnectedDevices({
    List<String> serviceUuids = const <String>[],
  }) async {
    final devices = await _authorizedDevices();
    final connected = devices.where((device) => device.gatt?.connected == true);
    final results = <BluetoothDevice>[];
    for (final device in connected) {
      if (serviceUuids.isEmpty || await _hasAnyService(device, serviceUuids)) {
        results.add(_deviceFromWeb(device));
      }
    }
    return results;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.getDevice]。
  ///
  /// Web 只能返回当前站点已授权或本次页面已选择过的设备。
  @override
  Future<BluetoothDevice?> getDevice(String deviceId) async {
    await _authorizedDevices();
    final device = _knownDevices[deviceId];
    return device == null ? null : _deviceFromWeb(device);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.getDevices]。
  ///
  /// Web 只能按 ID 返回当前站点已授权或本次页面已选择过的设备。
  @override
  Future<List<BluetoothDevice>> getDevices(List<String> deviceIds) async {
    await _authorizedDevices();
    return deviceIds
        .map((deviceId) => _knownDevices[deviceId])
        .whereType<_WebBluetoothDevice>()
        .map(_deviceFromWeb)
        .toList(growable: false);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.connect]。
  ///
  /// Web 只能连接已通过选择器授权给当前站点的 BLE GATT 设备。
  @override
  Future<void> connect(
    String deviceId, {
    bool autoConnect = false,
    Duration? timeout,
  }) async {
    final device = await _requireDevice(deviceId);
    final gatt = _requireGatt(device);
    if (gatt.connected) {
      _gattServers[deviceId] = gatt;
      _sendConnectionState(deviceId, BluetoothConnectionState.connected);
      return;
    }

    _sendConnectionState(deviceId, BluetoothConnectionState.connecting);
    try {
      final connectFuture = gatt.connect().toDart;
      final server = timeout == null
          ? await connectFuture
          : await connectFuture.timeout(timeout, onTimeout: () {
              gatt.disconnect();
              throw TimeoutException('Web Bluetooth connection timed out.');
            });
      _gattServers[deviceId] = server;
      _sendConnectionState(deviceId, BluetoothConnectionState.connected);
    } catch (_) {
      _sendConnectionState(deviceId, BluetoothConnectionState.disconnected);
      rethrow;
    }
  }

  /// 实现 [FlutterBluetoothPluginPlatform.disconnect]。
  ///
  /// Web 端断开已知设备；未知设备视为无操作。
  @override
  Future<void> disconnect(String deviceId) async {
    final device = _knownDevices[deviceId];
    final gatt = device?.gatt ?? _gattServers[deviceId];
    gatt?.disconnect();
    _gattServers.remove(deviceId);
    _serviceCache.remove(deviceId);
    _sendConnectionState(deviceId, BluetoothConnectionState.disconnected);
  }

  /// 实现 [FlutterBluetoothPluginPlatform.getConnectionState]。
  ///
  /// Web 根据已知设备的 `gatt.connected` 属性返回连接状态。
  @override
  Future<BluetoothConnectionState> getConnectionState(String deviceId) async {
    await _authorizedDevices();
    return _knownDevices[deviceId]?.gatt?.connected == true
        ? BluetoothConnectionState.connected
        : BluetoothConnectionState.disconnected;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.connectionState]。
  ///
  /// Web 端推送本插件发起连接/断开以及浏览器 gattserverdisconnected 事件。
  @override
  Stream<BluetoothConnectionStateEvent> get connectionState {
    return _connectionStateController.stream;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.discoverServices]。
  ///
  /// Web 只能发现设备授权范围内的 GATT 服务；请在 [startScan] 传入目标服务 UUID。
  @override
  Future<List<BluetoothGattService>> discoverServices(String deviceId) async {
    final server = await _connectedServer(deviceId);
    final webServices = (await server.getPrimaryServices().toDart).toDart;
    _serviceCache[deviceId] = webServices;

    final services = <BluetoothGattService>[];
    for (final service in webServices) {
      services.add(await _serviceFromWeb(service));
    }
    return services;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.readCharacteristic]。
  ///
  /// Web 要求服务 UUID 已在设备选择时授权。
  @override
  Future<Uint8List> readCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    final characteristic = await _characteristic(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );
    final bytes = _bytesFromDataView(await characteristic.readValue().toDart);
    _characteristicValuesController.add(
      BluetoothCharacteristicValue(
        deviceId: deviceId,
        serviceUuid: serviceUuid,
        characteristicUuid: characteristicUuid,
        value: bytes,
      ),
    );
    return bytes;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.writeCharacteristic]。
  ///
  /// Web 会优先使用 writeValueWithResponse/writeValueWithoutResponse，必要时回退到旧版 writeValue。
  @override
  Future<void> writeCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    BluetoothWriteType writeType = BluetoothWriteType.withResponse,
  }) async {
    final characteristic = await _characteristic(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );
    final data = value.toJS;
    final object = characteristic as JSObject;
    if (writeType == BluetoothWriteType.withoutResponse &&
        object.has('writeValueWithoutResponse')) {
      await characteristic.writeValueWithoutResponse(data).toDart;
      return;
    }
    if (writeType == BluetoothWriteType.withResponse &&
        object.has('writeValueWithResponse')) {
      await characteristic.writeValueWithResponse(data).toDart;
      return;
    }
    await characteristic.writeValue(data).toDart;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.setCharacteristicNotification]。
  ///
  /// Web 通过 startNotifications/stopNotifications 管理订阅，不直接写 CCCD。
  @override
  Future<void> setCharacteristicNotification({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required bool enable,
  }) async {
    final key = _characteristicKey(deviceId, serviceUuid, characteristicUuid);
    final characteristic = await _characteristic(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );

    final existing = _notificationListeners.remove(key);
    if (existing != null) {
      characteristic.removeEventListener(
          'characteristicvaluechanged', existing);
    }

    if (!enable) {
      await characteristic.stopNotifications().toDart;
      return;
    }

    final listener = ((web.Event event) {
      final bytes = _bytesFromDataView(characteristic.value);
      _characteristicValuesController.add(
        BluetoothCharacteristicValue(
          deviceId: deviceId,
          serviceUuid: serviceUuid,
          characteristicUuid: characteristicUuid,
          value: bytes,
        ),
      );
    }).toJS;

    characteristic.addEventListener('characteristicvaluechanged', listener);
    _notificationListeners[key] = listener;
    try {
      await characteristic.startNotifications().toDart;
    } catch (_) {
      characteristic.removeEventListener(
          'characteristicvaluechanged', listener);
      _notificationListeners.remove(key);
      rethrow;
    }
  }

  /// 实现 [FlutterBluetoothPluginPlatform.characteristicValues]。
  ///
  /// Web 端包含特征 readValue 结果和通知事件。
  @override
  Stream<BluetoothCharacteristicValue> get characteristicValues {
    return _characteristicValuesController.stream;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.readDescriptor]。
  ///
  /// Web 要求服务 UUID 已在设备选择时授权。
  @override
  Future<Uint8List> readDescriptor({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
  }) async {
    final descriptor = await _descriptor(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      descriptorUuid: descriptorUuid,
    );
    final bytes = _bytesFromDataView(await descriptor.readValue().toDart);
    _descriptorValuesController.add(
      BluetoothDescriptorValue(
        deviceId: deviceId,
        serviceUuid: serviceUuid,
        characteristicUuid: characteristicUuid,
        descriptorUuid: descriptorUuid,
        value: bytes,
      ),
    );
    return bytes;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.writeDescriptor]。
  ///
  /// Web 不允许通过描述符写入来订阅通知；请使用 [setCharacteristicNotification]。
  @override
  Future<void> writeDescriptor({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
    required Uint8List value,
  }) async {
    final descriptor = await _descriptor(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      descriptorUuid: descriptorUuid,
    );
    await descriptor.writeValue(value.toJS).toDart;
    _descriptorValuesController.add(
      BluetoothDescriptorValue(
        deviceId: deviceId,
        serviceUuid: serviceUuid,
        characteristicUuid: characteristicUuid,
        descriptorUuid: descriptorUuid,
        value: value,
      ),
    );
  }

  /// 实现 [FlutterBluetoothPluginPlatform.descriptorValues]。
  ///
  /// Web 端包含描述符 readValue/writeValue 后的本地事件。
  @override
  Stream<BluetoothDescriptorValue> get descriptorValues {
    return _descriptorValuesController.stream;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.readRssi]。
  ///
  /// Web Bluetooth 不公开 RSSI。
  @override
  Future<int> readRssi(String deviceId) {
    throw UnsupportedError('RSSI reads are not supported by Web Bluetooth.');
  }

  /// 实现 [FlutterBluetoothPluginPlatform.rssiUpdates]。
  ///
  /// Web Bluetooth 不公开 RSSI。
  @override
  Stream<BluetoothRssiEvent> get rssiUpdates =>
      const Stream<BluetoothRssiEvent>.empty();

  /// 实现 [FlutterBluetoothPluginPlatform.requestMtu]。
  ///
  /// Web Bluetooth 不公开 MTU 协商。
  @override
  Future<int> requestMtu(String deviceId, int mtu) async => 0;

  /// 实现 [FlutterBluetoothPluginPlatform.getMaximumWriteLength]。
  ///
  /// Web Bluetooth 不公开最大写入长度。
  @override
  Future<int> getMaximumWriteLength(
    String deviceId, {
    bool withoutResponse = true,
  }) async {
    return 0;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.mtuUpdates]。
  ///
  /// Web Bluetooth 不公开 MTU 更新。
  @override
  Stream<BluetoothMtuEvent> get mtuUpdates =>
      const Stream<BluetoothMtuEvent>.empty();

  /// 实现 [FlutterBluetoothPluginPlatform.setPreferredPhy]。
  ///
  /// Web Bluetooth 不支持 PHY 选择。
  @override
  Future<void> setPreferredPhy({
    required String deviceId,
    required BluetoothPhy txPhy,
    required BluetoothPhy rxPhy,
    int phyOptions = 0,
  }) {
    throw UnsupportedError('LE PHY APIs are not supported by Web Bluetooth.');
  }

  /// 实现 [FlutterBluetoothPluginPlatform.readPhy]。
  ///
  /// Web Bluetooth 不支持读取 PHY。
  @override
  Future<BluetoothPhyEvent> readPhy(String deviceId) async {
    return BluetoothPhyEvent(
      deviceId: deviceId,
      txPhy: BluetoothPhy.unknown,
      rxPhy: BluetoothPhy.unknown,
    );
  }

  /// 实现 [FlutterBluetoothPluginPlatform.phyUpdates]。
  ///
  /// Web Bluetooth 不推送 PHY 变化。
  @override
  Stream<BluetoothPhyEvent> get phyUpdates {
    return const Stream<BluetoothPhyEvent>.empty();
  }

  /// 实现 [FlutterBluetoothPluginPlatform.requestConnectionPriority]。
  ///
  /// Web Bluetooth 不支持连接优先级请求。
  @override
  Future<bool> requestConnectionPriority(
    String deviceId,
    BluetoothConnectionPriority priority,
  ) async {
    return false;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.createBond]。
  ///
  /// Web Bluetooth 不公开系统配对管理。
  @override
  Future<bool> createBond(String deviceId) async => false;

  /// 实现 [FlutterBluetoothPluginPlatform.removeBond]。
  ///
  /// Web Bluetooth 不公开系统配对管理。
  @override
  Future<bool> removeBond(String deviceId) async => false;

  /// 实现 [FlutterBluetoothPluginPlatform.bondState]。
  ///
  /// Web Bluetooth 不推送系统配对状态。
  @override
  Stream<BluetoothBondStateEvent> get bondState {
    return const Stream<BluetoothBondStateEvent>.empty();
  }

  /// 实现 [FlutterBluetoothPluginPlatform.isPeripheralSupported]。
  ///
  /// Web Bluetooth 不支持 BLE 外设/广播模式。
  @override
  Future<bool> isPeripheralSupported() async => false;

  /// 实现 [FlutterBluetoothPluginPlatform.startAdvertising]。
  ///
  /// Web Bluetooth 不支持 BLE 外设/广播模式。
  @override
  Future<void> startAdvertising({
    BluetoothAdvertisementData advertisementData =
        const BluetoothAdvertisementData(),
    BluetoothAdvertisementData? scanResponse,
    BluetoothAdvertisingSettings settings =
        const BluetoothAdvertisingSettings(),
  }) {
    throw UnsupportedError(
        'BLE advertising is not supported by Web Bluetooth.');
  }

  /// 实现 [FlutterBluetoothPluginPlatform.stopAdvertising]。
  ///
  /// Web Bluetooth 没有可停止的广播资源。
  @override
  Future<void> stopAdvertising() async {}

  /// 实现 [FlutterBluetoothPluginPlatform.advertisingState]。
  ///
  /// Web Bluetooth 不支持 BLE 外设/广播模式。
  @override
  Stream<BluetoothAdvertisingStateEvent> get advertisingState {
    return const Stream<BluetoothAdvertisingStateEvent>.empty();
  }

  /// 实现 [FlutterBluetoothPluginPlatform.setGattServerServices]。
  ///
  /// Web Bluetooth 不支持本地 GATT Server。
  @override
  Future<void> setGattServerServices(List<BluetoothGattService> services) {
    throw UnsupportedError(
        'GATT server APIs are not supported by Web Bluetooth.');
  }

  /// 实现 [FlutterBluetoothPluginPlatform.clearGattServerServices]。
  ///
  /// Web Bluetooth 没有可清理的本地 GATT Server。
  @override
  Future<void> clearGattServerServices() async {}

  /// 实现 [FlutterBluetoothPluginPlatform.updateLocalCharacteristicValue]。
  ///
  /// Web Bluetooth 不支持本地 GATT Server。
  @override
  Future<void> updateLocalCharacteristicValue({
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
  }) {
    throw UnsupportedError(
        'GATT server APIs are not supported by Web Bluetooth.');
  }

  /// 实现 [FlutterBluetoothPluginPlatform.notifyGattServerCharacteristic]。
  ///
  /// Web Bluetooth 不支持本地 GATT Server。
  @override
  Future<bool> notifyGattServerCharacteristic({
    String? deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    bool confirm = false,
  }) async {
    return false;
  }

  /// 实现 [FlutterBluetoothPluginPlatform.gattServerRequests]。
  ///
  /// Web Bluetooth 不支持本地 GATT Server。
  @override
  Stream<BluetoothGattServerRequest> get gattServerRequests {
    return const Stream<BluetoothGattServerRequest>.empty();
  }

  /// 实现 [FlutterBluetoothPluginPlatform.connectClassic]。
  ///
  /// Web Bluetooth 不支持 Classic Bluetooth/RFCOMM。
  @override
  Future<void> connectClassic({
    required String deviceId,
    required String serviceUuid,
    bool secure = true,
    Duration? timeout,
  }) {
    throw UnsupportedError('Classic Bluetooth is not supported on web.');
  }

  /// 实现 [FlutterBluetoothPluginPlatform.startClassicServer]。
  ///
  /// Web Bluetooth 不支持 Classic Bluetooth/RFCOMM。
  @override
  Future<void> startClassicServer({
    required String serviceUuid,
    String serviceName = 'FlutterBluetoothPlugin',
    bool secure = true,
  }) {
    throw UnsupportedError('Classic Bluetooth is not supported on web.');
  }

  /// 实现 [FlutterBluetoothPluginPlatform.stopClassicServer]。
  ///
  /// Web Bluetooth 没有 Classic Server 资源。
  @override
  Future<void> stopClassicServer() async {}

  /// 实现 [FlutterBluetoothPluginPlatform.disconnectClassic]。
  ///
  /// Web Bluetooth 没有 Classic 连接资源。
  @override
  Future<void> disconnectClassic(String deviceId) async {}

  /// 实现 [FlutterBluetoothPluginPlatform.writeClassic]。
  ///
  /// Web Bluetooth 不支持 Classic Bluetooth/RFCOMM。
  @override
  Future<void> writeClassic(String deviceId, Uint8List value) {
    throw UnsupportedError('Classic Bluetooth is not supported on web.');
  }

  /// 实现 [FlutterBluetoothPluginPlatform.classicConnectionState]。
  ///
  /// Web Bluetooth 不支持 Classic Bluetooth/RFCOMM。
  @override
  Stream<BluetoothClassicConnectionEvent> get classicConnectionState {
    return const Stream<BluetoothClassicConnectionEvent>.empty();
  }

  /// 实现 [FlutterBluetoothPluginPlatform.classicData]。
  ///
  /// Web Bluetooth 不支持 Classic Bluetooth/RFCOMM。
  @override
  Stream<BluetoothClassicDataEvent> get classicData {
    return const Stream<BluetoothClassicDataEvent>.empty();
  }

  bool get _isWebBluetoothSupported {
    return web.window.isSecureContext && _bluetooth != null;
  }

  _WebBluetooth? get _bluetooth {
    final navigator = web.window.navigator as JSObject;
    if (!navigator.has('bluetooth')) {
      return null;
    }
    return navigator.getProperty<_WebBluetooth?>('bluetooth'.toJS);
  }

  _WebBluetooth _requireBluetooth() {
    if (!web.window.isSecureContext) {
      throw UnsupportedError(
        'Web Bluetooth requires a secure context (HTTPS or localhost).',
      );
    }
    final bluetooth = _bluetooth;
    if (bluetooth == null) {
      throw UnsupportedError('Web Bluetooth is not supported by this browser.');
    }
    return bluetooth;
  }

  Future<bool?> _getAvailability() async {
    final bluetooth = _bluetooth;
    if (bluetooth == null) {
      return null;
    }
    if (!(bluetooth as JSObject).has('getAvailability')) {
      return true;
    }
    try {
      return (await bluetooth.getAvailability().toDart).toDart;
    } catch (_) {
      return null;
    }
  }

  void _attachAvailabilityListener() {
    final bluetooth = _bluetooth;
    if (bluetooth == null || _availabilityListener != null) {
      return;
    }
    final listener = ((web.Event event) {
      final value = (event as JSObject).getProperty<JSBoolean?>('value'.toJS);
      if (value == null) {
        return;
      }
      _adapterStateController.add(
        value.toDart
            ? BluetoothAdapterState.poweredOn
            : BluetoothAdapterState.poweredOff,
      );
    }).toJS;
    bluetooth.addEventListener('availabilitychanged', listener);
    _availabilityListener = listener;
  }

  _RequestDeviceOptions _requestDeviceOptions(List<String> serviceUuids) {
    if (serviceUuids.isEmpty) {
      return _RequestDeviceOptions(acceptAllDevices: true);
    }
    final services = _uuidArray(serviceUuids);
    return _RequestDeviceOptions(
      filters: <_BluetoothDeviceFilter>[
        _BluetoothDeviceFilter(services: services),
      ].toJS,
      optionalServices: services,
    );
  }

  JSArray<JSString> _uuidArray(List<String> uuids) {
    return uuids.map((uuid) => uuid.toJS).toList(growable: false).toJS;
  }

  Future<List<_WebBluetoothDevice>> _authorizedDevices() async {
    final bluetooth = _bluetooth;
    if (bluetooth != null && (bluetooth as JSObject).has('getDevices')) {
      try {
        final devices = (await bluetooth.getDevices().toDart).toDart;
        for (final device in devices) {
          _rememberDevice(device);
        }
      } catch (_) {
        // Some browsers expose Web Bluetooth but not getDevices(). Known devices
        // from this page session still remain usable.
      }
    }
    return _knownDevices.values.toList(growable: false);
  }

  Future<_WebBluetoothDevice> _requireDevice(String deviceId) async {
    await _authorizedDevices();
    final device = _knownDevices[deviceId];
    if (device == null) {
      throw StateError(
        'Device $deviceId is not available on web. Call startScan() from a user gesture first.',
      );
    }
    return device;
  }

  _WebBluetoothRemoteGATTServer _requireGatt(_WebBluetoothDevice device) {
    final gatt = device.gatt;
    if (gatt == null) {
      throw UnsupportedError(
          'The selected Web Bluetooth device has no GATT server.');
    }
    return gatt;
  }

  Future<_WebBluetoothRemoteGATTServer> _connectedServer(
    String deviceId,
  ) async {
    final device = await _requireDevice(deviceId);
    final gatt = device.gatt ?? _gattServers[deviceId];
    if (gatt == null || !gatt.connected) {
      throw StateError('Device $deviceId is not connected.');
    }
    return gatt;
  }

  void _rememberDevice(_WebBluetoothDevice device) {
    final deviceId = device.id;
    _knownDevices[deviceId] = device;
    if (_disconnectListeners.containsKey(deviceId)) {
      return;
    }

    final listener = ((web.Event event) {
      _gattServers.remove(deviceId);
      _serviceCache.remove(deviceId);
      _sendConnectionState(deviceId, BluetoothConnectionState.disconnected);
    }).toJS;
    device.addEventListener('gattserverdisconnected', listener);
    _disconnectListeners[deviceId] = listener;
  }

  BluetoothDevice _deviceFromWeb(_WebBluetoothDevice device) {
    final gatt = device.gatt;
    return BluetoothDevice(
      id: device.id,
      name: device.name,
      type: 'ble',
      isConnected: gatt?.connected == true,
      raw: <String, dynamic>{
        'platform': 'web',
        'id': device.id,
        'name': device.name,
        'isGattConnected': gatt?.connected == true,
      },
    );
  }

  Future<bool> _hasAnyService(
    _WebBluetoothDevice device,
    List<String> serviceUuids,
  ) async {
    final gatt = device.gatt;
    if (gatt == null || !gatt.connected) {
      return false;
    }
    for (final serviceUuid in serviceUuids) {
      try {
        await gatt.getPrimaryService(serviceUuid).toDart;
        return true;
      } catch (_) {
        // Continue checking other service UUIDs.
      }
    }
    return false;
  }

  Future<_WebBluetoothRemoteGATTService> _service({
    required String deviceId,
    required String serviceUuid,
  }) async {
    final cachedServices = _serviceCache[deviceId];
    if (cachedServices != null) {
      for (final service in cachedServices) {
        if (_sameUuid(service.uuid, serviceUuid)) {
          return service;
        }
      }
    }

    final server = await _connectedServer(deviceId);
    final service = await server.getPrimaryService(serviceUuid).toDart;
    _serviceCache.update(
      deviceId,
      (services) {
        if (!services.any((item) => _sameUuid(item.uuid, service.uuid))) {
          services.add(service);
        }
        return services;
      },
      ifAbsent: () => <_WebBluetoothRemoteGATTService>[service],
    );
    return service;
  }

  Future<_WebBluetoothRemoteGATTCharacteristic> _characteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    final service =
        await _service(deviceId: deviceId, serviceUuid: serviceUuid);
    return service.getCharacteristic(characteristicUuid).toDart;
  }

  Future<_WebBluetoothRemoteGATTDescriptor> _descriptor({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
  }) async {
    final characteristic = await _characteristic(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );
    return characteristic.getDescriptor(descriptorUuid).toDart;
  }

  Future<BluetoothGattService> _serviceFromWeb(
    _WebBluetoothRemoteGATTService service,
  ) async {
    final webCharacteristics =
        (await service.getCharacteristics().toDart).toDart;
    final characteristics = <BluetoothGattCharacteristic>[];
    for (final characteristic in webCharacteristics) {
      characteristics.add(await _characteristicFromWeb(characteristic));
    }
    return BluetoothGattService(
      uuid: service.uuid,
      isPrimary: service.isPrimary,
      characteristics: characteristics,
      raw: <String, dynamic>{'platform': 'web'},
    );
  }

  Future<BluetoothGattCharacteristic> _characteristicFromWeb(
    _WebBluetoothRemoteGATTCharacteristic characteristic,
  ) async {
    final descriptors = <BluetoothGattDescriptor>[];
    try {
      final webDescriptors =
          (await characteristic.getDescriptors().toDart).toDart;
      for (final descriptor in webDescriptors) {
        descriptors.add(_descriptorFromWeb(descriptor));
      }
    } catch (_) {
      // Descriptors are optional and may be hidden by browser permissions.
    }

    return BluetoothGattCharacteristic(
      uuid: characteristic.uuid,
      serviceUuid: characteristic.service.uuid,
      properties: _propertiesFromWeb(characteristic.properties),
      value: _bytesFromDataView(characteristic.value),
      descriptors: descriptors,
      raw: <String, dynamic>{'platform': 'web'},
    );
  }

  BluetoothGattDescriptor _descriptorFromWeb(
    _WebBluetoothRemoteGATTDescriptor descriptor,
  ) {
    return BluetoothGattDescriptor(
      uuid: descriptor.uuid,
      characteristicUuid: descriptor.characteristic.uuid,
      value: _bytesFromDataView(descriptor.value),
      raw: <String, dynamic>{'platform': 'web'},
    );
  }

  List<String> _propertiesFromWeb(
    _WebBluetoothCharacteristicProperties properties,
  ) {
    final result = <String>[];
    if (properties.broadcast) result.add('broadcast');
    if (properties.read) result.add('read');
    if (properties.writeWithoutResponse) result.add('writeWithoutResponse');
    if (properties.write) result.add('write');
    if (properties.notify) result.add('notify');
    if (properties.indicate) result.add('indicate');
    if (properties.authenticatedSignedWrites) {
      result.add('authenticatedSignedWrites');
    }
    if (properties.reliableWrite) result.add('reliableWrite');
    if (properties.writableAuxiliaries) result.add('writableAuxiliaries');
    return result;
  }

  Uint8List _bytesFromDataView(JSDataView? value) {
    if (value == null) {
      return Uint8List(0);
    }
    final byteData = value.toDart;
    return Uint8List.view(
      byteData.buffer,
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
  }

  void _sendConnectionState(
    String deviceId,
    BluetoothConnectionState state,
  ) {
    _connectionStateController.add(
      BluetoothConnectionStateEvent(deviceId: deviceId, state: state),
    );
  }

  String _characteristicKey(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) {
    return '$deviceId|${serviceUuid.toLowerCase()}|${characteristicUuid.toLowerCase()}';
  }

  bool _sameUuid(String first, String second) {
    return first.toLowerCase() == second.toLowerCase();
  }
}
