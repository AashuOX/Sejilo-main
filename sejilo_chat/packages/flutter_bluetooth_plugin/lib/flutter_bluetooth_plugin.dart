import 'dart:typed_data';

import 'flutter_bluetooth_plugin_models.dart';
import 'flutter_bluetooth_plugin_platform_interface.dart';

export 'flutter_bluetooth_plugin_models.dart';

/// Flutter 蓝牙插件的对外入口。
///
/// 主要覆盖 Android、iOS、macOS、Linux、Windows 的 BLE 中心设备与 GATT 客户端能力；
/// Android、iOS、macOS 还提供外设/广播能力，Android 额外提供 Classic RFCOMM、
/// MTU、PHY、绑定和连接优先级等系统能力；Linux 基于 BlueZ DBus，Windows 基于 WinRT。
/// Web 端基于浏览器 Web Bluetooth 支持受用户选择器约束的 BLE Central/GATT Client。
class FlutterBluetoothPlugin {
  /// 创建一个蓝牙插件访问对象。
  ///
  /// 无参数、无默认值；内部使用当前注册的平台实现。
  const FlutterBluetoothPlugin();

  FlutterBluetoothPluginPlatform get _platform =>
      FlutterBluetoothPluginPlatform.instance;

  /// 获取当前运行平台版本字符串。
  ///
  /// 无参数。Android 返回类似 `Android 14`，iOS 返回类似 `iOS 17.0`，macOS
  /// 返回类似 `macOS Version 14.0`；Linux 返回内核版本字符串；Windows 返回类似
  /// `Windows 10+`；Web 返回浏览器 User-Agent。
  Future<String?> getPlatformVersion() {
    return _platform.getPlatformVersion();
  }

  /// 判断当前设备/平台是否支持蓝牙能力。
  ///
  /// 无参数。Android/iOS/macOS 会查询系统蓝牙能力；Web 在安全上下文且浏览器
  /// 提供 Web Bluetooth API 时返回 `true`；Linux 会查询 BlueZ 适配器；Windows 会查询系统
  /// BLE 适配器。
  Future<bool> isSupported() {
    return _platform.isSupported();
  }

  /// 获取蓝牙适配器当前状态。
  ///
  /// 无参数。Android/iOS/macOS 返回真实状态；Linux 映射 BlueZ Adapter `Powered`，
  /// 找不到适配器时返回 [BluetoothAdapterState.unsupported]；Web 通过浏览器
  /// `navigator.bluetooth.getAvailability()` 映射为 poweredOn/poweredOff，不支持时返回
  /// [BluetoothAdapterState.unsupported]。建议在扫描、连接或广播前确认状态为
  /// [BluetoothAdapterState.poweredOn]。
  Future<BluetoothAdapterState> getAdapterState() {
    return _platform.getAdapterState();
  }

  /// 获取蓝牙适配器信息和平台能力。
  ///
  /// 无参数。Android 会返回更多硬件能力字段；iOS/macOS 仅公开 CoreBluetooth 允许的
  /// 信息，PHY、扩展广播、离线过滤等 Android 专属能力通常为 `false`；Linux
  /// 公开 BlueZ 适配器名称、地址、Powered/Discovering 状态和原始 DBus 路径；Windows
  /// 公开 BLE 支持、Radio 状态、适配器地址和 WinRT 原始字段；Web 仅公开是否支持、
  /// availability 映射状态和基础 BLE 能力，不公开适配器名称或地址。
  Future<BluetoothAdapterInfo> getAdapterInfo() {
    return _platform.getAdapterInfo();
  }

  /// 判断当前是否正在扫描。
  ///
  /// 无参数。Android 同时包含 BLE 扫描和 Classic discovery；Linux 反映 BlueZ
  /// Discovery 状态；iOS/macOS/Windows 仅包含 BLE 扫描；Web 仅在浏览器设备选择器打开期间
  /// 返回 `true`。
  Future<bool> isScanning() {
    return _platform.isScanning();
  }

  /// 设置本机蓝牙适配器名称。
  ///
  /// 参数：
  /// - [name]：目标名称，无默认值；建议保持短名称，避免不同系统 UI 截断。
  ///
  /// 平台差异：Android 原生实现会尝试修改适配器名称；Linux 会尝试写入 BlueZ
  /// Adapter `Alias`；iOS/macOS/Windows/Web 返回 `false`。Android 12+ 需要
  /// `BLUETOOTH_CONNECT` 权限。
  Future<bool> setAdapterName(String name) {
    return _platform.setAdapterName(name);
  }

