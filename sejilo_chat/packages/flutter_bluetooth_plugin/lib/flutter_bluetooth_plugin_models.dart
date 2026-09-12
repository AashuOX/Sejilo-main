/// Flutter 蓝牙插件 API 共用的中文模型、枚举和转换函数。
library;

import 'dart:typed_data';

/// 蓝牙适配器状态。
///
/// Android/iOS/macOS 会映射系统状态；Web 会根据 Web Bluetooth availability 映射
/// [poweredOn]/[poweredOff]，不支持时使用 [unsupported]；未知或无法识别的原生值会映射为
/// [unknown]。
enum BluetoothAdapterState {
  /// 状态未知，通常表示原生侧返回了未识别状态。
  unknown,

  /// 当前平台或设备不支持蓝牙。
  unsupported,

  /// 蓝牙权限未授权或被系统限制。
  unauthorized,

  /// 蓝牙已关闭。
  poweredOff,

  /// 蓝牙已开启。扫描、连接、广播前推荐确认处于该状态。
  poweredOn,

  /// 蓝牙适配器正在重置。
  resetting,

  /// 蓝牙正在开启。
  turningOn,

  /// 蓝牙正在关闭。
  turningOff,
}

/// 蓝牙权限状态。
///
/// Android 会按具体权限返回多个键；iOS/macOS 通常只返回 `bluetooth`；Web 没有全局
/// 预授权，不支持时返回 [notApplicable]，已授权过设备时返回 [granted]，否则返回
/// [notDetermined]。
enum BluetoothPermissionStatus {
  /// 状态未知，通常表示原生侧返回了未识别值。
  unknown,

  /// 尚未决定，常见于 iOS/macOS 首次触发 CoreBluetooth 授权前。
  notDetermined,

  /// 已授权。
  granted,

  /// 已拒绝。
  denied,

  /// 被系统策略限制，例如家长控制或企业策略。
  restricted,

  /// 永久拒绝，需要引导用户到系统设置中开启。
  permanentlyDenied,

  /// 当前平台或系统版本不需要/不适用该权限。
  notApplicable,
}

/// 扫描模式。
///
/// [ble] 为默认值和跨平台推荐值；[classic] 与 [dual] 的 Classic 部分仅 Android 有意义，
/// iOS/macOS/Linux/Windows/Web 不支持 Classic Bluetooth。Linux/Windows/Web 的 [dual] 仅使用 BLE 部分。
enum BluetoothScanMode {
  /// 仅扫描 BLE 设备，默认值，跨平台推荐。
  ble,

  /// 仅扫描 Android Classic Bluetooth 设备；其它平台通常返回不支持。
  classic,

  /// Android 上同时扫描 BLE 与 Classic 设备；Linux/Windows/Web 仅使用 BLE 部分；耗电和事件量更高。
  dual,
}

/// BLE 或 Classic 连接状态。
enum BluetoothConnectionState {
  /// 已断开。
  disconnected,

  /// 正在连接。
  connecting,

  /// 已连接。
  connected,

  /// 正在断开。
  disconnecting,

  /// 状态未知。
  unknown,
}

/// Android 配对/绑定状态。
///
/// iOS/macOS/Windows/Web 不公开可管理的配对状态；Linux/Android 可能产生该事件。
enum BluetoothBondState {
  /// 未绑定。
  none,

  /// 正在绑定。
  bonding,

  /// 已绑定。
  bonded,

  /// 状态未知。
  unknown,
}

/// GATT 特征写入类型。
enum BluetoothWriteType {
  /// 有响应写入，默认值；可靠性优先，适合配置、控制命令。
  withResponse,

  /// 无响应写入；吞吐优先，需确认特征支持 `writeWithoutResponse`。
  withoutResponse,
}

/// Android BLE 连接优先级。
///
/// 该枚举主要用于 `requestConnectionPriority`；iOS/macOS/Linux/Windows/Web 会忽略并返回不支持。
enum BluetoothConnectionPriority {
  /// 均衡模式，常规业务推荐值。
  balanced,

  /// 高优先级，适合短时间大数据传输，耗电更高。
  high,

  /// 低功耗，适合空闲保活或低频数据。
  lowPower,
}

/// 将原生字符串转换为 [BluetoothAdapterState]。
///
/// 参数：
/// - [value]：原生状态名称，默认可传 `null`；无法识别时返回
///   [BluetoothAdapterState.unknown]。
BluetoothAdapterState bluetoothAdapterStateFromString(String? value) {
  return BluetoothAdapterState.values.firstWhere(
    (state) => state.name == value,
    orElse: () => BluetoothAdapterState.unknown,
  );
}

/// 将原生字符串转换为 [BluetoothPermissionStatus]。
///
/// 参数：
/// - [value]：原生权限状态名称，默认可传 `null`；无法识别时返回
///   [BluetoothPermissionStatus.unknown]。
BluetoothPermissionStatus bluetoothPermissionStatusFromString(String? value) {
  return BluetoothPermissionStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => BluetoothPermissionStatus.unknown,
  );
}

/// 将原生字符串转换为 [BluetoothConnectionState]。
///
/// 参数：
/// - [value]：原生连接状态名称，默认可传 `null`；无法识别时返回
///   [BluetoothConnectionState.unknown]。
BluetoothConnectionState bluetoothConnectionStateFromString(String? value) {
  return BluetoothConnectionState.values.firstWhere(
    (state) => state.name == value,
    orElse: () => BluetoothConnectionState.unknown,
  );
}

/// 将原生字符串转换为 [BluetoothBondState]。
///
/// 参数：
/// - [value]：原生绑定状态名称，默认可传 `null`；无法识别时返回
///   [BluetoothBondState.unknown]。
BluetoothBondState bluetoothBondStateFromString(String? value) {
  return BluetoothBondState.values.firstWhere(
    (state) => state.name == value,
    orElse: () => BluetoothBondState.unknown,
  );
}

