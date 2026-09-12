# flutter_bluetooth_plugin

[English](README.md)

一个面向 Android、iOS、macOS、Linux、Windows 和 Web 的 Flutter 蓝牙插件。它把产品里最常见、最容易踩坑的蓝牙能力收敛到一套 Dart API：适配器状态、权限、BLE 扫描、GATT Client、本地 GATT Server/外设模式、BLE 广播、通知、RSSI、MTU、PHY、绑定、Android Classic RFCOMM、Linux BlueZ、Windows WinRT 以及浏览器 Web Bluetooth。

这个插件不会假装所有系统的蓝牙能力完全一致。它保留各平台真实行为，同时用尽量统一的方式暴露给 Flutter 层，方便你做跨平台产品、调试工具或硬件配套 App。

> 不支持能力的处理约定：安全的 stop/clear 调用会变成空操作；能力查询返回 `false`；不可用的数值返回 `0`；不支持的事件流保持为空；无法用当前平台表达的操作会抛出 unsupported 错误。

## 目录

- [适合做什么](#适合做什么)
- [平台能力地图](#平台能力地图)
- [安装](#安装)
- [平台配置](#平台配置)
- [快速开始：先扫到设备](#快速开始先扫到设备)
- [常用场景示例](#常用场景示例)
- [API 分类指南](#api-分类指南)
- [模型与枚举](#模型与枚举)
- [平台差异说明](#平台差异说明)
- [常见问题排查](#常见问题排查)
- [示例 App](#示例-app)
- [开源协议](#开源协议)

## 适合做什么

- BLE Central 应用：扫描、连接、发现服务、读写特征、订阅通知、读写描述符。
- Android、iOS、macOS 外设原型：本地 GATT 服务、BLE 广播、处理中心设备读写、主动通知。
- Android Classic Bluetooth RFCOMM：连接串口/SPP 类设备，或启动本机 RFCOMM 服务端。
- 桌面 BLE 工具：Linux 走 BlueZ/system DBus，Windows 走 WinRT BLE API。
- Web Bluetooth：通过浏览器设备选择器访问当前站点授权的 BLE 设备和服务。
- 蓝牙诊断台：查看适配器状态、权限、已绑定/已连接设备、RSSI、MTU、PHY 和原始平台字段。

## 平台能力地图

说明：`完整` 表示当前平台原生实现已覆盖；`有限` 表示受系统策略或浏览器授权限制；`不支持` 表示该平台没有对应能力或插件当前未实现。

| 能力 | Android | iOS | macOS | Linux | Windows | Web |
| --- | --- | --- | --- | --- | --- | --- |
| 适配器状态与信息 | 完整 | 完整 | 完整 | BlueZ | WinRT | 浏览器可用性 |
| 权限辅助 | 运行时权限 | CoreBluetooth 授权 | CoreBluetooth 授权 | 可用性映射 | 可用性映射 | 无全局预授权 |
| BLE 扫描 | 完整 | 完整 | 完整 | BlueZ discovery | BLE 广播扫描 | 浏览器选择器 |
| Service UUID 扫描过滤 | 完整 | 完整 | 完整 | BlueZ 过滤 | 广播过滤 | 选择器过滤 |
| Classic 发现模式 | 完整 | 不支持 | 不支持 | 仅 BlueZ discovery | 不支持 | 不支持 |
| 已绑定/已配对设备 | 完整 | 无公开列表 | 无公开列表 | BlueZ 已配对 | 尽量返回已配对 BLE | 当前站点授权设备 |
| 已连接设备 | 完整 | 按服务查询 | 按服务查询 | BlueZ 已连接 | 插件已知设备 | 当前站点授权且已连接 |
| BLE GATT Client | 完整 | 完整 | 完整 | 完整 | 完整 | 仅授权服务 |
| 特征通知/指示 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 |
| 描述符读写 | 完整 | 完整 | 完整 | 完整 | 完整 | 有限；CCCD 请用通知 API |
| RSSI | 已连接 RSSI | 已连接 RSSI | 已连接 RSSI | 缓存广播 RSSI | 缓存广播 RSSI | 不支持 |
| MTU 请求 | 完整 | 返回最大写入长度 | 返回最大写入长度 | 不支持 | 不支持 | 不支持 |
| 最大写入长度 | MTU - 3 | 完整 | 完整 | 不支持 | 不支持 | 不支持 |
| PHY 读写 | Android 8+ | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| 连接优先级 | 完整 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| 创建/移除绑定 | 完整 | 不支持 | 不支持 | BlueZ pair/remove | 不支持 | 不支持 |
| 本地 GATT Server | 完整 | 完整 | 完整 | 不支持 | 不支持 | 不支持 |
| BLE 广播 | 完整 | 有限 | 有限 | 不支持 | 不支持 | 不支持 |
| Android Classic RFCOMM | 完整 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |

## 安装

在业务 App 中添加依赖：

```yaml
dependencies:
  flutter_bluetooth_plugin: ^2.0.0
```

导入公共 API：

```dart
import 'dart:typed_data';

import 'package:flutter_bluetooth_plugin/flutter_bluetooth_plugin.dart';
```

创建插件对象：

```dart
final bluetooth = FlutterBluetoothPlugin();
```

## 平台配置

蓝牙权限和系统策略是“扫不到设备”的高频原因。建议先完成宿主 App 配置，再在合适的 UI 时机调用 `requestPermissions()`，最后再扫描、连接或广播。

### Android

插件 manifest 会向宿主 App 合并常用蓝牙权限和 feature：

- Android 12+ 使用运行时权限：`BLUETOOTH_SCAN`、`BLUETOOTH_CONNECT`、`BLUETOOTH_ADVERTISE`。
- Android 6-11 的 BLE 扫描结果通常需要定位权限，例如 `ACCESS_FINE_LOCATION`。
- Android 11 及以下还会使用 `BLUETOOTH`、`BLUETOOTH_ADMIN`。

推荐流程：

```dart
final permissions = await bluetooth.requestPermissions();
final state = await bluetooth.getAdapterState();

if (state != BluetoothAdapterState.poweredOn) {
  final opened = await bluetooth.requestEnable();
  if (!opened) await bluetooth.openBluetoothSettings();
}
```

### iOS

宿主 App 的 `Info.plist` 需要加入蓝牙用途说明：

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to scan, connect, and exchange data with nearby devices.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app uses Bluetooth to communicate with nearby peripherals.</string>
```

注意：

- `requestPermissions()` 会初始化 CoreBluetooth，从而触发系统授权流程。
- iOS 不允许 App 直接打开蓝牙，只能引导用户去系统设置。
- iOS 不向第三方 App 开放 Classic Bluetooth RFCOMM。

### macOS

`Info.plist` 需要蓝牙用途说明：

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to scan, connect, and exchange data with nearby devices.</string>
```

如果是沙盒 App，还需要蓝牙 entitlement：

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
```

### Linux

Linux 通过 BlueZ 和 system DBus 工作。

- `requestPermissions()` 会把适配器可用性映射成权限状态，不会弹系统权限框。
- `requestEnable()` 会尝试设置 BlueZ Adapter 的 `Powered` 属性。
- `openBluetoothSettings()` 会尝试打开 GNOME Control Center、Blueman、KDE 蓝牙设置等常见工具。
- 用户环境需要 BlueZ 正常运行，并且当前用户具备足够的 DBus 权限。

### Windows

Windows 通过 WinRT BLE API 工作。

- `requestPermissions()` 用于报告 BLE 适配器是否可用。
- `openBluetoothSettings()` 会打开 Windows 蓝牙设置页。
- 当前 Windows 实现重点覆盖 BLE Central/GATT Client。

### Web

Web Bluetooth 不是被动扫描，而是浏览器托管的设备选择器。

- 页面必须运行在安全上下文：HTTPS 或 localhost。
- `startScan()` 必须由用户手势触发，例如按钮点击。
- 如果连接后需要访问某些 GATT 服务，请把服务 UUID 传给 `startScan(serviceUuids: [...])`，浏览器会用这份列表授予服务访问权限。
- 如果 `serviceUuids` 为空，插件会使用 `acceptAllDevices`，用户更容易先看到附近 BLE 设备，但后续 GATT 服务访问可能受限。

## 快速开始：先扫到设备

第一次验证扫描能力时，请先不要填 Service UUID 过滤器。很多设备广播时不会带出它连接后才暴露的完整服务列表，过早过滤会让正常扫描看起来像“扫不到”。

```dart
final bluetooth = FlutterBluetoothPlugin();

await bluetooth.requestPermissions();

final adapterState = await bluetooth.getAdapterState();
if (adapterState != BluetoothAdapterState.poweredOn) {
  final opened = await bluetooth.requestEnable();
  if (!opened) await bluetooth.openBluetoothSettings();
}

final scanSub = bluetooth.scanResults.listen((result) {
  final name = result.device.name ?? result.localName ?? 'Unnamed';
  print('$name ${result.device.id} RSSI=${result.rssi}');
});

await bluetooth.startScan(
  serviceUuids: const <String>[], // 空列表表示不按 BLE 服务过滤。
  timeout: const Duration(seconds: 15),
  allowDuplicates: false,
  scanMode: BluetoothScanMode.ble,
);

await Future<void>.delayed(const Duration(seconds: 15));
await bluetooth.stopScan();
await scanSub.cancel();
```

当你已经知道目标设备会在广播里带出某个服务 UUID，再启用过滤：

```dart
await bluetooth.startScan(
  serviceUuids: const <String>['0000fff0-0000-1000-8000-00805f9b34fb'],
  timeout: const Duration(seconds: 10),
);
```

## 常用场景示例

### 连接、发现服务、读写特征、订阅通知

```dart
await bluetooth.connect(deviceId, timeout: const Duration(seconds: 15));

final services = await bluetooth.discoverServices(deviceId);
final service = services.first;
final characteristic = service.characteristics.first;

final value = await bluetooth.readCharacteristic(
  deviceId: deviceId,
  serviceUuid: service.uuid,
  characteristicUuid: characteristic.uuid,
);

await bluetooth.writeCharacteristic(
  deviceId: deviceId,
  serviceUuid: service.uuid,
  characteristicUuid: characteristic.uuid,
  value: value,
  writeType: BluetoothWriteType.withResponse,
);

final notifySub = bluetooth.characteristicValues.listen((event) {
  print('${event.characteristicUuid}: ${event.value}');
});

await bluetooth.setCharacteristicNotification(
  deviceId: deviceId,
  serviceUuid: service.uuid,
  characteristicUuid: characteristic.uuid,
  enable: true,
);
```

### 读写描述符

```dart
const cccd = '00002902-0000-1000-8000-00805f9b34fb';

final descriptorValue = await bluetooth.readDescriptor(
  deviceId: deviceId,
  serviceUuid: serviceUuid,
  characteristicUuid: characteristicUuid,
  descriptorUuid: cccd,
);

await bluetooth.writeDescriptor(
  deviceId: deviceId,
  serviceUuid: serviceUuid,
  characteristicUuid: characteristicUuid,
  descriptorUuid: cccd,
  value: descriptorValue,
);
```

订阅通知时，更推荐使用 `setCharacteristicNotification()`，不要直接写 CCCD；Web 平台尤其如此。

### RSSI、MTU、最大写入长度、PHY

```dart
final rssi = await bluetooth.readRssi(deviceId);
final mtu = await bluetooth.requestMtu(deviceId, 247);
final maxWrite = await bluetooth.getMaximumWriteLength(
  deviceId,
  withoutResponse: true,
);

final phy = await bluetooth.readPhy(deviceId);
if (phy.txPhy != BluetoothPhy.unknown) {
  await bluetooth.setPreferredPhy(
    deviceId: deviceId,
    txPhy: BluetoothPhy.le2m,
    rxPhy: BluetoothPhy.le2m,
  );
}
```

### 绑定与连接优先级

```dart
final bonded = await bluetooth.createBond(deviceId);

final priorityChanged = await bluetooth.requestConnectionPriority(
  deviceId,
  BluetoothConnectionPriority.high,
);
```

`requestConnectionPriority()` 仅 Android 支持；`createBond()` / `removeBond()` 当前主要由 Android 和 Linux 支持。

### 本地 GATT Server 与 BLE 广播

```dart
const serviceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
const characteristicUuid = '0000fff1-0000-1000-8000-00805f9b34fb';

if (await bluetooth.isPeripheralSupported()) {
  await bluetooth.setGattServerServices(
    <BluetoothGattService>[
      BluetoothGattService(
        uuid: serviceUuid,
        characteristics: <BluetoothGattCharacteristic>[
          BluetoothGattCharacteristic(
            uuid: characteristicUuid,
            serviceUuid: serviceUuid,
            properties: <String>[
              'read',
              'write',
              'writeWithoutResponse',
              'notify',
            ],
            permissions: <String>['read', 'write'],
            value: Uint8List.fromList(<int>[72, 101, 108, 108, 111]),
          ),
        ],
      ),
    ],
  );

  await bluetooth.startAdvertising(
    advertisementData: const BluetoothAdvertisementData(
      localName: 'Flutter BT',
      serviceUuids: <String>[serviceUuid],
      includeDeviceName: true,
      includeTxPowerLevel: true,
    ),
    settings: const BluetoothAdvertisingSettings(
      mode: BluetoothAdvertisingMode.lowLatency,
      txPowerLevel: BluetoothTxPowerLevel.high,
      connectable: true,
    ),
  );
}

final serverSub = bluetooth.gattServerRequests.listen((event) {
  print('${event.event} from ${event.deviceId}: ${event.value}');
});
```

更新本地特征值并主动通知中心设备：

```dart
await bluetooth.updateLocalCharacteristicValue(
  serviceUuid: serviceUuid,
  characteristicUuid: characteristicUuid,
  value: Uint8List.fromList(<int>[1, 2, 3]),
);

final sent = await bluetooth.notifyGattServerCharacteristic(
  serviceUuid: serviceUuid,
  characteristicUuid: characteristicUuid,
  value: Uint8List.fromList(<int>[1, 2, 3]),
  confirm: false,
);
```

### Android Classic RFCOMM

```dart
const sppUuid = '00001101-0000-1000-8000-00805f9b34fb';

await bluetooth.startClassicServer(
  serviceUuid: sppUuid,
  serviceName: 'FlutterBluetoothPlugin',
);

await bluetooth.connectClassic(
  deviceId: macAddress,
  serviceUuid: sppUuid,
  secure: true,
  timeout: const Duration(seconds: 15),
);

final classicStateSub = bluetooth.classicConnectionState.listen((event) {
  print('${event.deviceId}: ${event.state} ${event.error ?? ''}');
});

final classicDataSub = bluetooth.classicData.listen((event) {
  print('Classic ${event.deviceId}: ${event.value}');
});

await bluetooth.writeClassic(macAddress, Uint8List.fromList(<int>[1, 2, 3]));
```

## API 分类指南

### 适配器与权限

| API | 用途 | 平台差异 |
| --- | --- | --- |
| `getPlatformVersion()` | 获取平台版本字符串。 | 各平台返回自己的系统/浏览器版本信息。 |
| `isSupported()` | 判断当前设备/平台是否支持蓝牙。 | Web 还要求安全上下文和 Web Bluetooth API。 |
| `getAdapterState()` | 读取 `unknown`、`unsupported`、`unauthorized`、`poweredOff`、`poweredOn`、`resetting`、`turningOn`、`turningOff`。 | Linux 映射 BlueZ `Powered`；Web 映射浏览器 availability。 |
| `adapterState` | 监听适配器状态变化。 | Linux/Web 会尽量先发当前映射状态。 |
| `getAdapterInfo()` | 获取适配器名称、地址和能力标记。 | Android 能力字段最完整；Apple/Web 通常不公开硬件地址。 |
| `isScanning()` | 判断当前是否扫描/发现中。 | Android 包含 BLE 和 Classic discovery；Web 表示选择器是否打开。 |
| `setAdapterName(name)` | 尝试修改本机蓝牙适配器名称/别名。 | Android、Linux 有效；其它平台返回 `false`。 |
| `checkPermissions()` | 只读取权限状态，不触发弹窗。 | Android 返回多个权限键；iOS/macOS 返回 `bluetooth`。 |
| `requestPermissions()` | 触发或初始化权限流程。 | Web 没有全局弹窗，需在用户手势中调用 `startScan()`。 |
| `requestEnable()` | 请求开启蓝牙。 | Android 弹系统窗口；Linux 写 BlueZ `Powered`；其它平台返回 `false`。 |
| `openBluetoothSettings()` | 打开蓝牙或 App 设置页。 | Web 没有标准蓝牙设置页，当前为空操作。 |

### 扫描发现与设备查询

| API | 用途 | 平台差异 |
| --- | --- | --- |
| `startScan(serviceUuids, timeout, allowDuplicates, scanMode)` | 开始 BLE 扫描、Classic discovery 或 Web 设备选择。 | `serviceUuids` 为空表示不按 BLE 服务过滤，适合首次验证。 |
| `stopScan()` | 停止扫描/发现。 | Web 不能主动关闭浏览器原生选择器，只会清理本地状态。 |
| `scanResults` | 监听 `BluetoothScanResult`。 | 建议先订阅再调用 `startScan()`，避免漏掉早期结果。 |
| `getBondedDevices()` | 获取已绑定/已配对设备。 | Android/Linux 最完整；Apple 无公开配对列表。 |
| `getConnectedDevices(serviceUuids)` | 获取已连接设备。 | iOS/macOS/Web 建议传目标服务 UUID。 |
| `getDevice(deviceId)` | 查询一个已知设备。 | `deviceId` 是平台相关标识，建议保存扫描结果中的 ID。 |
| `getDevices(deviceIds)` | 批量查询已知设备。 | 适合合并扫描、已绑定、已连接设备缓存。 |

### BLE 连接与 GATT Client

| API | 用途 | 平台差异 |
| --- | --- | --- |
| `connect(deviceId, autoConnect, timeout)` | 建立 BLE GATT 连接。 | `autoConnect` 仅 Android 有意义；Web 设备必须经过选择器授权。 |
| `disconnect(deviceId)` | 断开 BLE 连接。 | Android 未连接也视为成功；Apple 找不到设备时可能报错。 |
| `getConnectionState(deviceId)` | 读取当前连接状态。 | UI 建议结合 `connectionState` 事件流。 |
| `connectionState` | 监听 `BluetoothConnectionStateEvent`。 | Android 事件可能带原生 GATT status。 |
| `discoverServices(deviceId)` | 发现 GATT 服务/特征/描述符。 | Web 只能发现选择器授权过的服务。 |
| `readCharacteristic(...)` | 读取特征值。 | 需要已连接设备和服务/特征 UUID。 |
| `writeCharacteristic(..., writeType)` | 写入特征值。 | `withResponse` 更可靠；`withoutResponse` 更适合高吞吐。 |
| `setCharacteristicNotification(..., enable)` | 开启/关闭特征通知或指示。 | 使用各平台原生订阅能力，优先于手写 CCCD。 |
| `characteristicValues` | 监听通知/指示/读值更新。 | 事件模型为 `BluetoothCharacteristicValue`。 |
| `readDescriptor(...)` | 读取描述符值。 | Web 要求父服务已授权。 |
| `writeDescriptor(...)` | 写入描述符值。 | Web 不允许通过直接写 CCCD 来订阅通知。 |
| `descriptorValues` | 监听描述符读写值事件。 | 主要用于诊断。 |

### 链路诊断与 Android BLE 扩展

| API | 用途 | 平台差异 |
| --- | --- | --- |
| `readRssi(deviceId)` | 读取信号强度。 | Android/iOS/macOS 需要连接；Linux/Windows 返回缓存广播 RSSI；Web 不支持。 |
| `rssiUpdates` | 监听 `BluetoothRssiEvent`。 | Web 为空流。 |
| `requestMtu(deviceId, mtu)` | 请求或读取 MTU/写入长度。 | Android 协商 MTU；iOS/macOS 返回最大写入长度；其它返回 `0`。 |
| `getMaximumWriteLength(deviceId, withoutResponse)` | 获取当前最大可写 payload。 | Android 按已知 MTU 计算；iOS/macOS 走原生最大写入长度；其它返回 `0`。 |
| `mtuUpdates` | 监听 MTU/写入长度变化。 | Android 协商完成后推送；iOS/macOS 推送当前写入长度。 |
| `setPreferredPhy(deviceId, txPhy, rxPhy, phyOptions)` | 请求 BLE PHY。 | 仅 Android 8+ 支持。 |
| `readPhy(deviceId)` | 读取当前 BLE PHY。 | 非 Android 平台通常返回 `unknown`。 |
| `phyUpdates` | 监听 PHY 变化。 | 主要 Android 8+ 有事件。 |
| `requestConnectionPriority(deviceId, priority)` | 请求 `balanced`、`high`、`lowPower` 连接优先级。 | 仅 Android 支持，其它平台返回 `false`。 |
| `createBond(deviceId)` | 发起配对/绑定。 | Android 和 Linux 支持。 |
| `removeBond(deviceId)` | 移除配对/绑定。 | Android 和 Linux 支持。 |
| `bondState` | 监听绑定状态事件。 | Android/Linux 有事件。 |

### 外设、本地 GATT Server 与广播

| API | 用途 | 平台差异 |
| --- | --- | --- |
| `isPeripheralSupported()` | 判断是否支持本地外设/广播能力。 | Android/iOS/macOS 可能支持；Linux/Windows/Web 返回 `false`。 |
| `setGattServerServices(services)` | 注册本地 GATT 服务。 | Android/iOS/macOS 支持。 |
| `clearGattServerServices()` | 清空本地 GATT 服务。 | 不支持平台为空操作。 |
| `startAdvertising(advertisementData, scanResponse, settings)` | 开始 BLE 广播。 | Android 支持字段最完整；iOS/macOS 主要使用 localName 和 serviceUuids。 |
| `stopAdvertising()` | 停止 BLE 广播。 | 不支持平台为空操作。 |
| `advertisingState` | 监听广播启动、停止或错误。 | Android 可带错误码。 |
| `updateLocalCharacteristicValue(...)` | 更新本地特征缓存值。 | 读响应或主动通知前可调用。 |
| `notifyGattServerCharacteristic(..., confirm)` | 从本地 GATT Server 发送通知/指示。 | Android 可指定设备和 indication 确认；iOS/macOS 发给已订阅中心设备。 |
| `gattServerRequests` | 监听本地服务端事件。 | Android/iOS/macOS 产生读写、订阅等事件。 |

### Android Classic RFCOMM

| API | 用途 | 平台差异 |
| --- | --- | --- |
| `connectClassic(deviceId, serviceUuid, secure, timeout)` | 连接 RFCOMM 服务。 | 仅 Android，`deviceId` 通常是 MAC 地址。 |
| `startClassicServer(serviceUuid, serviceName, secure)` | 启动 RFCOMM 服务端 Socket。 | 仅 Android。 |
| `stopClassicServer()` | 停止 RFCOMM 服务端。 | 不支持平台为空操作。 |
| `disconnectClassic(deviceId)` | 断开 Classic RFCOMM 连接。 | 仅 Android。 |
| `writeClassic(deviceId, value)` | 向 RFCOMM 连接写入字节。 | 仅 Android。 |
| `classicConnectionState` | 监听 Classic 连接状态。 | 仅 Android。 |
| `classicData` | 监听 Classic 收到的数据。 | 仅 Android。 |

## 模型与枚举

### 核心枚举

- `BluetoothAdapterState`：`unknown`、`unsupported`、`unauthorized`、`poweredOff`、`poweredOn`、`resetting`、`turningOn`、`turningOff`。
- `BluetoothPermissionStatus`：`unknown`、`notDetermined`、`granted`、`denied`、`restricted`、`permanentlyDenied`、`notApplicable`。
- `BluetoothScanMode`：`ble`、`classic`、`dual`。
- `BluetoothConnectionState`：`disconnected`、`connecting`、`connected`、`disconnecting`、`unknown`。
- `BluetoothBondState`：`none`、`bonding`、`bonded`、`unknown`。
- `BluetoothWriteType`：`withResponse`、`withoutResponse`。
- `BluetoothConnectionPriority`：`balanced`、`high`、`lowPower`。
- `BluetoothAdvertisingMode`：`lowPower`、`balanced`、`lowLatency`。
- `BluetoothTxPowerLevel`：`ultraLow`、`low`、`medium`、`high`。
- `BluetoothPhy`：`le1m`、`le2m`、`leCoded`、`unknown`。

### 数据模型

- `BluetoothAdapterInfo`：蓝牙支持状态、适配器状态、名称、地址、BLE 支持、Android 能力标记、是否发现中、原始平台字段。
- `BluetoothDevice`：`id`、`name`、`address`、`type`、`isConnected`、`isBonded`、`raw`。
- `BluetoothScanResult`：设备、RSSI、本地名称、服务 UUID、厂商数据、服务数据、发射功率、可连接标记、原始字段。
- `BluetoothGattService`：服务 UUID、是否主服务、包含服务、特征列表。
- `BluetoothGattCharacteristic`：特征 UUID、服务 UUID、属性、权限、值、描述符，以及 `canRead`、`canWrite`、`canNotify`、`canIndicate` 等快捷判断。
- `BluetoothGattDescriptor`：描述符 UUID、所属特征 UUID、描述符值。
- `BluetoothAdvertisementData`：本地名称、是否包含设备名、是否包含发射功率、服务 UUID、厂商数据、服务数据。
- `BluetoothAdvertisingSettings`：广播模式、发射功率、是否可连接、广播超时。

### 事件模型

- `BluetoothConnectionStateEvent`
- `BluetoothCharacteristicValue`
- `BluetoothDescriptorValue`
- `BluetoothRssiEvent`
- `BluetoothMtuEvent`
- `BluetoothBondStateEvent`
- `BluetoothAdvertisingStateEvent`
- `BluetoothGattServerRequest`
- `BluetoothPhyEvent`
- `BluetoothClassicConnectionEvent`
- `BluetoothClassicDataEvent`

### 转换辅助函数

这些函数把原生字符串转换成 Dart 枚举；输入为空或无法识别时，会回退到对应的 `unknown`：

- `bluetoothAdapterStateFromString(value)`
- `bluetoothPermissionStatusFromString(value)`
- `bluetoothConnectionStateFromString(value)`
- `bluetoothBondStateFromString(value)`
- `bluetoothPhyFromString(value)`

## 平台差异说明

### Android

Android 是当前能力最完整的平台：BLE Central、BLE Peripheral、本地 GATT Server、BLE 广播、绑定、MTU、PHY、连接优先级、Classic RFCOMM 都有覆盖。Android 12+ 把蓝牙权限拆成 scan/connect/advertise，建议始终检查 `requestPermissions()` 返回的权限 Map。

### iOS 与 macOS

Apple 平台支持 BLE Central 和 CoreBluetooth Peripheral，但不开放 Classic Bluetooth RFCOMM。App 不能直接开启蓝牙。查询已连接设备时，建议传入目标 Service UUID。外设广播主要使用 localName 和 serviceUuids；Android 专属的广播厂商数据等字段会被忽略。

### Linux

Linux 后端通过 system DBus 调用 BlueZ。BLE GATT Client 已实现；已绑定/已连接设备来自 BlueZ 对象；RSSI 来自最近一次广播缓存。BlueZ discovery 可以设置 LE、BR/EDR 或 auto transport，但本插件没有实现 Linux Classic RFCOMM Socket。

### Windows

Windows 后端使用 WinRT BLE API。当前支持 BLE 广播扫描、GATT Client、尽量查询已配对 BLE 设备和缓存 RSSI。本地 GATT Server、BLE 广播、Classic RFCOMM、MTU 协商、PHY 控制暂未实现。

### Web

Web 后端封装 Web Bluetooth。它不能被动扫描；`startScan()` 会打开浏览器设备选择器，并把用户选中的一个设备作为扫描结果返回。浏览器决定哪些设备可见、哪些服务可授权；GATT 访问受选择器授权范围限制。

## 常见问题排查

### 扫描结果为空

- 先清空 `serviceUuids`。UUID 过滤匹配的是“广播包里声明的服务”，不是设备连接后可能暴露的全部服务。
- 先订阅 `scanResults`，再调用 `startScan()`。
- 确认 `getAdapterState()` 返回 `BluetoothAdapterState.poweredOn`。
- Android 上先调用 `requestPermissions()`，并按系统版本授予附近设备/蓝牙/定位权限。
- iOS/macOS 上确认系统设置里已授权蓝牙权限。
- Web 上必须从用户手势中调用 `startScan()`，并运行在 HTTPS 或 localhost。
- iOS、macOS、Windows、Web 不会显示 Classic-only 设备；Android 需要使用 `BluetoothScanMode.classic` 或 `BluetoothScanMode.dual`。

### Web 能选到设备，但发现不了服务

连接前把目标服务传给 `startScan(serviceUuids: [...])`。Web Bluetooth 会根据设备选择器参数决定当前站点能访问哪些 GATT 服务。

### 收不到通知

- 确认特征属性包含 `notify` 或 `indicate`。
- 使用 `setCharacteristicNotification(..., enable: true)`，不要直接写 CCCD。
- 保持 `characteristicValues` 的订阅不被释放。
- 有些设备需要先配对/绑定，才允许加密通知。

### Android 广播启动失败

传统 BLE 广播数据空间很小。先只放一个短 `localName` 和一个 service UUID，确认能广播后，再逐步加入厂商数据或 scan response。

## 示例 App

`example/` 是一个 Cupertino 风格的蓝牙测试控制台，适合开发阶段验证插件能力：

- 平台版本、适配器、权限、扫描、设置页等诊断能力。
- BLE 扫描模式、重复扫描事件、已绑定设备、已连接设备、设备查询 API。
- BLE 连接状态、服务发现、特征/描述符读写、通知、RSSI、MTU、最大写入长度、PHY、连接优先级、绑定操作。
- 本地 GATT Server、BLE 广播、本地值更新、通知发送、服务清理。
- Android Classic RFCOMM 客户端/服务端 Socket 操作。
- 插件所有事件流的实时日志。

示例 App 默认已经清空 Service UUID 过滤器，首次点击扫描会尽量直接显示附近 BLE 设备。只有当你明确需要按服务过滤时，再手动输入 UUID。

运行方式：

```sh
cd example
flutter pub get
flutter run
```

Web Bluetooth 请使用 HTTPS 或 localhost，并从 App 内按钮触发扫描，让浏览器打开设备选择器。

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。