  /// 监听蓝牙适配器状态变化。
  ///
  /// 无参数。Android/iOS/macOS 会推送系统状态变化；Linux 监听 BlueZ Adapter
  /// `PropertiesChanged` 并在订阅时先发送当前状态；Web 先发送当前 availability 映射状态，
  /// 并在浏览器 availabilitychanged 时更新。建议用它驱动 UI，而不是频繁轮询 [getAdapterState]。
  Stream<BluetoothAdapterState> get adapterState => _platform.adapterState;

  /// 检查蓝牙相关权限状态，不触发系统授权弹窗。
  ///
  /// 无参数。Android 返回 `bluetoothScan`、`bluetoothConnect`、
  /// `bluetoothAdvertise`、`locationWhenInUse` 等键；iOS/macOS 返回 `bluetooth`；Web
  /// 没有全局预授权，不支持时返回 `notApplicable`，已授权过设备时返回 `granted`，否则返回
  /// `notDetermined`。Linux/Windows 返回 `bluetooth`，有可用适配器时为 `granted`，否则为
  /// `notApplicable`。
  Future<Map<String, BluetoothPermissionStatus>> checkPermissions() {
    return _platform.checkPermissions();
  }

  /// 请求蓝牙相关权限。
  ///
  /// 无参数。Android 会请求运行时权限；iOS/macOS 会初始化 CoreBluetooth 以触发系统授权；
  /// Web 不能预先弹出全局授权，需要在用户手势中通过 [startScan] 打开设备选择器；
  /// Linux/Windows 不会弹出蓝牙授权，直接返回当前可用性映射结果；建议在扫描、连接、
  /// 广播前调用，并检查返回值。
  Future<Map<String, BluetoothPermissionStatus>> requestPermissions() {
    return _platform.requestPermissions();
  }

  /// 请求用户开启蓝牙。
  ///
  /// 无参数。Android 会打开系统开启蓝牙弹窗；Linux 会尝试设置 BlueZ Adapter `Powered`；
  /// iOS/macOS/Windows/Web 无法由应用直接开启蓝牙，返回 `false`。跨平台推荐在返回
  /// `false` 时调用 [openBluetoothSettings] 或提示用户手动开启。
  Future<bool> requestEnable() {
    return _platform.requestEnable();
  }

  /// 打开系统蓝牙相关设置页。
  ///
  /// 无参数。Android 打开蓝牙设置；iOS 打开当前 App 设置页；macOS 打开系统蓝牙设置页；
  /// Linux 会尝试启动常见桌面蓝牙设置工具；Windows 打开系统蓝牙设置页；Web 没有可标准化
  /// 打开的蓝牙设置页，当前为空操作。
  Future<void> openBluetoothSettings() {
    return _platform.openBluetoothSettings();
  }

  /// 开始扫描附近设备。
  ///
  /// 参数：
  /// - [serviceUuids]：BLE 服务 UUID 过滤列表，默认 `const <String>[]` 表示不过滤。
  ///   iOS/macOS 上推荐传入目标服务 UUID 以提高可发现性；Android 可为空扫描全部；Web
  ///   会作为设备选择器 filters/optionalServices，后续需要访问 GATT 服务时应传入目标 UUID。
  /// - [timeout]：扫描超时，默认 `null` 表示不自动停止。推荐前台扫描使用
  ///   `Duration(seconds: 10)` 到 `Duration(seconds: 15)`，避免耗电。
  /// - [allowDuplicates]：是否允许同一设备重复上报，默认 `false`。需要实时 RSSI
  ///   或广播数据变化时可设为 `true`，但会明显增加事件量。
  /// - [scanMode]：扫描模式，默认 [BluetoothScanMode.ble]。Android 支持
  ///   `ble`、`classic`、`dual`；iOS/macOS 只支持 BLE，会忽略 Classic 相关模式；
  ///   Linux 使用 BlueZ `Transport` 过滤，支持 `le`/`bredr`/`auto` 发现但 GATT API 仍仅面向 BLE；
  ///   Windows 当前使用 BLE 广播扫描，`classic` 会返回不支持，`dual` 仅使用 BLE 部分；
  ///   Web 只支持 BLE 设备选择器，`classic` 会抛不支持，`dual` 仅使用 BLE 部分。
  ///
  /// Web 差异：不会持续被动扫描，会打开浏览器设备选择器；用户选中后 [scanResults]
  /// 产生一条结果，RSSI 固定为 `0`，且 [timeout]/[allowDuplicates] 无法控制选择器。
  Future<void> startScan({
    List<String> serviceUuids = const <String>[],
    Duration? timeout,
    bool allowDuplicates = false,
    BluetoothScanMode scanMode = BluetoothScanMode.ble,
  }) {
    return _platform.startScan(
      serviceUuids: serviceUuids,
      timeout: timeout,
      allowDuplicates: allowDuplicates,
      scanMode: scanMode,
    );
  }