Map<String, dynamic> _asStringMap(Object? value) {
  if (value == null) {
    return <String, dynamic>{};
  }
  return Map<String, dynamic>.from(value as Map<dynamic, dynamic>);
}

List<String> _asStringList(Object? value) {
  if (value == null) {
    return const <String>[];
  }
  return (value as List<dynamic>).map((item) => item.toString()).toList();
}

Uint8List _asByteList(Object? value) {
  if (value == null) {
    return Uint8List(0);
  }
  if (value is Uint8List) {
    return value;
  }
  if (value is ByteData) {
    return value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes);
  }
  if (value is List<int>) {
    return Uint8List.fromList(value);
  }
  return Uint8List.fromList(
    (value as List<dynamic>).map((item) => (item as num).toInt()).toList(),
  );
}

bool _asBool(Object? value, {bool defaultValue = false}) {
  return _asNullableBool(value) ?? defaultValue;
}

bool? _asNullableBool(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
  }
  return null;
}

Map<int, Uint8List> _asManufacturerData(Object? value) {
  final map = _asStringMap(value);
  return map.map(
    (key, bytes) => MapEntry(int.tryParse(key) ?? 0, _asByteList(bytes)),
  );
}

Map<String, Uint8List> _asServiceData(Object? value) {
  final map = _asStringMap(value);
  return map.map((key, bytes) => MapEntry(key, _asByteList(bytes)));
}

/// 蓝牙设备摘要信息。
///
/// Android 的 [id] 通常为 MAC 地址；Linux 通常为 BlueZ Address 或 DBus object path；
/// iOS/macOS 的 [id] 为 CoreBluetooth peripheral UUID；Web 的 [id] 为浏览器生成的站点内设备 ID，
/// 且不公开真实蓝牙地址。
class BluetoothDevice {
  /// 创建设备信息。
  ///
  /// 参数：
  /// - [id]：设备标识，无默认值。
  /// - [name]：设备名称，默认 `null`，可能因权限或广播缺失而为空。
  /// - [address]：设备地址，默认 `null`。Android 可能等同 MAC；iOS/macOS 通常不公开地址。
  /// - [type]：设备类型，默认 `null`，例如 `ble`、`classic` 或平台原生类型。
  /// - [isConnected]：是否已连接，默认 `false`。
  /// - [isBonded]：是否已绑定/配对，默认 `false`；主要 Android 有意义。
  /// - [raw]：原生完整字段，默认 `const <String, dynamic>{}`，用于排查平台差异。
  const BluetoothDevice({
    required this.id,
    this.name,
    this.address,
    this.type,
    this.isConnected = false,
    this.isBonded = false,
    this.raw = const <String, dynamic>{},
  });

  /// 从原生 Map 创建设备信息。
  ///
  /// 参数：
  /// - [map]：原生数据，无默认值；缺失字段会使用构造函数默认值。
  factory BluetoothDevice.fromMap(Map<String, dynamic> map) {
    return BluetoothDevice(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString(),
      address: map['address']?.toString(),
      type: map['type']?.toString(),
      isConnected: _asBool(map['isConnected']),
      isBonded: _asBool(map['isBonded']),
      raw: map,
    );
  }

  /// 设备标识。Android 通常为 MAC，Linux 通常为 BlueZ Address，iOS/macOS 为 peripheral UUID，
  /// Web 为浏览器生成 ID。
  final String id;

  /// 设备名称，可能为空。
  final String? name;

  /// 设备地址，默认 `null`；iOS/macOS 通常不公开真实地址。
  final String? address;

  /// 设备类型，默认 `null`。
  final String? type;

  /// 是否已连接，默认 `false`。
  final bool isConnected;

  /// 是否已绑定/配对，默认 `false`；主要 Android 有意义。
  final bool isBonded;

  /// 原生完整字段，默认空 Map。
  final Map<String, dynamic> raw;

  /// 转为可传给原生端的 Map。
  ///
  /// 无参数；不会写入 [raw] 中的额外字段。
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      if (name != null) 'name': name,
      if (address != null) 'address': address,
      if (type != null) 'type': type,
      'isConnected': isConnected,
      'isBonded': isBonded,
    };
  }

  /// 返回便于日志输出的设备摘要字符串。
  @override
  String toString() {
    return 'BluetoothDevice(id: $id, name: $name, type: $type)';
  }
}

/// 扫描结果。
class BluetoothScanResult {
  /// 创建扫描结果。
  ///
  /// 参数：
  /// - [device]：扫描到的设备，无默认值。
  /// - [rssi]：信号强度 dBm，无默认值，越接近 0 信号越强。
  /// - [localName]：广播本地名称，默认 `null`。
  /// - [serviceUuids]：广播服务 UUID，默认 `const <String>[]`。
  /// - [manufacturerData]：厂商数据，默认 `const <int, Uint8List>{}`；key 为 Company ID。
  /// - [serviceData]：服务数据，默认 `const <String, Uint8List>{}`。
  /// - [txPowerLevel]：广播发射功率，默认 `null`。
  /// - [isConnectable]：是否可连接，默认 `null`，并非所有平台都会返回。
  /// - [raw]：原生完整字段，默认 `const <String, dynamic>{}`。
  const BluetoothScanResult({
    required this.device,
    required this.rssi,
    this.localName,
    this.serviceUuids = const <String>[],
    this.manufacturerData = const <int, Uint8List>{},
    this.serviceData = const <String, Uint8List>{},
    this.txPowerLevel,
    this.isConnectable,
    this.raw = const <String, dynamic>{},
  });

  /// 从原生 Map 创建扫描结果。
  ///
  /// 参数：
  /// - [map]：原生扫描数据，无默认值；缺失集合字段会转换为空集合。
  factory BluetoothScanResult.fromMap(Map<String, dynamic> map) {
    final deviceMap = _asStringMap(map['device']);
    return BluetoothScanResult(
      device: BluetoothDevice.fromMap(deviceMap),
      rssi: (map['rssi'] as num?)?.toInt() ?? 0,
      localName: map['localName']?.toString(),
      serviceUuids: _asStringList(map['serviceUuids']),
      manufacturerData: _asManufacturerData(map['manufacturerData']),
      serviceData: _asServiceData(map['serviceData']),
      txPowerLevel: (map['txPowerLevel'] as num?)?.toInt(),
      isConnectable: _asNullableBool(map['isConnectable']),
      raw: map,
    );
  }

  /// 扫描到的设备。
  final BluetoothDevice device;

  /// 信号强度 dBm。
  final int rssi;

  /// 广播本地名称，默认 `null`。
  final String? localName;

  /// 广播服务 UUID 列表，默认空列表。
  final List<String> serviceUuids;

  /// 厂商数据，默认空 Map；key 为蓝牙 SIG Company ID。
  final Map<int, Uint8List> manufacturerData;

  /// 服务数据，默认空 Map；key 为服务 UUID。
  final Map<String, Uint8List> serviceData;

  /// 广播发射功率，默认 `null`。
  final int? txPowerLevel;

  /// 是否可连接，默认 `null`。
  final bool? isConnectable;

  /// 原生完整字段，默认空 Map。
  final Map<String, dynamic> raw;

  /// 返回便于日志输出的扫描结果摘要。
  @override
  String toString() {
    return 'BluetoothScanResult(device: $device, rssi: $rssi)';
  }
}

/// GATT 描述符。
class BluetoothGattDescriptor {
  /// 创建 GATT 描述符。
  ///
  /// 参数：
  /// - [uuid]：描述符 UUID，无默认值。
  /// - [characteristicUuid]：所属特征 UUID，默认 `null`。
  /// - [value]：描述符初始值，默认空 [Uint8List]。
  /// - [raw]：原生完整字段，默认 `const <String, dynamic>{}`。
  BluetoothGattDescriptor({
    required this.uuid,
    this.characteristicUuid,
    Uint8List? value,
    this.raw = const <String, dynamic>{},
  }) : value = value ?? Uint8List(0);

  /// 从原生 Map 创建 GATT 描述符。
  ///
  /// 参数：
  /// - [map]：原生描述符数据，无默认值。
  factory BluetoothGattDescriptor.fromMap(Map<String, dynamic> map) {
    return BluetoothGattDescriptor(
      uuid: map['uuid']?.toString() ?? '',
      characteristicUuid: map['characteristicUuid']?.toString(),
      value: _asByteList(map['value']),
      raw: map,
    );
  }

  /// 描述符 UUID。
  final String uuid;

  /// 所属特征 UUID，默认 `null`。
  final String? characteristicUuid;

  /// 描述符值，默认空字节数组。
  final Uint8List value;

  /// 原生完整字段，默认空 Map。
  final Map<String, dynamic> raw;

  /// 转为可传给原生端的 Map。
  ///
  /// 无参数；不会写入 [raw] 中的额外字段。
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'uuid': uuid,
      if (characteristicUuid != null) 'characteristicUuid': characteristicUuid,
      'value': value,
    };
  }
}

/// GATT 特征。
class BluetoothGattCharacteristic {
  /// 创建 GATT 特征。
  ///
  /// 参数：
  /// - [uuid]：特征 UUID，无默认值。
  /// - [serviceUuid]：所属服务 UUID，无默认值。
  /// - [properties]：特征属性，默认 `const <String>[]`。常用值：`read`、`write`、
  ///   `writeWithoutResponse`、`notify`、`indicate`。iOS/macOS 额外支持
  ///   `notifyEncryptionRequired`、`indicateEncryptionRequired`。
  /// - [permissions]：本地 GATT Server 权限，默认 `const <String>[]`。为空时 Android/iOS/macOS
  ///   都会按可读可写处理；加密权限存在平台差异，跨平台推荐使用 `read`、`write`。
  /// - [value]：初始值，默认空 [Uint8List]。
  /// - [descriptors]：描述符列表，默认 `const <BluetoothGattDescriptor>[]`。
  /// - [raw]：原生完整字段，默认 `const <String, dynamic>{}`。
  BluetoothGattCharacteristic({
    required this.uuid,
    required this.serviceUuid,
    this.properties = const <String>[],
    this.permissions = const <String>[],
    Uint8List? value,
    this.descriptors = const <BluetoothGattDescriptor>[],
    this.raw = const <String, dynamic>{},
  }) : value = value ?? Uint8List(0);

  /// 从原生 Map 创建 GATT 特征。
  ///
  /// 参数：
  /// - [map]：原生特征数据，无默认值。
  factory BluetoothGattCharacteristic.fromMap(Map<String, dynamic> map) {
    final descriptors =
        (map['descriptors'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => BluetoothGattDescriptor.fromMap(_asStringMap(item)))
            .toList(growable: false);
    return BluetoothGattCharacteristic(
      uuid: map['uuid']?.toString() ?? '',
      serviceUuid: map['serviceUuid']?.toString() ?? '',
      properties: _asStringList(map['properties']),
      permissions: _asStringList(map['permissions']),
      value: _asByteList(map['value']),
      descriptors: descriptors,
      raw: map,
    );
  }

  /// 特征 UUID。
  final String uuid;

  /// 所属服务 UUID。
  final String serviceUuid;

  /// 特征属性列表，默认空列表。
  final List<String> properties;

  /// 本地 GATT Server 权限列表，默认空列表。
  final List<String> permissions;

  /// 特征值，默认空字节数组。
  final Uint8List value;

  /// 描述符列表，默认空列表。
  final List<BluetoothGattDescriptor> descriptors;

  /// 原生完整字段，默认空 Map。
  final Map<String, dynamic> raw;

  /// 转为可传给原生端的 Map。
  ///
  /// 无参数；用于注册本地 GATT Server 服务时传给原生层。
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'uuid': uuid,
      'serviceUuid': serviceUuid,
      'properties': properties,
      'permissions': permissions,
      'value': value,
      'descriptors':
          descriptors.map((descriptor) => descriptor.toMap()).toList(),
    };
  }

  /// 是否支持读取。
  bool get canRead => properties.contains('read');

  /// 是否支持有响应写。
  bool get canWrite => properties.contains('write');

  /// 是否支持无响应写。
  bool get canWriteWithoutResponse =>
      properties.contains('writeWithoutResponse');

  /// 是否支持通知。
  bool get canNotify => properties.contains('notify');

  /// 是否支持指示。
  bool get canIndicate => properties.contains('indicate');
}