  /// 停止当前扫描。
  ///
  /// 无参数。Android 会同时停止 BLE 扫描和 Classic discovery；Linux 停止 BlueZ Discovery；
  /// iOS/macOS/Windows 停止 BLE 扫描；Web 无法主动关闭浏览器设备选择器，仅清理本地选择状态。
  /// 建议页面退出或拿到目标设备后主动调用。
  Future<void> stopScan() {
    return _platform.stopScan();
  }

  /// 监听扫描结果。
  ///
  /// 无参数。先订阅该流再调用 [startScan] 可避免漏掉早期结果；Android Classic
  /// 结果通常缺少 service/manufacturer 数据，iOS/macOS 仅返回 BLE 外设；Linux 返回
  /// BlueZ Device1 发现结果并使用地址作为设备 ID；Windows 返回 BLE 广播结果并使用蓝牙地址作为
  /// 设备 ID；Web 每次 [startScan] 成功只返回用户选择的一条 BLE 设备结果。
  Stream<BluetoothScanResult> get scanResults => _platform.scanResults;

  /// 获取已配对/已绑定设备列表。
  ///
  /// 无参数。Android 返回系统已绑定设备；iOS/macOS 没有公开配对列表，返回空列表；Web
  /// 不公开系统配对列表，浏览器支持 `getDevices()` 时返回已授权给当前站点的设备；
  /// Linux 返回 BlueZ `Paired` 设备；Windows 会尽量返回系统已配对的 BLE 设备。
  Future<List<BluetoothDevice>> getBondedDevices() {
    return _platform.getBondedDevices();
  }

  /// 获取当前已连接设备列表。
  ///
  /// 参数：
  /// - [serviceUuids]：服务 UUID 过滤列表，默认 `const <String>[]`。iOS/macOS 可用它查询
  ///   系统已连接且包含指定服务的外设；Android 当前忽略该参数并返回已连接 GATT 设备；
  ///   Linux 返回 BlueZ 已连接设备并可按 UUID 过滤；Windows 返回本插件已知的已连接 BLE 设备并可按服务过滤；
  ///   Web 仅能过滤当前站点已授权且已连接的设备。
  ///
  /// 推荐：需要兼容 iOS/macOS 或 Web 时传入目标服务 UUID；只关心本插件已连接设备时可使用默认值。
  Future<List<BluetoothDevice>> getConnectedDevices({
    List<String> serviceUuids = const <String>[],
  }) {
    return _platform.getConnectedDevices(serviceUuids: serviceUuids);
  }

  /// 根据设备 ID 获取设备信息。
  ///
  /// 参数：
  /// - [deviceId]：设备标识，无默认值。Android 通常是 MAC 地址；Linux 通常是 BlueZ
  ///   Address 或 DBus object path；Windows 通常是 12 位蓝牙地址或 WinRT DeviceId；
  ///   iOS/macOS 是 CoreBluetooth peripheral UUID，Web 是浏览器为当前站点生成的设备 ID；通常来自扫描结果。
  Future<BluetoothDevice?> getDevice(String deviceId) {
    return _platform.getDevice(deviceId);
  }

  /// 批量根据设备 ID 获取设备信息。
  ///
  /// 参数：
  /// - [deviceIds]：设备 ID 列表，无默认值。Android 可通过 MAC 地址构造远端设备；
  ///   Linux/Windows 可使用扫描得到的蓝牙地址或平台原生 ID；iOS/macOS 只能返回当前已扫描
  ///   或已记住的外设；Web 只能返回当前站点已授权或本页已选择设备。
  Future<List<BluetoothDevice>> getDevices(List<String> deviceIds) {
    return _platform.getDevices(deviceIds);
  }