/// GATT 服务。
class BluetoothGattService {
  /// 创建 GATT 服务。
  ///
  /// 参数：
  /// - [uuid]：服务 UUID，无默认值。
  /// - [isPrimary]：是否主服务，默认 `true`。
  /// - [characteristics]：特征列表，默认 `const <BluetoothGattCharacteristic>[]`。
  /// - [includedServices]：包含的服务 UUID，默认 `const <String>[]`。平台支持有限，通常可为空。
  /// - [raw]：原生完整字段，默认 `const <String, dynamic>{}`。
  const BluetoothGattService({
    required this.uuid,
    this.isPrimary = true,
    this.characteristics = const <BluetoothGattCharacteristic>[],
    this.includedServices = const <String>[],
    this.raw = const <String, dynamic>{},
  });

  /// 从原生 Map 创建 GATT 服务。
  ///
  /// 参数：
  /// - [map]：原生服务数据，无默认值。
  factory BluetoothGattService.fromMap(Map<String, dynamic> map) {
    final characteristics =
        (map['characteristics'] as List<dynamic>? ?? const <dynamic>[])
            .map(
              (item) => BluetoothGattCharacteristic.fromMap(_asStringMap(item)),
            )
            .toList(growable: false);
    return BluetoothGattService(
      uuid: map['uuid']?.toString() ?? '',
      isPrimary: _asBool(map['isPrimary'], defaultValue: true),
      characteristics: characteristics,
      includedServices: _asStringList(map['includedServices']),
      raw: map,
    );
  }

  /// 服务 UUID。
  final String uuid;

  /// 是否主服务，默认 `true`。
  final bool isPrimary;

  /// 特征列表，默认空列表。
  final List<BluetoothGattCharacteristic> characteristics;

  /// 包含服务 UUID 列表，默认空列表。
  final List<String> includedServices;

  /// 原生完整字段，默认空 Map。
  final Map<String, dynamic> raw;

  /// 转为可传给原生端的 Map。
  ///
  /// 无参数；用于注册本地 GATT Server 服务。
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'uuid': uuid,
      'isPrimary': isPrimary,
      'includedServices': includedServices,
      'characteristics': characteristics
          .map((characteristic) => characteristic.toMap())
          .toList(),
    };
  }
}

/// BLE 连接状态事件。
class BluetoothConnectionStateEvent {
  /// 创建连接状态事件。
  ///
  /// 参数：
  /// - [deviceId]：设备标识，无默认值。
  /// - [state]：连接状态，无默认值。
  /// - [status]：平台原生状态码，默认 `null`；Android 常见为 GATT status，iOS/macOS 通常为空。
  const BluetoothConnectionStateEvent({
    required this.deviceId,
    required this.state,
    this.status,
  });

  /// 从原生 Map 创建连接状态事件。
  ///
  /// 参数：
  /// - [map]：原生事件数据，无默认值。
  factory BluetoothConnectionStateEvent.fromMap(Map<String, dynamic> map) {
    return BluetoothConnectionStateEvent(
      deviceId: map['deviceId']?.toString() ?? '',
      state: bluetoothConnectionStateFromString(map['state']?.toString()),
      status: (map['status'] as num?)?.toInt(),
    );
  }

  /// 设备标识。
  final String deviceId;

  /// 连接状态。
  final BluetoothConnectionState state;

  /// 平台原生状态码，默认 `null`。
  final int? status;
}

/// GATT 特征值事件。
class BluetoothCharacteristicValue {
  /// 创建特征值事件。
  ///
  /// 参数：
  /// - [deviceId]：设备标识，无默认值。
  /// - [serviceUuid]：服务 UUID，无默认值。
  /// - [characteristicUuid]：特征 UUID，无默认值。
  /// - [value]：收到的字节数组，无默认值。
  const BluetoothCharacteristicValue({
    required this.deviceId,
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.value,
  });

  /// 从原生 Map 创建特征值事件。
  ///
  /// 参数：
  /// - [map]：原生事件数据，无默认值。
  factory BluetoothCharacteristicValue.fromMap(Map<String, dynamic> map) {
    return BluetoothCharacteristicValue(
      deviceId: map['deviceId']?.toString() ?? '',
      serviceUuid: map['serviceUuid']?.toString() ?? '',
      characteristicUuid: map['characteristicUuid']?.toString() ?? '',
      value: _asByteList(map['value']),
    );
  }

  /// 设备标识。
  final String deviceId;

  /// 服务 UUID。
  final String serviceUuid;

  /// 特征 UUID。
  final String characteristicUuid;

  /// 特征值字节数组。
  final Uint8List value;
}

/// GATT 描述符值事件。
class BluetoothDescriptorValue {
  /// 创建描述符值事件。
  ///
  /// 参数：
  /// - [deviceId]：设备标识，无默认值。
  /// - [serviceUuid]：服务 UUID，无默认值。
  /// - [characteristicUuid]：特征 UUID，无默认值。
  /// - [descriptorUuid]：描述符 UUID，无默认值。
  /// - [value]：收到的字节数组，无默认值。
  const BluetoothDescriptorValue({
    required this.deviceId,
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.descriptorUuid,
    required this.value,
  });

  /// 从原生 Map 创建描述符值事件。
  ///
  /// 参数：
  /// - [map]：原生事件数据，无默认值。
  factory BluetoothDescriptorValue.fromMap(Map<String, dynamic> map) {
    return BluetoothDescriptorValue(
      deviceId: map['deviceId']?.toString() ?? '',
      serviceUuid: map['serviceUuid']?.toString() ?? '',
      characteristicUuid: map['characteristicUuid']?.toString() ?? '',
      descriptorUuid: map['descriptorUuid']?.toString() ?? '',
      value: _asByteList(map['value']),
    );
  }

  /// 设备标识。
  final String deviceId;

  /// 服务 UUID。
  final String serviceUuid;

  /// 特征 UUID。
  final String characteristicUuid;

  /// 描述符 UUID。
  final String descriptorUuid;

  /// 描述符值字节数组。
  final Uint8List value;
}

/// RSSI 读取事件。
class BluetoothRssiEvent {
  /// 创建 RSSI 事件。
  ///
  /// 参数：
  /// - [deviceId]：设备标识，无默认值。
  /// - [rssi]：RSSI dBm，无默认值。
  const BluetoothRssiEvent({required this.deviceId, required this.rssi});

  /// 从原生 Map 创建 RSSI 事件。
  ///
  /// 参数：
  /// - [map]：原生事件数据，无默认值。
  factory BluetoothRssiEvent.fromMap(Map<String, dynamic> map) {
    return BluetoothRssiEvent(
      deviceId: map['deviceId']?.toString() ?? '',
      rssi: (map['rssi'] as num?)?.toInt() ?? 0,
    );
  }

  /// 设备标识。
  final String deviceId;

  /// RSSI dBm，通常为负数。
  final int rssi;
}

/// MTU 更新事件。
class BluetoothMtuEvent {
  /// 创建 MTU 事件。
  ///
  /// 参数：
  /// - [deviceId]：设备标识，无默认值。
  /// - [mtu]：MTU 或平台返回的最大写入长度，无默认值。
  const BluetoothMtuEvent({required this.deviceId, required this.mtu});

  /// 从原生 Map 创建 MTU 事件。
  ///
  /// 参数：
  /// - [map]：原生事件数据，无默认值。
  factory BluetoothMtuEvent.fromMap(Map<String, dynamic> map) {
    return BluetoothMtuEvent(
      deviceId: map['deviceId']?.toString() ?? '',
      mtu: (map['mtu'] as num?)?.toInt() ?? 0,
    );
  }

  /// 设备标识。
  final String deviceId;

  /// MTU 或最大写入长度。
  final int mtu;
}

/// Android 配对/绑定状态事件。
class BluetoothBondStateEvent {
  /// 创建绑定状态事件。
  ///
  /// 参数：
  /// - [deviceId]：设备标识，无默认值。
  /// - [state]：绑定状态，无默认值。
  const BluetoothBondStateEvent({required this.deviceId, required this.state});

  /// 从原生 Map 创建绑定状态事件。
  ///
  /// 参数：
  /// - [map]：原生事件数据，无默认值。
  factory BluetoothBondStateEvent.fromMap(Map<String, dynamic> map) {
    return BluetoothBondStateEvent(
      deviceId: map['deviceId']?.toString() ?? '',
      state: bluetoothBondStateFromString(map['state']?.toString()),
    );
  }

  /// 设备标识。
  final String deviceId;

  /// 绑定状态。
  final BluetoothBondState state;
}

/// BLE 广播模式。
///
/// 默认推荐 [balanced]。Android 会应用这些设置；iOS/macOS 当前忽略广播设置。
enum BluetoothAdvertisingMode {
  /// 低功耗广播，适合长时间后台或低频发现。
  lowPower,

  /// 均衡广播，默认值，常规推荐。
  balanced,

  /// 低延迟高频广播，适合短时间快速发现，耗电更高。
  lowLatency,
}

/// BLE 广播发射功率。
///
/// 默认推荐 [medium]。Android 会应用该设置；iOS/macOS 当前忽略。
enum BluetoothTxPowerLevel {
  /// 超低功率，范围最小、最省电。
  ultraLow,

  /// 低功率。
  low,

  /// 中等功率，默认值，常规推荐。
  medium,

  /// 高功率，范围更大但更耗电。
  high,
}

/// BLE PHY 类型。
///
/// Android 8.0+ 可读取/设置；iOS/macOS/Linux/Windows/Web 通常返回 [unknown]。
enum BluetoothPhy {
  /// LE 1M PHY，兼容性最好，默认回退推荐。
  le1m,

  /// LE 2M PHY，短距离高吞吐推荐，需硬件支持。
  le2m,

  /// LE Coded PHY，长距离低速场景使用，需硬件支持。
  leCoded,

  /// 未知或当前平台不支持读取。
  unknown,
}

/// 将原生字符串转换为 [BluetoothPhy]。
///
/// 参数：
/// - [value]：原生 PHY 名称，默认可传 `null`；无法识别时返回 [BluetoothPhy.unknown]。
BluetoothPhy bluetoothPhyFromString(String? value) {
  return BluetoothPhy.values.firstWhere(
    (phy) => phy.name == value,
    orElse: () => BluetoothPhy.unknown,
  );
}