  /// 连接 BLE 设备。
  ///
  /// 参数：
  /// - [deviceId]：设备标识，无默认值。Android 使用 MAC 地址；Linux 使用 BlueZ Address
  ///   或 DBus object path；Windows 使用扫描得到的蓝牙地址或 WinRT DeviceId；iOS/macOS 使用扫描得到的
  ///   peripheral UUID；Web 使用已通过设备选择器授权的浏览器设备 ID。
  /// - [autoConnect]：是否使用 Android 自动连接语义，默认 `false`。iOS/macOS/Linux/Windows/Web 会忽略该参数。
  ///   前台主动连接推荐保持 `false`；后台等待设备回连时 Android 可设为 `true`。
  /// - [timeout]：连接超时，默认 `null` 表示不由插件自动超时。前台连接推荐
  ///   `Duration(seconds: 10)` 到 `Duration(seconds: 15)`；Android `autoConnect: true`
  ///   语义下连接会立即返回，不建议依赖超时判断最终连接结果。Web 只能连接当前站点已授权设备。
  Future<void> connect(
    String deviceId, {
    bool autoConnect = false,
    Duration? timeout,
  }) {
    return _platform.connect(
      deviceId,
      autoConnect: autoConnect,
      timeout: timeout,
    );
  }

  /// 断开 BLE 连接。
  ///
  /// 参数：
  /// - [deviceId]：设备标识，无默认值。未连接时 Android 会视为成功；iOS/macOS 找不到设备时会返回错误。
  Future<void> disconnect(String deviceId) {
    return _platform.disconnect(deviceId);
  }

  /// 获取指定设备当前 BLE 连接状态。
  ///
  /// 参数：
  /// - [deviceId]：设备标识，无默认值。建议结合 [connectionState] 监听状态变化。
  Future<BluetoothConnectionState> getConnectionState(String deviceId) {
    return _platform.getConnectionState(deviceId);
  }

  /// 监听 BLE 连接状态变化。
  ///
  /// 无参数。事件中包含 [BluetoothConnectionStateEvent.deviceId] 和状态；Linux 由 BlueZ
  /// Device `Connected` 变化触发；Android 还可能包含原生 GATT 状态码。
  Stream<BluetoothConnectionStateEvent> get connectionState =>
      _platform.connectionState;

  /// 发现指定 BLE 设备的 GATT 服务。
  ///
  /// 参数：
  /// - [deviceId]：已连接设备标识，无默认值。调用读写特征/描述符前应先调用本方法；
  ///   Linux 从 BlueZ ObjectManager 读取已解析的 GATT 层级；Web 只能发现设备选择时已授权的服务，
  ///   建议在 [startScan] 传入目标 [serviceUuids]。
  Future<List<BluetoothGattService>> discoverServices(String deviceId) {
    return _platform.discoverServices(deviceId);
  }