/// 蓝牙适配器信息和能力摘要。
class BluetoothAdapterInfo {
  /// 创建适配器信息。
  ///
  /// 参数：
  /// - [isSupported]：是否支持蓝牙，无默认值。
  /// - [state]：当前适配器状态，无默认值。
  /// - [name]：适配器名称，默认 `null`。Android 需要连接权限；Linux 可能返回 BlueZ 名称；
  ///   iOS/macOS/Windows/Web 通常不公开。
  /// - [address]：适配器地址，默认 `null`。Android 可能受系统限制；Linux/Windows 可能返回本机蓝牙地址；
  ///   iOS/macOS/Web 不公开。
  /// - [isBleSupported]：是否支持 BLE，默认 `false`。
  /// - [isMultipleAdvertisementSupported]：是否支持多广播，默认 `false`；主要 Android 能力。
  /// - [isOffloadedFilteringSupported]：是否支持硬件离线过滤，默认 `false`；Android 能力。
  /// - [isOffloadedScanBatchingSupported]：是否支持硬件批量扫描，默认 `false`；Android 能力。
  /// - [isLe2MPhySupported]：是否支持 LE 2M PHY，默认 `false`；Android 8.0+ 能力。
  /// - [isLeCodedPhySupported]：是否支持 LE Coded PHY，默认 `false`；Android 8.0+ 能力。
  /// - [isLeExtendedAdvertisingSupported]：是否支持扩展广播，默认 `false`；Android 8.0+ 能力。
  /// - [isLePeriodicAdvertisingSupported]：是否支持周期广播，默认 `false`；Android 8.0+ 能力。
  /// - [isDiscovering]：当前是否正在扫描/发现，默认 `false`；Web 仅表示设备选择器是否打开。
  /// - [raw]：原生完整字段，默认 `const <String, dynamic>{}`。
  const BluetoothAdapterInfo({
    required this.isSupported,
    required this.state,
    this.name,
    this.address,
    this.isBleSupported = false,
    this.isMultipleAdvertisementSupported = false,
    this.isOffloadedFilteringSupported = false,
    this.isOffloadedScanBatchingSupported = false,
    this.isLe2MPhySupported = false,
    this.isLeCodedPhySupported = false,
    this.isLeExtendedAdvertisingSupported = false,
    this.isLePeriodicAdvertisingSupported = false,
    this.isDiscovering = false,
    this.raw = const <String, dynamic>{},
  });

  /// 从原生 Map 创建适配器信息。
  ///
  /// 参数：
  /// - [map]：原生适配器数据，无默认值；缺失布尔字段会按 `false` 处理。
  factory BluetoothAdapterInfo.fromMap(Map<String, dynamic> map) {
    return BluetoothAdapterInfo(
      isSupported: _asBool(map['isSupported']),
      state: bluetoothAdapterStateFromString(map['state']?.toString()),
      name: map['name']?.toString(),
      address: map['address']?.toString(),
      isBleSupported: _asBool(map['isBleSupported']),
      isMultipleAdvertisementSupported:
          _asBool(map['isMultipleAdvertisementSupported']),
      isOffloadedFilteringSupported:
          _asBool(map['isOffloadedFilteringSupported']),
      isOffloadedScanBatchingSupported:
          _asBool(map['isOffloadedScanBatchingSupported']),
      isLe2MPhySupported: _asBool(map['isLe2MPhySupported']),
      isLeCodedPhySupported: _asBool(map['isLeCodedPhySupported']),
      isLeExtendedAdvertisingSupported:
          _asBool(map['isLeExtendedAdvertisingSupported']),
      isLePeriodicAdvertisingSupported:
          _asBool(map['isLePeriodicAdvertisingSupported']),
      isDiscovering: _asBool(map['isDiscovering']),
      raw: map,
    );
  }

  /// 是否支持蓝牙。
  final bool isSupported;

  /// 当前适配器状态。
  final BluetoothAdapterState state;

  /// 适配器名称，默认 `null`；Linux 可能返回 BlueZ 名称，Web/Windows 通常不公开。
  final String? name;

  /// 适配器地址，默认 `null`；Web 不公开，Linux/Windows 可能返回本机蓝牙地址。
  final String? address;

  /// 是否支持 BLE，默认 `false`。
  final bool isBleSupported;

  /// 是否支持多广播，默认 `false`；主要 Android 有意义。
  final bool isMultipleAdvertisementSupported;

  /// 是否支持硬件离线过滤，默认 `false`；Android 能力。
  final bool isOffloadedFilteringSupported;

  /// 是否支持硬件批量扫描，默认 `false`；Android 能力。
  final bool isOffloadedScanBatchingSupported;

  /// 是否支持 LE 2M PHY，默认 `false`；Android 8.0+ 能力。
  final bool isLe2MPhySupported;

  /// 是否支持 LE Coded PHY，默认 `false`；Android 8.0+ 能力。
  final bool isLeCodedPhySupported;

  /// 是否支持扩展广播，默认 `false`；Android 8.0+ 能力。
  final bool isLeExtendedAdvertisingSupported;

  /// 是否支持周期广播，默认 `false`；Android 8.0+ 能力。
  final bool isLePeriodicAdvertisingSupported;

  /// 当前是否正在扫描/发现，默认 `false`；Web 仅表示设备选择器是否打开。
  final bool isDiscovering;

  /// 原生完整字段，默认空 Map。
  final Map<String, dynamic> raw;
}

/// BLE 广播数据。
class BluetoothAdvertisementData {
  /// 创建广播数据。
  ///
  /// 参数：
  /// - [localName]：广播本地名称，默认 `null`。iOS/macOS 当前只使用该字段和 [serviceUuids]。
  /// - [includeDeviceName]：是否包含适配器设备名，默认 `false`；Android 支持，iOS/macOS 忽略。
  /// - [includeTxPowerLevel]：是否包含发射功率，默认 `false`；Android 支持，iOS/macOS 忽略。
  /// - [serviceUuids]：广播服务 UUID，默认 `const <String>[]`。跨平台推荐只放必要服务。
  /// - [manufacturerData]：厂商数据，默认 `const <int, Uint8List>{}`；Android 支持，iOS/macOS 当前忽略。
  /// - [serviceData]：服务数据，默认 `const <String, Uint8List>{}`；Android 支持，iOS/macOS 当前忽略。
  ///
  /// 推荐：传统广播数据空间有限，优先保留 [localName] 和关键 [serviceUuids]，避免同时开启
  /// [includeDeviceName] 和大量厂商数据导致 Android 广播启动失败。
  const BluetoothAdvertisementData({
    this.localName,
    this.includeDeviceName = false,
    this.includeTxPowerLevel = false,
    this.serviceUuids = const <String>[],
    this.manufacturerData = const <int, Uint8List>{},
    this.serviceData = const <String, Uint8List>{},
  });

  /// 广播本地名称，默认 `null`。
  final String? localName;

  /// 是否包含适配器设备名，默认 `false`；Android 支持，iOS/macOS 忽略。
  final bool includeDeviceName;

  /// 是否包含发射功率，默认 `false`；Android 支持，iOS/macOS 忽略。
  final bool includeTxPowerLevel;

  /// 广播服务 UUID 列表，默认空列表。
  final List<String> serviceUuids;

  /// 厂商数据，默认空 Map；key 为 Company ID。
  final Map<int, Uint8List> manufacturerData;

  /// 服务数据，默认空 Map；key 为服务 UUID。
  final Map<String, Uint8List> serviceData;

  /// 转为可传给原生端的 Map。
  ///
  /// 无参数；Android 会读取全部字段，iOS/macOS 当前只读取 [localName] 和 [serviceUuids]。
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (localName != null) 'localName': localName,
      'includeDeviceName': includeDeviceName,
      'includeTxPowerLevel': includeTxPowerLevel,
      'serviceUuids': serviceUuids,
      'manufacturerData': manufacturerData.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      'serviceData': serviceData,
    };
  }
}

/// BLE 广播设置。
class BluetoothAdvertisingSettings {
  /// 创建广播设置。
  ///
  /// 参数：
  /// - [mode]：广播模式，默认 [BluetoothAdvertisingMode.balanced]，常规推荐。
  /// - [txPowerLevel]：发射功率，默认 [BluetoothTxPowerLevel.medium]，常规推荐。
  /// - [connectable]：是否可连接，默认 `true`。只做 beacon 广播可设为 `false`。
  /// - [timeout]：广播超时，默认 `null` 表示不设置超时；Android 会转换为 `0`，iOS/macOS 当前忽略。
  const BluetoothAdvertisingSettings({
    this.mode = BluetoothAdvertisingMode.balanced,
    this.txPowerLevel = BluetoothTxPowerLevel.medium,
    this.connectable = true,
    this.timeout,
  });

  /// 广播模式，默认 [BluetoothAdvertisingMode.balanced]。
  final BluetoothAdvertisingMode mode;

  /// 发射功率，默认 [BluetoothTxPowerLevel.medium]。
  final BluetoothTxPowerLevel txPowerLevel;

  /// 是否可连接，默认 `true`。
  final bool connectable;

  /// 广播超时，默认 `null` 表示不自动停止。
  final Duration? timeout;

  /// 转为可传给原生端的 Map。
  ///
  /// 无参数；Android 会读取全部字段，iOS/macOS 当前忽略。
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'mode': mode.name,
      'txPowerLevel': txPowerLevel.name,
      'connectable': connectable,
      'timeoutMs': timeout?.inMilliseconds,
    };
  }
}

/// BLE 广播状态事件。
class BluetoothAdvertisingStateEvent {
  /// 创建广播状态事件。
  ///
  /// 参数：
  /// - [isAdvertising]：当前是否正在广播，无默认值。
  /// - [errorCode]：Android 广播错误码，默认 `null`。
  /// - [message]：平台状态或错误消息，默认 `null`。
  const BluetoothAdvertisingStateEvent({
    required this.isAdvertising,
    this.errorCode,
    this.message,
  });

  /// 从原生 Map 创建广播状态事件。
  ///
  /// 参数：
  /// - [map]：原生事件数据，无默认值。
  factory BluetoothAdvertisingStateEvent.fromMap(Map<String, dynamic> map) {
    return BluetoothAdvertisingStateEvent(
      isAdvertising: _asBool(map['isAdvertising']),
      errorCode: (map['errorCode'] as num?)?.toInt(),
      message: map['message']?.toString(),
    );
  }

  /// 当前是否正在广播。
  final bool isAdvertising;

  /// Android 广播错误码，默认 `null`。
  final int? errorCode;

  /// 平台状态或错误消息，默认 `null`。
  final String? message;
}

/// 本地 GATT Server 请求/状态事件。
class BluetoothGattServerRequest {
  /// 创建 GATT Server 请求事件。
  ///
  /// 参数：
  /// - [event]：事件名称，无默认值。常见值包括 `serviceAdded`、`connectionState`、
  ///   `characteristicRead`、`characteristicWrite`、`descriptorRead`、`descriptorWrite`、
  ///   `subscribed`、`unsubscribed`、`notificationSent`。
  /// - [deviceId]：中心设备标识，无默认值；iOS/macOS 为 central UUID，Android 为设备地址。
  /// - [serviceUuid]：服务 UUID，默认 `null`。
  /// - [characteristicUuid]：特征 UUID，默认 `null`。
  /// - [descriptorUuid]：描述符 UUID，默认 `null`。
  /// - [requestId]：Android GATT 请求 ID，默认 `null`；iOS/macOS 通常为空。
  /// - [offset]：读写偏移，默认 `0`。
  /// - [value]：请求或响应字节数组，默认空 [Uint8List]。
  /// - [preparedWrite]：是否 prepared write，默认 `false`；主要 Android 有意义。
  /// - [responseNeeded]：是否需要响应，默认 `false`。
  /// - [raw]：原生完整字段，默认 `const <String, dynamic>{}`。
  BluetoothGattServerRequest({
    required this.event,
    required this.deviceId,
    this.serviceUuid,
    this.characteristicUuid,
    this.descriptorUuid,
    this.requestId,
    this.offset = 0,
    Uint8List? value,
    this.preparedWrite = false,
    this.responseNeeded = false,
    this.raw = const <String, dynamic>{},
  }) : value = value ?? Uint8List(0);