  /// 读取 GATT 特征值。
  ///
  /// 参数：
  /// - [deviceId]：已连接设备标识，无默认值。
  /// - [serviceUuid]：服务 UUID，无默认值。
  /// - [characteristicUuid]：特征 UUID，无默认值。Linux 使用 BlueZ `ReadValue`；Web 要求
  ///   [serviceUuid] 已在设备选择时授权。
  Future<Uint8List> readCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    return _platform.readCharacteristic(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );
  }

  /// 写入 GATT 特征值。
  ///
  /// 参数：
  /// - [deviceId]：已连接设备标识，无默认值。
  /// - [serviceUuid]：服务 UUID，无默认值。
  /// - [characteristicUuid]：特征 UUID，无默认值。
  /// - [value]：要写入的字节数组，无默认值。
  /// - [writeType]：写入类型，默认 [BluetoothWriteType.withResponse]。可靠性优先推荐
  ///   `withResponse`；吞吐优先且特征支持 `writeWithoutResponse` 时可用
  ///   [BluetoothWriteType.withoutResponse]。iOS/macOS/Web 的无响应写会立即完成，不等待回调；
  ///   Linux 使用 BlueZ `WriteValue` 的 `request`/`command` 类型；Windows 使用 WinRT `GattWriteOption`；
  ///   Web 要求 [serviceUuid] 已在设备选择时授权。
  Future<void> writeCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    BluetoothWriteType writeType = BluetoothWriteType.withResponse,
  }) {
    return _platform.writeCharacteristic(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: value,
      writeType: writeType,
    );
  }

  /// 开启或关闭 GATT 特征通知/指示。
  ///
  /// 参数：
  /// - [deviceId]：已连接设备标识，无默认值。
  /// - [serviceUuid]：服务 UUID，无默认值。
  /// - [characteristicUuid]：特征 UUID，无默认值。
  /// - [enable]：`true` 开启，`false` 关闭，无默认值。
  ///
  /// 收到的数据从 [characteristicValues] 监听。Android 会写 CCCD；iOS/macOS 使用
  /// CoreBluetooth 的通知订阅接口；Linux 使用 BlueZ `StartNotify`/`StopNotify` 并监听
  /// `PropertiesChanged(Value)`；Windows 写入 CCCD 并监听 WinRT ValueChanged；Web 使用
  /// `startNotifications()`，不会直接写 CCCD。
  Future<void> setCharacteristicNotification({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required bool enable,
  }) {
    return _platform.setCharacteristicNotification(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      enable: enable,
    );
  }

  /// 监听 GATT 特征通知、指示或读值更新。
  ///
  /// 无参数。需要先调用 [setCharacteristicNotification] 开启订阅。
  Stream<BluetoothCharacteristicValue> get characteristicValues {
    return _platform.characteristicValues;
  }

  /// 读取 GATT 描述符值。
  ///
  /// 参数：
  /// - [deviceId]：已连接设备标识，无默认值。
  /// - [serviceUuid]：服务 UUID，无默认值。
  /// - [characteristicUuid]：特征 UUID，无默认值。
  /// - [descriptorUuid]：描述符 UUID，无默认值。Linux 使用 BlueZ `ReadValue`；Web 要求
  ///   [serviceUuid] 已在设备选择时授权。
  Future<Uint8List> readDescriptor({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
  }) {
    return _platform.readDescriptor(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      descriptorUuid: descriptorUuid,
    );
  }

  /// 写入 GATT 描述符值。
  ///
  /// 参数：
  /// - [deviceId]：已连接设备标识，无默认值。
  /// - [serviceUuid]：服务 UUID，无默认值。
  /// - [characteristicUuid]：特征 UUID，无默认值。
  /// - [descriptorUuid]：描述符 UUID，无默认值。
  /// - [value]：要写入的字节数组，无默认值。Linux 使用 BlueZ `WriteValue`；Web 不允许通过
  ///   CCCD 描述符写入订阅通知，请使用 [setCharacteristicNotification]。
  Future<void> writeDescriptor({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
    required Uint8List value,
  }) {
    return _platform.writeDescriptor(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      descriptorUuid: descriptorUuid,
      value: value,
    );
  }

  /// 监听 GATT 描述符值变化。
  ///
  /// 无参数。通常由描述符读写操作触发。
  Stream<BluetoothDescriptorValue> get descriptorValues =>
      _platform.descriptorValues;

  /// 读取远端设备 RSSI。
  ///
  /// 参数：
  /// - [deviceId]：已连接设备标识，无默认值。Android/iOS/macOS 都需要设备处于已连接状态；
  ///   Web Bluetooth 不公开 RSSI，会抛出不支持错误；Linux/Windows 返回最近一次扫描缓存的
  ///   广播 RSSI，未缓存时返回 `0`。
  Future<int> readRssi(String deviceId) {
    return _platform.readRssi(deviceId);
  }

  /// 监听 RSSI 读取结果。
  ///
  /// 无参数。RSSI 单位为 dBm，通常为负数，数值越接近 0 信号越强；Web 为空流。
  Stream<BluetoothRssiEvent> get rssiUpdates => _platform.rssiUpdates;

  /// 请求或读取 BLE MTU/最大写入长度相关值。
  ///
  /// 参数：
  /// - [deviceId]：已连接设备标识，无默认值。
  /// - [mtu]：期望 MTU，无默认值。Android 会向系统发起 MTU 协商，常用推荐值为
  ///   `247`；确认外设支持且追求吞吐时可尝试 `517`。iOS/macOS 不开放 MTU 协商，会忽略
  ///   [mtu] 并返回当前最大无响应写入长度；Linux/Windows/Web 返回 `0`。
  Future<int> requestMtu(String deviceId, int mtu) {
    return _platform.requestMtu(deviceId, mtu);
  }

  /// 获取当前连接可写入的最大字节数。
  ///
  /// 参数：
  /// - [deviceId]：已连接设备标识，无默认值。
  /// - [withoutResponse]：是否按无响应写计算，默认 `true`。吞吐优先推荐 `true`；需要
  ///   每包确认时传 `false`。Android 当前按已知 MTU 返回 `mtu - 3`；iOS/macOS 会区分
  ///   `.withoutResponse` 与 `.withResponse`；Linux/Windows/Web 不公开该值，返回 `0`。
  Future<int> getMaximumWriteLength(
    String deviceId, {
    bool withoutResponse = true,
  }) {
    return _platform.getMaximumWriteLength(
      deviceId,
      withoutResponse: withoutResponse,
    );
  }

  /// 监听 MTU 更新事件。
  ///
  /// 无参数。Android 在 MTU 协商完成后推送；iOS/macOS 在 [requestMtu] 时推送当前可写长度；
  /// Linux/Windows 在 [requestMtu] 时推送 `0`；Web 为空流。
  Stream<BluetoothMtuEvent> get mtuUpdates => _platform.mtuUpdates;

  /// 设置 BLE 连接优先 PHY。
  ///
  /// 参数：
  /// - [deviceId]：已连接设备标识，无默认值。
  /// - [txPhy]：发送方向 PHY，无默认值。Android 8.0+ 支持；iOS/macOS/Linux/Windows/Web 不支持。
  /// - [rxPhy]：接收方向 PHY，无默认值。推荐与 [txPhy] 保持一致。
  /// - [phyOptions]：Android PHY 选项，默认 `0` 表示无偏好。只有使用
  ///   [BluetoothPhy.leCoded] 时才需要考虑平台常量 S2/S8；一般推荐保持 `0`。
  ///
  /// 推荐值：如果 [BluetoothAdapterInfo.isLe2MPhySupported] 为 `true`，短距离高吞吐可用
  /// [BluetoothPhy.le2m]；长距离低速可用 [BluetoothPhy.leCoded]；否则使用
  /// [BluetoothPhy.le1m]。
  Future<void> setPreferredPhy({
    required String deviceId,
    required BluetoothPhy txPhy,
    required BluetoothPhy rxPhy,
    int phyOptions = 0,
  }) {
    return _platform.setPreferredPhy(
      deviceId: deviceId,
      txPhy: txPhy,
      rxPhy: rxPhy,
      phyOptions: phyOptions,
    );
  }

  /// 读取 BLE 当前 PHY。
  ///
  /// 参数：
  /// - [deviceId]：已连接设备标识，无默认值。Android 8.0+ 返回真实值；iOS/macOS/Linux/Windows/Web
  ///   返回 [BluetoothPhy.unknown]。
  Future<BluetoothPhyEvent> readPhy(String deviceId) {
    return _platform.readPhy(deviceId);
  }

  /// 监听 PHY 变化。
  ///
  /// 无参数。当前主要由 Android 8.0+ 推送；其它平台通常为空流。
  Stream<BluetoothPhyEvent> get phyUpdates => _platform.phyUpdates;

  /// 请求 Android BLE 连接优先级。
  ///
  /// 参数：
  /// - [deviceId]：已连接设备标识，无默认值。
  /// - [priority]：目标优先级，无默认值。推荐默认业务用
  ///   [BluetoothConnectionPriority.balanced]，短时间大数据传输用
  ///   [BluetoothConnectionPriority.high]，空闲保活用 [BluetoothConnectionPriority.lowPower]。
  ///
  /// 平台差异：Android 原生支持；iOS/macOS/Linux/Windows/Web 返回 `false`。
  Future<bool> requestConnectionPriority(
    String deviceId,
    BluetoothConnectionPriority priority,
  ) {
    return _platform.requestConnectionPriority(deviceId, priority);
  }

  /// 创建系统配对/绑定。
  ///
  /// 参数：
  /// - [deviceId]：设备标识，无默认值。Android 使用 MAC 地址；Linux 使用 BlueZ `Pair`；
  ///   iOS/macOS/Windows/Web 不支持并返回 `false`。
  Future<bool> createBond(String deviceId) {
    return _platform.createBond(deviceId);
  }

  /// 移除系统配对/绑定。
  ///
  /// 参数：
  /// - [deviceId]：设备标识，无默认值。Android 会尝试解除绑定；Linux 使用 BlueZ
  ///   Adapter `RemoveDevice`；iOS/macOS/Windows/Web 返回 `false`。
  Future<bool> removeBond(String deviceId) {
    return _platform.removeBond(deviceId);
  }

  /// 监听配对/绑定状态变化。
  ///
  /// 无参数。当前主要由 Android/Linux 推送；iOS/macOS/Windows/Web 为空流。
  Stream<BluetoothBondStateEvent> get bondState => _platform.bondState;

  /// 判断当前平台是否支持 BLE 外设/广播模式。
  ///
  /// 无参数。Android 需要设备支持 BLE advertiser；iOS/macOS 返回支持 CoreBluetooth 外设模式；
  /// Linux/Windows 当前未实现本地 GATT Server/广播并返回 `false`；Web 返回 `false`。
  Future<bool> isPeripheralSupported() {
    return _platform.isPeripheralSupported();
  }

  /// 开始 BLE 广播。
  ///
  /// 参数：
  /// - [advertisementData]：主广播数据，默认 `const BluetoothAdvertisementData()`。
  ///   跨平台推荐只放 `localName` 与少量 `serviceUuids`，避免超过传统 31 字节限制。
  /// - [scanResponse]：扫描响应数据，默认 `null`。Android 支持；iOS/macOS 当前忽略；
  ///   Linux/Windows/Web 不支持广播。
  /// - [settings]：广播设置，默认 `const BluetoothAdvertisingSettings()`，即 balanced、
  ///   medium、connectable `true`、无超时。Android 支持这些设置；iOS/macOS 当前忽略设置；
  ///   Linux/Windows/Web 不支持广播。
  ///
  /// 平台差异：Android 支持 manufacturer/service data、scan response 和功率/模式设置；
  /// iOS/macOS 当前只使用 [BluetoothAdvertisementData.localName] 与 `serviceUuids`；
  /// Linux/Windows/Web 不支持。
  Future<void> startAdvertising({
    BluetoothAdvertisementData advertisementData =
        const BluetoothAdvertisementData(),
    BluetoothAdvertisementData? scanResponse,
    BluetoothAdvertisingSettings settings =
        const BluetoothAdvertisingSettings(),
  }) {
    return _platform.startAdvertising(
      advertisementData: advertisementData,
      scanResponse: scanResponse,
      settings: settings,
    );
  }

  /// 停止 BLE 广播。
  ///
  /// 无参数。Android/iOS/macOS 会停止外设广播；Linux/Windows/Web 为空操作。
  Future<void> stopAdvertising() {
    return _platform.stopAdvertising();
  }

  /// 监听 BLE 广播状态。
  ///
  /// 无参数。可用于获取广播启动成功、停止或错误信息。
  Stream<BluetoothAdvertisingStateEvent> get advertisingState {
    return _platform.advertisingState;
  }

  /// 设置本地 GATT Server 服务列表。
  ///
  /// 参数：
  /// - [services]：要暴露的服务列表，无默认值。Android/iOS/macOS 支持；Linux/Windows/Web 不支持。
  ///   推荐先调用本方法，再调用 [startAdvertising]。
  Future<void> setGattServerServices(List<BluetoothGattService> services) {
    return _platform.setGattServerServices(services);
  }

  /// 清空本地 GATT Server 服务列表。
  ///
  /// 无参数。Android/iOS/macOS 会移除已注册的本地服务；Linux/Windows/Web 为空操作。
  Future<void> clearGattServerServices() {
    return _platform.clearGattServerServices();
  }

  /// 更新本地 GATT 特征缓存值。
  ///
  /// 参数：
  /// - [serviceUuid]：本地服务 UUID，无默认值。
  /// - [characteristicUuid]：本地特征 UUID，无默认值。
  /// - [value]：新的字节数组，无默认值。
  ///
  /// 该方法只更新本地值；如需主动推送给已订阅中心设备，请调用 [notifyGattServerCharacteristic]。
  Future<void> updateLocalCharacteristicValue({
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
  }) {
    return _platform.updateLocalCharacteristicValue(
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: value,
    );
  }

  /// 通过本地 GATT Server 主动通知/指示特征值。
  ///
  /// 参数：
  /// - [deviceId]：目标中心设备 ID，默认 `null` 表示尽量发给所有已连接/已订阅设备。
  ///   Android 支持指定设备；iOS/macOS 当前忽略该参数并发给已订阅中心设备；Linux/Windows/Web
  ///   返回 `false`。
  /// - [serviceUuid]：本地服务 UUID，无默认值。
  /// - [characteristicUuid]：本地特征 UUID，无默认值。
  /// - [value]：要发送的字节数组，无默认值。
  /// - [confirm]：是否使用需要确认的 indication，默认 `false`。Android 支持；iOS/macOS 当前忽略；
  ///   Linux/Windows/Web 返回 `false`。需要可靠送达时可设为 `true`，高频数据推荐保持 `false`。
  Future<bool> notifyGattServerCharacteristic({
    String? deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    bool confirm = false,
  }) {
    return _platform.notifyGattServerCharacteristic(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: value,
      confirm: confirm,
    );
  }

  /// 监听本地 GATT Server 请求和状态事件。
  ///
  /// 无参数。事件包含连接、服务添加、读写、订阅、通知发送等平台事件；Android 事件更完整，
  /// iOS/macOS 主要包含读写和订阅事件；Linux/Windows/Web 为空流。
  Stream<BluetoothGattServerRequest> get gattServerRequests {
    return _platform.gattServerRequests;
  }

  /// 连接 Android Classic Bluetooth RFCOMM 设备。
  ///
  /// 参数：
  /// - [deviceId]：Classic 设备地址，Android 通常为 MAC 地址，无默认值。
  /// - [serviceUuid]：RFCOMM 服务 UUID，无默认值，SPP 常用
  ///   `00001101-0000-1000-8000-00805f9b34fb`。
  /// - [secure]：是否使用安全 RFCOMM，默认 `true`。已配对设备推荐 `true`；调试或对端仅支持
  ///   insecure socket 时可设为 `false`。
  /// - [timeout]：连接超时，默认 `null`。当前 Android 原生 Classic 连接未强制使用该超时，
  ///   建议业务层自行设置兜底超时。
  ///
  /// 平台差异：仅 Android 实现；iOS/macOS/Linux/Windows 会返回 `unsupported` 错误；Web
  /// 会抛出 UnsupportedError。
  Future<void> connectClassic({
    required String deviceId,
    required String serviceUuid,
    bool secure = true,
    Duration? timeout,
  }) {
    return _platform.connectClassic(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      secure: secure,
      timeout: timeout,
    );
  }

  /// 启动 Android Classic Bluetooth RFCOMM 服务端。
  ///
  /// 参数：
  /// - [serviceUuid]：RFCOMM 服务 UUID，无默认值。
  /// - [serviceName]：服务名称，默认 `FlutterBluetoothPlugin`。
  /// - [secure]：是否使用安全 RFCOMM，默认 `true`。对外发布生产服务推荐 `true`。
  ///
  /// 平台差异：仅 Android 实现；iOS/macOS/Linux/Windows 会返回 `unsupported` 错误；Web
  /// 会抛出 UnsupportedError。
  Future<void> startClassicServer({
    required String serviceUuid,
    String serviceName = 'FlutterBluetoothPlugin',
    bool secure = true,
  }) {
    return _platform.startClassicServer(
      serviceUuid: serviceUuid,
      serviceName: serviceName,
      secure: secure,
    );
  }

  /// 停止 Android Classic Bluetooth RFCOMM 服务端。
  ///
  /// 无参数。仅 Android 有效；iOS/macOS/Linux/Windows/Web 为空操作。
  Future<void> stopClassicServer() {
    return _platform.stopClassicServer();
  }

  /// 断开 Classic Bluetooth RFCOMM 连接。
  ///
  /// 参数：
  /// - [deviceId]：Classic 设备地址，无默认值。仅 Android 有效；iOS/macOS/Linux/Windows/Web
  ///   为空操作。
  Future<void> disconnectClassic(String deviceId) {
    return _platform.disconnectClassic(deviceId);
  }

  /// 向 Classic Bluetooth RFCOMM 连接写入数据。
  ///
  /// 参数：
  /// - [deviceId]：Classic 设备地址，无默认值。
  /// - [value]：要写入的字节数组，无默认值。
  ///
  /// 平台差异：仅 Android 实现；iOS/macOS/Linux/Windows 会返回 `unsupported` 错误；Web
  /// 会抛出 UnsupportedError。
  Future<void> writeClassic(String deviceId, Uint8List value) {
    return _platform.writeClassic(deviceId, value);
  }

  /// 监听 Classic Bluetooth 连接状态。
  ///
  /// 无参数。仅 Android 推送事件；iOS/macOS/Linux/Windows/Web 为空流。
  Stream<BluetoothClassicConnectionEvent> get classicConnectionState {
    return _platform.classicConnectionState;
  }

  /// 监听 Classic Bluetooth 收到的数据。
  ///
  /// 无参数。仅 Android 推送事件；iOS/macOS/Linux/Windows/Web 为空流。
  Stream<BluetoothClassicDataEvent> get classicData {
    return _platform.classicData;
  }
}