  /// 从原生 Map 创建 GATT Server 请求事件。
  ///
  /// 参数：
  /// - [map]：原生事件数据，无默认值。
  factory BluetoothGattServerRequest.fromMap(Map<String, dynamic> map) {
    return BluetoothGattServerRequest(
      event: map['event']?.toString() ?? '',
      deviceId: map['deviceId']?.toString() ?? '',
      serviceUuid: map['serviceUuid']?.toString(),
      characteristicUuid: map['characteristicUuid']?.toString(),
      descriptorUuid: map['descriptorUuid']?.toString(),
      requestId: (map['requestId'] as num?)?.toInt(),
      offset: (map['offset'] as num?)?.toInt() ?? 0,
      value: _asByteList(map['value']),
      preparedWrite: _asBool(map['preparedWrite']),
      responseNeeded: _asBool(map['responseNeeded']),
      raw: map,
    );
  }

  /// 事件名称。
  final String event;

  /// 中心设备标识。
  final String deviceId;

  /// 服务 UUID，默认 `null`。
  final String? serviceUuid;

  /// 特征 UUID，默认 `null`。
  final String? characteristicUuid;

  /// 描述符 UUID，默认 `null`。
  final String? descriptorUuid;

  /// Android GATT 请求 ID，默认 `null`。
  final int? requestId;

  /// 读写偏移，默认 `0`。
  final int offset;

  /// 请求或响应字节数组，默认空列表。
  final Uint8List value;

  /// 是否 prepared write，默认 `false`。
  final bool preparedWrite;

  /// 是否需要响应，默认 `false`。
  final bool responseNeeded;

  /// 原生完整字段，默认空 Map。
  final Map<String, dynamic> raw;
}

/// BLE PHY 事件。
class BluetoothPhyEvent {
  /// 创建 PHY 事件。
  ///
  /// 参数：
  /// - [deviceId]：设备标识，无默认值。
  /// - [txPhy]：发送方向 PHY，无默认值。
  /// - [rxPhy]：接收方向 PHY，无默认值。
  /// - [status]：平台原生状态码，默认 `null`；主要 Android 有意义。
  const BluetoothPhyEvent({
    required this.deviceId,
    required this.txPhy,
    required this.rxPhy,
    this.status,
  });

  /// 从原生 Map 创建 PHY 事件。
  ///
  /// 参数：
  /// - [map]：原生事件数据，无默认值。
  factory BluetoothPhyEvent.fromMap(Map<String, dynamic> map) {
    return BluetoothPhyEvent(
      deviceId: map['deviceId']?.toString() ?? '',
      txPhy: bluetoothPhyFromString(map['txPhy']?.toString()),
      rxPhy: bluetoothPhyFromString(map['rxPhy']?.toString()),
      status: (map['status'] as num?)?.toInt(),
    );
  }

  /// 设备标识。
  final String deviceId;

  /// 发送方向 PHY。
  final BluetoothPhy txPhy;

  /// 接收方向 PHY。
  final BluetoothPhy rxPhy;

  /// 平台原生状态码，默认 `null`。
  final int? status;
}

/// Classic Bluetooth 连接状态事件。
class BluetoothClassicConnectionEvent {
  /// 创建 Classic 连接状态事件。
  ///
  /// 参数：
  /// - [deviceId]：Classic 设备地址，无默认值。
  /// - [state]：连接状态，无默认值。
  /// - [error]：错误消息，默认 `null`。
  const BluetoothClassicConnectionEvent({
    required this.deviceId,
    required this.state,
    this.error,
  });

  /// 从原生 Map 创建 Classic 连接状态事件。
  ///
  /// 参数：
  /// - [map]：原生事件数据，无默认值。
  factory BluetoothClassicConnectionEvent.fromMap(Map<String, dynamic> map) {
    return BluetoothClassicConnectionEvent(
      deviceId: map['deviceId']?.toString() ?? '',
      state: bluetoothConnectionStateFromString(map['state']?.toString()),
      error: map['error']?.toString(),
    );
  }

  /// Classic 设备地址。
  final String deviceId;

  /// 连接状态。
  final BluetoothConnectionState state;

  /// 错误消息，默认 `null`。
  final String? error;
}

/// Classic Bluetooth 数据事件。
class BluetoothClassicDataEvent {
  /// 创建 Classic 数据事件。
  ///
  /// 参数：
  /// - [deviceId]：Classic 设备地址，无默认值。
  /// - [value]：收到的字节数组，无默认值。
  const BluetoothClassicDataEvent({
    required this.deviceId,
    required this.value,
  });

  /// 从原生 Map 创建 Classic 数据事件。
  ///
  /// 参数：
  /// - [map]：原生事件数据，无默认值。
  factory BluetoothClassicDataEvent.fromMap(Map<String, dynamic> map) {
    return BluetoothClassicDataEvent(
      deviceId: map['deviceId']?.toString() ?? '',
      value: _asByteList(map['value']),
    );
  }

  /// Classic 设备地址。
  final String deviceId;

  /// 收到的字节数组。
  final Uint8List value;
}
